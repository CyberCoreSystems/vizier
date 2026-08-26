#!/bin/sh
# Install Vizier.
#
#   curl -fsSL https://raw.githubusercontent.com/CyberCoreSystems/vizier/main/install.sh | sh
#
# Env:
#   VIZIER_VERSION  version to install (default: latest release)
#   VIZIER_BIN_DIR  install directory (default: /usr/local/bin, or ~/.local/bin
#                   when that is not writable)
set -eu

REPO="CyberCoreSystems/vizier"
BIN_DIR="${VIZIER_BIN_DIR:-}"

die() { echo "vizier install: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "$1 is required but not installed"; }

need uname
need tar
if command -v curl >/dev/null 2>&1; then
  fetch() { curl -fsSL "$1" -o "$2"; }
  fetch_stdout() { curl -fsSL "$1"; }
elif command -v wget >/dev/null 2>&1; then
  fetch() { wget -qO "$2" "$1"; }
  fetch_stdout() { wget -qO- "$1"; }
else
  die "need curl or wget"
fi

# Checksum verification is mandatory. Picking "no verification" as a fallback
# would defeat the point of the tool being installed.
if command -v sha256sum >/dev/null 2>&1; then
  sha256_of() { sha256sum "$1" | cut -d' ' -f1; }
elif command -v shasum >/dev/null 2>&1; then
  sha256_of() { shasum -a 256 "$1" | cut -d' ' -f1; }
else
  die "need sha256sum or shasum to verify the download; refusing to install unverified"
fi

os="$(uname -s | tr '[:upper:]' '[:lower:]')"
case "$os" in
  linux|darwin) ;;
  mingw*|msys*|cygwin*) die "on Windows, download the .zip from https://github.com/CyberCoreSystems/vizier/releases/latest and put vizier.exe on your PATH" ;;
  *) die "unsupported OS: $os" ;;
esac

arch="$(uname -m)"
case "$arch" in
  x86_64|amd64) arch=amd64 ;;
  arm64|aarch64) arch=arm64 ;;
  *) die "unsupported architecture: $arch" ;;
esac

VERSION="${VIZIER_VERSION:-}"
if [ -z "$VERSION" ]; then
  VERSION="$(fetch_stdout "https://api.github.com/repos/$REPO/releases/latest" |
    sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
  [ -n "$VERSION" ] || die "could not determine the latest release"
fi
VERSION="${VERSION#v}"

name="vizier_${VERSION}_${os}_${arch}"
base="https://github.com/$REPO/releases/download/v${VERSION}"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT INT TERM

echo "vizier install: downloading v${VERSION} (${os}/${arch})"
fetch "${base}/${name}.tar.gz" "$tmp/${name}.tar.gz" || die "download failed: ${base}/${name}.tar.gz"
fetch "${base}/checksums.txt" "$tmp/checksums.txt" || die "no checksums.txt in release v${VERSION}; refusing to install unverified"

# Tolerate every shape sha256sum/shasum emit for the same line: two spaces
# (GNU text mode, which is what the release runner produces) or " *" (binary
# mode, from Git Bash and `shasum -b`), with or without a leading "./".
# Matching only the GNU form made a valid archive fail with "no entry", which
# reads like a missing release rather than a parser that was too strict.
want="$(sed -n "s#^\([0-9a-f]\{64\}\)[[:space:]]*[*]\{0,1\}[.]\{0,1\}/\{0,1\}${name}\.tar\.gz\$#\1#p" "$tmp/checksums.txt" | head -1)"
[ -n "$want" ] || die "checksums.txt has no entry for ${name}.tar.gz; refusing to install unverified"

got="$(sha256_of "$tmp/${name}.tar.gz")"
if [ "$got" != "$want" ]; then
  die "checksum mismatch: got $got, expected $want -- NOT installing"
fi
echo "vizier install: checksum verified"

tar -xzf "$tmp/${name}.tar.gz" -C "$tmp"
[ -f "$tmp/vizier" ] || die "archive did not contain a vizier binary"
chmod +x "$tmp/vizier"

if [ -z "$BIN_DIR" ]; then
  if [ -w /usr/local/bin ] 2>/dev/null; then BIN_DIR=/usr/local/bin
  else BIN_DIR="$HOME/.local/bin"; fi
fi
mkdir -p "$BIN_DIR"
mv "$tmp/vizier" "$BIN_DIR/vizier" || die "could not install into $BIN_DIR"

echo "vizier install: installed $("$BIN_DIR/vizier" version 2>/dev/null || echo "v${VERSION}") -> $BIN_DIR/vizier"
case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *) echo "vizier install: note - $BIN_DIR is not on your PATH" ;;
esac
