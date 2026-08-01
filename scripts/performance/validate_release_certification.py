#!/usr/bin/env python3
"""Fail-closed promotion gate for the six required M1 certification rounds."""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import math
import re
import subprocess
import xml.etree.ElementTree as ElementTree
import zlib
from pathlib import Path
from typing import Any


SCHEMA_VERSION = 2
LOCKED_BASELINE_SUBJECT_GIT_SHA = "ad4013cce2a4e0a1648de2277126c736c0700b39"
REQUIRED_OS_ROUNDS = {"macOS13": 3, "macOS26": 3}
REQUIRED_TRACE_IDS = {
    "swiftui",
    "time-profiler-poi",
    "animation-hitches",
    "system-trace",
    "power-profiler",
    "allocations",
    "leaks",
}
REQUIRED_MICRO_METRICS = {
    "startup_snapshot_s1k",
    "search_t10k_sqlite",
    "upsert_t10k",
    "fts_hot_m100k",
    "fts_cold_m100k",
    "page_1k_m100k",
    "asset_scan_a3k",
    "asset_decode_a3k",
}
BENCHMARK_DRIVER_PATH = (
    "Tests/ClipEaseTests/EnterprisePerformanceBenchmarkDriverTests.swift"
)
REQUIRED_FAULT_TESTS = {
    "migrationInterruption": "sqliteStoreMigrationFailureRestoresBackupAndRetriesFromLegacyVersion",
    "diskFull": "clipboardMonitorReportsDiskFullWithoutCallingImporter",
    "databaseCorruption": "sqliteCorruptionIsReportedWithoutOverwritingDatabase",
    "sigkillDuringWrite": "sqliteWALSurvivesSIGKILLDuringUncommittedWrite",
    "sourceAppRapidSwitch": "sourceApplicationSnapshotUsesMostRecentRapidActivation",
    "lockSleepResume": "suspendedClipboardMonitorDoesNotReadPayloadAndResumePollsImmediately",
    "imageBurst30x8MiB": "thirtyIndependentEightMiBImagesApplyDeterministicMemoryBackpressure",
    "pdf25Pages": "pdfTwentyFivePageBoundaryIsAcceptedWithoutUnboundedOCR",
    "windowCycles100": "historyWindowOneHundredOpenCloseCyclesRemainBoundedAndLeakFree",
}
REQUIRED_FAULTS = set(REQUIRED_FAULT_TESTS)
CERTIFICATION_FIELDS = {
    "schemaVersion",
    "baselineSubjectGitSHA",
    "candidateSubjectGitSHA",
    "rounds",
    "faultInjection",
    "buildAndTests",
    "visualEvidence",
}
ROUND_FIELDS = {
    "roundID",
    "osTarget",
    "baselineReport",
    "candidateReport",
    "comparison",
    "runtimeEvidence",
}
BENCHMARK_REPORT_FIELDS = {
    "schemaVersion",
    "runID",
    "benchmark",
    "benchmarkKind",
    "warmupCount",
    "sampleCount",
    "gitSHA",
    "subjectGitSHA",
    "sourceEvidence",
    "environment",
    "fixtures",
    "metrics",
    "artifacts",
}
BENCHMARK_ARTIFACT_FIELDS = {
    "rawSamples",
    "fixtureManifest",
    "fixtureRoot",
    "trace",
}
BENCHMARK_TRACE_FIELDS = {
    "status",
    "path",
    "treeSHA256",
    "manifestSHA256",
    "sharingClassification",
    "pathContentPolicy",
}
BENCHMARK_FIXTURE_FIELDS = {
    "id",
    "itemCount",
    "relativePath",
    "fileCount",
    "payloadByteCount",
    "treeSHA256",
}
BENCHMARK_ENVIRONMENT_FIELDS = {
    "hardware",
    "os",
    "powerState",
    "thermalState",
}
BENCHMARK_HARDWARE_FIELDS = {
    "model",
    "chip",
    "memoryBytes",
    "physicalCPUCount",
}
BENCHMARK_OS_FIELDS = {"productVersion", "buildVersion"}
STRICT_RELEASE_BUILD_COMMAND = (
    "swift build -c release -Xswiftc -strict-concurrency=complete "
    "-Xswiftc -warnings-as-errors --product ClipEase"
)
STRICT_RELEASE_TEST_COMMAND = "swift test -c release --no-parallel"
FAULT_REPORT_FIELDS = {
    "schemaVersion",
    "subjectGitSHA",
    "sourceWorktreeStatus",
    "decision",
    "scenarios",
}
FAULT_RESULT_FIELDS = {"testName", "command", "exitCode", "status", "log"}
BUILD_FIELDS = {
    "strictReleaseWarnings",
    "allTestsPassed",
    "changedCodeCoveragePercent",
    "candidateSubjectGitSHA",
    "strictReleaseBuildCommand",
    "strictReleaseTestCommand",
    "strictReleaseBuildLog",
    "strictReleaseBuildLogSHA256",
    "xunitReport",
    "xunitReportSHA256",
    "coverageReport",
    "coverageReportSHA256",
}
VISUAL_TARGET_FIELDS = {
    "macOS13": {
        "decision", "reviewer", "screenshots", "recording60Hz", "mediaAudit"
    },
    "macOS26": {
        "decision", "reviewer", "screenshots", "recording60Hz", "mediaAudit"
    },
    "macOS26_120Hz": {
        "decision", "reviewer", "screenshots", "recording120Hz", "mediaAudit"
    },
}
VISUAL_AUDIT_FIELDS = {
    "schemaVersion",
    "target",
    "reviewer",
    "recordingFrameRateHz",
    "recordingFrameCount",
    "durationSeconds",
    "screenshotCount",
    "artifactSHA256",
    "baselineReferencePath",
    "baselineReferenceSHA256",
    "candidateReferencePath",
    "candidateReferenceSHA256",
    "changedFrameCount",
    "maxPixelDelta",
    "perceptualDiffDecision",
}
RUNTIME_REPORT_FIELDS = {
    "schemaVersion",
    "runID",
    "sampleCount",
    "baselineSubjectGitSHA",
    "candidateSubjectGitSHA",
    "sourceEvidence",
    "rawSamples",
    "privacyAudit",
    "absoluteMetrics",
    "absoluteMetricComparison",
    "absoluteThresholdFailures",
    "runtimeGates",
    "decision",
    "errors",
}
MACH_O_UUID_PATTERN = re.compile(
    r"[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-"
    r"[0-9A-F]{4}-[0-9A-F]{12}"
)
ABSOLUTE_PATH_PATTERN = re.compile(
    r"(?<![A-Za-z0-9._-])/(?:[^ \t\r\n\"']+)"
)

COMPARATOR_SPEC = importlib.util.spec_from_file_location(
    "_clipease_compare_benchmark_reports",
    Path(__file__).with_name("compare_benchmark_reports.py"),
)
if COMPARATOR_SPEC is None or COMPARATOR_SPEC.loader is None:
    raise RuntimeError("could not load the benchmark comparison implementation")
COMPARATOR = importlib.util.module_from_spec(COMPARATOR_SPEC)
COMPARATOR_SPEC.loader.exec_module(COMPARATOR)
RUNTIME_EVIDENCE_SPEC = importlib.util.spec_from_file_location(
    "_clipease_write_runtime_evidence",
    Path(__file__).with_name("write_runtime_evidence.py"),
)
if RUNTIME_EVIDENCE_SPEC is None or RUNTIME_EVIDENCE_SPEC.loader is None:
    raise RuntimeError("could not load the runtime evidence implementation")
RUNTIME_EVIDENCE = importlib.util.module_from_spec(RUNTIME_EVIDENCE_SPEC)
RUNTIME_EVIDENCE_SPEC.loader.exec_module(RUNTIME_EVIDENCE)


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
        relative = path.relative_to(root).as_posix().encode()
        digest.update(len(relative).to_bytes(4, "big"))
        digest.update(relative)
        digest.update(path.stat().st_size.to_bytes(8, "big"))
        digest.update(bytes.fromhex(file_sha256(path)))
    return digest.hexdigest()


def resolve_path(
    manifest: Path,
    value: Any,
    label: str,
    *,
    require_relative: bool = True,
) -> Path:
    if not isinstance(value, str) or not value:
        raise ValueError(f"{label} must be a non-empty path")
    path = Path(value)
    if path.is_absolute():
        raise ValueError(f"{label} must be relative to its evidence root")
    if not path.is_absolute():
        path = manifest.parent / path
    path = path.resolve()
    evidence_root = manifest.parent.resolve()
    if path != evidence_root and evidence_root not in path.parents:
        raise ValueError(f"{label} escapes the certification evidence package")
    if not path.exists():
        raise ValueError(f"{label} does not exist")
    return path


