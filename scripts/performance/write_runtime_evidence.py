#!/usr/bin/env python3
"""Derive fail-closed ClipEase M1 runtime evidence from paired app samples."""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import math
import random
import re
import shutil
import sqlite3
import tempfile
from pathlib import Path
from typing import Any
from xml.etree import ElementTree


COMPARATOR_SPEC = importlib.util.spec_from_file_location(
    "_clipease_runtime_comparator",
    Path(__file__).with_name("compare_benchmark_reports.py"),
)
if COMPARATOR_SPEC is None or COMPARATOR_SPEC.loader is None:
    raise RuntimeError("could not load paired bootstrap implementation")
COMPARATOR = importlib.util.module_from_spec(COMPARATOR_SPEC)
COMPARATOR_SPEC.loader.exec_module(COMPARATOR)

SCHEMA_VERSION = 2
PERCENTILES = {"p50": 0.50, "p95": 0.95, "p99": 0.99}
BOOTSTRAP_ROUNDS = 2_000
ABSOLUTE_METRICS = set(COMPARATOR.M1_RELEASE_DURATION_THRESHOLDS_MS)
MEASUREMENT_FIELDS = {"durationMS", "rssMiB", "cpuTimeMS"}
SOURCE_IDENTITY_FIELDS = {
    "runID",
    "subjectGitSHA",
    "targetProcess",
    "executableSHA256",
    "machOUUIDs",
    "traceTreeSHA256",
    "poiExportSHA256",
    "diagnosticsStoreSHA256",
    "poiEventIDs",
}
SCALAR_FIELDS = {
    "idleCPUPercent",
    "unchangedDiskWrites",
    "captureAttemptCount",
    "captureMissCount",
    "captureDuplicateCount",
    "refreshPeriodMS",
    "renderedFrameCount",
    "mainThreadDecodeSamples",
    "hiddenRSSMiB",
    "textRSSMiB",
    "mixedRSSMiB",
    "hiddenIncrementMiB",
    "leakCount",
    "standardDiagnosticsCPUTimeMS",
    "detailedDiagnosticsCPUTimeMS",
    "gpuTimeMS",
}
ARRAY_FIELDS = {
    "frameTimesMS",
    "hitchDurationsMS",
    "windowCycleRSSMiB",
}
RUNTIME_POI_EVENT_IDS = sorted({
    "clipboard.capture",
    "storage.operation",
    "history.window",
    "history.search",
    "asset.image-decode",
    "asset.ocr",
    "maintenance.cleanup",
})
PRIVACY_SENTINELS = (
    b"CLIPEASE_PRIVACY_SENTINEL",
    b"CLIPEASE_PRIVACY_CONTENT_SENTINEL",
    b"CLIPEASE_PRIVACY_PATH_SENTINEL",
    b"CLIPEASE_PRIVACY_SEARCH_SENTINEL",
)
PRIVACY_PROBE_SCENARIOS = {
    "runtime-samples": PRIVACY_SENTINELS[0],
    "poi-export": PRIVACY_SENTINELS[1],
    "diagnostics-payload": PRIVACY_SENTINELS[2],
    "diagnostics-search": PRIVACY_SENTINELS[3],
}
TRACE_MANIFEST_FIELDS = {
    "schemaVersion",
    "capturedAt",
    "runID",
    "subjectGitSHA",
    "captureHarnessSHA256",
    "targetProcess",
    "sourceWorktreeClean",
    "sharingClassification",
    "pathContentPolicy",
    "executable",
    "traces",
}
TRACE_EXECUTABLE_FIELDS = {"relativePath", "sha256", "machOUUIDs"}
TRACE_ENTRY_REQUIRED_FIELDS = {
    "id",
    "template",
    "relativePath",
    "sharingClassification",
}
TRACE_ENTRY_ALLOWED_FIELDS = TRACE_ENTRY_REQUIRED_FIELDS | {"instrument"}
PRIVACY_RECEIPT_FIELDS = {
    "schemaVersion",
    "runID",
    "baselineSubjectGitSHA",
    "candidateSubjectGitSHA",
    "baselineTraceTreeSHA256",
    "candidateTraceTreeSHA256",
    "baselinePOIExportSHA256",
    "candidatePOIExportSHA256",
    "injections",
}
PRIVACY_INJECTION_FIELDS = {
    "scenarioSHA256",
    "sentinelSHA256",
    "sourceArtifactSHA256",
    "probeArtifactSHA256",
    "detectedSentinelCount",
}
PRIVACY_AUDIT_FIELDS = {
    "schemaVersion",
    "status",
    "matchedSentinelCount",
    "privacyProbeReceipt",
    "scannedArtifacts",
}
HASHED_ARTIFACT_FIELDS = {"path", "sha256"}
DIAGNOSTICS_STORE_COLUMNS = {
    "id",
    "timestamp",
    "name",
    "category",
    "duration_ms",
    "item_count",
    "result_count",
    "payload",
    "payload_bytes",
}
DIAGNOSTICS_PAYLOAD_FIELDS = {
    "id",
    "timestamp",
    "name",
    "category",
    "durationMS",
    "metadata",
    "isMainThread",
}


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


def relative_artifact_path(
    path: Path,
    output_root: Path,
    label: str,
) -> str:
    resolved_path = path.resolve()
    resolved_root = output_root.resolve()
    try:
        relative = resolved_path.relative_to(resolved_root)
    except ValueError as error:
        raise ValueError(f"{label} is outside output root") from error
    return relative.as_posix()


def sha256_text(value: str | bytes) -> str:
    payload = value.encode() if isinstance(value, str) else value
    return hashlib.sha256(payload).hexdigest()


def privacy_probe_hash_pairs() -> list[tuple[str, str]]:
    return sorted(
        (sha256_text(scenario), sha256_text(sentinel))
        for scenario, sentinel in PRIVACY_PROBE_SCENARIOS.items()
    )


