#!/usr/bin/env bash
# Generates small fixture videos with ffmpeg and checks what carify makes of them.
# usage: tests/run.sh [bash|pwsh|powershell]   (default bash)
# CARIFY_BASH=/bin/bash picks the interpreter for the bash target (macOS 3.2 check).
# Needs ffmpeg/ffprobe with libx264, libx265 and ac3. Takes about a minute.
set -uo pipefail

target="${1:-bash}"
root=$(cd -- "$(dirname -- "$0")/.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/carify-test.XXXXXX")
trap 'rm -rf -- "$work"' EXIT
export NO_COLOR=1
unset CARIFY_USB_DIR CARIFY_URL CARIFY_REF

pass=0 fail=0
check() {  # check <name> <condition...>
    local name="$1"; shift
    if "$@"; then pass=$((pass + 1)); printf 'ok    %s\n' "$name"
    else fail=$((fail + 1)); printf 'FAIL  %s\n' "$name"; fi
}

# Run carify with bash-style flags; translated for the PowerShell script.
run() {
    case "$target" in
        bash) "${CARIFY_BASH:-bash}" "$root/carify" "$@" ;;
        pwsh|powershell)
            local args=()
            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --force) args+=(-Force) ;;
                    --no-usb) args+=(-NoUsb) ;;
                    --version) args+=(-Version) ;;
                    --max-height) args+=(-MaxHeight "$2"); shift ;;
                    *) args+=("$1") ;;
                esac
                shift
            done
            "$target" -NoProfile -ExecutionPolicy Bypass -File "$root/carify.ps1" "${args[@]}" ;;
        *) echo "unknown target: $target" >&2; exit 2 ;;
    esac
}

not() { ! "$@"; }
# A file:// URL curl can open: on Windows it wants the drive letter, not Git Bash's /c/...
file_url() {
    if [[ -n "$windows" ]]; then printf 'file:///%s' "$(cygpath -m "$1")"; else printf 'file://%s' "$1"; fi
}
# Run a command with every proxy set to a closed local port, so any download fails at once.
no_network() {
    local dead=http://127.0.0.1:9
    env http_proxy=$dead https_proxy=$dead all_proxy=$dead HTTP_PROXY=$dead HTTPS_PROXY=$dead ALL_PROXY=$dead \
        no_proxy= NO_PROXY= "$@"
}
# stream field from the first video/audio stream of a file
# (tr -d '\r': ffprobe on Windows ends lines with CRLF)
f() { ffprobe -v error -select_streams "$2" -show_entries "stream=$3" -of csv=p=0 "file:$1" | tr -d '\r' | head -n1; }
streams() { ffprobe -v error -show_entries stream=codec_type -of csv=p=0 "file:$1" | tr -d '\r' | tr '\n' ' ' | sed 's/ $//'; }
# true if the moov atom comes before mdat (faststart)
# (the first Python that runs: on Windows, python3 and python can be stubs that only point at the
# Store, and the py launcher is the real one)
py=(false)
for p in python3 python py; do
    try=("$p"); [[ "$p" == py ]] && try=(py -3)
    if command -v "$p" >/dev/null 2>&1 && "${try[@]}" -c '' >/dev/null 2>&1; then py=("${try[@]}"); break; fi
done
[[ "${py[0]}" != false ]] || echo "no Python 3 found: the faststart check fails" >&2
moov_first() { "${py[@]}" - "$1" <<'PY'
import struct, sys
with open(sys.argv[1], "rb") as fh:
    while True:
        h = fh.read(8)
        if len(h) < 8: sys.exit(1)
        size, kind = struct.unpack(">I4s", h)
        if kind == b"moov": sys.exit(0)
        if kind == b"mdat": sys.exit(1)
        if size == 1: size = struct.unpack(">Q", fh.read(8))[0]; fh.seek(size - 16, 1)
        else: fh.seek(size - 8, 1)
PY
}

gen() {  # gen <out> <ffmpeg output options...>
    local out="$1"; shift
    ffmpeg -hide_banner -loglevel error -nostdin -y \
        -f lavfi -i "testsrc2=size=${SIZE:-640x360}:rate=24:duration=${DUR:-2}" \
        -f lavfi -i "sine=frequency=440:duration=${DUR:-2}:sample_rate=48000" \
        "$@" "$out"
}

