#!/usr/bin/env bash
# Checks --dry-run (-DryRun): the probe and plan lines on stderr, the ffmpeg command on stdout,
# one argument per line, and nothing run, written or copied.
# usage: tests/dry-run.sh [bash|pwsh|powershell]   (default bash)
# CARIFY_BASH=/bin/bash picks the interpreter for the bash target.
# The checks are strings run by eval, so the $ in them is meant to wait (SC2016) and the want_*
# values they compare against look unused (SC2034).
# shellcheck disable=SC2016,SC2034
set -uo pipefail

target="${1:-bash}"
root=$(cd -- "$(dirname -- "$0")/.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/carify-dry-run.XXXXXX")
trap 'rm -rf -- "$work"' EXIT
export NO_COLOR=1
unset CARIFY_USB_DIR CARIFY_URL CARIFY_REF

pass=0 fail=0
check() {  # check <name> <condition...>
    local name="$1"; shift
    if "$@"; then pass=$((pass + 1)); printf 'ok %s\n' "$name"
    else fail=$((fail + 1)); printf 'FAIL %s\n' "$name"; fi
}

# Run carify with bash-style flags; translated for the PowerShell script.
run() {
    case "$target" in
        bash) "${CARIFY_BASH:-bash}" "$root/carify" "$@" ;;
        pwsh|powershell)
            local args=()
            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --dry-run) args+=(-DryRun) ;;
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