def validate_privacy_probe_receipt(
    receipt: Any,
    *,
    run_id: str,
    baseline_subject_git_sha: str,
    candidate_subject_git_sha: str,
    probe_artifacts: dict[str, Path] | None = None,
    baseline_poi_export_path: Path | None = None,
    candidate_poi_export_path: Path | None = None,
    baseline_trace_tree_sha256: str | None = None,
    candidate_trace_tree_sha256: str | None = None,
) -> None:
    if not isinstance(receipt, dict) or set(receipt) != PRIVACY_RECEIPT_FIELDS:
        raise ValueError("privacy-probe receipt fields do not match schema")
    expected_identity = {
        "schemaVersion": 1,
        "runID": run_id,
        "baselineSubjectGitSHA": baseline_subject_git_sha,
        "candidateSubjectGitSHA": candidate_subject_git_sha,
        "baselineTraceTreeSHA256": baseline_trace_tree_sha256,
        "candidateTraceTreeSHA256": candidate_trace_tree_sha256,
        "baselinePOIExportSHA256": (
            file_sha256(baseline_poi_export_path)
            if baseline_poi_export_path is not None
            else None
        ),
        "candidatePOIExportSHA256": (
            file_sha256(candidate_poi_export_path)
            if candidate_poi_export_path is not None
            else None
        ),
    }
    for field, expected in expected_identity.items():
        if receipt.get(field) != expected:
            raise ValueError(f"privacy-probe receipt {field} does not match")
    injections = receipt.get("injections")
    if not isinstance(injections, list):
        raise ValueError("privacy-probe receipt injections must be an array")
    if probe_artifacts is None or set(probe_artifacts) != set(
        PRIVACY_PROBE_SCENARIOS
    ):
        raise ValueError("privacy-probe source artifacts do not match schema")
    observed: list[tuple[str, str, str]] = []
    for injection in injections:
        if (
            not isinstance(injection, dict)
            or set(injection) != PRIVACY_INJECTION_FIELDS
        ):
            raise ValueError(
                "privacy-probe receipt injection fields do not match schema"
            )
        pair = (
            injection.get("scenarioSHA256"),
            injection.get("sentinelSHA256"),
            injection.get("sourceArtifactSHA256"),
        )
        if any(
            not isinstance(value, str)
            or re.fullmatch(r"[0-9a-f]{64}", value) is None
            for value in pair
        ):
            raise ValueError(
                "privacy-probe scenarios and sentinels must use SHA-256 only"
            )
        if (
            re.fullmatch(
                r"[0-9a-f]{64}",
                str(injection.get("probeArtifactSHA256", "")),
            ) is None
            or not isinstance(injection.get("detectedSentinelCount"), int)
            or injection["detectedSentinelCount"] <= 0
        ):
            raise ValueError("privacy-probe injection was not detected")
        observed.append(pair)
    expected = sorted(
        (
            sha256_text(scenario),
            sha256_text(sentinel),
            file_sha256(probe_artifacts[scenario]),
        )
        for scenario, sentinel in PRIVACY_PROBE_SCENARIOS.items()
    )
    if sorted(observed) != expected or len(observed) != len(set(observed)):
        raise ValueError(
            "privacy-probe receipt does not contain the exact required "
            "scenario/sentinel hash pairs"
        )
    replayed = run_privacy_positive_controls(probe_artifacts)
    if injections != replayed:
        raise ValueError(
            "privacy-probe positive-control replay does not match receipt"
        )


def load_privacy_probe_receipt(
    path: Path | None,
    *,
    run_id: str,
    baseline_subject_git_sha: str,
    candidate_subject_git_sha: str,
    probe_artifacts: dict[str, Path],
    baseline_poi_export_path: Path,
    candidate_poi_export_path: Path,
    baseline_trace_tree_sha256: str,
    candidate_trace_tree_sha256: str,
) -> dict[str, Any]:
    if path is None:
        raise ValueError("privacy-probe receipt is required")
    try:
        receipt = json.loads(path.read_text())
    except (OSError, json.JSONDecodeError) as error:
        raise ValueError(f"privacy-probe receipt is invalid: {error}") from error
    validate_privacy_probe_receipt(
        receipt,
        run_id=run_id,
        baseline_subject_git_sha=baseline_subject_git_sha,
        candidate_subject_git_sha=candidate_subject_git_sha,
        probe_artifacts=probe_artifacts,
        baseline_poi_export_path=baseline_poi_export_path,
        candidate_poi_export_path=candidate_poi_export_path,
        baseline_trace_tree_sha256=baseline_trace_tree_sha256,
        candidate_trace_tree_sha256=candidate_trace_tree_sha256,
    )
    return receipt


def inject_diagnostics_probe(path: Path, sentinel: bytes) -> None:
    connection = sqlite3.connect(path)
    try:
        row = connection.execute(
            "SELECT id, payload FROM performance_events ORDER BY timestamp LIMIT 1"
        ).fetchone()
        if row is None:
            raise ValueError("privacy-probe diagnostics store has no events")
        try:
            payload = json.loads(row[1])
        except json.JSONDecodeError as error:
            raise ValueError(
                "privacy-probe diagnostics payload is invalid"
            ) from error
        metadata = payload.get("metadata")
        if not isinstance(metadata, dict):
            raise ValueError("privacy-probe diagnostics metadata is invalid")
        payload["metadata"] = {
            **metadata,
            "privacyProbeHashInput": sentinel.decode(),
        }
        payload_text = json.dumps(payload, sort_keys=True)
        connection.execute(
            """
            UPDATE performance_events
            SET payload = ?, payload_bytes = ?
            WHERE id = ?
            """,
            (payload_text, len(payload_text.encode()), row[0]),
        )
        connection.commit()
    finally:
        connection.close()


def run_privacy_positive_controls(
    probe_artifacts: dict[str, Path],
) -> list[dict[str, Any]]:
    if set(probe_artifacts) != set(PRIVACY_PROBE_SCENARIOS):
        raise ValueError("privacy-probe source artifacts do not match schema")
    injections: list[dict[str, Any]] = []
    with tempfile.TemporaryDirectory(prefix="clipease-privacy-probe-") as directory:
        probe_root = Path(directory)
        for index, (scenario, sentinel) in enumerate(
            PRIVACY_PROBE_SCENARIOS.items()
        ):
            source = probe_artifacts[scenario]
            probe = probe_root / f"probe-{index}{source.suffix}"
            shutil.copy2(source, probe)
            if scenario.startswith("diagnostics-"):
                inject_diagnostics_probe(probe, sentinel)
                detected = max(
                    probe.read_bytes().count(sentinel),
                    diagnostics_payload_sentinel_count(probe),
                )
            else:
                with probe.open("ab") as stream:
                    stream.write(b"\n" + sentinel + b"\n")
                detected = probe.read_bytes().count(sentinel)
            if detected <= 0:
                raise ValueError(
                    "privacy-probe sentinel injection was not detected"
                )
            injections.append({
                "scenarioSHA256": sha256_text(scenario),
                "sentinelSHA256": sha256_text(sentinel),
                "sourceArtifactSHA256": file_sha256(source),
                "probeArtifactSHA256": file_sha256(probe),
                "detectedSentinelCount": detected,
            })
    return injections