def load_json(path: Path, label: str) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text())
    except OSError as error:
        raise ValueError(f"{label} could not be read") from error
    except json.JSONDecodeError as error:
        raise ValueError(f"{label} is not valid JSON: {error}") from error
    if not isinstance(value, dict):
        raise ValueError(f"{label} must contain a JSON object")
    return value


def percentile(values: list[float], fraction: float) -> float:
    ordered = sorted(values)
    position = (len(ordered) - 1) * fraction
    lower = math.floor(position)
    upper = math.ceil(position)
    return ordered[lower] + (ordered[upper] - ordered[lower]) * (position - lower)


def validate_metric_summaries(
    rows: list[dict[str, Any]],
    metrics: dict[str, Any],
    label: str,
) -> None:
    for metric_name, metric in metrics.items():
        if not isinstance(metric, dict):
            raise ValueError(f"{label} metric {metric_name!r} is invalid")
        expected_raw: list[dict[str, float | int]] = []
        for row in rows:
            measurement = row.get("metrics", {}).get(metric_name)
            if not isinstance(measurement, dict):
                raise ValueError(
                    f"{label} raw metric {metric_name!r} is not an object"
                )
            normalized: dict[str, float | int] = {"iteration": row["iteration"]}
            for field in ("durationMS", "rssMiB", "cpuTimeMS"):
                value = measurement.get(field)
                if (
                    not isinstance(value, (int, float))
                    or isinstance(value, bool)
                    or not math.isfinite(value)
                    or value < 0
                ):
                    raise ValueError(
                        f"{label} raw metric {metric_name!r} field {field!r} "
                        "must be finite and non-negative"
                    )
                normalized[field] = float(value)
            expected_raw.append(normalized)

        reported_raw = metric.get("rawSamples")
        if not isinstance(reported_raw, list) or len(reported_raw) != 30:
            raise ValueError(
                f"{label} metric {metric_name!r} must contain 30 raw samples"
            )
        normalized_reported: list[dict[str, float | int]] = []
        for sample in reported_raw:
            if not isinstance(sample, dict):
                raise ValueError(
                    f"{label} metric {metric_name!r} raw sample is invalid"
                )
            try:
                normalized_reported.append({
                    "iteration": int(sample["iteration"]),
                    "durationMS": float(sample["durationMS"]),
                    "rssMiB": float(sample["rssMiB"]),
                    "cpuTimeMS": float(sample["cpuTimeMS"]),
                })
            except (KeyError, TypeError, ValueError) as error:
                raise ValueError(
                    f"{label} metric {metric_name!r} raw sample is invalid"
                ) from error
        if normalized_reported != expected_raw:
            raise ValueError(
                f"{label} metric {metric_name!r} is not bound to its raw artifact"
            )

        for field in ("durationMS", "rssMiB", "cpuTimeMS"):
            summary = metric.get(field)
            if not isinstance(summary, dict):
                raise ValueError(
                    f"{label} metric {metric_name!r} summary {field!r} is invalid"
                )
            values = [float(sample[field]) for sample in expected_raw]
            expected = {
                "p50": percentile(values, 0.50),
                "p95": percentile(values, 0.95),
                "p99": percentile(values, 0.99),
                "max": max(values),
            }
            for statistic, expected_value in expected.items():
                actual = summary.get(statistic)
                if (
                    not isinstance(actual, (int, float))
                    or isinstance(actual, bool)
                    or not math.isclose(
                        float(actual),
                        expected_value,
                        rel_tol=1e-12,
                        abs_tol=1e-12,
                    )
                ):
                    raise ValueError(
                        f"{label} metric {metric_name!r} {field}.{statistic} "
                        "does not match its raw samples"
                    )
            confidence_intervals = summary.get("bootstrap95CI")
            if (
                not isinstance(confidence_intervals, dict)
                or set(confidence_intervals) != {"p50", "p95", "p99"}
            ):
                raise ValueError(
                    f"{label} metric {metric_name!r} {field} confidence "
                    "intervals are incomplete"
                )
            for statistic, interval in confidence_intervals.items():
                if (
                    not isinstance(interval, list)
                    or len(interval) != 2
                    or not all(
                        isinstance(value, (int, float))
                        and not isinstance(value, bool)
                        and math.isfinite(value)
                        for value in interval
                    )
                    or float(interval[0]) > float(interval[1])
                ):
                    raise ValueError(
                        f"{label} metric {metric_name!r} {field}.{statistic} "
                        "confidence interval is invalid"
                    )


def validate_m1_environment(report: dict[str, Any], os_target: str) -> None:
    environment = report.get("environment", {})
    if (
        not isinstance(environment, dict)
        or set(environment) != BENCHMARK_ENVIRONMENT_FIELDS
    ):
        raise ValueError("certification environment fields do not match schema")
    hardware = environment.get("hardware", {})
    operating_system = environment.get("os", {})
    if (
        not isinstance(hardware, dict)
        or set(hardware) != BENCHMARK_HARDWARE_FIELDS
        or not isinstance(operating_system, dict)
        or set(operating_system) != BENCHMARK_OS_FIELDS
    ):
        raise ValueError(
            "certification hardware or OS fields do not match schema"
        )
    if hardware.get("chip") != "Apple M1":
        raise ValueError("certification report was not captured on a base Apple M1")
    try:
        memory_bytes = int(hardware.get("memoryBytes", 0))
    except (TypeError, ValueError) as error:
        raise ValueError("certification memory size is invalid") from error
    if memory_bytes != 8 * 1_024**3:
        raise ValueError("certification report was not captured with exactly 8 GiB RAM")
    if environment.get("powerState") != "AC Power":
        raise ValueError("certification report was not captured on AC power")
    if environment.get("thermalState") != "nominal":
        raise ValueError("certification report was not captured at nominal thermal state")
    version = str(operating_system.get("productVersion", ""))
    expected_major = "13" if os_target == "macOS13" else "26"
    if version.split(".", 1)[0] != expected_major:
        raise ValueError(
            f"{os_target} certification report contains macOS {version or 'unknown'}"
        )


def validate_report_fixtures(
    report_path: Path,
    report: dict[str, Any],
    label: str,
) -> None:
    fixture_root = resolve_path(
        report_path,
        report.get("artifacts", {}).get("fixtureRoot"),
        f"{label} fixture root",
        require_relative=True,
    )
    if not fixture_root.is_dir():
        raise ValueError(f"{label} fixture root is not a directory")
    fixtures = report.get("fixtures")
    if not isinstance(fixtures, list):
        raise ValueError(f"{label} fixtures are missing")
    expected_counts = {
        "S1K": 1_000,
        "T10K": 10_000,
        "M100K": 100_000,
        "A3K": 3_000,
    }
    if {
        fixture.get("id"): fixture.get("itemCount")
        for fixture in fixtures
        if isinstance(fixture, dict)
    } != expected_counts:
        raise ValueError(f"{label} fixture contract does not match")
    for fixture in fixtures:
        if not isinstance(fixture, dict) or set(fixture) != BENCHMARK_FIXTURE_FIELDS:
            raise ValueError(f"{label} fixture fields do not match schema")
        relative_path = fixture.get("relativePath")
        if not isinstance(relative_path, str):
            raise ValueError(f"{label} fixture path is invalid")
        payload = (fixture_root / relative_path).resolve()
        if fixture_root.resolve() not in payload.parents or not payload.is_dir():
            raise ValueError(f"{label} fixture path escapes its root")
        files = [item for item in payload.rglob("*") if item.is_file()]
        if len(files) != fixture.get("fileCount"):
            raise ValueError(f"{label} fixture file count changed")
        if sum(item.stat().st_size for item in files) != fixture.get("payloadByteCount"):
            raise ValueError(f"{label} fixture payload size changed")
        if tree_sha256(payload) != fixture.get("treeSHA256"):
            raise ValueError(f"{label} fixture tree hash changed")


