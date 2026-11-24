# Design: the carify page (`docs/`) and README cluster

## Concept

carify's whole job is fitting a video under a line: the head unit plays 8-bit H.264 at 720p or smaller with AAC stereo, and anything over that is re-encoded down to it. So the page is a car's instrument cluster, and the head unit's limits are the Signal Crimson redlines. Two dials, frame height and audio channels, flank a centre screen, the way a speedometer and a rev counter flank a cluster's info display. A file's real stream values sit on the dials; carify's run brings each needle back under its redline, or leaves it where it is when it already fits.

## Brand System

Built on **Cyclorama Dawn `v2.1.0`** (`Real-Fruit-Snacks/rfs-brand`):
- **Default mode:** Beacon Horizon Dark (`LX 263`, matte `#050507`) with opt-in Alabaster Day Light (`LX 512`, `#F5F7F9`) toggle synced across tabs via `localStorage['rfs-theme']`.
- **Two chromatic poles:** Glacial Steel (`#1F547A` / `#74B8E8` / `#164669`) and Maritime Beacon Orange (`#F06E2B` / `#FF9254` / `#AD3D0A`), interpolated strictly in Cartesian `in oklab`.
- **Semantic signals:** Mint (`#3DDC97` / `#127247`) for `Fits` and `[ok]`, Amber (`#FFC247` / `#885800`) for warnings, and **Signal Crimson** (`#FF5C6C` / `#B91C2E`) for the gauge redlines, `Over`, ghost needles, limit table divider, and CLI errors.
- **Typography:** Self-hosted variable WOFF2 only — `Big Shoulders Stencil` (display titles, section headings, dial readouts), `Albert Sans` (UI and prose), and `Azeret Mono` (commands, terminal output, instrument telemetry).
- **Shell & scrollbars:** Uses `.rfs-shell` + `.rfs-shell-header` + `.rfs-scroll-region` so the vertical scrollbar begins strictly below the header hairline.

## README cluster & CI check

`docs/art/make-art.py` draws `docs/assets/cluster-{dark,light}.svg` with text converted to paths from `docs/fonts/`, writes `docs/runs.js`, and fills the `<!-- art:* -->` markers in `docs/index.html` and `README.md`.

`docs/art/record.py` generates four test clips with ffmpeg and records carify on each. `.github/workflows/test.yml` (`art` job) re-records them on Ubuntu 24.04, checks `docs/art/runs.json`, runs `docs/art/make-art.py`, and verifies zero git diff.

## Cover & social preview

`docs/assets/cover-{dark,light}.{svg,png}` and `docs/assets/social-{dark,light}.png` are generated from `docs/assets/cover.toml` using `rfs-brand/tools/make-cover.py`.
