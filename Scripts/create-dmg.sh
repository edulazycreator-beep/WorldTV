#!/usr/bin/env bash
# Packages build/export/World TV.app into dist/WorldTV-<version>-macOS.dmg.
#
# Environment:
#   VERSION                      Required version string for the file name.
#   SIGN_IDENTITY                Optional Developer ID identity to sign the DMG.
#   APPLE_ID, APPLE_TEAM_ID,
#   APPLE_APP_SPECIFIC_PASSWORD  When all three are set (and SIGN_IDENTITY is set)
#                                the DMG is notarized and stapled.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

VERSION="${VERSION:-$(awk -F'"' '/MARKETING_VERSION:/ {print $2; exit}' project.yml)}"
APP="$ROOT/build/export/World TV.app"
DIST="$ROOT/dist"
STAGING="$ROOT/build/dmg-staging"
DMG_NAME="WorldTV-${VERSION}-macOS.dmg"
DMG="$DIST/$DMG_NAME"
LOG_DIR="$ROOT/build/logs"

[[ -d "$APP" ]] || { echo "error: $APP not found. Run Scripts/build.sh first." >&2; exit 1; }

mkdir -p "$DIST" "$LOG_DIR"
rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"

ditto "$APP" "$STAGING/World TV.app"
ln -s /Applications "$STAGING/Applications"

cat > "$STAGING/READ ME FIRST.txt" <<TXT
World TV ${VERSION}

Install: drag "World TV" onto the Applications folder.

If this build is not notarized, macOS Gatekeeper will block the first launch.
To open it anyway:
  1. Open Applications, Control-click "World TV" and choose Open, then Open again.
  or
  2. System Settings > Privacy & Security > "World TV was blocked" > Open Anyway.
  or (Terminal)
     xattr -dr com.apple.quarantine "/Applications/World TV.app"

World TV does not host any television content. Streams come from public
sources listed in the in-app source attribution, or from playlists you import.
TXT

echo "==> Creating $DMG_NAME"
hdiutil create \
  -volname "World TV ${VERSION}" \
  -srcfolder "$STAGING" \
  -fs HFS+ \
  -format UDZO -imagekey zlib-level=9 \
  -ov "$DMG" 2>&1 | tee "$LOG_DIR/hdiutil-create.log"

if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  echo "==> Signing DMG"
  codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"

  if [[ -n "${APPLE_ID:-}" && -n "${APPLE_TEAM_ID:-}" && -n "${APPLE_APP_SPECIFIC_PASSWORD:-}" ]]; then
    echo "==> Notarizing (this can take several minutes)"
    xcrun notarytool submit "$DMG" \
      --apple-id "$APPLE_ID" \
      --team-id "$APPLE_TEAM_ID" \
      --password "$APPLE_APP_SPECIFIC_PASSWORD" \
      --wait --timeout 30m 2>&1 | tee "$LOG_DIR/notarization.log"
    if ! grep -q "status: Accepted" "$LOG_DIR/notarization.log"; then
      echo "error: notarization was not accepted; see $LOG_DIR/notarization.log" >&2
      exit 1
    fi
    echo "==> Stapling"
    xcrun stapler staple "$DMG"
    xcrun stapler validate "$DMG"
  else
    echo "==> Notarization credentials not set; DMG is signed but not notarized."
  fi
fi

(cd "$DIST" && shasum -a 256 "$DMG_NAME" > "$DMG_NAME.sha256")
echo "==> Created $DMG"
cat "$DMG.sha256"
