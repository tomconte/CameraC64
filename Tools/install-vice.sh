#!/bin/bash
# Builds VICE's x64sc without a user interface into /opt/vice, for the VICE
# comparison tests on Linux, such as in Claude Code web sessions. It takes
# about 5 minutes. On a Mac, `brew install vice` is enough.
#
# VICE is GPL software and comes with Commodore's ROMs: it is only run by the
# tests, never copied into the repository or the app.
set -euo pipefail

# Homebrew's version, which CI uses, and its checksum.
VICE_VERSION="3.10"
VICE_SHA256="8e5bac18cbcb9f192380ad3ef881f8790f5b75c41d7b3da65d831985d864d6d1"
PREFIX="${VICE_PREFIX:-/opt/vice}"

if [ -x "$PREFIX/bin/x64sc" ]; then
    echo "VICE is already in $PREFIX"
    exit 0
fi

packages=(bison build-essential dos2unix flex libpng-dev pkg-config texinfo xa65 zlib1g-dev)
missing=()
for package in "${packages[@]}"; do
    dpkg -s "$package" >/dev/null 2>&1 || missing+=("$package")
done
if [ ${#missing[@]} -gt 0 ]; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq >/dev/null 2>&1 || true
    apt-get install -y -qq "${missing[@]}" >/dev/null
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
curl -fsSL -o "$tmp/vice.tar.gz" \
    "https://downloads.sourceforge.net/project/vice-emu/releases/vice-$VICE_VERSION.tar.gz"
echo "$VICE_SHA256  $tmp/vice.tar.gz" | sha256sum -c --quiet -
tar -xzf "$tmp/vice.tar.gz" -C "$tmp"
cd "$tmp/vice-$VICE_VERSION"
./configure --prefix="$PREFIX" --enable-headlessui --disable-html-docs --disable-pdf-docs \
    --without-pulse --without-alsa --without-libcurl --disable-realdevice --disable-hardsid \
    --disable-cpuhistory >configure.log 2>&1 || { tail -20 configure.log; exit 1; }
make -j"$(nproc)" >make.log 2>&1 || { tail -40 make.log; exit 1; }
make install >install.log 2>&1 || { tail -20 install.log; exit 1; }
echo "VICE $VICE_VERSION is in $PREFIX"