def validate_benchmark_report(
    report_path: Path,
    report: dict[str, Any],
    label: str,
    role: str,
) -> dict[str, str]:
    if set(report) != BENCHMARK_REPORT_FIELDS:
        raise ValueError(f"{label} report fields do not match schema")
    if report.get("schemaVersion") != 3:
        raise ValueError(f"{label} report schemaVersion must be 3")
    if report.get("benchmark") != "clipease-enterprise-performance":
        raise ValueError(f"{label} report benchmark identity is invalid")
    if report.get("benchmarkKind") != "micro":
        raise ValueError(f"{label} report benchmarkKind must be micro")
    if report.get("warmupCount") != 5 or report.get("sampleCount") != 30:
        raise ValueError(f"{label} report must contain 5 warmups and 30 samples")
    git_sha = report.get("gitSHA")
    subject_git_sha = report.get("subjectGitSHA")
    if git_sha != subject_git_sha:
        raise ValueError(f"{label} measured Git SHA differs from its subject SHA")
    run_id = report.get("runID")
    if (
        not isinstance(run_id, str)
        or re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._:-]{0,127}", run_id) is None
    ):
        raise ValueError(f"{label} report runID is missing")
    source = report.get("sourceEvidence", {})
    if set(source) != {"benchmarkHarnessSHA256", "worktree"}:
        raise ValueError(f"{label} source evidence fields do not match schema")
    harness_hash = source.get("benchmarkHarnessSHA256")
    if not isinstance(harness_hash, str) or re.fullmatch(r"[0-9a-f]{64}", harness_hash) is None:
        raise ValueError(f"{label} benchmark harness hash is invalid")
    worktree = source.get("worktree")
    expected_worktree = (
        {"entryCount": 1, "state": "baseline-harness-only"}
        if role == "baseline"
        else {"entryCount": 0, "state": "clean"}
    )
    if worktree != expected_worktree:
        raise ValueError(
            f"{label} worktree state is not the permitted {role} state"
        )
    if "worktreeStatus" in source:
        raise ValueError(f"{label} must not persist changed worktree filenames")

    artifacts = report.get("artifacts", {})
    if not isinstance(artifacts, dict) or set(artifacts) != BENCHMARK_ARTIFACT_FIELDS:
        raise ValueError(f"{label} artifact fields do not match schema")
    raw = artifacts.get("rawSamples", {})
    if not isinstance(raw, dict) or set(raw) != {"path", "sha256"}:
        raise ValueError(f"{label} raw sample fields do not match schema")
    raw_path = resolve_path(
        report_path,
        raw.get("path"),
        f"{label} raw samples",
        require_relative=True,
    )
    if not raw_path.is_file() or raw.get("sha256") != file_sha256(raw_path):
        raise ValueError(f"{label} raw sample artifact hash does not match")
    try:
        rows = [
            json.loads(line)
            for line in raw_path.read_text().splitlines()
            if line.strip()
        ]
    except json.JSONDecodeError as error:
        raise ValueError(f"{label} raw sample artifact is invalid JSONL: {error}") from error
    if (
        len(rows) != 30
        or not all(isinstance(row, dict) for row in rows)
        or sorted(row.get("iteration") for row in rows) != list(range(30))
    ):
        raise ValueError(f"{label} raw samples must contain unique iterations 0...29")
    metric_sets = [
        set(row.get("metrics", {}))
        for row in rows
        if isinstance(row, dict)
    ]
    if (
        len(metric_sets) != 30
        or not metric_sets
        or any(metrics != metric_sets[0] for metrics in metric_sets)
        or metric_sets[0] != REQUIRED_MICRO_METRICS
    ):
        raise ValueError(f"{label} raw samples do not match the micro metric contract")
    metrics = report.get("metrics")
    if not isinstance(metrics, dict) or set(metrics) != metric_sets[0]:
        raise ValueError(f"{label} report metrics do not match its raw samples")
    validate_metric_summaries(rows, metrics, label)

    fixture_manifest = artifacts.get("fixtureManifest", {})
    if (
        not isinstance(fixture_manifest, dict)
        or set(fixture_manifest) != {"path", "sha256"}
    ):
        raise ValueError(f"{label} fixture manifest fields do not match schema")
    fixture_manifest_path = resolve_path(
        report_path,
        fixture_manifest.get("path"),
        f"{label} fixture manifest",
        require_relative=True,
    )
    if (
        not fixture_manifest_path.is_file()
        or fixture_manifest.get("sha256") != file_sha256(fixture_manifest_path)
    ):
        raise ValueError(f"{label} fixture manifest hash does not match")
    manifest_document = load_json(fixture_manifest_path, f"{label} fixture manifest")
    if set(manifest_document) != {"schemaVersion", "fixtures"}:
        raise ValueError(f"{label} fixture manifest fields do not match schema")
    if manifest_document.get("fixtures") != report.get("fixtures"):
        raise ValueError(f"{label} fixtures differ from the bound manifest")
    trace = artifacts.get("trace")
    if not isinstance(trace, dict) or set(trace) != BENCHMARK_TRACE_FIELDS:
        raise ValueError(f"{label} trace artifact fields do not match schema")
    validate_report_fixtures(report_path, report, label)
    return {
        "runID": run_id,
        "harnessSHA256": harness_hash,
        "rawSamplesSHA256": raw["sha256"],
    }


def validate_runtime_gates(runtime: dict[str, Any]) -> None:
    thresholds = {
        "idleCPUP95Percent": (1.0, False),
        "unchangedDiskWrites": (0.0, False),
        "captureMissRate": (1 / 10_000, True),
        "captureDuplicateRate": (1 / 10_000, True),
        "hitchRatio": (0.005, True),
        "maximumHitchMS": (100.0, True),
        "mainThreadDecodeSamples": (0.0, False),
        "hiddenRSSMiB": (120.0, False),
        "textRSSMiB": (250.0, False),
        "mixedRSSMiB": (400.0, False),
        "hiddenIncrementMiB": (50.0, False),
        "windowCycleSlopeMiB": (1.0, True),
        "leakCount": (0.0, False),
        "diagnosticsOverheadP50Percent": (2.0, False),
        "diagnosticsOverheadP95Percent": (5.0, False),
        "gpuRegressionBootstrap95CILowerPercent": (5.0, False),
    }
    for field, (limit, strict) in thresholds.items():
        value = runtime.get(field)
        if not isinstance(value, (int, float)):
            raise ValueError(f"runtime gate {field} is missing or not numeric")
        failed = value >= limit if strict else value > limit
        if failed:
            comparator = "<" if strict else "<="
            raise ValueError(f"runtime gate {field}={value} must be {comparator}{limit}")
    frame_p95 = runtime.get("frameP95MS")
    refresh_period = runtime.get("refreshPeriodMS")
    if not isinstance(frame_p95, (int, float)) or not isinstance(
        refresh_period,
        (int, float),
    ):
        raise ValueError("frameP95MS and refreshPeriodMS must be numeric")
    if frame_p95 > refresh_period:
        raise ValueError("p95 frame time exceeds the measured refresh period")
    if runtime.get("diagnosticsPrivacyAudit") != "pass":
        raise ValueError("diagnostics privacy audit did not pass")


def xctrace_toc(path: Path) -> str:
    try:
        result = subprocess.run(
            [
                "xcrun",
                "xctrace",
                "export",
                "--input",
                str(path),
                "--toc",
            ],
            capture_output=True,
            text=True,
            timeout=120,
        )
    except (FileNotFoundError, subprocess.TimeoutExpired) as error:
        raise ValueError("xctrace could not inspect the trace artifact") from error
    if result.returncode != 0 or not result.stdout.strip():
        raise ValueError("xctrace rejected the trace artifact")
    return result.stdout


def mach_o_uuids(path: Path) -> list[str]:
    try:
        result = subprocess.run(
            ["xcrun", "dwarfdump", "--uuid", str(path)],
            capture_output=True,
            text=True,
            timeout=30,
        )
    except (FileNotFoundError, subprocess.TimeoutExpired) as error:
        raise ValueError("dwarfdump could not inspect the executable") from error
    if result.returncode != 0:
        raise ValueError("dwarfdump rejected the executable")
    values = sorted(set(MACH_O_UUID_PATTERN.findall(result.stdout.upper())))
    if not values:
        raise ValueError("dwarfdump found no Mach-O UUIDs in the executable")
    return values


def validate_trace_toc(
    xml: str,
    *,
    expected_template: str,
    expected_process: str,
    label: str,
) -> None:
    try:
        root = ElementTree.fromstring(xml)
    except ElementTree.ParseError as error:
        raise ValueError(f"{label} xctrace TOC is invalid XML: {error}") from error
    if root.tag != "trace-toc":
        raise ValueError(f"{label} xctrace TOC has no trace-toc root")
    runs = root.findall("run")
    if not runs:
        raise ValueError(f"{label} xctrace TOC contains no runs")
    templates = {
        value.text
        for value in root.findall("./run/info/summary/template-name")
        if value.text
    }
    if expected_template not in templates:
        raise ValueError(
            f"{label} expected template {expected_template!r}, found {sorted(templates)}"
        )
    process_names = {
        process.get("name")
        for process in root.findall("./run/processes/process")
        if process.get("name")
    }
    if expected_process not in process_names:
        raise ValueError(
            f"{label} does not contain target process {expected_process!r}"
        )
    if not root.findall("./run/data/table"):
        raise ValueError(f"{label} contains no Instruments data tables")


