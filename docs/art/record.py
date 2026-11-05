"""Record the carify runs that the README cluster and the project page replay.

Makes four short test clips with ffmpeg's testsrc2 and sine sources, one for each thing carify
does to a file, runs carify on each the way a user would, and writes what it printed, how long
it took, and ffprobe of the input and the output to docs/art/runs.json.

    python3 docs/art/record.py                       # record into docs/art/runs.json
    python3 docs/art/record.py --out other.json      # record somewhere else
    python3 docs/art/record.py --check a.json b.json # same runs? (ignores timing and sizes)

Needs bash, and ffmpeg/ffprobe with libx264, libx265 and ac3. If a folder named MOVIES is
mounted where carify looks for the stick (/media/$USER/MOVIES and so on), carify copies
each result onto it, as it would for you. CI records on ubuntu-24.04 and checks the result
against the committed runs.json, so the README never shows output carify no longer prints.
"""
import argparse
import json
import os
import platform
import re
import shutil
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
SECONDS = 30

# name, file, why it's here, the ffmpeg output options that make it (inputs are testsrc2 + sine)
CLIPS = [
    ("road-trip", "road-trip.mkv", "won't play: HEVC 10-bit 1080p with AC3 5.1",
     "1920x1080", 24, ["-c:v", "libx265", "-preset", "ultrafast", "-pix_fmt", "yuv420p10le",
                       "-x265-params", "log-level=error", "-c:a", "ac3", "-ac", "6"]),
    ("cartoons", "cartoons.mkv", "plays without sound: H.264 720p with AC3 5.1",
     "1280x720", 24, ["-c:v", "libx264", "-preset", "veryfast", "-profile:v", "high", "-pix_fmt", "yuv420p",
                      "-c:a", "ac3", "-ac", "6"]),
    ("phone-video", "phone-video.mp4", "too tall: portrait 1080x1920 H.264 with AAC stereo",
     "1080x1920", 30, ["-c:v", "libx264", "-preset", "veryfast", "-profile:v", "high", "-pix_fmt", "yuv420p",
                       "-c:a", "aac", "-ac", "2"]),
    ("dashcam", "dashcam.mp4", "already fine: H.264 720p with AAC stereo",
     "1280x720", 30, ["-c:v", "libx264", "-preset", "veryfast", "-profile:v", "main", "-pix_fmt", "yuv420p",
                      "-c:a", "aac", "-ac", "2"]),
]


def run(cmd, **kw):
    return subprocess.run(cmd, check=True, capture_output=True, text=True, **kw)


def probe(path):
    """The first video and audio stream, as carify sees them, plus the file's size and length."""
    out = run(["ffprobe", "-v", "error", "-show_entries",
               "stream=codec_type,codec_name,profile,level,pix_fmt,width,height,channels,channel_layout,color_transfer"
               ":format=duration,size", "-of", "json", "file:" + path]).stdout
    data = json.loads(out)
    info = {"bytes": int(data["format"]["size"]), "duration": round(float(data["format"]["duration"]), 2)}
    for s in data["streams"]:
        kind = s.get("codec_type")
        if kind in ("video", "audio") and kind not in info:
            keep = ("codec_name", "profile", "level", "pix_fmt", "width", "height", "color_transfer") if kind == "video" \
                else ("codec_name", "profile", "channels", "channel_layout")
            info[kind] = {k: s[k] for k in keep if k in s}
    return info


def screen(stderr):
    """What a terminal is left showing: ffmpeg redraws its progress line with \\r."""
    lines = []
    for raw in stderr.replace("\r\n", "\n").split("\n"):
        parts = [p for p in raw.split("\r") if p.strip()]
        if parts:
            lines.append(parts[-1].rstrip())
    return lines


