#!/bin/bash
# Downloads the quality benchmark's photos, listed in photos.txt, into a
# directory (by default Tools/Benchmark/photos, which git ignores), and checks
# each one's SHA-256. Photos already there are only checked.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
directory="${1:-$here/photos}"
mkdir -p "$directory"

sha256() {
    if command -v sha256sum >/dev/null; then sha256sum "$1"; else shasum -a 256 "$1"; fi | cut -d' ' -f1
}

grep -v '^#' "$here/photos.txt" | while read -r file checksum _; do
    [ -n "$file" ] || continue
    target="$directory/$file"
    if [ ! -f "$target" ]; then
        # The site sometimes refuses a request; a later try usually works.
        for delay in 2 4 8 16 0; do
            curl -fsSL -o "$target.part" "https://r0k.us/graphics/kodak/kodak/$file" && break
            [ "$delay" = 0 ] && { echo "Could not download $file" >&2; exit 1; }
            sleep "$delay"
        done
        mv "$target.part" "$target"
    fi
    if [ "$(sha256 "$target")" != "$checksum" ]; then
        echo "$file does not match its checksum" >&2
        rm -f "$target"
        exit 1
    fi
done
echo "The benchmark's photos are in $directory"
