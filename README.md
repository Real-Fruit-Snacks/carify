# carify

Convert video for Uconnect USB playback, via ffmpeg

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/assets/cluster-dark.svg">
  <img alt="An instrument cluster replaying two carify runs. road-trip.mkv comes in 1080 pixels high with 6 audio channels, both needles past their redlines; when the re-encoded file is written they drop to 720 and 2, and the file is copied to the stick. Then cartoons.mkv: the video is already 720 and is copied, and only the audio needle drops from 6 to 2" src="docs/assets/cluster-light.svg" width="100%">
</picture>

```sh
curl -fsSL https://raw.githubusercontent.com/Real-Fruit-Snacks/carify/main/install.sh | sh
```

- **Stream-copy when compliant:** Probes with `ffprobe` and re-encodes only streams that fail Uconnect's common denominator (8-bit H.264 `yuv420p` ≤ 720p High@L4.1 + AAC stereo 160k), copying compliant video or audio untouched.
- **Safe atomic writes:** Writes `<name>-car.mp4` beside the original via a `.part` file with `+faststart`; never alters the source video.
- **Auto USB copy:** Copies the finished MP4 onto a mounted drive labelled **MOVIES** (`--no-usb` / `-NoUsb` turns it off).
- **Cross-platform & offline:** Ships matching Bash (`carify`) and PowerShell (`carify.ps1`) scripts with zero network calls and offline release zips.

## Documentation

- [Project Page & Interactive Replays](https://real-fruit-snacks.github.io/carify/)
- [Install (Windows/macOS/Linux/Offline), CLI Options & Known Issues](docs/USAGE.md)
- [Changelog](CHANGELOG.md) · [Contributing](CONTRIBUTING.md)

## License

[MIT](LICENSE)
