#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="ClipEase"
BUNDLE_ID="com.clipease.app"
MIN_SYSTEM_VERSION="13.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="$ROOT_DIR/.build/ClipEase.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
SIGN_IDENTITY="${CLIPEASE_CODESIGN_IDENTITY:-}"

case "$MODE" in
  run|--verify|verify|--logs|logs|--telemetry|telemetry|--debug|debug) ;;
  *)
    echo "usage: $0 [run|--verify|--logs|--telemetry|--debug]" >&2
    exit 2
    ;;
esac

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

swift build \
  -c release \
  -Xswiftc -strict-concurrency=complete \
  -Xswiftc -warnings-as-errors \
  --product "$APP_NAME"

BUILD_BINARY="$(swift build --show-bin-path --configuration release)/$APP_NAME"
if [[ ! -x "$BUILD_BINARY" ]]; then
  echo "release binary not found: $BUILD_BINARY" >&2
  exit 1
fi

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"
cp "$ROOT_DIR/Resources/Info.plist" "$APP_CONTENTS/Info.plist"
cp "$ROOT_DIR/Resources/ClipEase.icns" "$APP_RESOURCES/ClipEase.icns"
if [[ -d "$ROOT_DIR/Resources/Sounds" ]]; then
  cp -R "$ROOT_DIR/Resources/Sounds" "$APP_RESOURCES/Sounds"
fi
if [[ -d "$ROOT_DIR/Resources/Support" ]]; then
  cp -R "$ROOT_DIR/Resources/Support" "$APP_RESOURCES/Support"
fi

if [[ -z "$SIGN_IDENTITY" ]]; then
  SIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | awk -F '\"' '/Apple Development/ { print $2; exit }' || true)"
fi
if [[ -n "$SIGN_IDENTITY" ]]; then
  codesign --force --deep --options runtime --sign "$SIGN_IDENTITY" "$APP_BUNDLE"
else
  codesign --force --deep --sign - "$APP_BUNDLE"
fi

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --verify|verify)
    open_app
    sleep 2
    pgrep -x "$APP_NAME" >/dev/null
    echo "$APP_NAME is running (PID $(pgrep -x "$APP_NAME" | head -1))"
    ;;
  --logs|logs)
    open_app
    exec /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    exec /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --debug|debug)
    exec lldb -- "$APP_BINARY"
    ;;
esac
