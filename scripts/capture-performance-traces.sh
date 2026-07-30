#!/usr/bin/env bash
set -euo pipefail

usage() {
    echo "Usage: $0 --process NAME --output NEW_COLLECTION.trace --run-id ID --subject-git-sha SHA --source-root PATH --executable PATH [--duration 30s] [--include-sensitive-local-traces]"
}

process_name=""
output_path=""
duration="30s"
run_id=""
subject_git_sha=""
source_root=""
executable_path=""
include_sensitive_local_traces=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --process)
            process_name="${2:-}"
            shift 2
            ;;
        --output)
            output_path="${2:-}"
            shift 2
            ;;
        --duration)
            duration="${2:-}"
            shift 2
            ;;
        --run-id)
            run_id="${2:-}"
            shift 2
            ;;
        --subject-git-sha)
            subject_git_sha="${2:-}"
            shift 2
            ;;
        --source-root)
            source_root="${2:-}"
            shift 2
            ;;
        --executable)
            executable_path="${2:-}"
            shift 2
            ;;
        --include-sensitive-local-traces)
            include_sensitive_local_traces=true
            shift
            ;;
        *)
            usage
            exit 64
            ;;
    esac
done

if [[ ! "$process_name" =~ ^[A-Za-z0-9._\ -]+$ ]]; then
    echo "Process name is empty or contains unsupported characters." >&2
    exit 64
fi
if [[ -z "$output_path" || "${output_path##*.}" != "trace" ]]; then
    echo "Output must be a new path ending in .trace." >&2
    exit 64
fi
if [[ -e "$output_path" ]]; then
    echo "Refusing to replace existing trace collection: $output_path" >&2
    exit 73
fi
poi_output_path="${output_path%.trace}-poi.xml"
if [[ -e "$poi_output_path" ]]; then
    echo "Refusing to replace existing normalized POI export: $poi_output_path" >&2
    exit 73
fi
if [[ ! "$run_id" =~ ^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$ ]]; then
    echo "Run ID is empty or contains unsupported characters." >&2
    exit 64
fi
if [[ ! "$subject_git_sha" =~ ^[0-9a-fA-F]{40,64}$ ]]; then
    echo "Subject Git SHA must be a full hexadecimal object ID." >&2
    exit 64
fi
if [[ ! -d "$source_root" ]]; then
    echo "Source root does not exist: $source_root" >&2
    exit 66
fi
if [[ ! -f "$executable_path" ]]; then
    echo "Executable does not exist: $executable_path" >&2
    exit 66
fi

source_root="$(cd "$source_root" && pwd -P)"
executable_path="$(cd "$(dirname "$executable_path")" && pwd -P)/$(basename "$executable_path")"
actual_subject_git_sha="$(/usr/bin/git -C "$source_root" rev-parse HEAD)"
if [[ "$actual_subject_git_sha" != "$subject_git_sha" ]]; then
    echo "Source root HEAD does not match --subject-git-sha." >&2
    exit 65
fi
mapfile_status="$(/usr/bin/git -C "$source_root" status --porcelain --untracked-files=all)"
if [[ -n "$mapfile_status" ]]; then
    echo "Trace capture requires a clean source worktree." >&2
    exit 65
fi

pid_output="$(/usr/bin/pgrep -x "$process_name" || true)"
if [[ -z "$pid_output" ]]; then
    echo "Target process is not running: $process_name" >&2
    exit 69
fi
if [[ "$(printf '%s\n' "$pid_output" | /usr/bin/wc -l | tr -d ' ')" != "1" ]]; then
    echo "Trace capture requires exactly one target process: $process_name" >&2
    exit 69
fi
target_pid="$pid_output"
running_command="$(/bin/ps -p "$target_pid" -o comm= | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
if [[ "$(basename "$running_command")" != "$process_name" ]]; then
    echo "Resolved PID does not belong to the requested process." >&2
    exit 69