def generate_privacy_probe_receipt(
    path: Path,
    *,
    run_id: str,
    baseline_subject_git_sha: str,
    candidate_subject_git_sha: str,
    probe_artifacts: dict[str, Path],
    baseline_poi_export_path: Path,
    candidate_poi_export_path: Path,
    baseline_trace_tree_sha256: str,
    candidate_trace_tree_sha256: str,
) -> None:
    if path.exists():
        raise ValueError("privacy-probe receipt output already exists")
    if set(probe_artifacts) != set(PRIVACY_PROBE_SCENARIOS):
        raise ValueError("privacy-probe source artifacts do not match schema")
    validate_poi_export(
        baseline_poi_export_path,
        run_id=run_id,
        subject_git_sha=baseline_subject_git_sha,
        trace_tree_sha256=baseline_trace_tree_sha256,
    )
    validate_poi_export(
        candidate_poi_export_path,
        run_id=run_id,
        subject_git_sha=candidate_subject_git_sha,
        trace_tree_sha256=candidate_trace_tree_sha256,
    )
    injections = run_privacy_positive_controls(probe_artifacts)
    receipt = {
        "schemaVersion": 1,
        "runID": run_id,
        "baselineSubjectGitSHA": baseline_subject_git_sha,
        "candidateSubjectGitSHA": candidate_subject_git_sha,
        "baselineTraceTreeSHA256": baseline_trace_tree_sha256,
        "candidateTraceTreeSHA256": candidate_trace_tree_sha256,
        "baselinePOIExportSHA256": file_sha256(baseline_poi_export_path),
        "candidatePOIExportSHA256": file_sha256(candidate_poi_export_path),
        "injections": injections,
    }
    validate_privacy_probe_receipt(
        receipt,
        run_id=run_id,
        baseline_subject_git_sha=baseline_subject_git_sha,
        candidate_subject_git_sha=candidate_subject_git_sha,
        probe_artifacts=probe_artifacts,
        baseline_poi_export_path=baseline_poi_export_path,
        candidate_poi_export_path=candidate_poi_export_path,
        baseline_trace_tree_sha256=baseline_trace_tree_sha256,
        candidate_trace_tree_sha256=candidate_trace_tree_sha256,
    )
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(receipt, indent=2, sort_keys=True) + "\n")


def scan_privacy_artifacts(
    artifacts: dict[str, Path],
    *,
    output_root: Path,
    privacy_probe_receipt_path: Path | None = None,
    run_id: str | None = None,
    baseline_subject_git_sha: str | None = None,
    candidate_subject_git_sha: str | None = None,
    baseline_trace_tree_sha256: str | None = None,
    candidate_trace_tree_sha256: str | None = None,
) -> dict[str, Any]:
    if (
        run_id is None
        or baseline_subject_git_sha is None
        or candidate_subject_git_sha is None
        or baseline_trace_tree_sha256 is None
        or candidate_trace_tree_sha256 is None
    ):
        raise ValueError("privacy-probe receipt identity is required")
    if privacy_probe_receipt_path is None:
        raise ValueError("privacy-probe receipt is required")
    probe_artifacts = {
        "runtime-samples": artifacts["runtime-samples"],
        "poi-export": artifacts["candidate-poi"],
        "diagnostics-payload": artifacts["candidate-diagnostics"],
        "diagnostics-search": artifacts["baseline-diagnostics"],
    }
    validate_poi_export(
        artifacts["baseline-poi"],
        run_id=run_id,
        subject_git_sha=baseline_subject_git_sha,
        trace_tree_sha256=baseline_trace_tree_sha256,
    )
    validate_poi_export(
        artifacts["candidate-poi"],
        run_id=run_id,
        subject_git_sha=candidate_subject_git_sha,
        trace_tree_sha256=candidate_trace_tree_sha256,
    )
    load_privacy_probe_receipt(
        privacy_probe_receipt_path,
        run_id=run_id,
        baseline_subject_git_sha=baseline_subject_git_sha,
        candidate_subject_git_sha=candidate_subject_git_sha,
        probe_artifacts=probe_artifacts,
        baseline_poi_export_path=artifacts["baseline-poi"],
        candidate_poi_export_path=artifacts["candidate-poi"],
        baseline_trace_tree_sha256=baseline_trace_tree_sha256,
        candidate_trace_tree_sha256=candidate_trace_tree_sha256,
    )
    scanned = []
    matched_sentinel_count = 0
    for kind, path in artifacts.items():
        try:
            content = path.read_bytes()
        except OSError as error:
            raise ValueError(
                f"privacy audit artifact {kind!r} is unreadable: {error}"
            ) from error
        raw_match_count = sum(
            content.count(sentinel)
            for sentinel in PRIVACY_SENTINELS
        )
        if kind.endswith("-diagnostics"):
            matched_sentinel_count += max(
                raw_match_count,
                diagnostics_payload_sentinel_count(path),
            )
        else:
            matched_sentinel_count += raw_match_count
        scanned.append({
            "kind": kind,
            "path": relative_artifact_path(
                path,
                output_root,
                f"privacy audit artifact {kind}",
            ),
            "sha256": file_sha256(path),
        })
    return {
        "schemaVersion": 1,
        "status": "pass" if matched_sentinel_count == 0 else "fail",
        "matchedSentinelCount": matched_sentinel_count,
        "privacyProbeReceipt": {
            "path": relative_artifact_path(
                privacy_probe_receipt_path,
                output_root,
                "privacy-probe receipt",
            ),
            "sha256": file_sha256(privacy_probe_receipt_path),
        },
        "scannedArtifacts": scanned,
    }


