# carify

Convert any video so it plays from a USB stick on a Chrysler / Jeep / Dodge / Ram **Uconnect** head unit.

Uconnect is picky: it wants 8-bit H.264 (Baseline/Main/High profile, 720p or smaller) with AAC stereo audio in an MP4. `carify` probes your file with `ffprobe`, re-encodes only the streams that don't comply, and leaves the rest untouched. A file that's already compatible finishes in seconds; a 10-bit HEVC rip gets a proper re-encode.

Two drop-in scripts, same behaviour:

| Name| Description |
|---|---|
| `carify` | bash — Linux, macOS, WSL |
| `carify.ps1` | PowerShell — Windows |

## Requirements

[ffmpeg](https://ffmpeg.org/) on your PATH.

- Windows: `winget install Gyan.FFmpeg` (open a new terminal afterwards)
- Debian/Ubuntu: `sudo apt install ffmpeg`
- Fedora: `sudo dnf install ffmpeg`
- macOS: `brew install ffmpeg`

## Install

**Linux / macOS**

```bash
mkdir -p ~/.local/bin
curl -o ~/.local/bin/carify https://raw.githubusercontent.com/Real-Fruit-Snacks/carify/main/carify
chmod +x ~/.local/bin/carify
```

**Windows**

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned   # once, allows local scripts
mkdir $HOME\bin -Force
Invoke-WebRequest https://raw.githubusercontent.com/Real-Fruit-Snacks/carify/main/carify.ps1 -OutFile $HOME\bin\carify.ps1
```

Add `$HOME\bin` to your PATH (Settings → System → About → Advanced system settings → Environment Variables → User `Path`). Optionally, so you can type `carify` without the extension, add to your `$PROFILE`:

```powershell
function carify { & "$HOME\bin\carify.ps1" @args }
```

## Usage

```
carify [options] <video> [output.mp4]
```

```bash
carify movie.mkv                     # -> movie-car.mp4 next to the input
carify movie.mkv ~/out.mp4           # explicit output path
carify --force movie.mkv             # overwrite an existing output
carify --no-usb movie.mkv            # skip the USB copy
```

PowerShell uses `-Force` and `-NoUsb` instead of `--force` and `--no-usb`.

If a USB stick with the volume label **`MOVIES`** is plugged in, the result is copied onto it automatically. Rename the stick once (right-click → Properties on Windows, or your file manager's rename on Linux/macOS) and you never have to drag files again.

## What it actually does

1. Probes video codec, pixel format, H.264 profile and width; audio codec and channel count.
2. **Video** is copied as-is when it's `h264` + `yuv420p` + Baseline/Main/High profile + width ≤ 1280. Otherwise it's re-encoded with `libx264 -preset veryfast -crf 20 -profile:v high`, scaled down to 1280 wide if larger (never upscaled).
3. **Audio** is copied as-is when it's AAC with ≤ 2 channels. Otherwise it's re-encoded to AAC stereo at 160 kbps.
4. Keeps only the first video and first audio stream; subtitles and extra audio tracks are dropped.
5. Writes an MP4 with `-movflags +faststart` so the head unit can start playback before reading the whole file.

## Tested on

- *(add your vehicle and Uconnect version here, e.g. "2019 Pacifica, Uconnect 4C")*

Uconnect behaviour varies by model year and head-unit generation. The 720p H.264 + AAC stereo target is the common denominator that has worked across generations; if your unit handles 1080p, raise the `1280` limit in the script.

## License

[MIT](LICENSE)
