#!/usr/bin/env bash
# Builds World TV in Release configuration and exports "World TV.app".
#
# Environment:
#   VERSION        Marketing version (default: value in project.yml)
#   BUILD_NUMBER   Bundle build number (default: 1)
#   SIGN_IDENTITY  Optional codesign identity, e.g.
#                  "Developer ID Application: Jane Doe (TEAMID)".
#                  When empty the app is ad-hoc signed ("-").
#   RUN_TESTS      1 to run unit tests before archiving (default: 0)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

VERSION="${VERSION:-$(awk -F'"' '/MARKETING_VERSION:/ {print $2; exit}' project.yml)}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
SIGN_IDENTITY="${SIGN_IDENTITY:-}"
BUILD_DIR="$ROOT/build"
LOG_DIR="$BUILD_DIR/logs"
ARCHIVE="$BUILD_DIR/WorldTV.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
APP_NAME="World TV.app"

mkdir -p "$LOG_DIR"
rm -rf "$ARCHIVE" "$EXPORT_DIR"

echo "==> World TV $VERSION ($BUILD_NUMBER)"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "error: xcodegen not found. Install with: brew install xcodegen" >&2
  exit 1
fi

echo "==> Generating Xcode project"
xcodegen generate --spec project.yml | tee "$LOG_DIR/xcodegen.log"

COMMON_SETTINGS=(
  MARKETING_VERSION="$VERSION"
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER"
)

if [[ "${RUN_TESTS:-0}" == "1" ]]; then
  echo "==> Running unit tests"
  xcodebuild test \
    -project WorldTV.xcodeproj -scheme WorldTVUnit \
    -destination 'platform=macOS' \
    -resultBundlePath "$BUILD_DIR/UnitTests.xcresult" \
    "${COMMON_SETTINGS[@]}" 2>&1 | tee "$LOG_DIR/unit-tests.log"
fi

echo "==> Archiving (Release, universal arm64 + x86_64)"
xcodebuild archive \
  -project WorldTV.xcodeproj \
  -scheme WorldTV \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE" \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="" \
  "${COMMON_SETTINGS[@]}" 2>&1 | tee "$LOG_DIR/archive.log"

APP_SRC="$ARCHIVE/Products/Applications/$APP_NAME"
if [[ ! -d "$APP_SRC" ]]; then
  echo "error: archive did not contain $APP_NAME" >&2
  exit 1
fi

mkdir -p "$EXPORT_DIR"
ditto "$APP_SRC" "$EXPORT_DIR/$APP_NAME"
APP="$EXPORT_DIR/$APP_NAME"
ENTITLEMENTS="$ROOT/WorldTV/Resources/WorldTV.entitlements"

if [[ -n "$SIGN_IDENTITY" ]]; then
  echo "==> Signing with Developer ID (hardened runtime)"
  codesign --force --options runtime --timestamp \
    --entitlements "$ENTITLEMENTS" \
    --sign "$SIGN_IDENTITY" "$APP"
else
  echo "==> Ad-hoc signing (no Developer ID configured)"
  codesign --force --options runtime \
    --entitlements "$ENTITLEMENTS" \
    --sign - "$APP"
fi

codesign --verify --deep --strict --verbose=2 "$APP" 2>&1 | tee "$LOG_DIR/codesign-verify.log"
echo "==> Architectures: $(lipo -archs "$APP/Contents/MacOS/WorldTV")"
echo "==> Exported: $APP"
