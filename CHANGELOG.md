# Changelog

## v1.3.0

Added
- `--dry-run` / `-DryRun`: probe the file and print the plan and the exact ffmpeg command, one argument per line, without converting, writing a file or copying to the stick. A missing input or an existing output without `--force` still fails as in a normal run.

Changed
- Terminal output in `carify` and `carify.ps1` uses the Cyclorama Dawn `v2.1.0` palette (Maritime Beacon orange tags, Glacial Steel info, Mint ok, Amber warn, Signal Crimson errors), keeping `NO_COLOR` and non-TTY plain output intact.

Fixed
- PowerShell: `-Force` onto an output that couldn't be replaced (read-only, or open in a player) said it had written the file, exited 0 and copied the old file to the stick. It now stops with the reason.
- bash: `carify --force movie.mkv MOVIE.MKV` on a disk that ignores case (Windows, macOS) overwrote the input. The same file under another name is now refused, as an identical name already was. carify.ps1 refused it on Windows by comparing names; it now asks whether the two names are one file, so another case on macOS, a link or an 8.3 short name is refused too.
- An output path that is an existing folder: carify.ps1 reported success and wrote nothing, and the bash script left a full-size `.part` file inside the folder. Both now refuse it before converting.
- Converting a file that is already on the stick deleted the result: copying it onto itself failed, and the clean-up after a failed copy removed it. carify now sees it is already there, under whatever name.
- A full-range (`yuvj420p`) source came out full range again, so carify re-encoded its own output on every run. Re-encodes are now written in limited range.
- Two runs writing the same output at once both reported success, and only one conversion survived: they wrote the same hidden `.part` file. Each run's `.part` now has its process ID in its name, and without `--force` the run that finishes second stops with "output already exists" instead of replacing the other's file. The bash script also cleans up its `.part` when the terminal is closed.
- `install.ps1` run as `powershell -ExecutionPolicy Bypass -File .\install.ps1`, the offline route, never set the execution policy it promised: it read the policy of its own process, which `-ExecutionPolicy Bypass` sets to Bypass. It now reads the policy saved for the user or the machine, so on a Restricted machine `carify` runs afterwards, and says so: Set-ExecutionPolicy reports that the process's Bypass overrides the new setting, which install.ps1 used to print as a failure.
- bash: options after the file names, such as `carify movie.mkv --no-usb`, were taken as the output name. They are now options, as in carify.ps1; after `--` everything is a file name.
- bash under Git Bash on Windows: ffprobe's CRLF line ends made every file look 99999x99999, so everything was re-encoded. The line ends are now stripped.

Tests
- `tests/run.sh` has checks for each fix above, and more for carify.ps1: the MOVIES drive search and the FAT32 4 GB limit (with `Get-CimInstance` and the output's size stood in for), colour on a console, the size shown, a failed copy's reason, the help syntax and more. `install.ps1`'s policy is checked by running only its two policy functions, with stand-ins for `Get-ExecutionPolicy` and `Set-ExecutionPolicy` on made-up scopes, so nothing is changed.
- `tests/dry-run.sh` checks the dry run, and CI runs it on every target.
- `tests/run.sh` passes from Git Bash on Windows: the faststart check falls back to the `py` launcher when `python3` and `python` are the Store's stubs, and the `install.sh` checks give curl a `file:///C:/...` URL.

Docs
- README: who it's for first, an Install section per system with what each installer changes and how to undo it, offline steps with ffmpeg, how to run either script from a clone, then usage and the details.
- CONTRIBUTING lists everything the tests need and the Windows PowerShell 5.1 target.
- The README cluster's ghost needles, where the input was, are drawn at .8 opacity instead of .5, so they can be seen on both themes.
- Project page: the cluster is on the first screen at every width, and the four recorded files are a switch strip along the cluster's plate.

## v1.2.0

`carify` and `carify.ps1` are unchanged apart from the version number. This release adds downloads for a machine with no network.

Added
- `carify-1.2.0-offline.zip`: both scripts, both installers, the README, the licence and this changelog. Unzip it and run `sh ./install.sh`, or `powershell -ExecutionPolicy Bypass -File .\install.ps1`, in the folder. ffmpeg isn't in it.
- `install.sh` and `install.ps1`, run as files from a folder that also holds `carify` or `carify.ps1`, install that copy instead of downloading one. Piped to `sh` or `iex`, or with `CARIFY_URL` or `CARIFY_REF` set, they download as before.
- `carify-1.2.0-dev-windows-x64.zip`, for working on carify on Windows with no network: the repo, PSScriptAnalyzer, the Python packages the art script uses, and `offline\setup.ps1`, which checks the toolchains and sets up from the kit. CONTRIBUTING.md has the steps.
- `SHA256SUMS.txt`, the SHA-256 of every file in the release.

Tests
- The `offline` workflow builds both zips and runs each from a fresh folder with the network cut off: the installers and a conversion from the offline zip, and the tests, lint and art check from the dev kit. The release runs it before publishing.
- `tests/run.sh` checks the installers both ways, and uses a Python that runs (on Windows, `python3` can be the Store's stub).
- CI's versions are pinned in `tools/versions.env`: ShellCheck 0.11.0 (it used the runner's), Python 3.13.17 for the art job and ffmpeg 9.0.2 on Windows.

Docs
- The runs the README and the project page replay are recorded again with carify 1.2.0, so their timings changed: road-trip.mkv took 6.6 s this time, against 7.5 s.

## v1.1.2

`carify`, `carify.ps1` and the installers are unchanged apart from the version number. This release is the new README and project page.

Docs
- New README and project page: an instrument cluster replays four real carify runs, with the head unit's limits as redlines. The runs are recorded in CI from generated test clips, so every timing, size and output line shown is one carify printed. The old cover's example timings and sizes were not from a real run.
- CI: the `art` job records the runs again on every push, fails if carify's output changes, and redraws the README cluster; a `links` workflow checks the links monthly.

## v1.1.1

The `v1.1.0` tag was made before these fixes landed, so its scripts still have the bugs below. Use this release instead.

Fixed
- PowerShell 7 on Linux/macOS: a file name containing a colon was read as a drive and the run failed. `carify.ps1` now handles paths with .NET instead of PowerShell's providers.
- PowerShell: when the copy to the stick fails, the message gives the underlying reason (disk full, file too large) instead of a generic error.

Tests
- `tests/run.sh` passes on Windows (ffprobe's CRLF output) and with newer ffmpeg (the HDR fixture sets its colour flags in the HEVC stream too).

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
