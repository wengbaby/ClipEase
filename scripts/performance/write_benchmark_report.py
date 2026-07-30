#!/usr/bin/env python3
"""Write a versioned, per-metric ClipEase performance report."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import random
import re
from pathlib import Path
from typing import Any


PERCENTILES = {"p50": 0.50, "p95": 0.95, "p99": 0.99}
BOOTSTRAP_ROUNDS = 2_000
BASELINE_HARNESS_STATUS = (
    "?? Tests/ClipEaseTests/"
    "EnterprisePerformanceBenchmarkDriverTests.swift"
)


def percentile(values: list[float], fraction: float) -> float:
    if not values:
        raise ValueError("cannot calculate a percentile for an empty sample")
    ordered = sorted(values)
    position = (len(ordered) - 1) * fraction
    lower = math.floor(position)
    upper = math.ceil(position)
    return ordered[lower] + (ordered[upper] - ordered[lower]) * (position - lower)


def bootstrap_percentile_ci(
    values: list[float],
    fraction: float,
    rounds: int = BOOTSTRAP_ROUNDS,
) -> list[float]:
    seed = int(fraction * 10_000) + len(values)
    randomizer = random.Random(seed)
    estimates = []
    for _ in range(rounds):
        resample = [randomizer.choice(values) for _ in values]
        estimates.append(percentile(resample, fraction))
    return [percentile(estimates, 0.025), percentile(estimates, 0.975)]


def statistics(values: list[float]) -> dict[str, Any]:
    result: dict[str, Any] = {
        name: percentile(values, fraction)
        for name, fraction in PERCENTILES.items()
    }
    result["max"] = max(values)
    result["bootstrap95CI"] = {
        name: bootstrap_percentile_ci(values, fraction)
        for name, fraction in PERCENTILES.items()
    }
    return result


def load_sample_rows(path: Path, expected_count: int) -> list[dict[str, Any]]:
    rows = [
        json.loads(line)
        for line in path.read_text().splitlines()
        if line.strip()
    ]
    if len(rows) != expected_count:
        raise SystemExit(f"expected {expected_count} sample rows, got {len(rows)}")

    iterations = [row.get("iteration") for row in rows]
    if sorted(iterations) != list(range(expected_count)):
        raise SystemExit(
            "sample iterations must be unique and contiguous from 0 "
            f"through {expected_count - 1}; got {iterations}"
        )

    expected_metrics = set(rows[0].get("metrics", {}))
    if not expected_metrics:
        raise SystemExit("sample rows must include at least one metric")
    for row in rows:
        if set(row.get("metrics", {})) != expected_metrics:
            raise SystemExit("every sample row must contain the same metric names")
        for name, measurement in row["metrics"].items():
            for field in ("durationMS", "rssMiB", "cpuTimeMS"):
                value = measurement.get(field)
                if not isinstance(value, (int, float)) or not math.isfinite(value) or value < 0:
                    raise SystemExit(
                        f"metric {name!r} field {field!r} must be a finite non-negative number"
                    )
    return sorted(rows, key=lambda row: row["iteration"])


def build_metrics(rows: list[dict[str, Any]]) -> dict[str, Any]:
    metric_names = sorted(rows[0]["metrics"])
    metrics: dict[str, Any] = {}
    for name in metric_names:
        raw_samples = [
            {
                "iteration": row["iteration"],
                "durationMS": float(row["metrics"][name]["durationMS"]),
                "rssMiB": float(row["metrics"][name]["rssMiB"]),
                "cpuTimeMS": float(row["metrics"][name]["cpuTimeMS"]),
            }
            for row in rows
        ]
        metrics[name] = {
            "rawSamples": raw_samples,
            "durationMS": statistics(
                [sample["durationMS"] for sample in raw_samples]
            ),
            "rssMiB": statistics([sample["rssMiB"] for sample in raw_samples]),
            "cpuTimeMS": statistics(
                [sample["cpuTimeMS"] for sample in raw_samples]
            ),
        }
    return metrics


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--samples", required=True, type=Path)
    parser.add_argument("--fixtures", required=True, type=Path)
    parser.add_argument("--fixture-root", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--run-id", required=True)
    parser.add_argument("--git-sha", required=True)
    parser.add_argument("--subject-git-sha", required=True)
    parser.add_argument("--harness-sha256", required=True)
    parser.add_argument("--worktree-status", required=True)
    parser.add_argument("--hardware", required=True)
    parser.add_argument("--os", required=True)
    parser.add_argument("--power-state", required=True)
    parser.add_argument("--thermal-state", required=True)
    parser.add_argument("--warmups", required=True, type=int)
    parser.add_argument("--sample-count", required=True, type=int)
    parser.add_argument("--raw-artifact", required=True, type=Path)
    parser.add_argument(
        "--trace-status",
        required=True,
        choices=("available", "missing", "not-collected"),
    )
    parser.add_argument("--trace-path", type=Path)
    return parser.parse_args()


def parse_json_object(value: str, label: str) -> dict[str, Any]:
    try:
        parsed = json.loads(value)
    except json.JSONDecodeError as error:
        raise SystemExit(f"{label} must be a JSON object: {error}") from error
    if not isinstance(parsed, dict) or not parsed:
        raise SystemExit(f"{label} must be a non-empty JSON object")
    if any(item in ("", "unavailable") for item in parsed.values()):
        raise SystemExit(f"{label} contains unavailable metadata")
    return parsed


def validate_git_sha(value: str, label: str) -> str:
    if re.fullmatch(r"[0-9a-fA-F]{40,64}", value) is None:
        raise SystemExit(f"{label} must be a full hexadecimal Git object ID")
    return value.lower()


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def tree_sha256(root: Path) -> str:
    digest = hashlib.sha256()
    files = sorted(
        (path for path in root.rglob("*") if path.is_file()),
        key=lambda path: path.relative_to(root).as_posix(),
    )
    for path in files:
        relative = path.relative_to(root).as_posix().encode("utf-8")
        digest.update(len(relative).to_bytes(4, "big"))
        digest.update(relative)
        digest.update(path.stat().st_size.to_bytes(8, "big"))
        digest.update(bytes.fromhex(file_sha256(path)))
    return digest.hexdigest()


def relative_artifact_path(
    path: Path,
    output_root: Path,
    label: str,
) -> str:
    """Return a relocatable artifact path without leaking host directories."""
    resolved_path = path.resolve()
    resolved_root = output_root.resolve()
    try:
        relative = resolved_path.relative_to(resolved_root)
    except ValueError as error:
        raise ValueError(f"{label} is outside output root") from error
    return relative.as_posix()


def summarize_worktree_status(status: list[str]) -> dict[str, Any]:
    """Preserve certification state without persisting changed filenames."""
    if not status:
        return {"entryCount": 0, "state": "clean"}
    if status == [BASELINE_HARNESS_STATUS]:
        return {"entryCount": 1, "state": "baseline-harness-only"}
    return {"entryCount": len(status), "state": "dirty"}


def validate_fixture_payloads(
    fixtures: list[dict[str, Any]],
    fixture_root: Path,
) -> None:
    if not fixture_root.is_dir():
        raise SystemExit("fixture root does not exist")
    expected_counts = {
        "S1K": 1_000,
        "T10K": 10_000,
        "M100K": 100_000,
        "A3K": 3_000,
    }
    actual_counts = {
        fixture.get("id"): fixture.get("itemCount")
        for fixture in fixtures
    }
    if actual_counts != expected_counts:
        raise SystemExit("fixture IDs and item counts do not match the enterprise contract")
    standardized_root = fixture_root.resolve()
    for fixture in fixtures:
        relative_path = fixture.get("relativePath")
        if not isinstance(relative_path, str) or not relative_path:
            raise SystemExit("fixture relativePath must be a non-empty string")
        payload = (fixture_root / relative_path).resolve()
        if standardized_root not in payload.parents or not payload.is_dir():
            raise SystemExit("fixture relativePath escapes the fixture root")
        files = [path for path in payload.rglob("*") if path.is_file()]
        if len(files) != fixture.get("fileCount"):
            raise SystemExit(f"fixture {fixture.get('id')} file count changed")
        if sum(path.stat().st_size for path in files) != fixture.get("payloadByteCount"):
            raise SystemExit(f"fixture {fixture.get('id')} payload size changed")
        if tree_sha256(payload) != fixture.get("treeSHA256"):
            raise SystemExit(f"fixture {fixture.get('id')} tree hash changed")


def main() -> None:
    args = parse_arguments()
    if args.warmups != 5:
        raise SystemExit(f"enterprise contract requires 5 warmups, got {args.warmups}")
    if args.sample_count != 30:
        raise SystemExit(
            f"enterprise contract requires 30 formal samples, got {args.sample_count}"
        )
    if args.trace_status == "available" and args.trace_path is None:
        raise SystemExit("--trace-path is required when --trace-status=available")
    if args.trace_status != "available" and args.trace_path is not None:
        raise SystemExit("--trace-path is only valid when --trace-status=available")
    if args.trace_path is not None:
        if not args.trace_path.is_dir() or args.trace_path.suffix != ".trace":
            raise SystemExit(
                "available trace must be an existing .trace collection directory"
            )
        trace_manifest = args.trace_path / "clipease-trace-manifest.json"
        if not trace_manifest.is_file():
            raise SystemExit("available trace collection has no ClipEase manifest")
    if args.power_state != "AC Power":
        raise SystemExit("enterprise benchmark reports require AC Power")
    if args.thermal_state != "nominal":
        raise SystemExit("enterprise benchmark reports require nominal thermal state")
    if not args.raw_artifact.exists():
        raise SystemExit("raw sample artifact does not exist")
    if args.raw_artifact.resolve() != args.samples.resolve():
        raise SystemExit("raw sample artifact must identify the measured sample file")

    rows = load_sample_rows(args.samples, args.sample_count)
    fixture_document = json.loads(args.fixtures.read_text())
    if fixture_document.get("schemaVersion") != 2:
        raise SystemExit("fixture manifest schemaVersion must be 2")
    fixtures = fixture_document.get("fixtures")
    if not isinstance(fixtures, list) or not fixtures:
        raise SystemExit("fixture manifest must contain a non-empty fixtures array")
    for fixture in fixtures:
        tree_hash = fixture.get("treeSHA256") if isinstance(fixture, dict) else None
        if not isinstance(tree_hash, str) or re.fullmatch(r"[0-9a-f]{64}", tree_hash) is None:
            raise SystemExit("every fixture must contain a 64-character SHA-256 tree hash")
    validate_fixture_payloads(fixtures, args.fixture_root)

    output_root = args.output.parent.resolve()
    trace_path = (
        relative_artifact_path(args.trace_path, output_root, "trace collection")
        if args.trace_path
        else None
    )
    hardware = parse_json_object(args.hardware, "hardware")
    operating_system = parse_json_object(args.os, "os")
    git_sha = validate_git_sha(args.git_sha, "git SHA")
    subject_git_sha = validate_git_sha(args.subject_git_sha, "subject Git SHA")
    if re.fullmatch(r"[0-9a-f]{64}", args.harness_sha256) is None:
        raise SystemExit("harness SHA-256 must contain 64 lowercase hexadecimal characters")
    try:
        worktree_status = json.loads(args.worktree_status)
    except json.JSONDecodeError as error:
        raise SystemExit(f"worktree status must be a JSON array: {error}") from error
    if (
        not isinstance(worktree_status, list)
        or not all(isinstance(item, str) and item for item in worktree_status)
    ):
        raise SystemExit("worktree status must be an array of non-empty strings")
    trace_artifact: dict[str, Any] = {
        "status": args.trace_status,
        "path": trace_path,
    }
    if args.trace_path is not None:
        trace_manifest = args.trace_path / "clipease-trace-manifest.json"
        try:
            trace_manifest_document = json.loads(trace_manifest.read_text())
        except (OSError, json.JSONDecodeError) as error:
            raise SystemExit(f"trace manifest is invalid: {error}") from error
        trace_artifact.update({
            "treeSHA256": tree_sha256(args.trace_path),
            "manifestSHA256": file_sha256(trace_manifest),
            "sharingClassification": trace_manifest_document.get(
                "sharingClassification"
            ),
            "pathContentPolicy": trace_manifest_document.get(
                "pathContentPolicy"
            ),
        })

    report = {
        "schemaVersion": 3,
        "runID": args.run_id,
        "benchmark": "clipease-enterprise-performance",
        "benchmarkKind": "micro",
        "warmupCount": args.warmups,
        "sampleCount": args.sample_count,
        "gitSHA": git_sha,
        "subjectGitSHA": subject_git_sha,
        "sourceEvidence": {
            "benchmarkHarnessSHA256": args.harness_sha256,
            "worktree": summarize_worktree_status(worktree_status),
        },
        "environment": {
            "hardware": hardware,
            "os": operating_system,
            "powerState": args.power_state,
            "thermalState": args.thermal_state,
        },
        "fixtures": fixtures,
        "metrics": build_metrics(rows),
        "artifacts": {
            "rawSamples": {
                "path": relative_artifact_path(
                    args.raw_artifact,
                    output_root,
                    "raw samples",
                ),
                "sha256": file_sha256(args.raw_artifact),
            },
            "fixtureManifest": {
                "path": relative_artifact_path(
                    args.fixtures,
                    output_root,
                    "fixture manifest",
                ),
                "sha256": file_sha256(args.fixtures),
            },
            "fixtureRoot": relative_artifact_path(
                args.fixture_root,
                output_root,
                "fixture root",
            ),
            "trace": trace_artifact,
        },
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")


if __name__ == "__main__":
    main()
