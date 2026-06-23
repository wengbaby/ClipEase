#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/.build/release-artifacts"
APP_DIR="$ROOT_DIR/.build/ClipEase.app"
TEMPLATE_FILE="$ROOT_DIR/docs/releases/release-notes-template.md"
CUSTOM_NOTES_FILE=""
BUMP_TYPE="patch"
PUBLISH="false"
DRY_RUN="false"
SKIP_TESTS="false"
CREATED_TAG="false"

usage() {
  cat <<'EOF'
Usage: scripts/release.sh [options]

Options:
  --bump <none|patch|minor|major>  Version bump passed to scripts/build-app.sh. Default: patch.
  --publish                       Create git tag, GitHub Release, and upload the DMG.
  --dry-run                       Build and verify release artifacts without git tag, GitHub Release, or upload.
  --skip-tests                    Skip swift test. Use only when tests were already run.
  --notes-file <path>             Use human-written release notes, then append generated verification metadata.
  -h, --help                      Show this help.

Output:
  .build/release-artifacts/ClipEase-<version>-<build>.dmg
  .build/release-artifacts/release-v<version>-<build>.md
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bump)
      BUMP_TYPE="${2:-}"
      shift 2
      ;;
    --bump=*)
      BUMP_TYPE="${1#*=}"
      shift
      ;;
    --publish)
      PUBLISH="true"
      shift
      ;;
    --dry-run)
      DRY_RUN="true"
      shift
      ;;
    --skip-tests)
      SKIP_TESTS="true"
      shift
      ;;
    --notes-file)
      CUSTOM_NOTES_FILE="${2:-}"
      shift 2
      ;;
    --notes-file=*)
      CUSTOM_NOTES_FILE="${1#*=}"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

case "$BUMP_TYPE" in
  none|patch|minor|major) ;;
  *)
    echo "Unsupported bump type: $BUMP_TYPE" >&2
    exit 1
    ;;
esac

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

