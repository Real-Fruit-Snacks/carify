# Contributing

Bug reports and pull requests are welcome.

- `carify` and `carify.ps1` must behave the same. A change to one needs the matching change to the other.
- `carify` has to run on macOS's `/bin/bash` 3.2: no associative arrays, no `mapfile`, no `${var,,}`.
- `carify.ps1` has to run on Windows PowerShell 5.1 and stay ASCII.
- Run the tests before opening a PR. They need ffmpeg with libx264 and libx265, Python 3 as `python3`, `python` or `py` (the faststart check reads the MP4 with it), and [ShellCheck](https://www.shellcheck.net/) for the lint. `tests/run.sh pwsh` needs PowerShell 7 (`pwsh`); without it most checks fail instead of the run saying `pwsh` is missing. `tests/run.sh powershell` tests Windows PowerShell 5.1. On Windows, run these from Git Bash.

```sh
shellcheck carify install.sh tests/run.sh tests/dry-run.sh
tests/run.sh bash
tests/run.sh pwsh
tests/run.sh powershell   # Windows only: Windows PowerShell 5.1
tests/dry-run.sh bash     # and pwsh, powershell: --dry-run / -DryRun
```

- A new behaviour gets a check in `tests/run.sh` (`tests/dry-run.sh` for the dry run).
- Versions CI installs (PSScriptAnalyzer, Python, ShellCheck, the Windows ffmpeg) are pinned in `tools/versions.env`, and the art script's Python packages in `docs/art/requirements.txt`. Change them there; CI and the dev kit both read those files.
- If a file played or failed on your car, say which model year and head unit. That is the data this project is short of.

## Developing offline

Each release has `carify-<version>-dev-windows-x64.zip`, for working on carify on a Windows x64 machine with no network. It unzips to one folder, `carify-<version>-dev`: the repo at that release, plus `offline\` with PSScriptAnalyzer, the Python wheels `docs/art/make-art.py` needs, their licences, and a setup script. It doesn't carry the toolchains (Windows PowerShell 5.1, PowerShell 7, Git for Windows for Git Bash, Python, ffmpeg and ShellCheck); `offline\README.md` lists each with the version CI uses and a link to its offline installer. Install those, then in the kit folder:

```powershell
powershell -ExecutionPolicy Bypass -File offline\setup.ps1
```

It needs no network. It checks each toolchain and says what's missing, makes `.venv` from the bundled wheels, loads PSScriptAnalyzer from the kit at the pinned version, and prints the commands for the tests, the lint and the art check. `tools/build-dev-kit.ps1` builds the kit (`pwsh tools/build-dev-kit.ps1` writes it to `dist\`), and the `offline` workflow runs all of it from the unzipped kit with the network cut off, before every release.
