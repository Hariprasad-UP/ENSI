#!/usr/bin/env bash
# Replace the WSL build bundle with the glibc-2.31 bundle produced by the Docker
# (Ubuntu 20.04) build, then package it into the AppImage for release.
set -euo pipefail

B="$HOME/ensi-src/build/linux/x64/release/bundle"
rm -rf "$B"
mkdir -p "$B"
tar -xzf /mnt/c/Users/harih/ENSI/dist/ensi-linux-x64.tar.gz -C "$B"

echo -n "GLIBC_MAX in bundle: "
objdump -T "$B/ensi" 2>/dev/null | grep -oE 'GLIBC_[0-9.]+' | sort -V | tail -1 || echo "(objdump unavailable)"

bash /mnt/c/Users/harih/ENSI/scripts/wsl_appimage.sh