def normalize_poi_export(
    raw_export_path: Path,
    output_path: Path,
    *,
    run_id: str,
    subject_git_sha: str,
    trace_tree_sha256: str,
) -> None:
    if output_path.exists():
        raise ValueError("normalized POI export output already exists")
    try:
        raw_root = ElementTree.parse(raw_export_path).getroot()
    except (ElementTree.ParseError, OSError) as error:
        raise ValueError(f"xctrace POI export is invalid XML: {error}") from error
    exported_values = [
        *raw_root.itertext(),
        *[
            value
            for element in raw_root.iter()
            for value in element.attrib.values()
        ],
    ]
    exported_text = "\n".join(exported_values)
    missing_events = [
        event_id
        for event_id in RUNTIME_POI_EVENT_IDS
        if event_id not in exported_text
    ]
    if missing_events:
        raise ValueError(
            "xctrace POI export is missing required event IDs: "
            + ", ".join(missing_events)
        )
    root = ElementTree.Element(
        "clipease-poi-export",
        {
            "schemaVersion": "1",
            "runID": run_id,
            "subjectGitSHA": subject_git_sha,
            "traceTreeSHA256": trace_tree_sha256,
            "captureMode": "steady-state-attach",
        },
    )
    events = ElementTree.SubElement(root, "events")
    for event_id in RUNTIME_POI_EVENT_IDS:
        ElementTree.SubElement(events, "event", {"id": event_id})
    probes = ElementTree.SubElement(
        root,
        "privacy-probes",
        {"mode": "scanner-positive-control"},
    )
    for scenario_hash, sentinel_hash in privacy_probe_hash_pairs():
        ElementTree.SubElement(
            probes,
            "probe",
            {
                "scenarioSHA256": scenario_hash,
                "sentinelSHA256": sentinel_hash,
            },
        )
    output_path.parent.mkdir(parents=True, exist_ok=True)
    ElementTree.ElementTree(root).write(
        output_path,
        encoding="unicode",
        xml_declaration=True,
    )
    validate_poi_export(
        output_path,
        run_id=run_id,
        subject_git_sha=subject_git_sha,
        trace_tree_sha256=trace_tree_sha256,
    )


def validate_poi_export(
    path: Path,
    *,
    run_id: str,
    subject_git_sha: str,
    trace_tree_sha256: str,
) -> None:
    if path.suffix.lower() != ".xml":
        raise ValueError("runtime POI export must use the .xml suffix")
    try:
        root = ElementTree.parse(path).getroot()
    except (ElementTree.ParseError, OSError) as error:
        raise ValueError(
            f"runtime POI export must be structured XML: {error}"
        ) from error
    expected_attributes = {
        "schemaVersion": "1",
        "runID": run_id,
        "subjectGitSHA": subject_git_sha,
        "traceTreeSHA256": trace_tree_sha256,
        "captureMode": "steady-state-attach",
    }
    if root.tag != "clipease-poi-export":
        raise ValueError("runtime POI export must be structured XML")
    if set(root.attrib) != set(expected_attributes):
        raise ValueError("runtime POI export root fields do not match schema")
    for field, expected in expected_attributes.items():
        if root.attrib.get(field) != expected:
            raise ValueError(f"runtime POI export {field} does not match")
    children = {child.tag: child for child in list(root)}
    if set(children) != {"events", "privacy-probes"} or len(list(root)) != 2:
        raise ValueError("runtime POI export structure is invalid")
    events_root = children["events"]
    if events_root.attrib:
        raise ValueError("runtime POI export events fields do not match schema")
    event_ids: list[str] = []
    for event in list(events_root):
        if (
            event.tag != "event"
            or set(event.attrib) != {"id"}
            or list(event)
            or (event.text or "").strip()
        ):
            raise ValueError("runtime POI export event fields do not match schema")
        event_ids.append(event.attrib["id"])
    if sorted(event_ids) != RUNTIME_POI_EVENT_IDS:
        raise ValueError(
            "runtime POI export is missing required event IDs or contains extras"
        )
    privacy_root = children["privacy-probes"]
    if privacy_root.attrib != {"mode": "scanner-positive-control"}:
        raise ValueError("runtime POI privacy probe fields do not match schema")
    observed_pairs: list[tuple[str, str]] = []
    for probe in list(privacy_root):
        if (
            probe.tag != "probe"
            or set(probe.attrib)
            != {"scenarioSHA256", "sentinelSHA256"}
            or list(probe)
            or (probe.text or "").strip()
        ):
            raise ValueError(
                "runtime POI privacy probe fields do not match schema"
            )
        observed_pairs.append((
            probe.attrib["scenarioSHA256"],
            probe.attrib["sentinelSHA256"],
        ))
    if (
        sorted(observed_pairs) != privacy_probe_hash_pairs()
        or len(observed_pairs) != len(set(observed_pairs))
    ):
        raise ValueError(
            "runtime POI scanner positive-control hash pairs are incomplete"
        )


def validate_detailed_local_diagnostics_store(path: Path) -> int:
    if not path.is_file():
        raise ValueError(
            f"detailedLocal diagnostics store does not exist: {path}"
        )
    sidecars = [
        Path(str(path) + suffix)
        for suffix in ("-wal", "-shm")
        if Path(str(path) + suffix).exists()
    ]
    if sidecars:
        raise ValueError(
            "detailedLocal diagnostics artifact must be a standalone snapshot"
        )
    connection: sqlite3.Connection | None = None
    try:
        connection = sqlite3.connect(
            path.resolve().as_uri() + "?mode=ro",
            uri=True,
        )
        if connection.execute("PRAGMA quick_check").fetchone() != ("ok",):
            raise ValueError("detailedLocal diagnostics store failed quick_check")
        columns = {
            row[1]
            for row in connection.execute(
                "PRAGMA table_info(performance_events)"
            )
        }
        if columns != DIAGNOSTICS_STORE_COLUMNS:
            raise ValueError(
                "detailedLocal diagnostics store schema does not match ClipEase"
            )
        rows = connection.execute(
            "SELECT payload, payload_bytes FROM performance_events"
        ).fetchall()
        if not rows:
            raise ValueError(
                "detailedLocal diagnostics store contains no captured events"
            )
        for payload_text, payload_bytes in rows:
            payload = json.loads(payload_text)
            if (
                not isinstance(payload, dict)
                or not DIAGNOSTICS_PAYLOAD_FIELDS.issubset(payload)
                or payload_bytes != len(payload_text.encode("utf-8"))
            ):
                raise ValueError(
                    "detailedLocal diagnostics event payload is invalid"
                )
        return len(rows)
    except (json.JSONDecodeError, sqlite3.Error) as error:
        raise ValueError(
            f"detailedLocal diagnostics store is invalid: {error}"
        ) from error
    finally:
        if connection is not None:
            connection.close()


