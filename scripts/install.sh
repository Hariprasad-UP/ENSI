#!/usr/bin/env bash
# ENSI one-command installer (Linux & macOS)
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/Hariprasad-UP/ENSI/main/scripts/install.sh | bash
#
# Auto-detects OS + CPU architecture and installs the matching ENSI release.
# NOTE: requires published GitHub Releases assets to actually download a build.
set -euo pipefail

REPO="Hariprasad-UP/ENSI"
APP="ensi"
INSTALL_DIR="${ENSI_INSTALL_DIR:-$HOME/.local/bin}"

info()  { printf '\033[1;34m[ENSI]\033[0m %s\n' "$*"; }
warn()  { printf '\033[1;33m[ENSI]\033[0m %s\n' "$*"; }
err()   { printf '\033[1;31m[ENSI]\033[0m %s\n' "$*" >&2; }
die()   { err "$*"; exit 1; }

# --- 1. Detect OS -----------------------------------------------------------
UNAME_S="$(uname -s)"
case "$UNAME_S" in
  Linux*)  OS="linux" ;;
  Darwin*) OS="macos" ;;
  *)       die "Unsupported OS: $UNAME_S (this script is for Linux/macOS; use install.ps1 on Windows)." ;;
esac

# --- 2. Detect architecture -------------------------------------------------
UNAME_M="$(uname -m)"
case "$UNAME_M" in
  x86_64|amd64)        ARCH="x64" ;;
  arm64|aarch64)       ARCH="arm64" ;;
  *)                   die "Unsupported architecture: $UNAME_M" ;;
esac

info "Detected platform: ${OS}-${ARCH}"

# --- 3. Pick asset pattern per platform ------------------------------------
case "$OS" in
  linux)  ASSET_PATTERN="ensi-linux-${ARCH}.AppImage" ;;
  macos)  ASSET_PATTERN="ensi-macos-${ARCH}.dmg" ;;
esac

# --- 4. Resolve latest release & asset URL ---------------------------------
need() { command -v "$1" >/dev/null 2>&1 || die "Required tool '$1' not found."; }
need curl

API="https://api.github.com/repos/${REPO}/releases/latest"
info "Resolving latest release from ${REPO}..."
ASSET_URL="$(curl -fsSL "$API" \
  | grep -oE "https://[^\"]*${ASSET_PATTERN}" \
  | head -n1 || true)"

if [ -z "${ASSET_URL:-}" ]; then
  warn "No published release asset matching '${ASSET_PATTERN}' was found."
  warn "Publish a GitHub Release with platform assets, or build locally:"
  warn "    flutter build ${OS} --release"
  die  "Aborting: nothing to download yet."
fi

# --- 5. Download + install --------------------------------------------------
mkdir -p "$INSTALL_DIR"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
OUT="$TMP/$(basename "$ASSET_PATTERN")"

info "Downloading $ASSET_URL"
curl -fsSL "$ASSET_URL" -o "$OUT"

# Optional checksum verification (if a .sha256 sibling asset exists)
SUM_URL="${ASSET_URL}.sha256"
if curl -fsSL "$SUM_URL" -o "$OUT.sha256" 2>/dev/null; then
  info "Verifying checksum..."
  ( cd "$TMP" && shasum -a 256 -c "$(basename "$OUT").sha256" ) || die "Checksum mismatch!"
fi

case "$OS" in
  linux)
    DEST="$INSTALL_DIR/$APP"
    install -m 0755 "$OUT" "$DEST"
    info "Installed AppImage to $DEST"
    ;;
  macos)
    info "Mounting DMG..."
    MOUNT="$(hdiutil attach -nobrowse -quiet "$OUT" | tail -n1 | awk '{print $NF}')"
    cp -R "$MOUNT"/*.app "/Applications/" || die "Failed to copy .app"
    hdiutil detach -quiet "$MOUNT" || true
    info "Installed to /Applications. Grant Accessibility + Input Monitoring permission on first run."
    ;;
esac

# --- 6. PATH hint -----------------------------------------------------------
case ":$PATH:" in
  *":$INSTALL_DIR:"*) : ;;
  *) warn "Add $INSTALL_DIR to your PATH, e.g.:";
     warn "    echo 'export PATH=\"$INSTALL_DIR:\$PATH\"' >> ~/.bashrc" ;;
esac

info "Done. Launch ENSI and follow the pairing prompts."