cd "$work" || exit 1
echo "target: $target  ($(ffmpeg -version | head -n1 | cut -d' ' -f1-3))"
echo "fixtures..."
gen ok.mp4      -map 0:v -map 1:a -c:v libx264 -profile:v high -pix_fmt yuv420p -c:a aac -ac 2
gen hevc10.mkv  -map 0:v -map 1:a -c:v libx265 -pix_fmt yuv420p10le -x265-params log-level=error \
                -c:a ac3 -ac 6 -s 1920x1080
SIZE=1080x1920 gen portrait.mp4 -map 0:v -map 1:a -c:v libx264 -profile:v high -pix_fmt yuv420p -c:a aac -ac 2
SIZE=1920x1080 gen full-hd.mp4  -map 0:v -map 1:a -c:v libx264 -profile:v high -level:v 4.1 -pix_fmt yuv420p -c:a aac -ac 2
gen silent.mp4  -map 0:v -c:v libx264 -pix_fmt yuv420p
gen level51.mp4 -map 0:v -map 1:a -c:v libx264 -profile:v high -level:v 5.1 -pix_fmt yuv420p -c:a aac -ac 2
# HDR10 flags go into the HEVC bitstream (VUI) as well as the container, so every ffmpeg version reads them
gen hdr.mkv     -map 0:v -map 1:a -vf setparams=color_primaries=bt2020:color_trc=smpte2084:colorspace=bt2020nc \
                -c:v libx265 -pix_fmt yuv420p10le \
                -x265-params log-level=error:colorprim=bt2020:transfer=smpte2084:colormatrix=bt2020nc -c:a aac
gen hi422.mkv   -map 0:v -map 1:a -c:v libx264 -pix_fmt yuv422p -c:a aac -ac 2
# full range ("JPEG") H.264, as some phones and screen recorders write it
gen fullrange.mp4 -map 0:v -map 1:a -c:v libx264 -profile:v high -pix_fmt yuvj420p -c:a aac -ac 2
# long enough to re-encode that a second run can start while it does
SIZE=1920x1080 DUR=30 gen long.mp4 -map 0:v -map 1:a -c:v libx264 -preset ultrafast -crf 30 -pix_fmt yuv420p \
                -c:a aac -ac 2
# wider than 1280 but well under 720 high: only the width limit says it must shrink
SIZE=1920x360 gen wide.mp4 -map 0:v -map 1:a -c:v libx264 -profile:v high -pix_fmt yuv420p -c:a aac -ac 2
# MPEG-2 Main profile, 8-bit 4:2:0, level 8: only the codec says it needs re-encoding
gen mpeg2-main.mp4 -map 0:v -map 1:a -c:v mpeg2video -pix_fmt yuv420p -c:a aac -ac 2
gen ac3-stereo.mp4 -map 0:v -map 1:a -c:v libx264 -profile:v high -pix_fmt yuv420p -c:a ac3 -ac 2
# Cover art: an MKV with an image attachment, and an MP3 whose only "video" is the cover
ffmpeg -hide_banner -loglevel error -nostdin -y -f lavfi -i "color=c=orange:size=300x300:duration=1" -frames:v 1 cover.png
ffmpeg -hide_banner -loglevel error -nostdin -y -i ok.mp4 -map 0 -c copy \
    -attach cover.png -metadata:s:t mimetype=image/png -metadata:s:t filename=cover.png covered.mkv
ffmpeg -hide_banner -loglevel error -nostdin -y -f lavfi -i "sine=duration=2" -i cover.png \
    -map 0:a -map 1:v -c:a libmp3lame -c:v png -disposition:v:0 attached_pic song.mp3 2>/dev/null \
  || ffmpeg -hide_banner -loglevel error -nostdin -y -f lavfi -i "sine=duration=2" -i cover.png \
    -map 0:a -map 1:v -c:a aac -c:v png -disposition:v:0 attached_pic song.m4a
mkdir -p "dir.v1" "sub dir" usb
cp ok.mp4 "dir.v1/movie"
windows=
case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) windows=1 ;; esac
odd="sub dir/-dash: name"            # colons are not allowed in Windows names
[[ -n "$windows" ]] && odd="sub dir/-dash name"
cp ok.mp4 "$odd.mkv"
head -c 50000 /dev/urandom > broken.mkv