def diagnostics_payload_sentinel_count(path: Path) -> int:
    validate_detailed_local_diagnostics_store(path)
    connection: sqlite3.Connection | None = None
    try:
        connection = sqlite3.connect(
            path.resolve().as_uri() + "?mode=ro",
            uri=True,
        )
        values = connection.execute(
            """
            SELECT id, name, category, payload
            FROM performance_events
            """
        ).fetchall()
        return sum(
            encoded.count(sentinel)
            for row in values
            for value in row
            for encoded in [str(value).encode("utf-8")]
            for sentinel in PRIVACY_SENTINELS
        )
    except sqlite3.Error as error:
        raise ValueError(
            f"detailedLocal diagnostics scan failed: {error}"
        ) from error
    finally:
        if connection is not None:
            connection.close()


def numeric(value: Any, label: str, *, positive: bool = False) -> float:
    if (
        not isinstance(value, (int, float))
        or isinstance(value, bool)
        or not math.isfinite(value)
        or value < 0
        or (positive and value <= 0)
    ):
        comparator = "positive" if positive else "non-negative"
        raise ValueError(f"{label} must be finite and {comparator}")
    return float(value)


def percentile(values: list[float], fraction: float) -> float:
    return COMPARATOR.percentile(values, fraction)


def bootstrap_percentile_ci(
    values: list[float],
    fraction: float,
    rounds: int = BOOTSTRAP_ROUNDS,
) -> list[float]:
    if len(set(values)) == 1:
        return [values[0], values[0]]
    randomizer = random.Random(
        91_000 + int(fraction * 10_000) + len(values)
    )
    estimates = [
        percentile(
            [randomizer.choice(values) for _ in values],
            fraction,
        )
        for _ in range(rounds)
    ]
    return [
        percentile(estimates, 0.025),
        percentile(estimates, 0.975),
    ]


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


def validate_source_identity(
    source: Any,
    *,
    expected: dict[str, Any],
    role: str,
    iteration: int,
) -> None:
    if not isinstance(source, dict):
        raise ValueError(f"runtime iteration {iteration} {role} source is missing")
    expected_fields = SOURCE_IDENTITY_FIELDS | {"observationID"}
    if set(source) != expected_fields:
        raise ValueError(
            f"runtime iteration {iteration} {role} source fields do not match schema"
        )
    for field in SOURCE_IDENTITY_FIELDS:
        if source.get(field) != expected.get(field):
            raise ValueError(
                f"runtime iteration {iteration} {role} source {field} "
                "does not match its trace evidence"
            )
    expected_observation_id = f"{role}:{iteration}"
    if source.get("observationID") != expected_observation_id:
        raise ValueError(
            f"runtime iteration {iteration} {role} observationID must be "
            f"{expected_observation_id!r}"
        )


def validate_metrics(metrics: Any, *, role: str, iteration: int) -> None:
    if not isinstance(metrics, dict) or set(metrics) != ABSOLUTE_METRICS:
        raise ValueError(
            f"runtime iteration {iteration} {role} must contain all "
            "14 absolute metrics"
        )
    for metric_name, measurement in metrics.items():
        if not isinstance(measurement, dict) or set(measurement) != MEASUREMENT_FIELDS:
            raise ValueError(
                f"runtime iteration {iteration} {role} metric "
                f"{metric_name!r} fields do not match schema"
            )
        for field in MEASUREMENT_FIELDS:
            numeric(
                measurement[field],
                f"runtime iteration {iteration} {role} "
                f"{metric_name} {field}",
            )


def validate_rows(
    rows: list[dict[str, Any]],
    *,
    baseline_source: dict[str, Any],
    candidate_source: dict[str, Any],
) -> None:
    if (
        len(rows) != 30
        or not all(isinstance(row, dict) for row in rows)
        or sorted(row.get("iteration") for row in rows) != list(range(30))
    ):
        raise ValueError("runtime sample iterations must be unique 0...29")
    expected_role_fields = {"source", "metrics", "gpuTimeMS"}
    expected_candidate_fields = (
        expected_role_fields | SCALAR_FIELDS | ARRAY_FIELDS
    )
    for row in rows:
        iteration = row["iteration"]
        baseline = row.get("baseline")
        candidate = row.get("candidate")
        if not isinstance(baseline, dict) or not isinstance(candidate, dict):
            raise ValueError(f"runtime iteration {iteration} roles are missing")
        if set(baseline) != expected_role_fields:
            raise ValueError(
                f"runtime iteration {iteration} baseline fields do not match schema"
            )
        if set(candidate) != expected_candidate_fields:
            raise ValueError(
                f"runtime iteration {iteration} candidate fields do not match schema"
            )
        validate_source_identity(
            baseline["source"],
            expected=baseline_source,
            role="baseline",
            iteration=iteration,
        )
        validate_source_identity(
            candidate["source"],
            expected=candidate_source,
            role="candidate",
            iteration=iteration,
        )
        validate_metrics(
            baseline["metrics"],
            role="baseline",
            iteration=iteration,
        )
        validate_metrics(
            candidate["metrics"],
            role="candidate",
            iteration=iteration,
        )
        numeric(
            baseline["gpuTimeMS"],
            f"runtime iteration {iteration} baseline gpuTimeMS",
            positive=True,
        )
        for field in SCALAR_FIELDS:
            numeric(
                candidate[field],
                f"runtime iteration {iteration} candidate {field}",
                positive=field
                in {
                    "captureAttemptCount",
                    "refreshPeriodMS",
                    "renderedFrameCount",
                    "standardDiagnosticsCPUTimeMS",
                    "gpuTimeMS",
                },
            )
        if int(candidate["captureAttemptCount"]) < 10_000:
            raise ValueError(
                "every runtime iteration must cover at least 10,000 captures"
            )
        if (
            candidate["captureMissCount"] > candidate["captureAttemptCount"]
            or candidate["captureDuplicateCount"] > candidate["captureAttemptCount"]
        ):
            raise ValueError("capture fault counts exceed attempted captures")
        for field in ARRAY_FIELDS:
            values = candidate[field]
            if not isinstance(values, list):
                raise ValueError(f"runtime field {field} must be an array")
            if field != "hitchDurationsMS" and not values:
                raise ValueError(f"runtime field {field} must not be empty")
            for value in values:
                numeric(
                    value,
                    f"runtime iteration {iteration} candidate {field}",
                )
        if len(candidate["windowCycleRSSMiB"]) != 101:
            raise ValueError(
                "windowCycleRSSMiB must contain the initial RSS plus 100 cycles"
            )
        if len(candidate["hitchDurationsMS"]) > candidate["renderedFrameCount"]:
            raise ValueError("hitch count exceeds rendered frame count")


