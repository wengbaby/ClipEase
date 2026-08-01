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
PRESERVE_BUILD="false"
STRICT_RELEASE_BUILD_COMMAND=(
  swift build
  -c release
  -Xswiftc -strict-concurrency=complete
  -Xswiftc -warnings-as-errors
  --product ClipEase
)

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
    --preserve-build)
      PRESERVE_BUILD="true"
      shift
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

BUMP_ARGS=(--bump "$BUMP_TYPE")
if [[ "$PRESERVE_BUILD" == "true" ]]; then
  BUMP_ARGS+=(--preserve-build)
fi

python3 "$ROOT_DIR/scripts/bump_version.py" "${BUMP_ARGS[@]}"

CANDIDATE_SUBJECT_GIT_SHA="$(git -C "$ROOT_DIR" rev-parse HEAD)"
STRICT_RELEASE_BUILD_COMMAND_TEXT="${STRICT_RELEASE_BUILD_COMMAND[*]}"
printf 'Subject Git SHA: %s\n' "$CANDIDATE_SUBJECT_GIT_SHA"
printf 'Strict release build command: %s\n' "$STRICT_RELEASE_BUILD_COMMAND_TEXT"
"${STRICT_RELEASE_BUILD_COMMAND[@]}"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$BUILD_DIR/ClipEase" "$MACOS_DIR/ClipEase"
cp "$ROOT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$ROOT_DIR/Resources/ClipEase.icns" "$RESOURCES_DIR/ClipEase.icns"
if [[ -d "$ROOT_DIR/Resources/Sounds" ]]; then
  cp -R "$ROOT_DIR/Resources/Sounds" "$RESOURCES_DIR/Sounds"
fi
if [[ -d "$ROOT_DIR/Resources/Support" ]]; then
  cp -R "$ROOT_DIR/Resources/Support" "$RESOURCES_DIR/Support"
fi

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