resolve_notes_file() {
  local path="$1"

  if [[ -z "$path" ]]; then
    echo "--notes-file requires a path." >&2
    exit 1
  fi

  if [[ "$path" != /* ]]; then
    path="$ROOT_DIR/$path"
  fi

  if [[ ! -f "$path" ]]; then
    echo "Release notes file does not exist: $path" >&2
    exit 1
  fi

  CUSTOM_NOTES_FILE="$path"
}

if [[ -n "$CUSTOM_NOTES_FILE" ]]; then
  resolve_notes_file "$CUSTOM_NOTES_FILE"
fi

ensure_clean_worktree_for_publish() {
  if [[ "$BUMP_TYPE" != "none" ]]; then
    echo "Release publishing requires a committed version. Re-run with --bump none after committing the version bump." >&2
    exit 1
  fi

  if [[ -n "$(git status --porcelain)" ]]; then
    echo "Release publishing requires a clean git worktree." >&2
    exit 1
  fi
}

verify_remote_state_before_publish() {
  git fetch origin main

  local current_branch
  current_branch="$(git branch --show-current)"
  if [[ -z "$current_branch" ]]; then
    echo "Cannot publish from detached HEAD." >&2
    exit 1
  fi

  if ! git merge-base --is-ancestor origin/main HEAD; then
    echo "Remote main has commits not present locally. Rebase or merge origin/main before publishing." >&2
    exit 1
  fi

  PUBLISH_BRANCH="$current_branch"
}

ensure_tests_run_before_publish() {
  if [[ "$PUBLISH" == "true" && "$DRY_RUN" != "true" && "$SKIP_TESTS" == "true" ]]; then
    echo "Release publishing cannot use --skip-tests. Run full tests before creating a release." >&2
    exit 1
  fi
}

cleanup_created_tag() {
  if [[ "${CREATED_TAG:-false}" == "true" ]]; then
    git tag -d "$TAG" >/dev/null 2>&1 || true
  fi
}

plist_value() {
  /usr/libexec/PlistBuddy -c "Print :$2" "$1"
}

verify_release_notes_metadata() {
  local body_path="$1"
  local version="$2"
  local build="$3"
  local dmg_name="$4"
  local sha256="$5"

  if ! grep -Fq "$version ($build)" "$body_path"; then
    echo "Release notes missing version metadata: $version ($build)" >&2
    exit 1
  fi
  if ! grep -Fq "$dmg_name" "$body_path"; then
    echo "Release notes missing DMG name: $dmg_name" >&2
    exit 1
  fi
  if ! grep -Fq "$sha256" "$body_path"; then
    echo "Release notes missing SHA-256: $sha256" >&2
    exit 1
  fi
}

verify_github_release_asset_hash() {
  local tag="$1"
  local asset_name="$2"
  local expected_sha256="$3"
  local download_dir
  local downloaded_asset
  local actual_sha256

  download_dir="$(mktemp -d "${TMPDIR:-/tmp}/clipease-release-asset.XXXXXX")"
  gh release download "$tag" --pattern "$asset_name" --dir "$download_dir" --clobber
  downloaded_asset="$download_dir/$asset_name"

  actual_sha256="$(shasum -a 256 "$downloaded_asset" | awk '{ print $1 }')"
  rm -rf "$download_dir"

  if [[ "$actual_sha256" != "$expected_sha256" ]]; then
    echo "GitHub release asset SHA-256 mismatch: expected=$expected_sha256, actual=$actual_sha256" >&2
    exit 1
  fi

  echo "Verified GitHub release asset SHA-256: $actual_sha256"
}

print_publish_fallback_instructions() {
  cat <<EOF
免费发布失败恢复步骤：
1. 如果分支推送失败，修复网络或认证后重跑本脚本，或先手动执行：git push origin "HEAD:${PUBLISH_BRANCH}"
2. 如果 tag 推送失败，确认本地 tag 存在后执行：git push origin "$TAG"
3. 如果 GitHub Release 创建失败，确认 tag 已推送后执行：
   gh release create "$TAG" "$DMG_PATH" --title "$TITLE" --notes-file "$BODY_PATH"
4. 如果上传后 hash 校验失败，删除远端错误 asset 后重新上传，并用本地 SHA-256 对照：$SHA256
GitHub 网页备用：
   打开 GitHub Releases 页面，选择 tag "$TAG"，标题填写 "$TITLE"，正文使用 "$BODY_PATH"，上传 "$DMG_PATH"。
GitHub API 备用：
   可用 GitHub REST API 创建 release，再按 upload_url 上传 "$DMG_NAME"；上传后必须重新校验 SHA-256。
SSH 443 备用：
   如果普通 SSH 推送失败，可配置 github.com 走 ssh.github.com:443 后再重试 git push。
EOF
}

require_command swift
require_command create-dmg
require_command hdiutil
require_command shasum

if [[ "$PUBLISH" == "true" && "$DRY_RUN" != "true" ]]; then
  require_command git
  require_command gh
  ensure_tests_run_before_publish
  ensure_clean_worktree_for_publish
  verify_remote_state_before_publish
fi

if [[ "$SKIP_TESTS" != "true" ]]; then
  swift test
fi

BUILD_ARGS=(--bump "$BUMP_TYPE")
if [[ "$BUMP_TYPE" == "none" ]]; then
  BUILD_ARGS+=(--preserve-build)
fi

"$ROOT_DIR/scripts/build-app.sh" "${BUILD_ARGS[@]}"

VERSION="$(plist_value "$ROOT_DIR/Resources/Info.plist" CFBundleShortVersionString)"
BUILD="$(plist_value "$ROOT_DIR/Resources/Info.plist" CFBundleVersion)"
APP_VERSION="$(plist_value "$APP_DIR/Contents/Info.plist" CFBundleShortVersionString)"
APP_BUILD="$(plist_value "$APP_DIR/Contents/Info.plist" CFBundleVersion)"

if [[ "$APP_VERSION" != "$VERSION" || "$APP_BUILD" != "$BUILD" ]]; then
  echo "App version mismatch: Resources=$VERSION ($BUILD), app=$APP_VERSION ($APP_BUILD)" >&2
  exit 1
fi

TAG="v${VERSION}-${BUILD}"
TITLE="ClipEase ${VERSION} (${BUILD})"
DMG_NAME="ClipEase-${VERSION}-${BUILD}.dmg"
DMG_PATH="$DIST_DIR/$DMG_NAME"
BODY_PATH="$DIST_DIR/release-${TAG}.md"
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/clipease-release.XXXXXX")"
MOUNT_POINT=""

cleanup() {
  if [[ -n "$MOUNT_POINT" && -d "$MOUNT_POINT" ]]; then
    hdiutil detach "$MOUNT_POINT" >/dev/null 2>&1 || true
  fi
  rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR" "$STAGING_DIR"
cp -R "$APP_DIR" "$STAGING_DIR/ClipEase.app"

create-dmg \
  --volname "ClipEase ${VERSION}" \
  --volicon "$ROOT_DIR/Resources/ClipEase.icns" \
  --window-size 640 420 \
  --icon-size 96 \
  --icon "ClipEase.app" 180 190 \
  --app-drop-link 460 190 \
  --no-internet-enable \
  "$DMG_PATH" \
  "$STAGING_DIR"

hdiutil verify "$DMG_PATH"

MOUNT_OUTPUT="$(hdiutil attach "$DMG_PATH" -nobrowse -readonly)"
MOUNT_POINT="$(printf '%s\n' "$MOUNT_OUTPUT" | awk '/\/Volumes\// { sub(/^.*\/Volumes\//, "/Volumes/"); print; exit }')"

if [[ -z "$MOUNT_POINT" || ! -d "$MOUNT_POINT/ClipEase.app" ]]; then
  echo "Failed to locate mounted ClipEase.app in DMG." >&2
  exit 1
fi

DMG_APP_VERSION="$(plist_value "$MOUNT_POINT/ClipEase.app/Contents/Info.plist" CFBundleShortVersionString)"
DMG_APP_BUILD="$(plist_value "$MOUNT_POINT/ClipEase.app/Contents/Info.plist" CFBundleVersion)"

if [[ "$DMG_APP_VERSION" != "$VERSION" || "$DMG_APP_BUILD" != "$BUILD" ]]; then
  echo "DMG version mismatch: expected=$VERSION ($BUILD), dmg=$DMG_APP_VERSION ($DMG_APP_BUILD)" >&2
  exit 1
fi

hdiutil detach "$MOUNT_POINT" >/dev/null
MOUNT_POINT=""

SHA256="$(shasum -a 256 "$DMG_PATH" | awk '{ print $1 }')"
TEST_LINE="已通过 \`swift test\`。"
if [[ "$SKIP_TESTS" == "true" ]]; then
  TEST_LINE="本次脚本跳过 \`swift test\`，请确认发布前已单独通过完整测试。"
fi

python3 - "$TEMPLATE_FILE" "$CUSTOM_NOTES_FILE" "$BODY_PATH" "$VERSION" "$BUILD" "$DMG_NAME" "$SHA256" "$TEST_LINE" <<'PY'
import sys
from pathlib import Path

template_path, notes_path, body_path, version, build, dmg_name, sha256, test_line = sys.argv[1:]
if notes_path:
    intro = Path(notes_path).read_text(encoding="utf-8").strip()
    body = f"""{intro}

## 验证

- {test_line}
- 已构建 `.build/ClipEase.app`，版本为 `{version} ({build})`。
- 已生成并验证 `{dmg_name}`。
- 已挂载 DMG 检查内部 `ClipEase.app` 版本为 `{version} ({build})`。
- DMG SHA-256：`{sha256}`。
"""
else:
    body = Path(template_path).read_text(encoding="utf-8")
replacements = {
    "{{VERSION}}": version,
    "{{BUILD}}": build,
    "{{DMG_NAME}}": dmg_name,
    "{{SHA256}}": sha256,
    "{{TEST_LINE}}": test_line,
}
for key, value in replacements.items():
    body = body.replace(key, value)
Path(body_path).write_text(body, encoding="utf-8")
PY

verify_release_notes_metadata "$BODY_PATH" "$VERSION" "$BUILD" "$DMG_NAME" "$SHA256"

echo "Release title: $TITLE"
echo "Release tag:   $TAG"
echo "DMG:           $DMG_PATH"
echo "SHA-256:       $SHA256"
echo "Body:          $BODY_PATH"

if [[ "$DRY_RUN" == "true" ]]; then
  echo "Dry run complete. No git tag, GitHub Release, or upload was created."
  exit 0
fi

if [[ "$PUBLISH" == "true" ]]; then
  if git rev-parse "$TAG" >/dev/null 2>&1; then
    echo "Tag already exists locally: $TAG" >&2
    exit 1
  fi
  if gh release view "$TAG" >/dev/null 2>&1; then
    echo "Release already exists remotely: $TAG" >&2
    exit 1
  fi

  print_publish_fallback_instructions
  git push origin "HEAD:${PUBLISH_BRANCH}"
  git tag "$TAG"
  CREATED_TAG="true"
  trap 'cleanup_created_tag; cleanup' EXIT

  git push origin "$TAG"
  gh release create "$TAG" "$DMG_PATH" --title "$TITLE" --notes-file "$BODY_PATH"
  verify_github_release_asset_hash "$TAG" "$DMG_NAME" "$SHA256"
  CREATED_TAG="false"
fi
