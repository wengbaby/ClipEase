#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build/release"
APP_DIR="$ROOT_DIR/.build/ClipEase.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
BUMP_TYPE="none"
RUN_APP="false"

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

echo "Built $APP_DIR"

if [[ "$RUN_APP" == "true" ]]; then
  pkill -x ClipEase >/dev/null 2>&1 || true
  sleep 1
  open -n "$APP_DIR"
  sleep 1
  pgrep -fl ClipEase || true
fi
