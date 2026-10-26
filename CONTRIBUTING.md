# Contributing

Bug reports and pull requests are welcome.

- `carify` and `carify.ps1` must behave the same. A change to one needs the matching change to the other.
- `carify` has to run on macOS's `/bin/bash` 3.2: no associative arrays, no `mapfile`, no `${var,,}`.
- `carify.ps1` has to run on Windows PowerShell 5.1 and stay ASCII.
- Run the tests before opening a PR. They need ffmpeg with libx264 and libx265.

```sh
shellcheck carify install.sh tests/run.sh
tests/run.sh bash
tests/run.sh pwsh
```

- A new behaviour gets a check in `tests/run.sh`.
- If a file played or failed on your car, say which model year and head unit. That is the data this project is short of.
