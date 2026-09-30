#!/bin/bash
# SessionStart hook for Claude Code on the web: installs the Swift toolchain so
# C64Core and the tools can be built, linted and tested in web sessions, and
# cc65 to assemble the display programs (C64/build.sh). The iOS app needs
# Xcode, so it is built and tested by CI (.github/workflows/ci.yml). VICE, for
# the comparison tests, takes minutes to build: Tools/install-vice.sh does it
# when needed.
set -euo pipefail

if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
    exit 0
fi

# Keep in step with the Swift that ships with Xcode on CI.
SWIFT_VERSION="6.3.3"
SWIFT_ROOT="${SWIFT_ROOT:-/opt/swift}"
INSTALL_DIR="$SWIFT_ROOT-$SWIFT_VERSION"

if [ ! -x "$INSTALL_DIR/usr/bin/swift" ]; then
    packages=(binutils git gnupg2 libc6-dev libcurl4-openssl-dev libedit2 libgcc-13-dev libncurses-dev
        libpython3-dev libsqlite3-0 libstdc++-13-dev libxml2-dev libz3-dev pkg-config tzdata unzip zlib1g-dev)
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
    export GNUPGHOME="$tmp/gnupg"
    mkdir -m 700 "$GNUPGHOME"
    url="https://download.swift.org/swift-$SWIFT_VERSION-release/ubuntu2404/swift-$SWIFT_VERSION-RELEASE/swift-$SWIFT_VERSION-RELEASE-ubuntu24.04.tar.gz"
    # swift.org serves these gzip-encoded even when not asked, hence --compressed.
    curl -fsSL --compressed https://www.swift.org/keys/all-keys.asc | gpg --batch --quiet --import
    curl -fsSL --compressed -o "$tmp/swift.tar.gz.sig" "$url.sig"
    curl -fsSL -o "$tmp/swift.tar.gz" "$url"
    gpg --batch --verify "$tmp/swift.tar.gz.sig" "$tmp/swift.tar.gz" 2>/dev/null
    mkdir -p "$INSTALL_DIR"
    tar -xzf "$tmp/swift.tar.gz" -C "$INSTALL_DIR" --strip-components=1
fi

if ! command -v ca65 >/dev/null; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq >/dev/null 2>&1 || true
    apt-get install -y -qq cc65 >/dev/null
fi

ln -sfn "$INSTALL_DIR" "$SWIFT_ROOT"
if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
    echo "export PATH=\"$SWIFT_ROOT/usr/bin:\$PATH\"" >>"$CLAUDE_ENV_FILE"
fi
echo "$("$SWIFT_ROOT/usr/bin/swift" --version 2>&1 | head -1) is ready"
