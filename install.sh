#!/bin/sh
# Installs carify to ~/.local/bin.
#   curl -fsSL https://raw.githubusercontent.com/Real-Fruit-Snacks/carify/main/install.sh | sh
# CARIFY_BIN=<dir>   install somewhere else
# CARIFY_REF=v1.1.0  install a tagged version instead of main
# CARIFY_URL=<url>   download the script from a mirror
set -eu

ref="${CARIFY_REF:-main}"
bin="${CARIFY_BIN:-$HOME/.local/bin}"
url="${CARIFY_URL:-https://raw.githubusercontent.com/Real-Fruit-Snacks/carify/$ref/carify}"

mkdir -p "$bin"
tmp="$bin/.carify.download"
trap 'rm -f "$tmp"' EXIT

if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$url" -o "$tmp"
elif command -v wget >/dev/null 2>&1; then
    wget -qO "$tmp" "$url"
else
    echo "error: need curl or wget" >&2; exit 1
fi
if ! grep -q '^CARIFY_VERSION=' "$tmp"; then
    echo "error: $url did not look like carify" >&2; exit 1
fi
chmod +x "$tmp"
mv -f "$tmp" "$bin/carify"
echo "installed: $bin/carify ($("$bin/carify" --version))"

case ":$PATH:" in
    *":$bin:"*) ;;
    *) echo "note: $bin is not on PATH. Add this to your shell profile:"
       echo "      export PATH=\"$bin:\$PATH\"" ;;
esac
if ! command -v ffmpeg >/dev/null 2>&1; then
    echo "note: ffmpeg not found. Debian/Ubuntu: sudo apt install ffmpeg  Fedora: sudo dnf install ffmpeg  macOS: brew install ffmpeg"
fi