def linear_slope(values: list[float]) -> float:
    count = len(values)
    mean_x = (count - 1) / 2
    mean_y = sum(values) / count
    numerator = sum(
        (index - mean_x) * (value - mean_y)
        for index, value in enumerate(values)
    )
    denominator = sum((index - mean_x) ** 2 for index in range(count))
    return numerator / denominator if denominator else 0.0


def role_metric_summaries(
    rows: list[dict[str, Any]],
    role: str,
) -> dict[str, Any]:
    summaries: dict[str, Any] = {}
    for metric_name in sorted(ABSOLUTE_METRICS):
        raw_samples = [
            {
                "iteration": row["iteration"],
                **{
                    field: float(row[role]["metrics"][metric_name][field])
                    for field in MEASUREMENT_FIELDS
                },
            }
            for row in sorted(rows, key=lambda item: item["iteration"])
        ]
        summaries[metric_name] = {
            "rawSamples": raw_samples,
            **{
                field: statistics(
                    [float(sample[field]) for sample in raw_samples]
                )
                for field in MEASUREMENT_FIELDS
            },
        }
    return summaries


def derive_runtime_gates(
    rows: list[dict[str, Any]],
    privacy_audit: dict[str, Any],
) -> dict[str, Any]:
    ordered = sorted(rows, key=lambda row: row["iteration"])
    candidates = [row["candidate"] for row in ordered]
    baseline_gpu = [float(row["baseline"]["gpuTimeMS"]) for row in ordered]
    candidate_gpu = [float(row["candidate"]["gpuTimeMS"]) for row in ordered]
    frame_times = [
        float(value)
        for candidate in candidates
        for value in candidate["frameTimesMS"]
    ]
    hitch_durations = [
        float(value)
        for candidate in candidates
        for value in candidate["hitchDurationsMS"]
    ]
    capture_attempts = sum(
        int(candidate["captureAttemptCount"]) for candidate in candidates
    )
    diagnostic_overheads = [
        COMPARATOR.percent_change(
            float(candidate["standardDiagnosticsCPUTimeMS"]),
            float(candidate["detailedDiagnosticsCPUTimeMS"]),
        )
        for candidate in candidates
    ]
    gpu_interval = COMPARATOR.paired_bootstrap_regression_ci(
        baseline_gpu,
        candidate_gpu,
        0.50,
    )
    return {
        "idleCPUP95Percent": percentile(
            [float(candidate["idleCPUPercent"]) for candidate in candidates],
            0.95,
        ),
        "unchangedDiskWrites": sum(
            int(candidate["unchangedDiskWrites"]) for candidate in candidates
        ),
        "captureMissRate": (
            sum(int(candidate["captureMissCount"]) for candidate in candidates)
            / capture_attempts
        ),
        "captureDuplicateRate": (
            sum(
                int(candidate["captureDuplicateCount"])
                for candidate in candidates
            )
            / capture_attempts
        ),
        "frameP95MS": percentile(frame_times, 0.95),
        "refreshPeriodMS": min(
            float(candidate["refreshPeriodMS"]) for candidate in candidates
        ),
        "hitchRatio": (
            len(hitch_durations)
            / sum(int(candidate["renderedFrameCount"]) for candidate in candidates)
        ),
        "maximumHitchMS": max(hitch_durations, default=0.0),
        "mainThreadDecodeSamples": sum(
            int(candidate["mainThreadDecodeSamples"])
            for candidate in candidates
        ),
        "hiddenRSSMiB": max(
            float(candidate["hiddenRSSMiB"]) for candidate in candidates
        ),
        "textRSSMiB": max(
            float(candidate["textRSSMiB"]) for candidate in candidates
        ),
        "mixedRSSMiB": max(
            float(candidate["mixedRSSMiB"]) for candidate in candidates
        ),
        "hiddenIncrementMiB": max(
            float(candidate["hiddenIncrementMiB"]) for candidate in candidates
        ),
        "windowCycleSlopeMiB": max(
            linear_slope(
                [float(value) for value in candidate["windowCycleRSSMiB"]]
            )
            for candidate in candidates
        ),
        "leakCount": sum(int(candidate["leakCount"]) for candidate in candidates),
        "diagnosticsOverheadP50Percent": percentile(
            diagnostic_overheads,
            0.50,
        ),
        "diagnosticsOverheadP95Percent": percentile(
            diagnostic_overheads,
            0.95,
        ),
        "gpuRegressionBootstrap95CILowerPercent": gpu_interval[0],
        "gpuRegressionBootstrap95CI": gpu_interval,
        "diagnosticsPrivacyAudit": privacy_audit["status"],
    }


def runtime_gate_errors(runtime: dict[str, Any]) -> list[str]:
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
    errors = []
    for field, (limit, strict) in thresholds.items():
        value = float(runtime[field])
        failed = value >= limit if strict else value > limit
        if failed:
            comparator = "<" if strict else "<="
            errors.append(f"{field}={value} must be {comparator}{limit}")
    if float(runtime["frameP95MS"]) > float(runtime["refreshPeriodMS"]):
        errors.append("frameP95MS exceeds refreshPeriodMS")
    if runtime["diagnosticsPrivacyAudit"] != "pass":
        errors.append("diagnosticsPrivacyAudit did not pass")
    return errors