def validate_trace_collection(
    path: Path,
    label: str,
    *,
    expected_run_id: str,
    expected_subject_git_sha: str,
) -> dict[str, Any]:
    if not path.is_dir() or path.suffix != ".trace":
        raise ValueError(f"{label} must be a .trace collection directory")
    manifest_path = path / "clipease-trace-manifest.json"
    manifest = load_json(manifest_path, f"{label} manifest")
    if "targetPID" in manifest:
        raise ValueError(f"{label} must not persist targetPID")
    if "hostAbsolutePath" in manifest:
        raise ValueError(f"{label} must not persist hostAbsolutePath")
    if "sourceWorktreeStatus" in manifest:
        raise ValueError(f"{label} must not persist changed worktree filenames")
    if set(manifest) != RUNTIME_EVIDENCE.TRACE_MANIFEST_FIELDS:
        raise ValueError(f"{label} manifest fields do not match schema")
    if manifest.get("schemaVersion") != 2:
        raise ValueError(f"{label} manifest schemaVersion must be 2")
    if manifest.get("runID") != expected_run_id:
        raise ValueError(f"{label} manifest runID does not match its benchmark run")
    if manifest.get("subjectGitSHA") != expected_subject_git_sha:
        raise ValueError(
            f"{label} manifest subjectGitSHA does not match its benchmark subject"
        )
    capture_harness_hash = manifest.get("captureHarnessSHA256")
    if (
        not isinstance(capture_harness_hash, str)
        or re.fullmatch(r"[0-9a-f]{64}", capture_harness_hash) is None
    ):
        raise ValueError(f"{label} capture harness hash is invalid")
    if manifest.get("sourceWorktreeClean") is not True:
        raise ValueError(f"{label} trace source worktree was not clean")
    if (
        manifest.get("sharingClassification") != "shareable"
        or manifest.get("pathContentPolicy") != "file-activity-excluded"
    ):
        raise ValueError(
            f"{label} must be shareable with File Activity excluded"
        )
    traces = manifest.get("traces")
    if not isinstance(traces, list):
        raise ValueError(f"{label} manifest traces must be an array")
    ids = {
        trace.get("id")
        for trace in traces
        if isinstance(trace, dict)
    }
    if (
        ids != REQUIRED_TRACE_IDS
        or len(traces) != len(REQUIRED_TRACE_IDS)
    ):
        raise ValueError(f"{label} does not contain the required Instruments set")
    target_process = manifest.get("targetProcess")
    if target_process != "ClipEase":
        raise ValueError(f"{label} targetProcess must be ClipEase")
    standardized_root = path.resolve()
    executable = manifest.get("executable")
    if (
        not isinstance(executable, dict)
        or set(executable) != RUNTIME_EVIDENCE.TRACE_EXECUTABLE_FIELDS
    ):
        raise ValueError(f"{label} executable evidence is missing")
    executable_relative_path = executable.get("relativePath")
    if not isinstance(executable_relative_path, str):
        raise ValueError(f"{label} executable path is invalid")
    executable_path = (path / executable_relative_path).resolve()
    if (
        executable_path.parent != standardized_root
        or not executable_path.is_file()
    ):
        raise ValueError(f"{label} executable evidence escapes the collection")
    executable_hash = executable.get("sha256")
    if executable_hash != file_sha256(executable_path):
        raise ValueError(f"{label} executable SHA-256 does not match")
    expected_uuids = executable.get("machOUUIDs")
    if (
        not isinstance(expected_uuids, list)
        or not expected_uuids
        or len(expected_uuids) != len(set(expected_uuids))
        or any(
            not isinstance(value, str)
            or MACH_O_UUID_PATTERN.fullmatch(value) is None
            for value in expected_uuids
        )
    ):
        raise ValueError(f"{label} executable Mach-O UUID evidence is invalid")
    actual_uuids = mach_o_uuids(executable_path)
    if sorted(expected_uuids) != actual_uuids:
        raise ValueError(f"{label} executable Mach-O UUIDs do not match")
    for trace in traces:
        if (
            not isinstance(trace, dict)
            or not RUNTIME_EVIDENCE.TRACE_ENTRY_REQUIRED_FIELDS <= set(trace)
            or not set(trace) <= RUNTIME_EVIDENCE.TRACE_ENTRY_ALLOWED_FIELDS
        ):
            raise ValueError(f"{label} trace entry fields do not match schema")
        if trace.get("sharingClassification") != "shareable":
            raise ValueError(
                f"{label} contains a local-only sensitive trace"
            )
        relative_path = trace.get("relativePath")
        if not isinstance(relative_path, str):
            raise ValueError(f"{label} contains an invalid trace path")
        artifact = (path / relative_path).resolve()
        if artifact.parent != standardized_root or artifact.suffix != ".trace":
            raise ValueError(f"{label} trace path escapes the collection")
        if not artifact.exists():
            raise ValueError(f"{label} trace artifact does not exist")
        template = trace.get("template")
        if not isinstance(template, str) or not template:
            raise ValueError(f"{label} trace template is missing")
        validate_trace_toc(
            xctrace_toc(artifact),
            expected_template=template,
            expected_process=target_process,
            label=f"{label} {trace.get('id')}",
        )
    return {
        "treeSHA256": tree_sha256(path),
        "manifestSHA256": file_sha256(manifest_path),
        "captureHarnessSHA256": capture_harness_hash,
        "executableSHA256": executable_hash,
        "machOUUIDs": actual_uuids,
        "sharingClassification": manifest["sharingClassification"],
        "pathContentPolicy": manifest["pathContentPolicy"],
    }


