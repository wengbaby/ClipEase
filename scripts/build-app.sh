#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build/release"
APP_DIR="$ROOT_DIR/.build/ClipEase.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
BUMP_TYPE="patch"
RUN_APP="false"
SIGN_IDENTITY="${CLIPEASE_CODESIGN_IDENTITY:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --run)
      RUN_APP="true"
      shift
      ;;
    --bump)
      BUMP_TYPE="${2:-}"
      shift 2
      ;;
    --bump=*)
      BUMP_TYPE="${1#*=}"
      shift
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

python3 "$ROOT_DIR/scripts/bump_version.py" --bump "$BUMP_TYPE"

swift build -c release --product ClipEase

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$BUILD_DIR/ClipEase" "$MACOS_DIR/ClipEase"
cp "$ROOT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$ROOT_DIR/Resources/ClipEase.icns" "$RESOURCES_DIR/ClipEase.icns"

if [[ -z "$SIGN_IDENTITY" ]]; then
  SIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | awk -F '\"' '/Apple Development/ { print $2; exit }' || true)"
fi

if [[ -n "$SIGN_IDENTITY" ]]; then
  codesign --force --deep --options runtime --sign "$SIGN_IDENTITY" "$APP_DIR"
else
  codesign --force --deep --sign - "$APP_DIR"
fi

echo "Built $APP_DIR"

if [[ "$RUN_APP" == "true" ]]; then
  pkill -f "$APP_DIR/Contents/MacOS/ClipEase" >/dev/null 2>&1 || true
  sleep 1
  open -n "$APP_DIR"
  sleep 2
  pgrep -fl "$APP_DIR/Contents/MacOS/ClipEase" || true
fi