def source_identity(
    *,
    trace_path: Path,
    poi_export_path: Path,
    diagnostics_export_path: Path,
    run_id: str,
    subject_git_sha: str,
    output_root: Path,
) -> tuple[dict[str, Any], dict[str, Any]]:
    manifest_path = trace_path / "clipease-trace-manifest.json"
    try:
        manifest = json.loads(manifest_path.read_text())
    except (OSError, json.JSONDecodeError) as error:
        raise ValueError(f"runtime trace manifest is invalid: {error}") from error
    if manifest.get("schemaVersion") != 2:
        raise ValueError("runtime trace manifest schemaVersion must be 2")
    if manifest.get("runID") != run_id:
        raise ValueError("runtime trace runID does not match")
    if manifest.get("subjectGitSHA") != subject_git_sha:
        raise ValueError("runtime trace subjectGitSHA does not match")
    if manifest.get("targetProcess") != "ClipEase":
        raise ValueError("runtime trace target process must be ClipEase")
    if "targetPID" in manifest:
        raise ValueError("runtime trace manifest must not persist targetPID")
    if "sourceWorktreeStatus" in manifest:
        raise ValueError(
            "runtime trace manifest must not persist changed worktree filenames"
        )
    if "hostAbsolutePath" in manifest:
        raise ValueError("runtime trace manifest must not persist hostAbsolutePath")
    if set(manifest) != TRACE_MANIFEST_FIELDS:
        raise ValueError("runtime trace manifest fields do not match schema")
    if (
        manifest.get("sharingClassification") != "shareable"
        or manifest.get("pathContentPolicy") != "file-activity-excluded"
    ):
        raise ValueError("runtime trace must be shareable with File Activity excluded")
    executable = manifest.get("executable")
    if (
        not isinstance(executable, dict)
        or set(executable) != TRACE_EXECUTABLE_FIELDS
    ):
        raise ValueError("runtime trace executable evidence is missing")
    traces = manifest.get("traces")
    if (
        not isinstance(traces, list)
        or any(
            not isinstance(trace, dict)
            or not TRACE_ENTRY_REQUIRED_FIELDS <= set(trace)
            or not set(trace) <= TRACE_ENTRY_ALLOWED_FIELDS
            for trace in traces
        )
    ):
        raise ValueError("runtime trace entries do not match schema")
    executable_sha = executable.get("sha256")
    mach_o_uuids = executable.get("machOUUIDs")
    if (
        not isinstance(executable_sha, str)
        or re.fullmatch(r"[0-9a-f]{64}", executable_sha) is None
        or not isinstance(mach_o_uuids, list)
        or not mach_o_uuids
        or not all(isinstance(value, str) and value for value in mach_o_uuids)
    ):
        raise ValueError("runtime trace executable identity is invalid")
    trace_tree_hash = tree_sha256(trace_path)
    validate_poi_export(
        poi_export_path,
        run_id=run_id,
        subject_git_sha=subject_git_sha,
        trace_tree_sha256=trace_tree_hash,
    )
    diagnostics_event_count = validate_detailed_local_diagnostics_store(
        diagnostics_export_path
    )
    diagnostics_store_sha256 = file_sha256(diagnostics_export_path)
    identity = {
        "runID": run_id,
        "subjectGitSHA": subject_git_sha,
        "targetProcess": "ClipEase",
        "executableSHA256": executable_sha,
        "machOUUIDs": mach_o_uuids,
        "traceTreeSHA256": trace_tree_hash,
        "poiExportSHA256": file_sha256(poi_export_path),
        "diagnosticsStoreSHA256": diagnostics_store_sha256,
        "poiEventIDs": RUNTIME_POI_EVENT_IDS,
    }
    evidence = {
        **identity,
        "trace": {
            "path": relative_artifact_path(
                trace_path,
                output_root,
                "runtime trace",
            ),
            "treeSHA256": identity["traceTreeSHA256"],
            "manifestSHA256": file_sha256(manifest_path),
        },
        "poiExport": {
            "path": relative_artifact_path(
                poi_export_path,
                output_root,
                "runtime POI export",
            ),
            "sha256": identity["poiExportSHA256"],
        },
        "diagnosticsStore": {
            "path": relative_artifact_path(
                diagnostics_export_path,
                output_root,
                "runtime diagnostics store",
            ),
            "sha256": diagnostics_store_sha256,
            "format": "clipease-detailed-local-sqlite",
            "eventCount": diagnostics_event_count,
        },
    }
    return identity, evidence


def build_runtime_evidence(
    rows: list[dict[str, Any]],
    *,
    run_id: str,
    baseline_subject_git_sha: str,
    candidate_subject_git_sha: str,
    baseline_source: dict[str, Any],
    candidate_source: dict[str, Any],
    baseline_source_evidence: dict[str, Any],
    candidate_source_evidence: dict[str, Any],
    raw_path: Path,
    raw_sha256: str,
    output_root: Path,
    privacy_audit: dict[str, Any],
) -> dict[str, Any]:
    validate_rows(
        rows,
        baseline_source=baseline_source,
        candidate_source=candidate_source,
    )
    baseline_metrics = role_metric_summaries(rows, "baseline")
    candidate_metrics = role_metric_summaries(rows, "candidate")
    comparisons = {
        name: COMPARATOR.compare_metric(
            baseline_metrics[name],
            candidate_metrics[name],
        )
        for name in sorted(ABSOLUTE_METRICS)
    }
    absolute_failures = COMPARATOR.absolute_metric_failures(
        candidate_metrics,
        "m1-8gb-release",
    )
    if not isinstance(privacy_audit, dict):
        raise ValueError("privacy audit does not match its sentinel count")
    expected_privacy_status = (
        "pass"
        if privacy_audit.get("matchedSentinelCount") == 0
        else "fail"
    )
    receipt_evidence = privacy_audit.get("privacyProbeReceipt")
    scanned_artifacts = privacy_audit.get("scannedArtifacts")
    if (
        set(privacy_audit) != PRIVACY_AUDIT_FIELDS
        or privacy_audit.get("schemaVersion") != 1
        or privacy_audit.get("status") != expected_privacy_status
        or not isinstance(privacy_audit.get("matchedSentinelCount"), int)
        or privacy_audit["matchedSentinelCount"] < 0
        or not isinstance(receipt_evidence, dict)
        or set(receipt_evidence) != HASHED_ARTIFACT_FIELDS
        or Path(str(receipt_evidence.get("path", ""))).is_absolute()
        or re.fullmatch(
            r"[0-9a-f]{64}",
            str(receipt_evidence.get("sha256", "")),
        ) is None
        or not isinstance(scanned_artifacts, list)
        or any(
            not isinstance(artifact, dict)
            or set(artifact) != {"kind", "path", "sha256"}
            or not isinstance(artifact["kind"], str)
            or Path(str(artifact["path"])).is_absolute()
            or re.fullmatch(r"[0-9a-f]{64}", str(artifact["sha256"])) is None
            for artifact in scanned_artifacts
        )
    ):
        raise ValueError("privacy audit does not match its sentinel count")
    runtime_gates = derive_runtime_gates(rows, privacy_audit)
    errors = runtime_gate_errors(runtime_gates)
    failed_comparisons = {
        name: result["reasons"]
        for name, result in comparisons.items()
        if result["decision"] != "pass"
    }
    if failed_comparisons:
        errors.append("absolute metric relative regression gate failed")
    if absolute_failures:
        errors.append("absolute duration threshold gate failed")
    return {
        "schemaVersion": SCHEMA_VERSION,
        "runID": run_id,
        "sampleCount": len(rows),
        "baselineSubjectGitSHA": baseline_subject_git_sha,
        "candidateSubjectGitSHA": candidate_subject_git_sha,
        "sourceEvidence": {
            "baseline": baseline_source_evidence,
            "candidate": candidate_source_evidence,
        },
        "rawSamples": {
            "path": relative_artifact_path(
                raw_path,
                output_root,
                "runtime raw samples",
            ),
            "sha256": raw_sha256,
        },
        "privacyAudit": privacy_audit,
        "absoluteMetrics": {
            "baseline": baseline_metrics,
            "candidate": candidate_metrics,
        },
        "absoluteMetricComparison": comparisons,
        "absoluteThresholdFailures": absolute_failures,
        "runtimeGates": runtime_gates,
        "decision": "pass" if not errors else "fail",
        "errors": errors,
    }