echo "cases..."
log=$(run --no-usb ok.mp4 2>&1)
check "compliant file: both streams copied"  grep -q 'video  copy' <<< "$log"
check "compliant file: audio copied"         grep -q 'audio  copy' <<< "$log"
check "compliant file: default name"         test -f ok-car.mp4
check "compliant file: faststart"            moov_first ok-car.mp4
check "compliant file: video stays h264"     test "$(f ok-car.mp4 v:0 codec_name)" = h264
check "compliant file: probe reports the audio" grep -q 'audio aac' <<< "$log"
ok_size=$(( $(wc -c < ok-car.mp4) ))
check "under 1 MiB: size shown in KB"        grep -qF "($(( ok_size / 1024 )) KB)" <<< "$log"

run --no-usb ok.mp4 >/dev/null 2>&1
check "existing output refused"              test $? -ne 0
run --no-usb --force ok.mp4 >/dev/null 2>&1
check "--force overwrites"                   test $? -eq 0
run --no-usb --force ok.mp4 ok.mp4 >/dev/null 2>&1
check "output == input refused"              test $? -ne 0
check "input untouched after refusal"        test "$(f ok.mp4 v:0 codec_name)" = h264
# On a disk that ignores case (Windows, macOS) CASE.mp4 is the input itself; on one that doesn't,
# it is a new file. Either way the input must come through unchanged.
cp ok.mp4 case.mp4
run --no-usb --force case.mp4 CASE.mp4 >/dev/null 2>&1; rc=$?
check "output == input in another case: input untouched" cmp -s case.mp4 ok.mp4
if [[ -n "$windows" ]]; then
    check "output == input in another case refused (Windows)" test $rc -ne 0
fi

# --force onto an output that can't be replaced (read-only here; on Windows a player holding the file
# open does the same): either it is replaced, or the run fails. The old file is never reported as
# written or copied to the stick.
printf 'an older conversion' > stuck-car.mp4
chmod a-w stuck-car.mp4
mkdir -p usb-stuck
log=$(CARIFY_USB_DIR=usb-stuck run --force ok.mp4 stuck-car.mp4 2>&1); rc=$?
chmod u+w stuck-car.mp4
replaced() { test "$(f stuck-car.mp4 v:0 codec_name 2>/dev/null)" = h264; }
failed_or_replaced() { [[ $rc -ne 0 ]] || replaced; }
check "--force, output can't be replaced: fails unless replaced" failed_or_replaced
check "--force, output can't be replaced: old file not copied"   not grep -qsF 'an older conversion' usb-stuck/stuck-car.mp4
check "--force, output can't be replaced: no temp file left"     test ! -e .stuck-car.mp4.part
log=$(run --no-usb missing.mp4 2>&1)
check "missing input: file not found"        grep -q 'file not found' <<< "$log"
log=$(run --no-usb < /dev/null 2>&1)
check "no input given: not taken for a missing file" not grep -q 'file not found' <<< "$log"

run --no-usb hevc10.mkv >/dev/null 2>&1
check "hevc 10-bit: re-encoded to h264"      test "$(f hevc10-car.mp4 v:0 codec_name)" = h264
check "hevc 10-bit: 8-bit 4:2:0"             test "$(f hevc10-car.mp4 v:0 pix_fmt)" = yuv420p
check "hevc 10-bit: 1280x720"                test "$(f hevc10-car.mp4 v:0 width,height)" = "1280,720"
check "5.1 ac3: aac"                          test "$(f hevc10-car.mp4 a:0 codec_name)" = aac
check "5.1 ac3: stereo"                       test "$(f hevc10-car.mp4 a:0 channels)" = 2
check "re-encode: level <= 4.1"              test "$(f hevc10-car.mp4 v:0 level)" -le 41

run --no-usb portrait.mp4 >/dev/null 2>&1
check "portrait 1080x1920: fits 720 high"    test "$(f portrait-car.mp4 v:0 width,height)" = "406,720"

run --no-usb full-hd.mp4 >/dev/null 2>&1
check "1080p: scaled to 1280x720"            test "$(f full-hd-car.mp4 v:0 width,height)" = "1280,720"
run --no-usb wide.mp4 >/dev/null 2>&1
check "wide 1920x360: fits 1280 wide"        test "$(f wide-car.mp4 v:0 width,height)" = "1280,240"
log=$(run --no-usb --force --max-height 1080 full-hd.mp4 2>&1)
check "--max-height 1080: 1080p copied"      grep -q 'video  copy' <<< "$log"
check "--max-height 1080: size kept"         test "$(f full-hd-car.mp4 v:0 width,height)" = "1920,1080"
run --no-usb --force --max-height abc full-hd.mp4 >/dev/null 2>&1
check "--max-height rejects non-numbers"     test $? -ne 0

