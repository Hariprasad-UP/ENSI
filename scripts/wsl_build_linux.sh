#!/usr/bin/env bash
# Build the ENSI Linux desktop app inside WSL Ubuntu and drop a tarball back
# onto the Windows filesystem. Idempotent: re-running reuses the Flutter SDK
# and apt packages already present.
set -euo pipefail

FLUTTER_VERSION="3.38.7"
FLUTTER_DIR="$HOME/flutter"
SRC_WIN="/mnt/c/Users/harih/ENSI"
SRC="$HOME/ensi-src"
DIST_WIN="$SRC_WIN/dist"

log() { printf '\n\033[1;34m[wsl-build]\033[0m %s\n' "$*"; }

# --- 1. apt build dependencies ---------------------------------------------
log "Installing build dependencies (apt)..."
sudo apt-get update -y
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
  curl wget git unzip zip xz-utils \
  clang cmake ninja-build pkg-config build-essential \
  libgtk-3-dev liblzma-dev libglu1-mesa

# --- 2. Linux-native Flutter SDK -------------------------------------------
if [ ! -x "$FLUTTER_DIR/bin/flutter" ]; then
  log "Downloading Flutter $FLUTTER_VERSION (Linux)..."
  TARBALL="flutter_linux_${FLUTTER_VERSION}-stable.tar.xz"
  URL="https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/${TARBALL}"
  wget -q --show-progress -O "/tmp/$TARBALL" "$URL"
  log "Extracting Flutter to $FLUTTER_DIR..."
  tar -xf "/tmp/$TARBALL" -C "$HOME"
  rm -f "/tmp/$TARBALL"
else
  log "Flutter already present at $FLUTTER_DIR — skipping download."
fi
export PATH="$FLUTTER_DIR/bin:$PATH"
git config --global --add safe.directory "$FLUTTER_DIR" || true
flutter --version

# --- 3. Copy source into the Linux filesystem ------------------------------
log "Syncing source from $SRC_WIN -> $SRC ..."
mkdir -p "$SRC"
rsync -a --delete \
  --exclude '.git/' \
  --exclude 'build/' \
  --exclude '.dart_tool/' \
  --exclude 'windows/' \
  --exclude '.idea/' \
  "$SRC_WIN/" "$SRC/"

# --- 4. Build --------------------------------------------------------------
cd "$SRC"
flutter config --enable-linux-desktop
flutter pub get
log "Building release (this is the slow part)..."
flutter build linux --release

# --- 5. Package + hand back to Windows -------------------------------------
BUNDLE="$SRC/build/linux/x64/release/bundle"
mkdir -p "$DIST_WIN"
tar -C "$BUNDLE" -czf "$DIST_WIN/ensi-linux-x64.tar.gz" .
log "DONE. Tarball at: C:\\Users\\harih\\ENSI\\dist\\ensi-linux-x64.tar.gz"
ls -lh "$DIST_WIN/ensi-linux-x64.tar.gz"
