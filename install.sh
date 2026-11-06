#!/bin/sh
# Installs carify to ~/.local/bin.
#   curl -fsSL https://raw.githubusercontent.com/Real-Fruit-Snacks/carify/main/install.sh | sh
# Offline, in the folder unzipped from a release's carify-<version>-offline.zip:
#   sh ./install.sh    (run as a file next to carify, it installs that copy instead of downloading)
# CARIFY_BIN=<dir>   install somewhere else
# CARIFY_REF=v1.1.2  install a tagged version instead of main
# CARIFY_URL=<url>   download the script from a mirror
set -eu

ref="${CARIFY_REF:-main}"
bin="${CARIFY_BIN:-$HOME/.local/bin}"
url="${CARIFY_URL:-https://raw.githubusercontent.com/Real-Fruit-Snacks/carify/$ref/carify}"
# The folder this script is in when it runs as a file; empty when it is piped to sh.
# CARIFY_URL or CARIFY_REF still mean download.
here=
case "$0" in
    *install.sh) [ -n "${CARIFY_URL:-}${CARIFY_REF:-}" ] || here=$(cd -- "$(dirname -- "$0")" && pwd) ;;
esac

mkdir -p "$bin"
tmp="$bin/.carify.download"
trap 'rm -f "$tmp"' EXIT

if [ -n "$here" ] && [ -f "$here/carify" ]; then
    from="$here/carify"
    echo "using the carify next to install.sh: $from"
    cp "$from" "$tmp"
elif command -v curl >/dev/null 2>&1; then
    from=$url
    curl -fsSL "$url" -o "$tmp"
elif command -v wget >/dev/null 2>&1; then
    from=$url
    wget -qO "$tmp" "$url"
else
    echo "error: need curl or wget" >&2; exit 1
fi
if ! grep -q '^CARIFY_VERSION=' "$tmp"; then
    echo "error: $from did not look like carify" >&2; exit 1
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