log=$(run --no-usb silent.mp4 2>&1)
check "no audio: succeeds"                   test -f silent-car.mp4
check "no audio: warns"                      grep -q 'no audio stream' <<< "$log"
check "no audio: video only"                 test "$(streams silent-car.mp4)" = video
check "no audio: probe reports audio none"   grep -q 'audio none' <<< "$log"

run --no-usb level51.mp4 >/dev/null 2>&1
check "level 5.1: re-encoded to <= 4.1"      test "$(f level51-car.mp4 v:0 level)" -le 41
log=$(run --no-usb hdr.mkv 2>&1)
check "HDR source: warns"                    grep -q 'HDR source' <<< "$log"
log=$(run --no-usb --force ok.mp4 2>&1)
check "SDR source: no HDR warning"           not grep -q 'HDR source' <<< "$log"
run --no-usb hi422.mkv >/dev/null 2>&1
check "4:2:2: re-encoded to 4:2:0"           test "$(f hi422-car.mp4 v:0 pix_fmt)" = yuv420p
run --no-usb fullrange.mp4 >/dev/null 2>&1
check "full range: re-encoded to limited range" test "$(f fullrange-car.mp4 v:0 pix_fmt)" = yuv420p
log=$(run --no-usb fullrange-car.mp4 2>&1)
check "full range: the output is copied next time" grep -q 'video  copy' <<< "$log"
run --no-usb mpeg2-main.mp4 >/dev/null 2>&1
check "mpeg2 4:2:0 Main: re-encoded to h264" test "$(f mpeg2-main-car.mp4 v:0 codec_name)" = h264
run --no-usb ac3-stereo.mp4 >/dev/null 2>&1
check "stereo ac3: re-encoded to aac"        test "$(f ac3-stereo-car.mp4 a:0 codec_name)" = aac

log=$(run --no-usb covered.mkv 2>&1)
check "attachment: video copied"             grep -q 'video  copy' <<< "$log"
check "attachment: dropped from output"      test "$(streams covered-car.mp4)" = "video audio"
songs=(song.*); song="${songs[0]}"
log=$(run --no-usb "$song" 2>&1)
check "audio + cover art: refused"           grep -q 'no video stream' <<< "$log"

run --no-usb "dir.v1/movie" >/dev/null 2>&1
check "no extension in a dotted folder"      test -f "dir.v1/movie-car.mp4"
run --no-usb "$odd.mkv" >/dev/null 2>&1
check "dash, colon and space in name"        test -f "$odd-car.mp4"

run --no-usb broken.mkv >/dev/null 2>&1
check "broken input: non-zero exit"          test $? -ne 0
check "broken input: no output left"         test ! -e broken-car.mp4
parts=(.*.part)
check "broken input: no temp file left"      test ! -e "${parts[0]}"
# An output path that is a folder: refused before converting, with or without --force
mkdir -p folder-out.mp4
log=$(CARIFY_USB_DIR=usb run --force ok.mp4 folder-out.mp4 2>&1); rc=$?
check "output is a folder: refused"           test $rc -ne 0
check "output is a folder: says so"           grep -q 'is a folder' <<< "$log"
check "output is a folder: nothing written in it" test -z "$(ls -A folder-out.mp4)"
check "output is a folder: no temp file left" test ! -e .folder-out.mp4.part
check "output is a folder: nothing copied"    test ! -e usb/folder-out.mp4