def validate_runtime_evidence(
    manifest_path: Path,
    evidence: Any,
    *,
    expected_run_id: str,
    baseline_subject: str,
    candidate_subject: str,
    baseline_trace_tree_sha256: str,
    candidate_trace_tree_sha256: str,
) -> str:
    if not isinstance(evidence, dict) or set(evidence) != {"path", "sha256"}:
        raise ValueError("runtimeEvidence must reference one hashed report")
    report_path = resolve_path(
        manifest_path,
        evidence.get("path"),
        "runtime evidence report",
    )
    if not report_path.is_file() or evidence.get("sha256") != file_sha256(report_path):
        raise ValueError("runtime evidence report hash does not match")
    report = load_json(report_path, "runtime evidence report")
    if set(report) != RUNTIME_REPORT_FIELDS:
        raise ValueError("runtime evidence report fields do not match schema")
    expected_identity = {
        "schemaVersion": RUNTIME_EVIDENCE.SCHEMA_VERSION,
        "runID": expected_run_id,
        "sampleCount": 30,
        "baselineSubjectGitSHA": baseline_subject,
        "candidateSubjectGitSHA": candidate_subject,
    }
    for field, expected in expected_identity.items():
        if report.get(field) != expected:
            raise ValueError(f"runtime evidence {field} does not match its round")
    raw = report.get("rawSamples")
    if not isinstance(raw, dict) or set(raw) != {"path", "sha256"}:
        raise ValueError("runtime evidence raw samples are missing")
    raw_path = resolve_path(
        report_path,
        raw.get("path"),
        "runtime raw samples",
        require_relative=True,
    )
    if not raw_path.is_file() or raw.get("sha256") != file_sha256(raw_path):
        raise ValueError("runtime raw sample hash does not match")
    privacy_audit = report.get("privacyAudit")
    if (
        not isinstance(privacy_audit, dict)
        or set(privacy_audit) != RUNTIME_EVIDENCE.PRIVACY_AUDIT_FIELDS
    ):
        raise ValueError("runtime privacy audit fields do not match schema")
    receipt_reference = privacy_audit.get("privacyProbeReceipt")
    if (
        not isinstance(receipt_reference, dict)
        or set(receipt_reference) != RUNTIME_EVIDENCE.HASHED_ARTIFACT_FIELDS
    ):
        raise ValueError("runtime privacy-probe receipt reference is missing")
    privacy_probe_receipt_path = resolve_path(
        report_path,
        receipt_reference.get("path"),
        "runtime privacy-probe receipt",
    )
    if (
        not privacy_probe_receipt_path.is_file()
        or receipt_reference.get("sha256")
        != file_sha256(privacy_probe_receipt_path)
    ):
        raise ValueError("runtime privacy-probe receipt hash does not match")
    source_evidence = report.get("sourceEvidence")
    if (
        not isinstance(source_evidence, dict)
        or set(source_evidence) != {"baseline", "candidate"}
    ):
        raise ValueError("runtime source evidence is missing")
    source_inputs: dict[str, tuple[dict[str, Any], dict[str, Any]]] = {}
    poi_paths: dict[str, Path] = {}
    diagnostics_paths: dict[str, Path] = {}
    for role, subject, expected_trace_hash in (
        ("baseline", baseline_subject, baseline_trace_tree_sha256),
        ("candidate", candidate_subject, candidate_trace_tree_sha256),
    ):
        evidence_for_role = source_evidence.get(role)
        expected_source_fields = (
            RUNTIME_EVIDENCE.SOURCE_IDENTITY_FIELDS
            | {"trace", "poiExport", "diagnosticsStore"}
        )
        if (
            not isinstance(evidence_for_role, dict)
            or set(evidence_for_role) != expected_source_fields
        ):
            raise ValueError(f"runtime {role} source evidence is invalid")
        trace = evidence_for_role.get("trace")
        poi_export = evidence_for_role.get("poiExport")
        diagnostics_store = evidence_for_role.get("diagnosticsStore")
        if (
            not isinstance(trace, dict)
            or set(trace) != {"path", "treeSHA256", "manifestSHA256"}
            or not isinstance(poi_export, dict)
            or set(poi_export) != {"path", "sha256"}
            or not isinstance(diagnostics_store, dict)
            or set(diagnostics_store)
            != {"path", "sha256", "format", "eventCount"}
        ):
            raise ValueError(
                f"runtime {role} trace, POI, or diagnostics evidence is missing"
            )
        trace_path = resolve_path(
            report_path,
            trace.get("path"),
            f"runtime {role} trace",
            require_relative=True,
        )
        poi_export_path = resolve_path(
            report_path,
            poi_export.get("path"),
            f"runtime {role} POI export",
            require_relative=True,
        )
        diagnostics_path = resolve_path(
            report_path,
            diagnostics_store.get("path"),
            f"runtime {role} detailedLocal diagnostics store",
            require_relative=True,
        )
        try:
            source_identity, recomputed_source_evidence = (
                RUNTIME_EVIDENCE.source_identity(
                    trace_path=trace_path,
                    poi_export_path=poi_export_path,
                    diagnostics_export_path=diagnostics_path,
                    run_id=expected_run_id,
                    subject_git_sha=subject,
                    output_root=report_path.parent,
                )
            )
        except (KeyError, TypeError, ValueError) as error:
            raise ValueError(
                f"runtime {role} source evidence could not be verified: {error}"
            ) from error
        if source_identity["traceTreeSHA256"] != expected_trace_hash:
            raise ValueError(
                f"runtime {role} source trace differs from the round trace"
            )
        if evidence_for_role != recomputed_source_evidence:
            raise ValueError(
                f"runtime {role} source evidence does not match its artifacts"
            )
        source_inputs[role] = (
            source_identity,
            recomputed_source_evidence,
        )
        poi_paths[role] = poi_export_path
        diagnostics_paths[role] = diagnostics_path
    try:
        rows = RUNTIME_EVIDENCE.load_rows(raw_path)
        privacy_audit = RUNTIME_EVIDENCE.scan_privacy_artifacts(
            {
                "runtime-samples": raw_path,
                "baseline-poi": poi_paths["baseline"],
                "candidate-poi": poi_paths["candidate"],
                "baseline-diagnostics": diagnostics_paths["baseline"],
                "candidate-diagnostics": diagnostics_paths["candidate"],
            },
            output_root=report_path.parent,
            privacy_probe_receipt_path=privacy_probe_receipt_path,
            run_id=expected_run_id,
            baseline_subject_git_sha=baseline_subject,
            candidate_subject_git_sha=candidate_subject,
            baseline_trace_tree_sha256=source_inputs["baseline"][0][
                "traceTreeSHA256"
            ],
            candidate_trace_tree_sha256=source_inputs["candidate"][0][
                "traceTreeSHA256"
            ],
        )
        recomputed = RUNTIME_EVIDENCE.build_runtime_evidence(
            rows,
            run_id=expected_run_id,
            baseline_subject_git_sha=baseline_subject,
            candidate_subject_git_sha=candidate_subject,
            baseline_source=source_inputs["baseline"][0],
            candidate_source=source_inputs["candidate"][0],
            baseline_source_evidence=source_inputs["baseline"][1],
            candidate_source_evidence=source_inputs["candidate"][1],
            raw_path=raw_path,
            raw_sha256=raw["sha256"],
            output_root=report_path.parent,
            privacy_audit=privacy_audit,
        )
    except (KeyError, TypeError, ValueError) as error:
        raise ValueError(
            f"runtime evidence could not be recomputed: {error}"
        ) from error
    if report != recomputed:
        raise ValueError(
            "runtime evidence report does not match a fresh raw-sample recomputation"
        )
    if recomputed.get("decision") != "pass" or recomputed.get("errors"):
        raise ValueError("freshly recomputed runtime evidence did not pass")
    if recomputed.get("absoluteThresholdFailures"):
        raise ValueError("runtime absolute duration thresholds did not pass")
    comparisons = recomputed.get("absoluteMetricComparison")
    if (
        not isinstance(comparisons, dict)
        or set(comparisons) != RUNTIME_EVIDENCE.ABSOLUTE_METRICS
        or any(
            not isinstance(result, dict) or result.get("decision") != "pass"
            for result in comparisons.values()
        )
    ):
        raise ValueError("runtime absolute metric comparisons did not pass")
    runtime = recomputed.get("runtimeGates")
    if not isinstance(runtime, dict):
        raise ValueError("runtime evidence gates are missing")
    validate_runtime_gates(runtime)
    return raw["sha256"]


def validate_round(
    manifest_path: Path,
    entry: dict[str, Any],
    baseline_subject: str,
    candidate_subject: str,
) -> tuple[str, str, str, str, str, str]:
    if set(entry) != ROUND_FIELDS:
        raise ValueError("certification round fields do not match schema")
    os_target = entry.get("osTarget")
    if os_target not in REQUIRED_OS_ROUNDS:
        raise ValueError(f"invalid certification osTarget: {os_target!r}")
    round_id = entry.get("roundID")
    if not isinstance(round_id, str) or not round_id:
        raise ValueError("every certification round needs a roundID")

    baseline_path = resolve_path(
        manifest_path,
        entry.get("baselineReport"),
        f"{round_id} baseline report",
    )
    candidate_path = resolve_path(
        manifest_path,
        entry.get("candidateReport"),
        f"{round_id} candidate report",
    )
    comparison_path = resolve_path(
        manifest_path,
        entry.get("comparison"),
        f"{round_id} comparison",
    )
    baseline = load_json(baseline_path, f"{round_id} baseline report")
    candidate = load_json(candidate_path, f"{round_id} candidate report")
    comparison = load_json(comparison_path, f"{round_id} comparison")

    if baseline.get("subjectGitSHA") != baseline_subject:
        raise ValueError(f"{round_id} baseline subject SHA does not match the manifest")
    if candidate.get("subjectGitSHA") != candidate_subject:
        raise ValueError(f"{round_id} candidate subject SHA does not match the manifest")
    validate_m1_environment(candidate, os_target)
    if baseline.get("environment") != candidate.get("environment"):
        raise ValueError(f"{round_id} baseline and candidate environments differ")
    baseline_evidence = validate_benchmark_report(
        baseline_path,
        baseline,
        f"{round_id} baseline",
        "baseline",
    )
    candidate_evidence = validate_benchmark_report(
        candidate_path,
        candidate,
        f"{round_id} candidate",
        "candidate",
    )
    if baseline_evidence["runID"] != candidate_evidence["runID"]:
        raise ValueError(f"{round_id} report runIDs differ")
    if (
        baseline_evidence["harnessSHA256"]
        != candidate_evidence["harnessSHA256"]
    ):
        raise ValueError(f"{round_id} reports used different benchmark harnesses")
    if (
        baseline_evidence["rawSamplesSHA256"]
        == candidate_evidence["rawSamplesSHA256"]
    ):
        raise ValueError(f"{round_id} baseline and candidate raw samples are identical")
    trace_evidence: dict[str, dict[str, Any]] = {}
    for report_name, report_path, report in (
        ("baseline", baseline_path, baseline),
        ("candidate", candidate_path, candidate),
    ):
        trace = report.get("artifacts", {}).get("trace", {})
        if trace.get("status") != "available":
            raise ValueError(
                f"{round_id} {report_name} Instruments trace is unavailable"
            )
        trace_path = resolve_path(
            report_path,
            trace.get("path"),
            f"{round_id} {report_name} Instruments trace",
        )
        evidence = validate_trace_collection(
            trace_path,
            f"{round_id} {report_name} Instruments trace",
            expected_run_id=baseline_evidence["runID"],
            expected_subject_git_sha=report["subjectGitSHA"],
        )
        if (
            trace.get("treeSHA256") != evidence["treeSHA256"]
            or trace.get("manifestSHA256") != evidence["manifestSHA256"]
            or trace.get("sharingClassification")
            != evidence["sharingClassification"]
            or trace.get("pathContentPolicy") != evidence["pathContentPolicy"]
        ):
            raise ValueError(
                f"{round_id} {report_name} trace hashes do not match the report"
            )
        trace_evidence[report_name] = evidence
    if (
        trace_evidence["baseline"]["treeSHA256"]
        == trace_evidence["candidate"]["treeSHA256"]
    ):
        raise ValueError(f"{round_id} baseline and candidate traces are identical")
    if (
        trace_evidence["baseline"]["captureHarnessSHA256"]
        != trace_evidence["candidate"]["captureHarnessSHA256"]
    ):
        raise ValueError(f"{round_id} traces used different capture harnesses")
    if (
        trace_evidence["baseline"]["executableSHA256"]
        == trace_evidence["candidate"]["executableSHA256"]
    ):
        raise ValueError(
            f"{round_id} baseline and candidate trace executables are identical"
        )

    try:
        recomputed_comparison = COMPARATOR.build_comparison(
            baseline,
            candidate,
            baseline_path=baseline_path,
            candidate_path=candidate_path,
            profile="m1-8gb-release",
            require_trace=True,
        )
    except (KeyError, TypeError, ValueError) as error:
        raise ValueError(
            f"{round_id} benchmark comparison could not be recomputed: {error}"
        ) from error
    if comparison != recomputed_comparison:
        raise ValueError(
            f"{round_id} comparison artifact does not match a fresh recomputation"
        )
    if (
        recomputed_comparison.get("decision") != "pass"
        or recomputed_comparison.get("contractErrors")
        or recomputed_comparison.get("baselineAccepted") is not False
    ):
        raise ValueError(f"{round_id} freshly recomputed comparison did not pass")

    runtime_raw_hash = validate_runtime_evidence(
        manifest_path,
        entry.get("runtimeEvidence"),
        expected_run_id=baseline_evidence["runID"],
        baseline_subject=baseline_subject,
        candidate_subject=candidate_subject,
        baseline_trace_tree_sha256=trace_evidence["baseline"]["treeSHA256"],
        candidate_trace_tree_sha256=trace_evidence["candidate"]["treeSHA256"],
    )
    return (
        os_target,
        round_id,
        baseline_evidence["runID"],
        trace_evidence["baseline"]["treeSHA256"],
        trace_evidence["candidate"]["treeSHA256"],
        runtime_raw_hash,
    )


