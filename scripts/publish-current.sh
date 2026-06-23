#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NOTES_FILE=""

usage() {
  cat <<'EOF'
Usage: scripts/publish-current.sh --notes-file <path>

Publishes the already-committed current version:
  1. runs scripts/release.sh --bump none --publish --notes-file <path>
  2. rebuilds and runs .build/ClipEase.app for local testing

The notes file should contain the human-written release body for this release.
The release script appends generated verification metadata automatically.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --notes-file)
      NOTES_FILE="${2:-}"
      shift 2
      ;;
    --notes-file=*)
      NOTES_FILE="${1#*=}"
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

if [[ -z "$NOTES_FILE" ]]; then
  echo "Missing required --notes-file." >&2
  usage >&2
  exit 1
fi

"$ROOT_DIR/scripts/release.sh" --bump none --publish --notes-file "$NOTES_FILE"
"$ROOT_DIR/scripts/build-app.sh" --bump none --preserve-build --run