fi
if [[ "$(basename "$executable_path")" != "$process_name" ]]; then
    echo "Executable basename does not match the requested process." >&2
    exit 65
fi

executable_sha256="$(/usr/bin/shasum -a 256 "$executable_path" | /usr/bin/awk '{print $1}')"
uuid_output="$(xcrun dwarfdump --uuid "$executable_path")"
if [[ -z "$uuid_output" || "$uuid_output" != *"UUID:"* ]]; then
    echo "Executable has no inspectable Mach-O UUID." >&2
    exit 65
fi
script_path="$(cd "$(dirname "$0")" && pwd -P)/$(basename "$0")"
capture_harness_sha256="$(/usr/bin/shasum -a 256 "$script_path" | /usr/bin/awk '{print $1}')"

mkdir -p "$output_path"
executable_artifact="$output_path/ClipEase-executable"
/bin/cp -p "$executable_path" "$executable_artifact"

trace_ids=(
    swiftui
    time-profiler-poi
    animation-hitches
    system-trace
    power-profiler
    allocations
    leaks
)
templates=(
    "SwiftUI"
    "Time Profiler"
    "Animation Hitches"
    "System Trace"
    "Power Profiler"
    "Allocations"
    "Leaks"
)
extra_instruments=(
    ""
    "Points of Interest"
    "Core Animation FPS"
    ""
    ""
    ""
    ""
)
if [[ "$include_sensitive_local_traces" == true ]]; then
    trace_ids+=(file-activity)
    templates+=("File Activity")
    extra_instruments+=("")
fi

echo "Continuously repeat the approved ClipEase workload while traces are captured."
for index in "${!trace_ids[@]}"; do
    trace_id="${trace_ids[$index]}"
    template="${templates[$index]}"
    instrument="${extra_instruments[$index]}"
    destination="$output_path/$trace_id.trace"
    arguments=(
        xcrun xctrace record
        --no-prompt
        --template "$template"
        --attach "$target_pid"
        --time-limit "$duration"
        --output "$destination"
        --run-name "ClipEase enterprise performance $run_id"
    )
    if [[ -n "$instrument" ]]; then
        arguments+=(--instrument "$instrument")
    fi
    echo "Capturing $template ($trace_id)..."
    "${arguments[@]}"
    if [[ ! -e "$destination" ]]; then
        echo "xctrace did not produce $destination" >&2
        exit 74
    fi
done

captured_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
/usr/bin/python3 - \
    "$output_path/clipease-trace-manifest.json" \
    "$captured_at" \
    "$run_id" \
    "$subject_git_sha" \
    "$capture_harness_sha256" \
    "$process_name" \
    "$executable_sha256" \
    "$uuid_output" \
    "$include_sensitive_local_traces" <<'PY'
import json
import re
import sys
from pathlib import Path

(
    manifest_path,
    captured_at,
    run_id,
    subject_git_sha,
    capture_harness_sha256,
    process_name,
    executable_sha256,
    uuid_output,
    include_sensitive_local_traces,
) = sys.argv[1:]
uuids = sorted(set(re.findall(
    r"[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-"
    r"[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}",
    uuid_output,
)))
if not uuids:
    raise SystemExit("dwarfdump returned no parseable Mach-O UUID")