def validate_visual_artifact(path: Path, expected_suffix: str, label: str) -> None:
    if expected_suffix == ".png":
        _validate_png_container(path, label)
        return

    if expected_suffix == ".mov":
        _validate_movie_atoms(path, label)
        return

    raise ValueError(f"{label} uses an unsupported media suffix")


def _validate_png_container(path: Path, label: str) -> None:
    signature = b"\x89PNG\r\n\x1a\n"
    seen_ihdr = False
    seen_idat = False
    seen_iend = False
    with path.open("rb") as stream:
        if stream.read(len(signature)) != signature:
            raise ValueError(f"{label} is not a valid PNG container")
        while True:
            length_bytes = stream.read(4)
            if not length_bytes:
                break
            if len(length_bytes) != 4:
                raise ValueError(f"{label} has a truncated PNG chunk length")
            length = int.from_bytes(length_bytes, "big")
            chunk_type = stream.read(4)
            if len(chunk_type) != 4 or not all(
                65 <= byte <= 90 or 97 <= byte <= 122 for byte in chunk_type
            ):
                raise ValueError(f"{label} has an invalid PNG chunk type")
            if length > 128 * 1024 * 1024:
                raise ValueError(f"{label} contains an oversized PNG chunk")
            data = stream.read(length)
            crc_bytes = stream.read(4)
            if len(data) != length or len(crc_bytes) != 4:
                raise ValueError(f"{label} has a truncated PNG chunk")
            expected_crc = int.from_bytes(crc_bytes, "big")
            actual_crc = zlib.crc32(chunk_type + data) & 0xFFFFFFFF
            if actual_crc != expected_crc:
                raise ValueError(f"{label} has a PNG CRC mismatch")
            if not seen_ihdr:
                if chunk_type != b"IHDR" or length != 13:
                    raise ValueError(f"{label} is missing its first IHDR chunk")
                width = int.from_bytes(data[0:4], "big")
                height = int.from_bytes(data[4:8], "big")
                if width <= 0 or height <= 0:
                    raise ValueError(f"{label} has invalid PNG dimensions")
                seen_ihdr = True
            elif chunk_type == b"IHDR":
                raise ValueError(f"{label} contains more than one PNG IHDR")
            if chunk_type == b"IDAT":
                seen_idat = True
            if chunk_type == b"IEND":
                if length != 0:
                    raise ValueError(f"{label} has a non-empty PNG IEND chunk")
                seen_iend = True
                if stream.read(1):
                    raise ValueError(f"{label} contains data after PNG IEND")
                break
    if not seen_ihdr or not seen_idat or not seen_iend:
        raise ValueError(f"{label} has no complete PNG image payload")


def _validate_movie_atoms(path: Path, label: str) -> None:
    file_size = path.stat().st_size
    offset = 0
    found_types: set[bytes] = set()
    with path.open("rb") as stream:
        while offset < file_size:
            stream.seek(offset)
            header = stream.read(8)
            if len(header) != 8:
                raise ValueError(f"{label} has a truncated movie atom header")
            size32 = int.from_bytes(header[:4], "big")
            atom_type = header[4:8]
            header_size = 8
            if size32 == 1:
                extended_size = stream.read(8)
                if len(extended_size) != 8:
                    raise ValueError(f"{label} has a truncated extended atom size")
                atom_size = int.from_bytes(extended_size, "big")
                header_size = 16
            elif size32 == 0:
                atom_size = file_size - offset
            else:
                atom_size = size32
            if atom_size < header_size or offset + atom_size > file_size:
                raise ValueError(f"{label} has an invalid movie atom boundary")
            if atom_type == b"ftyp":
                if atom_size < header_size + 8:
                    raise ValueError(f"{label} has an invalid ftyp atom")
                major_brand = stream.read(4)
                if len(major_brand) != 4 or major_brand == b"\x00\x00\x00\x00":
                    raise ValueError(f"{label} has an empty movie major brand")
                found_types.add(atom_type)
            elif atom_type in {b"moov", b"mdat"}:
                found_types.add(atom_type)
            offset += atom_size
    if not {b"ftyp", b"moov", b"mdat"}.issubset(found_types):
        raise ValueError(f"{label} has no complete movie metadata and media atoms")


def _validate_sha256(value: Any, label: str) -> str:
    if not isinstance(value, str) or re.fullmatch(r"[0-9a-fA-F]{64}", value) is None:
        raise ValueError(f"{label} must be a SHA-256 digest")
    return value.lower()


