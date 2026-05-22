#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/.build/ClipEase.app"
SOURCE_INFO="$ROOT_DIR/Resources/Info.plist"
APP_INFO="$APP_DIR/Contents/Info.plist"
DIST_DIR="$ROOT_DIR/dist"
STAGING_DIR="$DIST_DIR/dmg-staging"

plist_value() {
  /usr/libexec/PlistBuddy -c "Print :$1" "$2"
}

if [[ ! -d "$APP_DIR" ]]; then
  echo "Missing $APP_DIR. Run ./scripts/build-app.sh --bump patch --run after App code changes." >&2
  exit 1
fi

if ! command -v hdiutil >/dev/null 2>&1; then
  echo "hdiutil is required to create a DMG." >&2
  exit 1
fi

SOURCE_SHORT_VERSION="$(plist_value CFBundleShortVersionString "$SOURCE_INFO")"
SOURCE_BUILD_VERSION="$(plist_value CFBundleVersion "$SOURCE_INFO")"
APP_SHORT_VERSION="$(plist_value CFBundleShortVersionString "$APP_INFO")"
APP_BUILD_VERSION="$(plist_value CFBundleVersion "$APP_INFO")"

if [[ "$SOURCE_SHORT_VERSION" != "$APP_SHORT_VERSION" || "$SOURCE_BUILD_VERSION" != "$APP_BUILD_VERSION" ]]; then
  echo "App bundle version does not match Resources/Info.plist:" >&2
  echo "  app:    $APP_SHORT_VERSION ($APP_BUILD_VERSION)" >&2
  echo "  source: $SOURCE_SHORT_VERSION ($SOURCE_BUILD_VERSION)" >&2
  echo "Run ./scripts/build-app.sh --bump patch --run before packaging." >&2
  exit 1
fi

DMG_PATH="$DIST_DIR/ClipEase-${SOURCE_SHORT_VERSION}-${SOURCE_BUILD_VERSION}.dmg"

rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR" "$DIST_DIR"
trap 'rm -rf "$STAGING_DIR"' EXIT

ditto "$APP_DIR" "$STAGING_DIR/ClipEase.app"
ln -s /Applications "$STAGING_DIR/Applications"

rm -f "$DMG_PATH"
hdiutil create \
  -volname "ClipEase" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

echo "Created $DMG_PATH"
shasum -a 256 "$DMG_PATH"
