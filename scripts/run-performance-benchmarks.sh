#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WARMUP_COUNT=5
SAMPLE_COUNT=30
FIXTURE_GENERATOR="$ROOT_DIR/scripts/performance/generate_fixtures.py"
MATRIX_RUNNER="$ROOT_DIR/scripts/performance/run_benchmark_matrix.py"
BENCHMARK_DRIVER="$ROOT_DIR/Tests/ClipEaseTests/EnterprisePerformanceBenchmarkDriverTests.swift"
LOCKED_BASELINE_SHA="ad4013cce2a4e0a1648de2277126c736c0700b39"
BASELINE_PARENT=""
BASELINE_ROOT=""

test -f "$FIXTURE_GENERATOR"
test -f "$MATRIX_RUNNER"
test -f "$BENCHMARK_DRIVER"

for argument in "$@"; do
    case "$argument" in
        --candidate-root|--candidate-root=*|--baseline-root|--baseline-root=*|\
        --candidate-only|--warmups|--warmups=*|--sample-count|--sample-count=*|\
        --baseline-subject-sha|--baseline-subject-sha=*|\
        --candidate-subject-sha|--candidate-subject-sha=*)
            echo "Protected benchmark argument cannot be overridden: $argument" >&2
            exit 64
            ;;
    esac
done

cleanup() {
    if [[ -n "$BASELINE_ROOT" && -d "$BASELINE_ROOT" ]]; then
        git -C "$ROOT_DIR" worktree remove --force "$BASELINE_ROOT" >/dev/null 2>&1 || true
    fi
    if [[ -n "$BASELINE_PARENT" && -d "$BASELINE_PARENT" ]]; then
        rmdir "$BASELINE_PARENT" >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT

runner_arguments=(
    --candidate-root "$ROOT_DIR"
    --warmups "$WARMUP_COUNT"
    --sample-count "$SAMPLE_COUNT"
)

if [[ "${PERFORMANCE_CANDIDATE_ONLY:-0}" == "1" ]]; then
    runner_arguments+=(
        --candidate-only
        --candidate-subject-sha "$(git -C "$ROOT_DIR" rev-parse HEAD)"
    )
else
    if [[ -n "$(git -C "$ROOT_DIR" status --porcelain --untracked-files=all)" ]]; then
        echo "Gating benchmarks require a clean candidate worktree." >&2
        echo "Use PERFORMANCE_CANDIDATE_ONLY=1 only for non-gating diagnostics." >&2
        exit 65
    fi
    BASELINE_PARENT="$(mktemp -d "${TMPDIR:-/tmp}/clipease-performance-baseline.XXXXXX")"
    BASELINE_ROOT="$BASELINE_PARENT/worktree"
    baseline_sha="$(git -C "$ROOT_DIR" rev-parse "$LOCKED_BASELINE_SHA^{commit}")"
    if [[ "$baseline_sha" != "$LOCKED_BASELINE_SHA" ]]; then
        echo "Locked performance baseline could not be resolved exactly." >&2
        exit 66
    fi
    git -C "$ROOT_DIR" worktree add --detach "$BASELINE_ROOT" "$baseline_sha" >/dev/null
    cp "$BENCHMARK_DRIVER" \
        "$BASELINE_ROOT/Tests/ClipEaseTests/EnterprisePerformanceBenchmarkDriverTests.swift"
    runner_arguments+=(
        --baseline-root "$BASELINE_ROOT"
        --baseline-subject-sha "$baseline_sha"
        --candidate-subject-sha "$(git -C "$ROOT_DIR" rev-parse HEAD)"
    )
fi

if [[ -n "${PERFORMANCE_BENCHMARK_OUTPUT_DIR:-}" ]]; then
    runner_arguments+=(--output-root "$PERFORMANCE_BENCHMARK_OUTPUT_DIR")
fi

python3 "$MATRIX_RUNNER" "${runner_arguments[@]}" "$@"