def validate_visual_media_audit(
    manifest_path: Path,
    value: Any,
    *,
    target: str,
    reviewer: str,
    screenshot_paths: list[Path],
    recording_path: Path,
    expected_frame_rate: float,
) -> None:
    audit_path = resolve_path(manifest_path, value, f"{target} media audit")
    audit = load_json(audit_path, f"{target} media audit")
    if not isinstance(audit, dict) or set(audit) != VISUAL_AUDIT_FIELDS:
        raise ValueError(f"{target} media audit fields do not match schema")
    if audit.get("schemaVersion") != 1 or audit.get("target") != target:
        raise ValueError(f"{target} media audit identity is invalid")
    if audit.get("reviewer") != reviewer:
        raise ValueError(f"{target} media audit reviewer does not match manifest")
    frame_rate = audit.get("recordingFrameRateHz")
    if (
        not isinstance(frame_rate, (int, float))
        or not math.isfinite(float(frame_rate))
        or abs(float(frame_rate) - expected_frame_rate) > 1.0
    ):
        raise ValueError(
            f"{target} recording frame rate is not {expected_frame_rate:g}Hz"
        )
    for field, minimum in (
        ("recordingFrameCount", 2),
        ("screenshotCount", 1),
    ):
        count = audit.get(field)
        if not isinstance(count, int) or isinstance(count, bool) or count < minimum:
            raise ValueError(f"{target} media audit {field} is invalid")
    duration = audit.get("durationSeconds")
    if (
        not isinstance(duration, (int, float))
        or isinstance(duration, bool)
        or not math.isfinite(float(duration))
        or duration <= 0
    ):
        raise ValueError(f"{target} media audit duration is invalid")
    changed_frames = audit.get("changedFrameCount")
    if (
        not isinstance(changed_frames, int)
        or isinstance(changed_frames, bool)
        or changed_frames < 0
    ):
        raise ValueError(f"{target} changedFrameCount is invalid")
    if audit["screenshotCount"] != len(screenshot_paths):
        raise ValueError(f"{target} screenshotCount does not match artifacts")
    expected_frame_count = float(frame_rate) * float(duration)
    if abs(float(audit["recordingFrameCount"]) - expected_frame_count) > max(
        2.0, expected_frame_count * 0.05
    ):
        raise ValueError(f"{target} recording frame count does not match duration")
    pixel_delta = audit.get("maxPixelDelta")
    if (
        not isinstance(pixel_delta, (int, float))
        or isinstance(pixel_delta, bool)
        or not math.isfinite(float(pixel_delta))
        or pixel_delta < 0
    ):
        raise ValueError(f"{target} maxPixelDelta is invalid")
    if audit.get("perceptualDiffDecision") != "pass":
        raise ValueError(f"{target} perceptual diff was not approved")
    _validate_sha256(
        audit.get("baselineReferenceSHA256"), f"{target} baseline reference"
    )
    _validate_sha256(
        audit.get("candidateReferenceSHA256"), f"{target} candidate reference"
    )
    if (
        audit["baselineReferenceSHA256"].lower()
        == audit["candidateReferenceSHA256"].lower()
    ):
        raise ValueError(f"{target} visual comparison references are identical")
    baseline_reference = resolve_path(
        manifest_path,
        audit.get("baselineReferencePath"),
        f"{target} baseline reference artifact",
    )
    candidate_reference = resolve_path(
        manifest_path,
        audit.get("candidateReferencePath"),
        f"{target} candidate reference artifact",
    )
    if not baseline_reference.is_file() or not candidate_reference.is_file():
        raise ValueError(f"{target} visual comparison reference is missing")
    if file_sha256(baseline_reference) != audit["baselineReferenceSHA256"].lower():
        raise ValueError(f"{target} baseline reference hash does not match artifact")
    if file_sha256(candidate_reference) != audit["candidateReferenceSHA256"].lower():
        raise ValueError(f"{target} candidate reference hash does not match artifact")

    artifacts = audit.get("artifactSHA256")
    if (
        not isinstance(artifacts, dict)
        or set(artifacts) != {"screenshots", "recording"}
    ):
        raise ValueError(f"{target} media audit artifact hashes are invalid")
    screenshot_hashes = artifacts["screenshots"]
    if (
        not isinstance(screenshot_hashes, list)
        or len(screenshot_hashes) != len(screenshot_paths)
    ):
        raise ValueError(f"{target} screenshot hash count does not match artifacts")
    for index, (path, expected_hash) in enumerate(
        zip(screenshot_paths, screenshot_hashes)
    ):
        if _validate_sha256(
            expected_hash, f"{target} screenshot hash[{index}]"
        ) != file_sha256(path):
            raise ValueError(f"{target} screenshot hash does not match artifact")
    if _validate_sha256(
        artifacts["recording"], f"{target} recording hash"
    ) != file_sha256(recording_path):
        raise ValueError(f"{target} recording hash does not match artifact")


def validate_visual_evidence(manifest_path: Path, visual: dict[str, Any]) -> None:
    required = {
        "macOS13": ("screenshots", "recording60Hz"),
        "macOS26": ("screenshots", "recording60Hz"),
        "macOS26_120Hz": ("screenshots", "recording120Hz"),
    }
    if not isinstance(visual, dict) or set(visual) != set(required):
        raise ValueError("visual evidence fields do not match schema")
    for target, fields in required.items():
        evidence = visual.get(target)
        if (
            not isinstance(evidence, dict)
            or set(evidence) != VISUAL_TARGET_FIELDS[target]
        ):
            raise ValueError(f"{target} visual evidence fields do not match schema")
        if evidence.get("decision") != "pass":
            raise ValueError(f"{target} visual evidence is missing or not approved")
        reviewer = evidence.get("reviewer")
        if not isinstance(reviewer, str) or not reviewer.strip():
            raise ValueError(f"{target} visual evidence needs a named human reviewer")
        artifact_paths: dict[str, list[Path]] = {}
        recording_path: Path | None = None
        for field in fields:
            if field == "mediaAudit":
                continue
            value = evidence.get(field)
            values = value if isinstance(value, list) else [value]
            if not values or values == [None]:
                raise ValueError(f"{target} visual field {field} is empty")
            for index, item in enumerate(values):
                artifact = resolve_path(
                    manifest_path,
                    item,
                    f"{target} {field}[{index}]",
                )
                if not artifact.is_file() or artifact.stat().st_size == 0:
                    raise ValueError(f"{target} visual artifact is empty")
                expected_suffix = ".png" if field == "screenshots" else ".mov"
                if artifact.suffix.lower() != expected_suffix:
                    raise ValueError(
                        f"{target} {field} must use {expected_suffix} artifacts"
                    )
                validate_visual_artifact(
                    artifact, expected_suffix, f"{target} {field}[{index}]"
                )
                if field == "screenshots":
                    artifact_paths.setdefault(field, []).append(artifact)
                else:
                    recording_path = artifact
        if recording_path is None:
            raise ValueError(f"{target} recording artifact is missing")
        screenshot_paths = artifact_paths.get("screenshots", [])
        if not screenshot_paths:
            raise ValueError(f"{target} screenshots are missing")
        expected_frame_rate = 120.0 if "recording120Hz" in fields else 60.0
        validate_visual_media_audit(
            manifest_path,
            evidence.get("mediaAudit"),
            target=target,
            reviewer=reviewer,
            screenshot_paths=screenshot_paths,
            recording_path=recording_path,
            expected_frame_rate=expected_frame_rate,
        )


def validate_fault_injection(
    manifest_path: Path,
    evidence: Any,
    candidate_subject: str,
) -> None:
    if not isinstance(evidence, dict) or set(evidence) != {"path", "sha256"}:
        raise ValueError("faultInjection must reference one hashed suite report")
    report_path = resolve_path(
        manifest_path,
        evidence.get("path"),
        "fault injection report",
    )
    if not report_path.is_file() or evidence.get("sha256") != file_sha256(report_path):
        raise ValueError("fault injection report hash does not match")
    report = load_json(report_path, "fault injection report")
    if set(report) != FAULT_REPORT_FIELDS:
        raise ValueError("fault report fields do not match schema")
    if report.get("schemaVersion") != 1:
        raise ValueError("fault injection report schemaVersion must be 1")
    if report.get("subjectGitSHA") != candidate_subject:
        raise ValueError("fault injection report subjectGitSHA does not match")
    if report.get("sourceWorktreeStatus") != []:
        raise ValueError("fault injection suite did not run from a clean worktree")
    if report.get("decision") != "pass":
        raise ValueError("fault injection suite decision did not pass")
    scenarios = report.get("scenarios")
    if not isinstance(scenarios, dict) or set(scenarios) != REQUIRED_FAULTS:
        raise ValueError("fault injection report has an incomplete scenario set")
    for scenario, expected_test_name in REQUIRED_FAULT_TESTS.items():
        result = scenarios.get(scenario)
        if (
            not isinstance(result, dict)
            or set(result) != FAULT_RESULT_FIELDS
        ):
            raise ValueError(f"fault injection result is invalid: {scenario}")
        if result.get("testName") != expected_test_name:
            raise ValueError(
                f"fault injection test identity changed for {scenario}"
            )
        expected_command = [
            "swift",
            "test",
            "-c",
            "release",
            "--skip-build",
            "--filter",
            expected_test_name,
        ]
        if result.get("command") != expected_command:
            raise ValueError(f"fault injection command changed for {scenario}")
        if result.get("exitCode") != 0 or result.get("status") != "pass":
            raise ValueError(f"fault injection did not pass: {scenario}")
        log = result.get("log")
        if not isinstance(log, dict) or set(log) != {"path", "sha256"}:
            raise ValueError(f"fault injection log is missing: {scenario}")
        log_path = resolve_path(
            report_path,
            log.get("path"),
            f"{scenario} fault injection log",
        )
        if not log_path.is_file() or log.get("sha256") != file_sha256(log_path):
            raise ValueError(f"fault injection log hash changed: {scenario}")
        log_text = log_path.read_text(errors="replace")
        passing_test_pattern = re.compile(
            rf"Test\s+{re.escape(expected_test_name)}\(\)\s+passed\b"
        )
        passing_suite_pattern = re.compile(
            r"Test run with 1 test(?: in \d+ suites?)? passed\b"
        )
        if (
            passing_test_pattern.search(log_text) is None
            or passing_suite_pattern.search(log_text) is None
            or re.search(r"\bfailed\b", log_text, re.IGNORECASE) is not None
        ):
            raise ValueError(
                f"fault injection log has no exclusive passing test marker: {scenario}"
            )