manifest = {
    "schemaVersion": 2,
    "capturedAt": captured_at,
    "runID": run_id,
    "subjectGitSHA": subject_git_sha.lower(),
    "captureHarnessSHA256": capture_harness_sha256,
    "targetProcess": process_name,
    "sourceWorktreeClean": True,
    "sharingClassification": (
        "local-only-sensitive-paths"
        if include_sensitive_local_traces == "true"
        else "shareable"
    ),
    "pathContentPolicy": (
        "contains-sensitive-path-data"
        if include_sensitive_local_traces == "true"
        else "file-activity-excluded"
    ),
    "executable": {
        "relativePath": "ClipEase-executable",
        "sha256": executable_sha256,
        "machOUUIDs": [value.upper() for value in uuids],
    },
    "traces": [
        {
            "id": "swiftui",
            "template": "SwiftUI",
            "relativePath": "swiftui.trace",
            "sharingClassification": "shareable",
        },
        {
            "id": "time-profiler-poi",
            "template": "Time Profiler",
            "instrument": "Points of Interest",
            "relativePath": "time-profiler-poi.trace",
            "sharingClassification": "shareable",
        },
        {
            "id": "animation-hitches",
            "template": "Animation Hitches",
            "instrument": "Core Animation FPS",
            "relativePath": "animation-hitches.trace",
            "sharingClassification": "shareable",
        },
        {
            "id": "system-trace",
            "template": "System Trace",
            "relativePath": "system-trace.trace",
            "sharingClassification": "shareable",
        },
        {
            "id": "power-profiler",
            "template": "Power Profiler",
            "relativePath": "power-profiler.trace",
            "sharingClassification": "shareable",
        },
        {
            "id": "allocations",
            "template": "Allocations",
            "relativePath": "allocations.trace",
            "sharingClassification": "shareable",
        },
        {
            "id": "leaks",
            "template": "Leaks",
            "relativePath": "leaks.trace",
            "sharingClassification": "shareable",
        },
    ],
}
if include_sensitive_local_traces == "true":
    manifest["traces"].append({
        "id": "file-activity",
        "template": "File Activity",
        "relativePath": "file-activity.trace",
        "sharingClassification": "local-only-sensitive-paths",
    })
Path(manifest_path).write_text(
    json.dumps(manifest, indent=2, sort_keys=True) + "\n"
)
PY

poi_export_tmp="$(mktemp -d "${TMPDIR:-/tmp}/clipease-poi.XXXXXX")"
cleanup_poi_export_tmp() {
    /bin/rm -rf "$poi_export_tmp"
}
trap cleanup_poi_export_tmp EXIT
raw_poi_export="$poi_export_tmp/xctrace-poi.xml"
xcrun xctrace export \
    --input "$output_path/time-profiler-poi.trace" \
    --xpath '/trace-toc/run[@number="1"]/data/table[@schema="os-signpost"]' \
    --output "$raw_poi_export"
trace_tree_sha256="$(/usr/bin/python3 - "$output_path" <<'PY'
import hashlib
import sys
from pathlib import Path

root = Path(sys.argv[1])
digest = hashlib.sha256()
for path in sorted(item for item in root.rglob("*") if item.is_file()):
    relative = path.relative_to(root).as_posix().encode()
    file_digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            file_digest.update(chunk)
    digest.update(len(relative).to_bytes(4, "big"))
    digest.update(relative)
    digest.update(path.stat().st_size.to_bytes(8, "big"))
    digest.update(file_digest.digest())
print(digest.hexdigest())
PY
)"
runtime_evidence_module="$(cd "$(dirname "$0")" && pwd -P)/performance/write_runtime_evidence.py"
/usr/bin/python3 - \
    "$runtime_evidence_module" \
    "$raw_poi_export" \
    "$poi_output_path" \
    "$run_id" \
    "$subject_git_sha" \
    "$trace_tree_sha256" <<'PY'
import importlib.util
import sys
from pathlib import Path

(
    module_path,
    raw_export_path,
    output_path,
    run_id,
    subject_git_sha,
    trace_tree_sha256,
) = sys.argv[1:]
spec = importlib.util.spec_from_file_location(
    "_clipease_runtime_evidence",
    module_path,
)
if spec is None or spec.loader is None:
    raise SystemExit("could not load the POI normalization validator")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
module.normalize_poi_export(
    Path(raw_export_path),
    Path(output_path),
    run_id=run_id,
    subject_git_sha=subject_git_sha.lower(),
    trace_tree_sha256=trace_tree_sha256,
)
PY

echo "Trace collection ready: $output_path"
echo "Normalized POI export ready: $poi_output_path"
