#!/usr/bin/env bash
# Package the already-built ENSI Linux bundle into a single-file AppImage
# (the Linux equivalent of a .dmg — copy to any Ubuntu box, chmod +x, run).
# Run AFTER wsl_build_linux.sh has produced the release bundle.
set -euo pipefail

SRC="$HOME/ensi-src"
BUNDLE="$SRC/build/linux/x64/release/bundle"
DIST_WIN="/mnt/c/Users/harih/ENSI/dist"
APPDIR="$HOME/ensi-AppDir"

log() { printf '\n\033[1;34m[appimage]\033[0m %s\n' "$*"; }

[ -d "$BUNDLE" ] || { echo "Bundle not found at $BUNDLE — run the build first."; exit 1; }

log "Installing packaging tools..."
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y imagemagick file desktop-file-utils >/dev/null

# --- Lay out the AppDir ----------------------------------------------------
rm -rf "$APPDIR"
mkdir -p "$APPDIR/usr/bin"
cp -r "$BUNDLE"/. "$APPDIR/usr/bin/"

# Icon (required by appimagetool).
convert -size 256x256 xc:'#1565C0' -gravity center -pointsize 96 \
  -fill white -annotate 0 'E' "$APPDIR/ensi.png"

# Desktop entry.
cat > "$APPDIR/ensi.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=ENSI
Comment=Effortless Network Shared Input
Exec=ensi
Icon=ensi
Categories=Utility;Network;
Terminal=false
EOF

# AppRun launcher.
cat > "$APPDIR/AppRun" <<'EOF'
#!/bin/sh
HERE="$(dirname "$(readlink -f "$0")")"
exec "$HERE/usr/bin/ensi" "$@"
EOF
chmod +x "$APPDIR/AppRun"

# --- Fetch appimagetool and build -----------------------------------------
TOOL="$HOME/appimagetool"
if [ ! -x "$TOOL" ]; then
  log "Downloading appimagetool..."
  wget -q -O "$TOOL" \
    https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage
  chmod +x "$TOOL"
fi

mkdir -p "$DIST_WIN"
log "Building AppImage..."
ARCH=x86_64 APPIMAGE_EXTRACT_AND_RUN=1 "$TOOL" "$APPDIR" "$DIST_WIN/ensi-linux-x64.AppImage"

log "DONE."
ls -lh "$DIST_WIN/ensi-linux-x64.AppImage"
echo "On your Ubuntu device:  chmod +x ensi-linux-x64.AppImage && ./ensi-linux-x64.AppImage"