def validate_build_and_tests(
    manifest_path: Path,
    build: Any,
    candidate_subject: str,
) -> None:
    if not isinstance(build, dict) or set(build) != BUILD_FIELDS:
        raise ValueError("buildAndTests fields do not match schema")
    if build.get("candidateSubjectGitSHA") != candidate_subject:
        raise ValueError("buildAndTests candidateSubjectGitSHA does not match")
    if build.get("strictReleaseBuildCommand") != STRICT_RELEASE_BUILD_COMMAND:
        raise ValueError("strict release build command is not the required command")
    if build.get("strictReleaseTestCommand") != STRICT_RELEASE_TEST_COMMAND:
        raise ValueError("strict release test command is not the required command")

    build_log = resolve_path(
        manifest_path,
        build.get("strictReleaseBuildLog"),
        "strict Release build log",
    )
    build_log_hash = _validate_sha256(
        build.get("strictReleaseBuildLogSHA256"),
        "strict Release build log hash",
    )
    if not build_log.is_file() or file_sha256(build_log) != build_log_hash:
        raise ValueError("strict Release build log hash does not match")
    build_log_text = build_log.read_text(errors="replace")
    if f"Subject Git SHA: {candidate_subject}" not in build_log_text:
        raise ValueError("strict Release build log subject does not match")
    if (
        f"Strict release build command: {STRICT_RELEASE_BUILD_COMMAND}"
        not in build_log_text
    ):
        raise ValueError("strict Release build log command does not match")
    warning_count = len(re.findall(r"\bwarning:", build_log_text, re.IGNORECASE))
    if build.get("strictReleaseWarnings") != warning_count or warning_count != 0:
        raise ValueError("strict Release build must contain zero warnings")

    xunit_path = resolve_path(
        manifest_path,
        build.get("xunitReport"),
        "xUnit test report",
    )
    xunit_hash = _validate_sha256(
        build.get("xunitReportSHA256"),
        "xUnit test report hash",
    )
    if not xunit_path.is_file() or file_sha256(xunit_path) != xunit_hash:
        raise ValueError("xUnit test report hash does not match")
    try:
        xunit_root = ElementTree.parse(xunit_path).getroot()
    except (ElementTree.ParseError, OSError) as error:
        raise ValueError(f"xUnit test report is invalid: {error}") from error
    if xunit_root.attrib.get("subjectGitSHA") != candidate_subject:
        raise ValueError("xUnit test report subject does not match")
    if xunit_root.attrib.get("command") != STRICT_RELEASE_TEST_COMMAND:
        raise ValueError("xUnit test report command does not match")
    if xunit_root.tag == "testsuite":
        suites = [xunit_root]
    elif xunit_root.tag == "testsuites":
        suites = list(xunit_root)
        if any(suite.tag != "testsuite" for suite in suites):
            raise ValueError("xUnit suite child tag is invalid")
    else:
        raise ValueError("xUnit root tag is invalid")
    try:
        test_count = sum(int(suite.attrib.get("tests", 0)) for suite in suites)
        failure_count = sum(int(suite.attrib.get("failures", 0)) for suite in suites)
        error_count = sum(int(suite.attrib.get("errors", 0)) for suite in suites)
    except (TypeError, ValueError) as error:
        raise ValueError(f"xUnit test report counts are invalid: {error}") from error
    if (
        build.get("allTestsPassed") is not True
        or test_count <= 0
        or failure_count != 0
        or error_count != 0
    ):
        raise ValueError("the complete test suite did not pass")

    coverage_path = resolve_path(
        manifest_path,
        build.get("coverageReport"),
        "changed-code coverage report",
    )
    coverage_hash = _validate_sha256(
        build.get("coverageReportSHA256"),
        "changed-code coverage report hash",
    )
    if not coverage_path.is_file() or file_sha256(coverage_path) != coverage_hash:
        raise ValueError("changed-code coverage report hash does not match")
    coverage_report = load_json(coverage_path, "changed-code coverage report")
    if coverage_report.get("subjectGitSHA") != candidate_subject:
        raise ValueError("changed-code coverage report subject does not match")
    coverage = coverage_report.get("changedCodeCoveragePercent")
    if (
        coverage_report.get("decision") != "pass"
        or not isinstance(coverage, (int, float))
        or coverage < 80
        or build.get("changedCodeCoveragePercent") != coverage
    ):
        raise ValueError("changed-code coverage must be at least 80%")


def validate_document(manifest_path: Path, document: dict[str, Any]) -> dict[str, Any]:
    if (
        not isinstance(document, dict)
        or set(document) != CERTIFICATION_FIELDS
    ):
        raise ValueError("certification top-level fields do not match schema")
    if document.get("schemaVersion") != SCHEMA_VERSION:
        raise ValueError(f"schemaVersion must be {SCHEMA_VERSION}")
    baseline_subject = document.get("baselineSubjectGitSHA")
    candidate_subject = document.get("candidateSubjectGitSHA")
    for label, value in (
        ("baselineSubjectGitSHA", baseline_subject),
        ("candidateSubjectGitSHA", candidate_subject),
    ):
        if not isinstance(value, str) or re.fullmatch(r"[0-9a-fA-F]{40,64}", value) is None:
            raise ValueError(f"{label} must be a full hexadecimal Git object ID")
    if baseline_subject != LOCKED_BASELINE_SUBJECT_GIT_SHA:
        raise ValueError(
            "baselineSubjectGitSHA must equal the locked ad4013c performance baseline"
        )

    rounds = document.get("rounds")
    if not isinstance(rounds, list):
        raise ValueError("rounds must be an array")
    visual_schema = document.get("visualEvidence")
    if not isinstance(visual_schema, dict):
        raise ValueError("visualEvidence is missing")
    validate_visual_evidence(manifest_path, visual_schema)
    os_counts = {target: 0 for target in REQUIRED_OS_ROUNDS}
    round_ids: set[str] = set()
    run_ids: set[str] = set()
    trace_hashes: set[str] = set()
    runtime_raw_hashes: set[str] = set()
    for entry in rounds:
        if not isinstance(entry, dict):
            raise ValueError("every certification round must be an object")
        (
            os_target,
            round_id,
            run_id,
            baseline_trace_hash,
            candidate_trace_hash,
            runtime_raw_hash,
        ) = validate_round(
            manifest_path,
            entry,
            baseline_subject,
            candidate_subject,
        )
        if round_id in round_ids:
            raise ValueError(f"duplicate certification roundID: {round_id}")
        if run_id in run_ids:
            raise ValueError(f"duplicate certification benchmark runID: {run_id}")
        for trace_hash in (baseline_trace_hash, candidate_trace_hash):
            if trace_hash in trace_hashes:
                raise ValueError(
                    "duplicate certification Instruments trace artifact"
                )
            trace_hashes.add(trace_hash)
        if runtime_raw_hash in runtime_raw_hashes:
            raise ValueError("duplicate certification runtime raw sample artifact")
        runtime_raw_hashes.add(runtime_raw_hash)
        round_ids.add(round_id)
        run_ids.add(run_id)
        os_counts[os_target] += 1
    if os_counts != REQUIRED_OS_ROUNDS:
        raise ValueError(
            f"certification requires exactly three rounds on each OS: {os_counts}"
        )

    validate_fault_injection(
        manifest_path,
        document.get("faultInjection"),
        candidate_subject,
    )

    validate_build_and_tests(
        manifest_path,
        document.get("buildAndTests"),
        candidate_subject,
    )

    visual = document.get("visualEvidence")
    if not isinstance(visual, dict):
        raise ValueError("visualEvidence is missing")
    validate_visual_evidence(manifest_path, visual)
    return {
        "schemaVersion": SCHEMA_VERSION,
        "decision": "pass",
        "baselineAccepted": False,
        "baselineSubjectGitSHA": baseline_subject,
        "candidateSubjectGitSHA": candidate_subject,
        "roundCounts": os_counts,
    }


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    return parser.parse_args()


def persisted_error_message(error: Exception) -> str:
    return ABSOLUTE_PATH_PATTERN.sub("<absolute-path>", str(error))


def main() -> None:
    args = parse_arguments()
    document = load_json(args.manifest, "certification manifest")
    try:
        result = validate_document(args.manifest.resolve(), document)
    except ValueError as error:
        result = {
            "schemaVersion": SCHEMA_VERSION,
            "decision": "fail",
            "baselineAccepted": False,
            "errors": [persisted_error_message(error)],
        }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    if result["decision"] != "pass":
        raise SystemExit(2)


if __name__ == "__main__":
    main()
