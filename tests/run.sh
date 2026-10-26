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
unset CARIFY_USB_DIR

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
# stream field from the first video/audio stream of a file
# (tr -d '\r': ffprobe on Windows ends lines with CRLF)
f() { ffprobe -v error -select_streams "$2" -show_entries "stream=$3" -of csv=p=0 "file:$1" | tr -d '\r' | head -n1; }
streams() { ffprobe -v error -show_entries stream=codec_type -of csv=p=0 "file:$1" | tr -d '\r' | tr '\n' ' ' | sed 's/ $//'; }
# true if the moov atom comes before mdat (faststart)
py=$(command -v python3 || command -v python)
moov_first() { "$py" - "$1" <<'PY'
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
        -f lavfi -i "testsrc2=size=${SIZE:-640x360}:rate=24:duration=2" \
        -f lavfi -i "sine=frequency=440:duration=2:sample_rate=48000" \
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
odd="sub dir/-dash: name"            # colons are not allowed in Windows names
case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) odd="sub dir/-dash name" ;; esac
cp ok.mp4 "$odd.mkv"
head -c 50000 /dev/urandom > broken.mkv

echo "cases..."
log=$(run --no-usb ok.mp4 2>&1)
check "compliant file: both streams copied"  grep -q 'video  copy' <<< "$log"
check "compliant file: audio copied"         grep -q 'audio  copy' <<< "$log"
check "compliant file: default name"         test -f ok-car.mp4
check "compliant file: faststart"            moov_first ok-car.mp4
check "compliant file: video stays h264"     test "$(f ok-car.mp4 v:0 codec_name)" = h264

run --no-usb ok.mp4 >/dev/null 2>&1
check "existing output refused"              test $? -ne 0
run --no-usb --force ok.mp4 >/dev/null 2>&1
check "--force overwrites"                   test $? -eq 0
run --no-usb --force ok.mp4 ok.mp4 >/dev/null 2>&1
check "output == input refused"              test $? -ne 0
check "input untouched after refusal"        test "$(f ok.mp4 v:0 codec_name)" = h264

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
log=$(run --no-usb --force --max-height 1080 full-hd.mp4 2>&1)
check "--max-height 1080: 1080p copied"      grep -q 'video  copy' <<< "$log"
check "--max-height 1080: size kept"         test "$(f full-hd-car.mp4 v:0 width,height)" = "1920,1080"
run --no-usb --force --max-height abc full-hd.mp4 >/dev/null 2>&1
check "--max-height rejects non-numbers"     test $? -ne 0

log=$(run --no-usb silent.mp4 2>&1)
check "no audio: succeeds"                   test -f silent-car.mp4
check "no audio: warns"                      grep -q 'no audio stream' <<< "$log"
check "no audio: video only"                 test "$(streams silent-car.mp4)" = video

run --no-usb level51.mp4 >/dev/null 2>&1
check "level 5.1: re-encoded to <= 4.1"      test "$(f level51-car.mp4 v:0 level)" -le 41
log=$(run --no-usb hdr.mkv 2>&1)
check "HDR source: warns"                    grep -q 'HDR source' <<< "$log"
log=$(run --no-usb --force ok.mp4 2>&1)
check "SDR source: no HDR warning"           not grep -q 'HDR source' <<< "$log"
run --no-usb hi422.mkv >/dev/null 2>&1
check "4:2:2: re-encoded to 4:2:0"           test "$(f hi422-car.mp4 v:0 pix_fmt)" = yuv420p

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

CARIFY_USB_DIR=usb run ok.mp4 out-usb.mp4 >/dev/null 2>&1
check "usb: copied to CARIFY_USB_DIR"        test -f usb/out-usb.mp4
CARIFY_USB_DIR=usb run --no-usb ok.mp4 out-nousb.mp4 >/dev/null 2>&1
check "--no-usb: not copied"                 test ! -e usb/out-nousb.mp4

check "--version"                            grep -Eq '^carify [0-9]+\.[0-9]+\.[0-9]+$' <<< "$(run --version 2>&1 | tr -d '\r')"

if [[ "$target" == bash ]]; then
    CARIFY_BIN="$work/bin" CARIFY_URL="file://$root/carify" sh "$root/install.sh" >/dev/null 2>&1
    check "install.sh: installs a runnable carify"  test "$("$work/bin/carify" --version)" = "$(run --version)"
    CARIFY_BIN="$work/bin2" CARIFY_URL="file://$root/README.md" sh "$root/install.sh" >/dev/null 2>&1
    check "install.sh: rejects a non-carify download" test ! -e "$work/bin2/carify"
fi

echo "$pass passed, $fail failed"
[[ $fail -eq 0 ]]