# dry <name> <carify args...>: run carify, keep its stdout, stderr (CR dropped) and exit code under <name>
logs="$work/logs"
dry() {
    local name="$1"; shift
    run "$@" >"$logs/$name.o" 2>"$logs/$name.e"
    echo $? >"$logs/$name.rc"
    tr -d '\r' <"$logs/$name.o" >"$logs/$name.out"
    tr -d '\r' <"$logs/$name.e" >"$logs/$name.err"
}
code() { cat "$logs/$1.rc"; }
# the probe, plan and warning lines of a run's stderr
planned() { grep -E '^(probe|video|audio|warn) ' "$logs/$1.err"; }
errors() { grep -E '^error ' "$logs/$1.err"; }
# stdout with each file: argument cut down to its file name (each script spells the folder its own way),
# and the run's process ID taken out of the temp file's name (.ok-car.mp4.1234.part)
args() { sed -E 's#^file:.*[/\\]#file:#; s#\.[0-9]+\.part$#.part#' "$logs/$1.out"; }
# the stdout lines between -map 0:V:0 and -sn
between() { awk '$0 == "-sn" { f = 0 } f; $0 == "0:V:0" { f = 1 }' "$logs/$1.out"; }
before_sn() { awk '$0 == "-sn" { print prev; exit } { prev = $0 }' "$logs/$1.out"; }
input_arg() { awk 'p { print; exit } $0 == "-i" { p = 1 }' "$logs/$1.out"; }
output_arg() { tail -n 1 "$logs/$1.out"; }
path_of() { sed -E 's#^file:##' <<< "$1"; }
folder_of() {
    local p; p=$(path_of "$1")
    case "$p" in
        */*|*\\*) sed -E 's#[/\\][^/\\]*$##' <<< "$p" ;;
        *) echo . ;;
    esac
}
name_of() { sed -E 's#^.*[/\\]##; s#\.[0-9]+\.part$#.part#' <<< "$(path_of "$1")"; }
# no_part <output>: no hidden temp file of any run beside <output>
no_part() { local p=("$(dirname -- "$1")/.$(basename -- "$1")".*part); [[ ! -e "${p[0]}" ]]; }
lines() { printf '%s\n' "$@"; }
empty_dir() { [[ -d "$1" && -z "$(ls -A "$1")" ]]; }

# the ffmpeg command, one argument per line
cmd_head() { lines ffmpeg -hide_banner -nostdin -loglevel warning -stats -y -i "file:$1" -map 0:V:0; }
cmd_tail() { lines -sn -dn -map_metadata 0 -movflags +faststart -f mp4 "file:$1"; }
scale720="scale=w='min(1280,iw)':h='min(720,ih)':force_original_aspect_ratio=decrease:force_divisible_by=2:out_range=tv"
scale1080="scale=w='min(1920,iw)':h='min(1080,ih)':force_original_aspect_ratio=decrease:force_divisible_by=2:out_range=tv"
reencode() {
    lines -c:v libx264 -preset veryfast -crf 20 -profile:v high -level:v 4.1 -pix_fmt yuv420p -color_range tv -vf "$1" \
        -map 0:a:0 -c:a aac -ac 2 -b:a 160k
}
want_ok=$(cmd_head ok.mp4; lines -c:v copy -map 0:a:0 -c:a copy; cmd_tail .ok-car.mp4.part)
want_hevc=$(cmd_head hevc10.mkv; reencode "$scale720"; cmd_tail .hevc10-car.mp4.part)
want_hevc_between=$(reencode "$scale720")
want_silent=$(cmd_head silent.mp4; lines -c:v copy -an; cmd_tail .silent-car.mp4.part)
want_fhd=$(cmd_head full-hd.mp4; lines -c:v copy -map 0:a:0 -c:a copy; cmd_tail .full-hd-car.mp4.part)

gen() {  # gen <out> <ffmpeg output options...>
    local out="$1"; shift
    ffmpeg -hide_banner -loglevel error -nostdin -y \
        -f lavfi -i "testsrc2=size=${SIZE:-640x360}:rate=24:duration=2" \
        -f lavfi -i "sine=frequency=440:duration=2:sample_rate=48000" \
        "$@" "$out"
}

cd "$work" || exit 1
mkdir -p "$logs"
echo "target: $target  ($(ffmpeg -version | head -n1 | cut -d' ' -f1-3))"
echo "fixtures..."
gen ok.mp4      -map 0:v -map 1:a -c:v libx264 -profile:v high -pix_fmt yuv420p -c:a aac -ac 2
gen hevc10.mkv  -map 0:v -map 1:a -c:v libx265 -pix_fmt yuv420p10le -x265-params log-level=error \
                -c:a ac3 -ac 6 -s 1920x1080
SIZE=1920x1080 gen full-hd.mp4  -map 0:v -map 1:a -c:v libx264 -profile:v high -level:v 4.1 -pix_fmt yuv420p -c:a aac -ac 2
gen silent.mp4  -map 0:v -c:v libx264 -pix_fmt yuv420p
head -c 50000 /dev/urandom > broken.mkv
cp ok.mp4 "my movie.mp4"
mkdir -p a3/usb exists normal
cp ok.mp4 a3/ok.mp4
cp ok.mp4 exists/ok.mp4
printf 'an earlier conversion\n' > exists/ok-car.mp4
cp exists/ok-car.mp4 "$logs/ok-car.mp4.before"
cp silent.mp4 normal/silent.mp4

echo "runs..."
dry ok          --dry-run --no-usb ok.mp4
dry hevc        --dry-run --no-usb hevc10.mkv
dry hevc1080    --dry-run --no-usb --max-height 1080 hevc10.mkv
dry silent      --dry-run --no-usb silent.mp4
dry fhd_first   --dry-run --no-usb --max-height 1080 full-hd.mp4
dry fhd_last    --no-usb --max-height 1080 --dry-run full-hd.mp4
dry spaces      --dry-run --no-usb "my movie.mp4"
dry missing     --dry-run --no-usb missing.mp4
dry broken      --dry-run --no-usb broken.mkv
dry broken_real --no-usb broken.mkv
(cd normal && dry silent_real --no-usb silent.mp4)
(cd a3 && CARIFY_USB_DIR=usb dry a3 --dry-run ok.mp4)
(cd a3 && CARIFY_USB_DIR=usb dry a3_out --dry-run ok.mp4 out.mp4)
(cd exists && dry exists --dry-run --no-usb ok.mp4)
(cd exists && dry exists_force --dry-run --no-usb --force ok.mp4)

echo "cases..."
check "ok.mp4: exits 0 with the probe, video and audio lines on stderr" eval '
    [[ $(code ok) -eq 0 ]] &&
    [[ "$(planned ok)" == "$(lines "probe  video h264/yuv420p/High 640x360  audio aac 2ch" "video  copy" "audio  copy")" ]]'
check "hevc10.mkv: re-encode plan lines for video and audio" eval '
    [[ $(code hevc) -eq 0 ]] &&
    [[ "$(grep -E "^(video|audio) " "$logs/hevc.err")" == "$(lines "video  re-encode to H.264 High 8-bit, fits 1280x720 (slow)" "audio  re-encode to AAC stereo 160k")" ]]'
check "no audio stream: warns and still exits 0" eval '
    [[ $(code silent) -eq 0 ]] && grep -Fxq "warn   no audio stream; the output will be silent" "$logs/silent.err"'
check "no audio stream: same plan and warning lines as a normal run, in order" eval '
    [[ $(code silent) -eq 0 ]] && [[ -n "$(planned silent_real)" ]] &&
    [[ "$(planned silent)" == "$(planned silent_real)" ]]'
check "--max-height 1080 full-hd.mp4: video copy" eval '
    [[ $(code fhd_first) -eq 0 ]] && grep -Fxq "video  copy" "$logs/fhd_first.err"'
check "--dry-run before or after the other options: same output" eval '
    [[ $(code fhd_first) -eq 0 && $(code fhd_last) -eq 0 ]] && grep -Fxq "video  copy" "$logs/fhd_last.err" &&
    [[ "$(args fhd_first)" == "$(args fhd_last)" ]] && cmp -s "$logs/fhd_first.err" "$logs/fhd_last.err"'

check "ok.mp4: stdout is the ffmpeg command, one argument per line" eval '
    [[ $(code ok) -eq 0 ]] && [[ "$(args ok)" == "$want_ok" ]]'
check "ok.mp4: last argument is the hidden .part file in the output folder" eval '
    [[ "$(name_of "$(output_arg ok)")" == .ok-car.mp4.part ]] && [[ "$(folder_of "$(output_arg ok)")" -ef . ]]'
check "hevc10.mkv: re-encode arguments between -map 0:V:0 and -sn" eval '
    [[ "$(between hevc)" == "$want_hevc_between" ]]'
check "hevc10.mkv: -vf value is one argument line, quotes and colons kept" grep -Fxq "$scale720" "$logs/hevc.out"
check "no audio stream: -an where the audio arguments go" eval '
    [[ "$(before_sn silent)" == -an ]] && ! grep -Eq "^(-c:a|0:a:0)$" "$logs/silent.out"'
check "--max-height 1080 hevc10.mkv: scale fits 1920x1080" grep -Fxq "$scale1080" "$logs/hevc1080.out"
check "name with spaces: input is one file: line" eval '
    [[ $(code spaces) -eq 0 ]] && grep -Eq "^file:(.*[/\\\\])?my movie\\.mp4$" <<< "$(input_arg spaces)"'

check "dry run: no output file written" eval '
    [[ $(code a3) -eq 0 ]] && grep -Fxq ffmpeg "$logs/a3.out" && test ! -e a3/ok-car.mp4'
check "dry run: no hidden .part file written" eval '
    [[ $(code a3) -eq 0 ]] && grep -Fxq ffmpeg "$logs/a3.out" && no_part a3/ok-car.mp4'
check "dry run: nothing copied to CARIFY_USB_DIR without --no-usb" eval '
    [[ $(code a3) -eq 0 ]] && grep -Fxq ffmpeg "$logs/a3.out" && empty_dir a3/usb'
check "dry run with an output name: no out.mp4" eval '
    [[ $(code a3_out) -eq 0 ]] && grep -Fxq ffmpeg "$logs/a3_out.out" && test ! -e a3/out.mp4 && empty_dir a3/usb'
check "dry run: no wrote or usb line" eval '
    [[ $(code a3) -eq 0 ]] && grep -q "^probe " "$logs/a3.err" && ! grep -Eq "^(wrote|usb) " "$logs/a3.err"'

check "hevc10.mkv: probe and plan lines" eval '
    [[ "$(planned hevc)" == "$(lines "probe  video hevc/yuv420p10le/Main 10 1920x1080  audio ac3 6ch" "video  re-encode to H.264 High 8-bit, fits 1280x720 (slow)" "audio  re-encode to AAC stereo 160k")" ]]'
check "hevc10.mkv: ffmpeg arguments" eval '[[ "$(args hevc)" == "$want_hevc" ]]'
check "silent.mp4: probe, plan and warning lines" eval '
    [[ "$(planned silent)" == "$(lines "probe  video h264/yuv420p/High 640x360  audio none" "video  copy" "warn   no audio stream; the output will be silent")" ]]'
check "silent.mp4: ffmpeg arguments, -an included" eval '[[ "$(args silent)" == "$want_silent" ]]'
check "--max-height 1080 full-hd.mp4: plan lines" eval '
    [[ "$(grep -E "^(video|audio) " "$logs/fhd_first.err")" == "$(lines "video  copy" "audio  copy")" ]]'
check "--max-height 1080 full-hd.mp4: ffmpeg arguments" eval '[[ "$(args fhd_first)" == "$want_fhd" ]]'
check "file: lines name the input file and its temp file" eval '
    [[ "$(path_of "$(input_arg hevc)")" -ef hevc10.mkv ]] &&
    [[ "$(name_of "$(output_arg hevc)")" == .hevc10-car.mp4.part ]] && [[ "$(folder_of "$(output_arg hevc)")" -ef . ]]'

check "missing input: non-zero exit, file not found" eval '
    [[ $(code missing) -ne 0 ]] && grep -Fq "file not found: missing.mp4" "$logs/missing.err"'
check "existing output: refused with output already exists, left unchanged" eval '
    [[ $(code exists) -ne 0 ]] && grep -q "^error .*output already exists" "$logs/exists.err" &&
    cmp -s exists/ok-car.mp4 "$logs/ok-car.mp4.before"'
check "existing output with --force: plan printed, exit 0" eval '
    [[ $(code exists_force) -eq 0 ]] && grep -Fxq "video  copy" "$logs/exists_force.err" &&
    grep -Fxq ffmpeg "$logs/exists_force.out"'
check "existing output with --force: left unchanged" eval '
    [[ $(code exists_force) -eq 0 ]] && cmp -s exists/ok-car.mp4 "$logs/ok-car.mp4.before"'
check "unreadable input: fails as a normal run does, nothing written" eval '
    [[ $(code broken) -ne 0 ]] && test ! -e broken-car.mp4 && no_part broken-car.mp4 &&
    [[ -n "$(errors broken_real)" ]] && [[ "$(errors broken)" == "$(errors broken_real)" ]]'

help_lists_dry_run() {
    local out
    if [[ "$target" == bash ]]; then
        out=$(run --help 2>&1) && grep -q -- '--dry-run' <<< "$out"
    else
        out=$(cd "$root" && "$target" -NoProfile -ExecutionPolicy Bypass -Command "Get-Help ./carify.ps1 -Parameter DryRun" 2>&1) &&
        tr -d '\r' <<< "$out" | awk '
            /^-DryRun/ { p = 1; next }
            p && /Required\?/ { exit }
            p && NF { found = 1 }
            END { exit !found }'
    fi
}
check "help describes the dry-run option" help_lists_dry_run

echo "$pass passed, $fail failed"
[[ $fail -eq 0 ]]