# An output of exactly 1 MiB: ok.mp4 padded with a comment tag (carify keeps the metadata),
# the padding sized from a first run's output.
mib=1048576
pad_ok() {  # pad_ok <comment length>: writes padded.mp4
    { echo ';FFMETADATA1'; printf 'comment='; head -c "$1" /dev/zero | tr '\0' x; echo; } > pad.txt
    ffmpeg -hide_banner -loglevel error -nostdin -y -i ok.mp4 -f ffmetadata -i pad.txt \
        -map 0 -map_metadata 1 -c copy padded.mp4
}
pad_ok 900000
run --no-usb padded.mp4 >/dev/null 2>&1
pad_ok $(( 900000 + mib - $(wc -c < padded-car.mp4) ))
log=$(run --no-usb --force padded.mp4 2>&1)
check "exactly 1 MiB: output is 1048576 bytes" test "$(( $(wc -c < padded-car.mp4) ))" -eq $mib
check "exactly 1 MiB: size shown as 1 MB"    grep -qF '(1 MB)' <<< "$log"

CARIFY_USB_DIR=usb run ok.mp4 out-usb.mp4 >/dev/null 2>&1
check "usb: copied to CARIFY_USB_DIR"        test -f usb/out-usb.mp4
CARIFY_USB_DIR=usb run --no-usb ok.mp4 out-nousb.mp4 >/dev/null 2>&1
check "--no-usb: not copied"                 test ! -e usb/out-nousb.mp4
# A file already on the stick: the result is written next to it, which is the stick, and kept
mkdir -p stick
cp ok.mp4 stick/onstick.mp4
CARIFY_USB_DIR=./stick run stick/onstick.mp4 >/dev/null 2>&1
check "input on the stick: succeeds"         test $? -eq 0
check "input on the stick: the result is kept" test "$(f stick/onstick-car.mp4 v:0 codec_name 2>/dev/null)" = h264
# Options after the input, the way PowerShell takes them
cp ok.mp4 late.mp4
CARIFY_USB_DIR=usb run late.mp4 --no-usb >/dev/null 2>&1
check "option after the input: still an option" test -f late-car.mp4 -a ! -e ./--no-usb
check "option after the input: honoured"     test ! -e usb/late-car.mp4 -a ! -e usb/--no-usb

# Two runs to one output name at once: the second is refused, and the first run's file is kept
run --no-usb long.mp4 same-car.mp4 >/dev/null 2>&1 &
first=$!
for _ in $(seq 300); do [[ -e .same-car.mp4.part ]] && break; sleep 0.1; done
run --no-usb ok.mp4 same-car.mp4 >/dev/null 2>&1; second=$?
wait "$first"; first=$?
check "two runs, one output: the second is refused" test $second -ne 0
check "two runs, one output: the first succeeds" test $first -eq 0
check "two runs, one output: the first one's file is kept" test "$(f same-car.mp4 v:0 width,height 2>/dev/null)" = "1280,720"
check "two runs, one output: no temp file left" test ! -e .same-car.mp4.part
# The same, made certain: another run's temp file is there, as it is while that run converts
printf 'another run' > .busy-car.mp4.part
log=$(run --no-usb ok.mp4 busy-car.mp4 2>&1)
check "output being written by another run: refused" test ! -e busy-car.mp4
check "output being written by another run: says so" grep -q 'another carify' <<< "$log"
check "output being written by another run: its temp file kept" grep -qx 'another run' .busy-car.mp4.part
rm -f .busy-car.mp4.part
log=$(CARIFY_USB_DIR=no-such-folder run ok.mp4 out-badusb.mp4 2>&1); rc=$?
check "CARIFY_USB_DIR not a folder: still succeeds" test $rc -eq 0
check "CARIFY_USB_DIR not a folder: warns"   grep -q 'CARIFY_USB_DIR is not a folder' <<< "$log"
printf 'an older copy' > usb/out-usb-again.mp4
CARIFY_USB_DIR=usb run ok.mp4 out-usb-again.mp4 >/dev/null 2>&1
check "usb: replaces an older copy on the stick" test $? -eq 0
check "usb: the stick's copy is the new file"  cmp -s out-usb-again.mp4 usb/out-usb-again.mp4
if [[ "$target" != bash ]]; then
    mkdir -p usb/out-usb-blocked.mp4     # a folder where the copy should go, so the copy fails
    log=$(CARIFY_USB_DIR=usb run ok.mp4 out-usb-blocked.mp4 2>&1)
    check "usb: failed copy gives its reason"    grep -q 'copy to .* failed: .' <<< "$log"
    check "usb: failed copy reason has no PowerShell wrapper" not grep -q 'Exception calling' <<< "$log"
fi

check "--version"                            grep -Eq '^carify [0-9]+\.[0-9]+\.[0-9]+$' <<< "$(run --version 2>&1 | tr -d '\r')"
run --version >/dev/null 2>&1
check "--version: exits 0"                   test $? -eq 0