def record(out_path):
    for tool in ("ffmpeg", "ffprobe", "bash"):
        if not shutil.which(tool):
            sys.exit(f"{tool} not found")
    bash = shutil.which("bash")
    carify = os.path.join(ROOT, "carify")
    env = dict(os.environ, NO_COLOR="1")
    env.pop("CARIFY_USB_DIR", None)
    os_name = platform.platform()
    if os.path.exists("/etc/os-release"):
        with open("/etc/os-release", encoding="utf-8") as fh:
            m = re.search(r'^PRETTY_NAME="?([^"\n]+)', fh.read(), re.M)
            os_name = m.group(1) if m else os_name
    result = {
        "recorded": {
            "os": os_name,
            "ffmpeg": run(["ffmpeg", "-version"]).stdout.splitlines()[0],
            "bash": run([bash, "-c", "echo $BASH_VERSION"]).stdout.strip(),
            "carify": run([bash, carify, "--version"]).stdout.strip(),
            "clips": f"{SECONDS} s of ffmpeg's testsrc2 picture and a sine tone",
        },
        "runs": [],
    }
    work = tempfile.mkdtemp(prefix="carify-record.")
    try:
        for name, fname, why, size, rate, opts in CLIPS:
            make = ["ffmpeg", "-hide_banner", "-loglevel", "error", "-nostdin", "-y",
                    "-f", "lavfi", "-i", f"testsrc2=size={size}:rate={rate}:duration={SECONDS}",
                    "-f", "lavfi", "-i", f"sine=frequency=330:duration={SECONDS}:sample_rate=48000",
                    "-map", "0:v", "-map", "1:a", *opts, fname]
            run(make, cwd=work)
            t0 = time.monotonic()
            p = subprocess.run([bash, carify, fname], cwd=work, env=env, capture_output=True, text=True)
            took = time.monotonic() - t0
            if p.returncode != 0:
                sys.exit(f"carify failed on {fname} (exit {p.returncode}):\n{p.stderr}")
            out_name = os.path.splitext(fname)[0] + "-car.mp4"
            result["runs"].append({
                "name": name,
                "file": fname,
                "why": why,
                "cmd": f"carify {fname}",
                "lines": screen(p.stderr),
                "seconds": round(took, 1),
                "in": probe(os.path.join(work, fname)),
                "out": probe(os.path.join(work, out_name)),
            })
            print(f"{fname}: {took:.1f} s", file=sys.stderr)
    finally:
        shutil.rmtree(work, ignore_errors=True)
    with open(out_path, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(result, fh, indent=1, sort_keys=True)
        fh.write("\n")
    print(f"wrote {out_path}", file=sys.stderr)


def stable(data):
    """The parts of a recording that don't change from run to run: no timings, sizes or progress."""
    keep = []
    for r in data["runs"]:
        lines = []
        for line in r["lines"]:
            if line.startswith("frame="):
                line = "frame=..."
            lines.append(re.sub(r"\(\d+ (KB|MB)\)$", "(...)", line))
        side = lambda d: {k: v for k, v in d.items() if k not in ("bytes",)}
        keep.append({"name": r["name"], "cmd": r["cmd"], "lines": lines, "in": side(r["in"]), "out": side(r["out"])})
    return keep


def check(a_path, b_path):
    with open(a_path, encoding="utf-8") as fa, open(b_path, encoding="utf-8") as fb:
        a, b = stable(json.load(fa)), stable(json.load(fb))
    if a == b:
        print(f"{a_path} matches a fresh recording ({len(a)} runs)")
        return
    import difflib
    sa = json.dumps(a, indent=1, sort_keys=True).splitlines()
    sb = json.dumps(b, indent=1, sort_keys=True).splitlines()
    print("\n".join(difflib.unified_diff(sa, sb, a_path, b_path, lineterm="")))
    sys.exit(f"{a_path} no longer matches what carify prints; run docs/art/record.py and commit the result")


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--out", default=os.path.join(HERE, "runs.json"))
    ap.add_argument("--check", nargs=2, metavar=("COMMITTED", "FRESH"))
    args = ap.parse_args()
    if args.check:
        check(*args.check)
    else:
        record(args.out)
