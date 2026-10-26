# Changelog

## v1.1.0

Added
- `--max-height` / `-MaxHeight` (default 720) replaces editing the 1280 limit in the script.
- `--version` / `-Version`.
- `CARIFY_USB_DIR` to copy to a folder other than a MOVIES stick.
- `install.sh` and `install.ps1`.
- Warning for HDR sources, which are not tone-mapped.
- Colour status output (respects `NO_COLOR`; `CARIFY_THEME=dayshift` for light terminals).
- `tests/run.sh` and CI on Ubuntu, macOS and Windows.

Changed
- Portrait and square video is now scaled to fit 1280x720. Before, only width was checked, so a 1080x1920 phone video was copied unchanged.
- H.264 above level 4.1 is re-encoded; re-encodes are written at level 4.1.
- Files with no audio track are converted silent instead of refused.
- Status lines go to stderr; ffmpeg prints warnings and a progress line instead of its full log.

Fixed
- An interrupted or failed run left a partial output file, which then blocked the next run. Output is now written to a `.part` file and renamed.
- `carify movie.mkv movie.mkv --force` overwrote the input while reading it. Now refused.
- Cover art stored as a video stream could be picked instead of the film.
- bash: a file without an extension in a folder with a dot (`dir.v1/movie`) got an output name of `dir-car.mp4`.
- bash: file names starting with `-` or containing `:` were read as ffprobe options or protocols.
- bash: exited with "unbound variable" when `$USER` was unset (cron, some containers).
- Both: a width or channel count of `N/A` from ffprobe crashed the comparison (bash: "N: unbound variable").
- A failed USB copy left a partial file on the stick. It is now removed, with a hint when the stick is FAT32 and the file is over 4 GB.
- PowerShell: error messages go to stderr. `Get-Volume` replaced with CIM on Windows and the same mount paths as bash on Linux/macOS, so `carify.ps1` also runs under PowerShell 7 there.
- PowerShell: on a FAT32 MOVIES drive, a file over 4 GB is refused before copying instead of failing part-way.

## v1.0.0

First release: `carify` (bash) and `carify.ps1` (PowerShell).
