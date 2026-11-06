#!/usr/bin/env bash
# Validates a World TV DMG: image checksum, mount, bundle contents, version,
# architectures and code signature. Usage: Scripts/validate.sh [path/to.dmg]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${VERSION:-$(awk -F'"' '/MARKETING_VERSION:/ {print $2; exit}' "$ROOT/project.yml")}"
DMG="${1:-$ROOT/dist/WorldTV-${VERSION}-macOS.dmg}"
MOUNT="$(mktemp -d /tmp/worldtv-dmg.XXXXXX)"
FAIL=0

cleanup() { hdiutil detach "$MOUNT" -quiet >/dev/null 2>&1 || true; rmdir "$MOUNT" 2>/dev/null || true; }
trap cleanup EXIT

check() { if eval "$2"; then echo "  ok   $1"; else echo "  FAIL $1"; FAIL=1; fi; }

echo "==> Validating $DMG"
[[ -f "$DMG" ]] || { echo "error: $DMG does not exist" >&2; exit 1; }

check "image checksum (hdiutil verify)" 'hdiutil verify "$DMG" >/dev/null 2>&1'
hdiutil attach "$DMG" -nobrowse -readonly -noautoopen -mountpoint "$MOUNT" >/dev/null

APP="$MOUNT/World TV.app"
PLIST="$APP/Contents/Info.plist"
BIN="$APP/Contents/MacOS/WorldTV"

check "app bundle present"            '[[ -d "$APP" ]]'
check "Applications symlink present"  '[[ -L "$MOUNT/Applications" ]]'
check "executable present"            '[[ -x "$BIN" ]]'
check "version is $VERSION"           '[[ "$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$PLIST")" == "$VERSION" ]]'
check "minimum macOS is 13.0"         '[[ "$(/usr/libexec/PlistBuddy -c "Print :LSMinimumSystemVersion" "$PLIST")" == "13.0" ]]'
check "contains arm64 slice"          'lipo -archs "$BIN" | grep -q arm64'
check "contains x86_64 slice"         'lipo -archs "$BIN" | grep -q x86_64'
check "app icon compiled"             '[[ -f "$APP/Contents/Resources/AppIcon.icns" || -f "$APP/Contents/Resources/Assets.car" ]]'
check "code signature valid"          'codesign --verify --deep --strict "$APP" >/dev/null 2>&1'

echo "  info Gatekeeper assessment (expected to reject unsigned/un-notarized builds):"
spctl --assess --type execute --verbose=2 "$APP" 2>&1 | sed 's/^/       /' || true

if [[ $FAIL -ne 0 ]]; then
  echo "==> DMG validation FAILED"
  exit 1
fi
echo "==> DMG validation passed"