# Status is coloured only where it's shown: never when stderr is captured, as it is here.
log=$(unset NO_COLOR; WT_SESSION=1 TERM_PROGRAM=vscode COLORTERM=truecolor run --no-usb missing.mp4 2>&1)
check "captured stderr: no colour, even in a colour terminal" not grep -qF $'\e[' <<< "$log"

if [[ "$target" != bash ]]; then
    syntax=$(cd "$root" && "$target" -NoProfile -ExecutionPolicy Bypass -Command 'Get-Command ./carify.ps1 -Syntax' 2>&1 | tr -d '\r')
    check "help: the input file is required"     grep -q '^carify\.ps1 \[-In\] <string> ' <<< "$syntax"
    check "help: -Version is a form of its own"  grep -qx 'carify\.ps1 -Version \[<CommonParameters>\]' <<< "$syntax"
fi

# Colour on a console. Windows PowerShell only: carify.ps1 runs in a host whose stderr is the
# console (CONOUT$) while [Console]::Error is a buffer printed afterwards, so the colour codes can be
# read. CARIFY_TEST_PS_MAJOR makes $PSVersionTable claim that PowerShell version.
if [[ "$target" == powershell ]]; then
    cat > console-run.ps1 <<'PS'
Add-Type -Namespace CarifyTest -Name Kernel -MemberDefinition @'
[DllImport("kernel32.dll", SetLastError = true)] public static extern bool SetStdHandle(int n, IntPtr h);
[DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
public static extern IntPtr CreateFile(string name, uint access, uint share, IntPtr sa, uint disp, uint flags, IntPtr t);
'@
$carify = $args[0]
$con = [CarifyTest.Kernel]::CreateFile('CONOUT$', [uint32]3221225472, 3, [IntPtr]::Zero, 3, 0, [IntPtr]::Zero)
$null = [CarifyTest.Kernel]::SetStdHandle(-12, $con)
# .NET Framework remembers whether stderr was redirected: make it look again
[Console].GetField('_stdErrRedirectQueried', [Reflection.BindingFlags]'Static,NonPublic').SetValue($null, $false)
if ([Console]::IsErrorRedirected) { 'console-run: no console to write to'; exit 99 }
if ($env:CARIFY_TEST_PS_MAJOR) { $PSVersionTable.PSVersion = [version]"$env:CARIFY_TEST_PS_MAJOR.0" }
$buffer = New-Object IO.StringWriter
[Console]::SetError($buffer)
& $carify missing.mp4 -NoUsb
$code = $LASTEXITCODE
[Console]::Out.Write($buffer.ToString())
exit $code
PS
    # console_err [NAME=value...]: what carify.ps1 shows on a console for a missing input
    console_err() {
        env -u NO_COLOR -u WT_SESSION -u TERM_PROGRAM -u CARIFY_THEME -u CARIFY_TEST_PS_MAJOR "$@" \
            "$target" -NoProfile -ExecutionPolicy Bypass -File console-run.ps1 "$root/carify.ps1" 2>&1 | tr -d '\r'
    }
    night_err=$'\e[38;2;255;110;122m' day_err=$'\e[38;2;176;32;48m'
    check "console, Windows Terminal: nightshift colours" grep -qF "$night_err" <<< "$(console_err WT_SESSION=1)"
    check "console, VS Code terminal: coloured"           grep -qF "$night_err" <<< "$(console_err TERM_PROGRAM=vscode)"
    check "console, PowerShell 7: coloured"               grep -qF "$night_err" <<< "$(console_err CARIFY_TEST_PS_MAJOR=7)"
    check "console, CARIFY_THEME=dayshift: dayshift colours" grep -qF "$day_err" <<< "$(console_err WT_SESSION=1 CARIFY_THEME=dayshift)"
    log=$(console_err WT_SESSION=1 NO_COLOR=1)
    check "console, NO_COLOR: message still shown"       grep -q 'file not found' <<< "$log"
    check "console, NO_COLOR: no colour codes"            not grep -qF $'\e[' <<< "$log"
fi

# carify.ps1 on Windows: the MOVIES drive search and the FAT32 4 GB limit. No real drive is used:
# run_fake_movies stands in for Get-CimInstance (a MOVIES drive that is a folder here, with the
# file system given) and, when a size is given, for New-Object IO.FileInfo (the output's size),
# so the 4 GB limit is reached without writing 4 GB.
if [[ "$target" != bash && -n "$windows" ]]; then
    cat > fake-movies.ps1 <<'PS'
param([string]$FakeCarify, [string]$FakeDrive, [string]$FakeFs, [long]$FakeSize)
function Get-CimInstance { [pscustomobject]@{ DeviceID = $FakeDrive; FileSystem = $FakeFs } }
function New-Object {
    if ($FakeSize -ge 0 -and "$($args[0])" -eq 'IO.FileInfo') { return [pscustomobject]@{ Length = $FakeSize } }
    Microsoft.PowerShell.Utility\New-Object @args
}
& $FakeCarify @args
exit $LASTEXITCODE
PS
    run_fake_movies() {  # run_fake_movies <drive folder> <file system> <size, -1 for real> <carify args...>
        local drive="$1" fs="$2" size="$3"; shift 3
        mkdir -p "$drive"
        "$target" -NoProfile -ExecutionPolicy Bypass -File "$(cygpath -w fake-movies.ps1)" \
            -FakeCarify "$(cygpath -w "$root/carify.ps1")" -FakeDrive "$(cygpath -w "$drive")" \
            -FakeFs "$fs" -FakeSize "$size" "$@"
    }
    run_fake_movies movies-exfat exFAT -1 ok.mp4 out-movies.mp4 >/dev/null 2>&1
    check "usb: MOVIES drive found, copied to it"  test -f movies-exfat/out-movies.mp4
    run_fake_movies movies-fat32 FAT32 -1 ok.mp4 out-fat32-small.mp4 >/dev/null 2>&1
    check "usb: FAT32 MOVIES drive takes a small file" test -f movies-fat32/out-fat32-small.mp4
    run_fake_movies movies-fat32 FAT32 4294967295 ok.mp4 out-fat32-4g.mp4 >/dev/null 2>&1
    check "usb: FAT32 MOVIES drive takes a file of 4 GB less a byte" test -f movies-fat32/out-fat32-4g.mp4
    run_fake_movies movies-fat32 FAT32 4294967296 ok.mp4 out-fat32-over.mp4 >/dev/null 2>&1
    check "usb: FAT32 MOVIES drive refuses a file over 4 GB" test $? -ne 0 -a ! -e movies-fat32/out-fat32-over.mp4
    run_fake_movies movies-exfat exFAT 4294967296 ok.mp4 out-exfat-over.mp4 >/dev/null 2>&1
    check "usb: exFAT MOVIES drive takes a file over 4 GB" test -f movies-exfat/out-exfat-over.mp4

    # Outside Windows (OS not Windows_NT) carify.ps1 looks in /run/media/$USER/MOVIES and the like.
    # A USER that climbs out of /run/media points that search at a folder here instead.
    here_nodrive=$(cygpath -m "$work"); here_nodrive=${here_nodrive#?:}
    mkdir -p home-user/MOVIES
    OS=Linux USER="../..$here_nodrive/home-user" run ok.mp4 out-user-movies.mp4 >/dev/null 2>&1
    check "usb: outside Windows, MOVIES under /run/media/\$USER is used" test -f home-user/MOVIES/out-user-movies.mp4
    OS=Linux USER=carify-test-nobody run ok.mp4 out-no-movies.mp4 >/dev/null 2>&1
    check "usb: outside Windows, no MOVIES folder still succeeds" test $? -eq 0
fi

if [[ "$target" == bash ]]; then
    CARIFY_BIN="$work/bin" CARIFY_URL="$(file_url "$root/carify")" sh "$root/install.sh" >/dev/null 2>&1
    check "install.sh: installs a runnable carify"  test "$("$work/bin/carify" --version)" = "$(run --version)"
    CARIFY_BIN="$work/bin2" CARIFY_URL="$(file_url "$root/README.md")" sh "$root/install.sh" >/dev/null 2>&1
    check "install.sh: rejects a non-carify download" test ! -e "$work/bin2/carify"
    # Unzipped from carify-<version>-offline.zip: run as a file, install.sh installs the carify
    # beside it (marked 9.9.9 here). Piped to sh it downloads, never the copy in the folder.
    mkdir -p "$work/unzipped"
    sed 's/^CARIFY_VERSION=.*/CARIFY_VERSION="9.9.9"/' "$root/carify" > "$work/unzipped/carify"
    cp "$root/install.sh" "$work/unzipped/install.sh"
    (cd "$work/unzipped" && no_network CARIFY_BIN="$work/bin3" sh ./install.sh) >/dev/null 2>&1
    check "install.sh: run as a file, installs the carify beside it" test "$("$work/bin3/carify" --version 2>/dev/null)" = "carify 9.9.9"
    (cd "$work/unzipped" && no_network CARIFY_BIN="$work/bin4" sh < install.sh) >/dev/null 2>&1
    check "install.sh: piped to sh, ignores the carify in the folder" test "$("$work/bin4/carify" --version 2>/dev/null)" != "carify 9.9.9"
fi

# install.ps1 the same way. On Windows it also adds its folder to the user PATH in the registry,
# so there it is left to the offline workflow, which runs it on a throwaway runner.
if [[ "$target" != bash && -z "$windows" ]]; then
    mkdir -p "$work/unzipped-ps"
    sed "s/^\(.CarifyVersion = '\)[^']*'/\19.9.9'/" "$root/carify.ps1" > "$work/unzipped-ps/carify.ps1"
    cp "$root/install.ps1" "$work/unzipped-ps/install.ps1"
    (cd "$work/unzipped-ps" && no_network CARIFY_BIN="$work/psbin" "$target" -NoProfile -File ./install.ps1) >/dev/null 2>&1
    check "install.ps1: run as a file, installs the carify.ps1 beside it" grep -qF "= '9.9.9'" "$work/psbin/carify.ps1"
    (cd "$work/unzipped-ps" && no_network CARIFY_BIN="$work/psbin2" "$target" -NoProfile -Command 'Get-Content -Raw ./install.ps1 | Invoke-Expression') >/dev/null 2>&1
    check "install.ps1: piped to iex, ignores the carify.ps1 in the folder" not grep -qsF "= '9.9.9'" "$work/psbin2/carify.ps1"
fi

# install.ps1 decides on the execution policy saved for the user or the machine, not this process's:
# run as "powershell -ExecutionPolicy Bypass -File .\install.ps1", Get-ExecutionPolicy says Bypass.
# Only its Get-SavedExecutionPolicy function runs here, against made-up scopes, so nothing is changed.
if [[ "$target" != bash ]]; then
    cat > saved-policy.ps1 <<'PS'
param([string]$Install, [string]$Scopes)
$fake = @{}
foreach ($pair in $Scopes -split ',') { $k, $v = $pair -split '=', 2; if ($k) { $fake[$k] = $v } }
function Get-ExecutionPolicy([string]$Scope) { if ($fake.ContainsKey($Scope)) { $fake[$Scope] } else { 'Undefined' } }
$ast = [Management.Automation.Language.Parser]::ParseFile($Install, [ref]$null, [ref]$null)
$fn = $ast.Find({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and
    $n.Name -eq 'Get-SavedExecutionPolicy' }, $true)
if (-not $fn) { 'install.ps1 has no Get-SavedExecutionPolicy'; exit 1 }
. ([scriptblock]::Create($fn.Extent.Text))
Get-SavedExecutionPolicy
PS
    saved_policy() {
        "$target" -NoProfile -ExecutionPolicy Bypass -File saved-policy.ps1 "$root/install.ps1" "$1" 2>&1 | tr -d '\r'
    }
    check "install.ps1: under -ExecutionPolicy Bypass, the saved policy" \
        test "$(saved_policy Process=Bypass,LocalMachine=Restricted)" = Restricted
    check "install.ps1: the user's policy before the machine's" \
        test "$(saved_policy Process=Bypass,CurrentUser=RemoteSigned,LocalMachine=Restricted)" = RemoteSigned
    check "install.ps1: Group Policy before both" \
        test "$(saved_policy MachinePolicy=AllSigned,CurrentUser=RemoteSigned)" = AllSigned
    check "install.ps1: nothing saved is Undefined"   test "$(saved_policy Process=Bypass)" = Undefined
    check "install.ps1: decides on the saved policy"  grep -qF 'policy = Get-SavedExecutionPolicy' "$root/install.ps1"
fi

echo "$pass passed, $fail failed"
[[ $fail -eq 0 ]]
