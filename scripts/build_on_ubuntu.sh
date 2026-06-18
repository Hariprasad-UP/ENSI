#!/usr/bin/env bash
# Build ENSI natively on THIS Ubuntu machine — guaranteed glibc-compatible.
# Usage (on the Ubuntu box):
#   curl -fsSL https://raw.githubusercontent.com/Hariprasad-UP/ENSI/main/scripts/build_on_ubuntu.sh | bash
set -euo pipefail

FLUTTER_VERSION="3.38.7"
SRC="$HOME/ENSI"

echo "== ENSI native build (Ubuntu) =="
echo "[1/4] Installing build + runtime dependencies (sudo)..."
sudo apt-get update
sudo apt-get install -y \
  curl git unzip xz-utils zip clang cmake ninja-build pkg-config \
  libgtk-3-dev liblzma-dev build-essential libx11-6 libxtst6 libfuse2

echo "[2/4] Installing Flutter $FLUTTER_VERSION (if needed)..."
if [ ! -x "$HOME/flutter/bin/flutter" ]; then
  curl -fsSL "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" -o /tmp/flutter.tar.xz
  tar -xf /tmp/flutter.tar.xz -C "$HOME"
  rm -f /tmp/flutter.tar.xz
fi
export PATH="$HOME/flutter/bin:$PATH"
git config --global --add safe.directory "$HOME/flutter" || true

echo "[3/4] Getting ENSI source..."
if [ -d "$SRC/.git" ]; then
  git -C "$SRC" pull --ff-only || true
else
  git clone https://github.com/Hariprasad-UP/ENSI.git "$SRC"
fi

echo "[4/4] Building (this is the slow part)..."
cd "$SRC"
flutter config --enable-linux-desktop
flutter pub get
flutter build linux --release

echo
echo "================================================================"
echo " BUILD DONE. Launch ENSI with:"
echo "   $SRC/build/linux/x64/release/bundle/ensi"
echo " (Use an Xorg session: echo \$XDG_SESSION_TYPE should print x11)"
echo "================================================================"