def load_rows(path: Path) -> list[dict[str, Any]]:
    try:
        rows = [
            json.loads(line)
            for line in path.read_text().splitlines()
            if line.strip()
        ]
    except (OSError, json.JSONDecodeError) as error:
        raise ValueError(f"runtime sample JSONL is invalid: {error}") from error
    return rows


def validated_sha(value: str, label: str) -> str:
    normalized = value.lower()
    if re.fullmatch(r"[0-9a-f]{40,64}", normalized) is None:
        raise ValueError(f"{label} must be a full hexadecimal object ID")
    return normalized


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--samples", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--run-id", required=True)
    parser.add_argument("--baseline-subject-git-sha", required=True)
    parser.add_argument("--candidate-subject-git-sha", required=True)
    parser.add_argument("--baseline-trace", required=True, type=Path)
    parser.add_argument("--candidate-trace", required=True, type=Path)
    parser.add_argument("--baseline-poi-export", required=True, type=Path)
    parser.add_argument("--candidate-poi-export", required=True, type=Path)
    parser.add_argument(
        "--privacy-probe-receipt-output",
        required=True,
        type=Path,
    )
    parser.add_argument(
        "--baseline-diagnostics-export",
        required=True,
        type=Path,
    )
    parser.add_argument(
        "--candidate-diagnostics-export",
        required=True,
        type=Path,
    )
    return parser.parse_args()


def main() -> None:
    args = parse_arguments()
    if args.output.exists():
        raise SystemExit(f"runtime evidence output already exists: {args.output}")
    for label, path in (
        ("baseline", args.baseline_trace),
        ("candidate", args.candidate_trace),
    ):
        if not path.is_dir() or path.suffix != ".trace":
            raise SystemExit(f"{label} trace must be a .trace collection")
    for label, path in (
        ("baseline", args.baseline_poi_export),
        ("candidate", args.candidate_poi_export),
    ):
        if not path.is_file() or path.stat().st_size == 0:
            raise SystemExit(f"{label} POI export must be a non-empty file")
    for label, path in (
        ("baseline", args.baseline_diagnostics_export),
        ("candidate", args.candidate_diagnostics_export),
    ):
        try:
            validate_detailed_local_diagnostics_store(path)
        except ValueError as error:
            raise SystemExit(
                f"{label} detailedLocal diagnostics export is invalid: {error}"
            ) from error
    if re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._:-]{0,127}", args.run_id) is None:
        raise SystemExit("runtime run ID contains unsupported characters")
    try:
        output_root = args.output.parent.resolve()
        baseline_subject = validated_sha(
            args.baseline_subject_git_sha,
            "baseline subject",
        )
        candidate_subject = validated_sha(
            args.candidate_subject_git_sha,
            "candidate subject",
        )
        baseline_source, baseline_evidence = source_identity(
            trace_path=args.baseline_trace,
            poi_export_path=args.baseline_poi_export,
            diagnostics_export_path=args.baseline_diagnostics_export,
            run_id=args.run_id,
            subject_git_sha=baseline_subject,
            output_root=output_root,
        )
        candidate_source, candidate_evidence = source_identity(
            trace_path=args.candidate_trace,
            poi_export_path=args.candidate_poi_export,
            diagnostics_export_path=args.candidate_diagnostics_export,
            run_id=args.run_id,
            subject_git_sha=candidate_subject,
            output_root=output_root,
        )
        probe_artifacts = {
            "runtime-samples": args.samples,
            "poi-export": args.candidate_poi_export,
            "diagnostics-payload": args.candidate_diagnostics_export,
            "diagnostics-search": args.baseline_diagnostics_export,
        }
        generate_privacy_probe_receipt(
            args.privacy_probe_receipt_output,
            run_id=args.run_id,
            baseline_subject_git_sha=baseline_subject,
            candidate_subject_git_sha=candidate_subject,
            probe_artifacts=probe_artifacts,
            baseline_poi_export_path=args.baseline_poi_export,
            candidate_poi_export_path=args.candidate_poi_export,
            baseline_trace_tree_sha256=baseline_source["traceTreeSHA256"],
            candidate_trace_tree_sha256=candidate_source["traceTreeSHA256"],
        )
        privacy_audit = scan_privacy_artifacts(
            {
                "runtime-samples": args.samples,
                "baseline-poi": args.baseline_poi_export,
                "candidate-poi": args.candidate_poi_export,
                "baseline-diagnostics": args.baseline_diagnostics_export,
                "candidate-diagnostics": args.candidate_diagnostics_export,
            },
            output_root=output_root,
            privacy_probe_receipt_path=args.privacy_probe_receipt_output,
            run_id=args.run_id,
            baseline_subject_git_sha=baseline_subject,
            candidate_subject_git_sha=candidate_subject,
            baseline_trace_tree_sha256=baseline_source["traceTreeSHA256"],
            candidate_trace_tree_sha256=candidate_source["traceTreeSHA256"],
        )
        report = build_runtime_evidence(
            load_rows(args.samples),
            run_id=args.run_id,
            baseline_subject_git_sha=baseline_subject,
            candidate_subject_git_sha=candidate_subject,
            baseline_source=baseline_source,
            candidate_source=candidate_source,
            baseline_source_evidence=baseline_evidence,
            candidate_source_evidence=candidate_evidence,
            raw_path=args.samples,
            raw_sha256=file_sha256(args.samples),
            output_root=output_root,
            privacy_audit=privacy_audit,
        )
    except ValueError as error:
        raise SystemExit(str(error)) from error
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    if report["decision"] != "pass":
        raise SystemExit(2)


if __name__ == "__main__":
    main()
