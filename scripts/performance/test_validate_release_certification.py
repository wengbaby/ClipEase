import hashlib
import importlib.util
import json
import sqlite3
import tempfile
import unittest
import sys
import zlib
from pathlib import Path
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "validate_release_certification",
    ROOT / "scripts/performance/validate_release_certification.py",
)
certification = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(certification)

FAULT_RUNNER_SPEC = importlib.util.spec_from_file_location(
    "run_fault_injection_suite",
    ROOT / "scripts/performance/run_fault_injection_suite.py",
)
fault_runner = importlib.util.module_from_spec(FAULT_RUNNER_SPEC)
assert FAULT_RUNNER_SPEC.loader is not None
FAULT_RUNNER_SPEC.loader.exec_module(fault_runner)


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def valid_png_bytes() -> bytes:
    def chunk(kind: bytes, payload: bytes) -> bytes:
        return (
            len(payload).to_bytes(4, "big")
            + kind
            + payload
            + (zlib.crc32(kind + payload) & 0xFFFFFFFF).to_bytes(4, "big")
        )

    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", b"\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00")
        + chunk(b"IDAT", zlib.compress(b"\x00\x00\x00\x00\x00"))
        + chunk(b"IEND", b"")
    )


def valid_movie_bytes() -> bytes:
    def atom(kind: bytes, payload: bytes) -> bytes:
        return (8 + len(payload)).to_bytes(4, "big") + kind + payload

    return (
        atom(b"ftyp", b"qt  \x00\x00\x00\x00")
        + atom(b"moov", b"\x00\x00\x00\x00")
        + atom(b"mdat", b"\x00\x00\x00\x00")
    )


def report_artifact_path(report_path: Path, value: str) -> Path:
    path = Path(value)
    return path if path.is_absolute() else report_path.parent / path


def certification_artifact_path(manifest_path: Path, value: str) -> Path:
    return manifest_path.parent / value


def poi_xml(
    *,
    run_id: str,
    subject_git_sha: str,
    trace_tree_sha256: str,
) -> str:
    events = "".join(
        f'<event id="{event_id}" />'
        for event_id in certification.RUNTIME_EVIDENCE.RUNTIME_POI_EVENT_IDS
    )
    probes = "".join(
        '<probe '
        f'scenarioSHA256="{scenario_hash}" '
        f'sentinelSHA256="{sentinel_hash}" />'
        for scenario_hash, sentinel_hash in (
            certification.RUNTIME_EVIDENCE.privacy_probe_hash_pairs()
        )
    )
    return (
        '<clipease-poi-export schemaVersion="1" '
        f'runID="{run_id}" subjectGitSHA="{subject_git_sha}" '
        f'traceTreeSHA256="{trace_tree_sha256}" '
        'captureMode="steady-state-attach">'
        f"<events>{events}</events>"
        '<privacy-probes mode="scanner-positive-control">'
        f"{probes}</privacy-probes>"
        "</clipease-poi-export>"
    )


def make_diagnostics_store(
    path: Path,
    *,
    event_id: str,
    marker: str = "",
) -> None:
    connection = sqlite3.connect(path)
    connection.execute(
        """
        CREATE TABLE performance_events (
            id TEXT PRIMARY KEY,
            timestamp REAL NOT NULL,
            name TEXT NOT NULL,
            category TEXT NOT NULL,
            duration_ms REAL NOT NULL,
            item_count INTEGER,
            result_count INTEGER,
            payload TEXT NOT NULL,
            payload_bytes INTEGER NOT NULL
        )
        """
    )
    payload = json.dumps({
        "id": event_id,
        "timestamp": "2026-07-31T00:00:00Z",
        "name": "diagnostics.session.start",
        "category": "diagnostics",
        "durationMS": 1,
        "metadata": {"marker": marker} if marker else {},
        "isMainThread": False,
    })
    connection.execute(
        """
        INSERT INTO performance_events (
            id, timestamp, name, category, duration_ms,
            item_count, result_count, payload, payload_bytes
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (
            event_id,
            1.0,
            "diagnostics.session.start",
            "diagnostics",
            1.0,
            None,
            None,
            payload,
            len(payload.encode()),
        ),
    )
    connection.commit()
    connection.close()


def metric_summary(rows: list[dict], metric_name: str) -> dict:
    raw_samples = [
        {
            "iteration": row["iteration"],
            "durationMS": float(row["metrics"][metric_name]["durationMS"]),
            "rssMiB": float(row["metrics"][metric_name]["rssMiB"]),
            "cpuTimeMS": float(row["metrics"][metric_name]["cpuTimeMS"]),
        }
        for row in rows
    ]

    def summary(field: str) -> dict:
        value = raw_samples[0][field]
        return {
            "p50": value,
            "p95": value,
            "p99": value,
            "max": value,
            "bootstrap95CI": {
                "p50": [value, value],
                "p95": [value, value],
                "p99": [value, value],
            },
        }

    return {
        "rawSamples": raw_samples,
        "durationMS": summary("durationMS"),
        "rssMiB": summary("rssMiB"),
        "cpuTimeMS": summary("cpuTimeMS"),
    }


def runtime_metric_values(duration_ms: float = 1.0) -> dict:
    return {
        metric_name: {
            "durationMS": duration_ms,
            "rssMiB": 100.0,
            "cpuTimeMS": 0.5,
        }
        for metric_name in certification.RUNTIME_EVIDENCE.ABSOLUTE_METRICS
    }


def runtime_sample_row(
    iteration: int,
    *,
    round_offset: float,
    baseline_source: dict,
    candidate_source: dict,
) -> dict:
    gpu_time = 10.0 + round_offset
    return {
        "iteration": iteration,
        "baseline": {
            "source": {
                **baseline_source,
                "observationID": f"baseline:{iteration}",
            },
            "metrics": runtime_metric_values(),
            "gpuTimeMS": gpu_time,
        },
        "candidate": {
            "source": {
                **candidate_source,
                "observationID": f"candidate:{iteration}",
            },
            "metrics": runtime_metric_values(),
            "idleCPUPercent": 0.9,
            "unchangedDiskWrites": 0,
            "captureAttemptCount": 10_000,
            "captureMissCount": 0,
            "captureDuplicateCount": 0,
            "frameTimesMS": [16.0, 16.1],
            "refreshPeriodMS": 16.67,
            "hitchDurationsMS": [],
            "renderedFrameCount": 1_000,
            "mainThreadDecodeSamples": 0,
            "hiddenRSSMiB": 119.0,
            "textRSSMiB": 249.0,
            "mixedRSSMiB": 399.0,
            "hiddenIncrementMiB": 49.0,
            "windowCycleRSSMiB": [100.0] * 101,
            "leakCount": 0,
            "standardDiagnosticsCPUTimeMS": 10.0,
            "detailedDiagnosticsCPUTimeMS": 10.1,
            "gpuTimeMS": gpu_time,
        },
    }


def runtime_source_identity_from_evidence(evidence: dict) -> dict:
    return {
        field: evidence[field]
        for field in certification.RUNTIME_EVIDENCE.SOURCE_IDENTITY_FIELDS
    }


class ReleaseCertificationTests(unittest.TestCase):
    fault_tests = {
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
    trace_templates = {
        "swiftui": "SwiftUI",
        "time-profiler-poi": "Time Profiler",
        "animation-hitches": "Animation Hitches",
        "system-trace": "System Trace",
        "power-profiler": "Power Profiler",
        "allocations": "Allocations",
        "leaks": "Leaks",
    }

    def test_fault_test_contract_matches_fault_runner(self):
        self.assertEqual(
            certification.REQUIRED_FAULT_TESTS,
            fault_runner.REQUIRED_FAULT_TESTS,
        )

    @staticmethod
    def trace_toc(template: str = "SwiftUI") -> str:
        return f"""\
<trace-toc>
  <run number="1">
    <info><summary><template-name>{template}</template-name></summary></info>
    <processes><process name="ClipEase" pid="1" /></processes>
    <data><table schema="time-profile" /></data>
  </run>
</trace-toc>
"""

    @staticmethod
    def trace_executable_uuids(path: Path) -> list[str]:
        manifest = json.loads(
            (path.parent / "clipease-trace-manifest.json").read_text()
        )
        return manifest["executable"]["machOUUIDs"]

    def trace_probe_patches(self):
        return (
            patch.object(
                certification,
                "xctrace_toc",
                side_effect=lambda path: self.trace_toc(
                    self.trace_templates[path.stem]
                ),
            ),
            patch.object(
                certification,
                "mach_o_uuids",
                side_effect=self.trace_executable_uuids,
            ),
        )

    def make_manifest(self, root: Path) -> tuple[Path, dict]:
        root.mkdir(parents=True, exist_ok=True)
        baseline_subject = certification.LOCKED_BASELINE_SUBJECT_GIT_SHA
        candidate_subject = "b" * 40
        rounds = []
        round_number = 0
        for os_target, version in (("macOS13", "13.7.8"), ("macOS26", "26.5.2")):
            for index in range(3):
                round_number += 1
                round_id = f"{os_target}-{index + 1}"
                run_id = f"certification:{round_id}"
                directory = root / round_id
                directory.mkdir()
                trace_paths = {}
                trace_hashes = {}
                for role in ("baseline", "candidate"):
                    subject = (
                        baseline_subject if role == "baseline" else candidate_subject
                    )
                    trace = directory / f"{role}.trace"
                    trace.mkdir()
                    executable = trace / "ClipEase-executable"
                    executable.write_bytes(
                        f"{round_id}:{role}:executable".encode()
                    )
                    uuid_hex = hashlib.md5(
                        f"{round_id}:{role}".encode(),
                        usedforsecurity=False,
                    ).hexdigest().upper()
                    executable_uuid = (
                        f"{uuid_hex[:8]}-{uuid_hex[8:12]}-{uuid_hex[12:16]}-"
                        f"{uuid_hex[16:20]}-{uuid_hex[20:]}"
                    )
                    trace_entries = []
                    for trace_id in sorted(certification.REQUIRED_TRACE_IDS):
                        artifact = trace / f"{trace_id}.trace"
                        artifact.mkdir()
                        (artifact / "run_data").write_text(
                            f"{round_id}:{role}:{trace_id}"
                        )
                        trace_entries.append({
                            "id": trace_id,
                            "template": self.trace_templates[trace_id],
                            "relativePath": artifact.name,
                            "sharingClassification": "shareable",
                        })
                    (trace / "clipease-trace-manifest.json").write_text(json.dumps({
                        "schemaVersion": 2,
                        "capturedAt": f"2026-07-30T00:00:0{index}Z",
                        "runID": run_id,
                        "subjectGitSHA": subject,
                        "captureHarnessSHA256": "d" * 64,
                        "targetProcess": "ClipEase",
                        "sourceWorktreeClean": True,
                        "sharingClassification": "shareable",
                        "pathContentPolicy": "file-activity-excluded",
                        "executable": {
                            "relativePath": executable.name,
                            "sha256": sha256(executable),
                            "machOUUIDs": [executable_uuid],
                        },
                        "traces": trace_entries,
                    }))
                    trace_paths[role] = trace
                    trace_hashes[role] = {
                        "treeSHA256": certification.tree_sha256(trace),
                        "manifestSHA256": sha256(
                            trace / "clipease-trace-manifest.json"
                        ),
                    }
                fixture_root = directory / "fixtures"
                fixtures = []
                for fixture_id, item_count in (
                    ("S1K", 1_000),
                    ("T10K", 10_000),
                    ("M100K", 100_000),
                    ("A3K", 3_000),
                ):
                    payload_root = fixture_root / fixture_id
                    payload_root.mkdir(parents=True)
                    payload = payload_root / "payload"
                    payload.write_text(fixture_id)
                    fixtures.append({
                        "id": fixture_id,
                        "itemCount": item_count,
                        "relativePath": fixture_id,
                        "fileCount": 1,
                        "payloadByteCount": payload.stat().st_size,
                        "treeSHA256": certification.tree_sha256(payload_root),
                    })
                fixture_manifest_path = directory / "fixtures.json"
                fixture_manifest_path.write_text(json.dumps({
                    "schemaVersion": 2,
                    "fixtures": fixtures,
                }))
                environment = {
                    "hardware": {
                        "model": "MacBookAir10,1",
                        "chip": "Apple M1",
                        "memoryBytes": str(8 * 1_024**3),
                        "physicalCPUCount": "8",
                    },
                    "os": {
                        "productVersion": version,
                        "buildVersion": "test",
                    },
                    "powerState": "AC Power",
                    "thermalState": "nominal",
                }
                raw_paths = {}
                metric_documents = {}
                for role in ("baseline", "candidate"):
                    rows = [
                        {
                            "iteration": sample_index,
                            "sourceRole": role,
                            "metrics": {
                                metric_name: {
                                    "durationMS": 1.0,
                                    "rssMiB": 100.0,
                                    "cpuTimeMS": 0.5,
                                }
                                for metric_name in sorted(
                                    certification.REQUIRED_MICRO_METRICS
                                )
                            },
                        }
                        for sample_index in range(30)
                    ]
                    raw_path = directory / f"{role}-raw.jsonl"
                    raw_path.write_text(
                        "".join(json.dumps(row) + "\n" for row in rows)
                    )
                    raw_paths[role] = raw_path
                    metric_documents[role] = {
                        metric_name: metric_summary(rows, metric_name)
                        for metric_name in sorted(
                            certification.REQUIRED_MICRO_METRICS
                        )
                    }
                baseline_path = directory / "baseline.json"
                candidate_path = directory / "candidate.json"
                baseline_path.write_text(json.dumps({
                    "schemaVersion": 3,
                    "runID": run_id,
                    "benchmark": "clipease-enterprise-performance",
                    "benchmarkKind": "micro",
                    "warmupCount": 5,
                    "sampleCount": 30,
                    "gitSHA": baseline_subject,
                    "subjectGitSHA": baseline_subject,
                    "sourceEvidence": {
                        "benchmarkHarnessSHA256": "c" * 64,
                        "worktree": {
                            "entryCount": 1,
                            "state": "baseline-harness-only",
                        },
                    },
                    "environment": environment,
                    "fixtures": fixtures,
                    "metrics": metric_documents["baseline"],
                    "artifacts": {
                        "rawSamples": {
                            "path": raw_paths["baseline"].name,
                            "sha256": sha256(raw_paths["baseline"]),
                        },
                        "fixtureManifest": {
                            "path": fixture_manifest_path.name,
                            "sha256": sha256(fixture_manifest_path),
                        },
                        "fixtureRoot": fixture_root.name,
                        "trace": {
                            "status": "available",
                            "path": trace_paths["baseline"].name,
                            "sharingClassification": "shareable",
                            "pathContentPolicy": "file-activity-excluded",
                            **trace_hashes["baseline"],
                        },
                    },
                }))
                candidate_path.write_text(json.dumps({
                    "schemaVersion": 3,
                    "runID": run_id,
                    "benchmark": "clipease-enterprise-performance",
                    "benchmarkKind": "micro",
                    "warmupCount": 5,
                    "sampleCount": 30,
                    "gitSHA": candidate_subject,
                    "subjectGitSHA": candidate_subject,
                    "sourceEvidence": {
                        "benchmarkHarnessSHA256": "c" * 64,
                        "worktree": {
                            "entryCount": 0,
                            "state": "clean",
                        },
                    },
                    "environment": environment,
                    "fixtures": fixtures,
                    "metrics": metric_documents["candidate"],
                    "artifacts": {
                        "rawSamples": {
                            "path": raw_paths["candidate"].name,
                            "sha256": sha256(raw_paths["candidate"]),
                        },
                        "fixtureManifest": {
                            "path": fixture_manifest_path.name,
                            "sha256": sha256(fixture_manifest_path),
                        },
                        "fixtureRoot": fixture_root.name,
                        "trace": {
                            "status": "available",
                            "path": trace_paths["candidate"].name,
                            "sharingClassification": "shareable",
                            "pathContentPolicy": "file-activity-excluded",
                            **trace_hashes["candidate"],
                        },
                    },
                }))
                comparison_path = directory / "comparison.json"
                comparison_path.write_text(json.dumps(
                    certification.COMPARATOR.build_comparison(
                        json.loads(baseline_path.read_text()),
                        json.loads(candidate_path.read_text()),
                        baseline_path=baseline_path,
                        candidate_path=candidate_path,
                        profile="m1-8gb-release",
                        require_trace=True,
                    )
                ))
                runtime_sources = {}
                runtime_source_evidence = {}
                runtime_poi_paths = {}
                runtime_diagnostics_paths = {}
                for role, subject in (
                    ("baseline", baseline_subject),
                    ("candidate", candidate_subject),
                ):
                    poi_export = directory / f"{role}-runtime-poi.xml"
                    poi_export.write_text(
                        poi_xml(
                            run_id=run_id,
                            subject_git_sha=subject,
                            trace_tree_sha256=trace_hashes[role][
                                "treeSHA256"
                            ],
                        )
                    )
                    runtime_poi_paths[role] = poi_export
                    diagnostics_export = (
                        directory / f"{role}-diagnostics.sqlite"
                    )
                    make_diagnostics_store(
                        diagnostics_export,
                        event_id=f"{round_id}:{role}:diagnostics",
                    )
                    runtime_diagnostics_paths[role] = diagnostics_export
                    (
                        runtime_sources[role],
                        runtime_source_evidence[role],
                    ) = certification.RUNTIME_EVIDENCE.source_identity(
                        trace_path=trace_paths[role],
                        poi_export_path=poi_export,
                        diagnostics_export_path=diagnostics_export,
                        run_id=run_id,
                        subject_git_sha=subject,
                        output_root=directory,
                    )
                runtime_rows = [
                    runtime_sample_row(
                        sample_index,
                        round_offset=round_number / 100,
                        baseline_source=runtime_sources["baseline"],
                        candidate_source=runtime_sources["candidate"],
                    )
                    for sample_index in range(30)
                ]
                runtime_raw_path = directory / "runtime-raw.jsonl"
                runtime_raw_path.write_text(
                    "".join(json.dumps(row) + "\n" for row in runtime_rows)
                )
                privacy_probe_receipt_path = (
                    directory / "privacy-probe-receipt.json"
                )
                certification.RUNTIME_EVIDENCE.generate_privacy_probe_receipt(
                    privacy_probe_receipt_path,
                    run_id=run_id,
                    baseline_subject_git_sha=baseline_subject,
                    candidate_subject_git_sha=candidate_subject,
                    probe_artifacts={
                        "runtime-samples": runtime_raw_path,
                        "poi-export": runtime_poi_paths["candidate"],
                        "diagnostics-payload": (
                            runtime_diagnostics_paths["candidate"]
                        ),
                        "diagnostics-search": (
                            runtime_diagnostics_paths["baseline"]
                        ),
                    },
                    baseline_poi_export_path=runtime_poi_paths["baseline"],
                    candidate_poi_export_path=runtime_poi_paths["candidate"],
                    baseline_trace_tree_sha256=runtime_sources["baseline"][
                        "traceTreeSHA256"
                    ],
                    candidate_trace_tree_sha256=runtime_sources["candidate"][
                        "traceTreeSHA256"
                    ],
                )
                privacy_audit = (
                    certification.RUNTIME_EVIDENCE.scan_privacy_artifacts(
                        {
                            "runtime-samples": runtime_raw_path,
                            "baseline-poi": runtime_poi_paths["baseline"],
                            "candidate-poi": runtime_poi_paths["candidate"],
                            "baseline-diagnostics": (
                                runtime_diagnostics_paths["baseline"]
                            ),
                            "candidate-diagnostics": (
                                runtime_diagnostics_paths["candidate"]
                            ),
                        },
                        output_root=directory,
                        privacy_probe_receipt_path=privacy_probe_receipt_path,
                        run_id=run_id,
                        baseline_subject_git_sha=baseline_subject,
                        candidate_subject_git_sha=candidate_subject,
                        baseline_trace_tree_sha256=runtime_sources["baseline"][
                            "traceTreeSHA256"
                        ],
                        candidate_trace_tree_sha256=runtime_sources["candidate"][
                            "traceTreeSHA256"
                        ],
                    )
                )
                runtime_report_path = directory / "runtime-evidence.json"
                runtime_report_path.write_text(json.dumps(
                    certification.RUNTIME_EVIDENCE.build_runtime_evidence(
                        runtime_rows,
                        run_id=run_id,
                        baseline_subject_git_sha=baseline_subject,
                        candidate_subject_git_sha=candidate_subject,
                        baseline_source=runtime_sources["baseline"],
                        candidate_source=runtime_sources["candidate"],
                        baseline_source_evidence=runtime_source_evidence["baseline"],
                        candidate_source_evidence=runtime_source_evidence["candidate"],
                        raw_path=runtime_raw_path,
                        raw_sha256=sha256(runtime_raw_path),
                        output_root=directory,
                        privacy_audit=privacy_audit,
                    )
                ))
                rounds.append({
                    "roundID": round_id,
                    "osTarget": os_target,
                    "baselineReport": baseline_path.relative_to(root).as_posix(),
                    "candidateReport": candidate_path.relative_to(root).as_posix(),
                    "comparison": comparison_path.relative_to(root).as_posix(),
                    "runtimeEvidence": {
                        "path": runtime_report_path.relative_to(root).as_posix(),
                        "sha256": sha256(runtime_report_path),
                    },
                })

        screenshot = root / "visual.png"
        recording = root / "visual.mov"
        build_log = root / "strict-release-build.log"
        xunit = root / "tests.xml"
        coverage = root / "changed-code-coverage.json"
        coverage_json = root / "swift-code-coverage.json"
        screenshot.write_bytes(valid_png_bytes())
        recording.write_bytes(valid_movie_bytes())
        media_audits = {}
        for target, frame_rate in (
            ("macOS13", 60),
            ("macOS26", 60),
            ("macOS26_120Hz", 120),
        ):
            audit_path = root / f"{target}-media-audit.json"
            baseline_reference = root / f"{target}-baseline-reference.png"
            candidate_reference = root / f"{target}-candidate-reference.mov"
            baseline_reference.write_bytes(valid_png_bytes())
            candidate_reference.write_bytes(valid_movie_bytes())
            audit_path.write_text(json.dumps({
                "schemaVersion": 1,
                "target": target,
                "reviewer": "Release Reviewer",
                "recordingFrameRateHz": frame_rate,
                "recordingFrameCount": frame_rate * 2,
                "durationSeconds": 2.0,
                "screenshotCount": 1,
                "artifactSHA256": {
                    "screenshots": [sha256(screenshot)],
                    "recording": sha256(recording),
                },
                "baselineReferencePath": baseline_reference.relative_to(root).as_posix(),
                "baselineReferenceSHA256": sha256(baseline_reference),
                "candidateReferencePath": candidate_reference.relative_to(root).as_posix(),
                "candidateReferenceSHA256": sha256(candidate_reference),
                "changedFrameCount": 0,
                "maxPixelDelta": 0.0,
                "perceptualDiffDecision": "pass",
            }))
            media_audits[target] = audit_path
        build_log.write_text(
            f"Subject Git SHA: {candidate_subject}\n"
            f"Strict release build command: {certification.STRICT_RELEASE_BUILD_COMMAND}\n"
            f"Strict release test command: {certification.STRICT_RELEASE_TEST_COMMAND}\n"
            "Build complete! (0 warnings)\n"
        )
        xunit.write_text(
            f'<testsuites subjectGitSHA="{candidate_subject}" '
            f'command="{certification.STRICT_RELEASE_TEST_COMMAND}" '
            'tests="1" failures="0" errors="0">'
            '<testsuite name="fixture" tests="1" failures="0" errors="0">'
            '<testcase name="fixtureTest" time="0.001000" />'
            '</testsuite></testsuites>'
        )
        coverage_json.write_text(json.dumps({"data": []}))
        coverage.write_text(json.dumps({
            "schemaVersion": 1,
            "subjectGitSHA": candidate_subject,
            "baseRef": baseline_subject,
            "coverageJSON": coverage_json.name,
            "coverageJSONSHA256": sha256(coverage_json),
            "worktreeClean": True,
            "decision": "pass",
            "changedCodeCoveragePercent": 80,
        }))
        fault_root = root / "fault-injection"
        fault_root.mkdir()
        fault_scenarios = {}
        for scenario, test_name in self.fault_tests.items():
            log_path = fault_root / f"{scenario}.log"
            log_path.write_text(
                f"◇ Test {test_name}() started.\n"
                f"✔ Test {test_name}() passed after 0.010 seconds.\n"
                "✔ Test run with 1 test in 0 suites passed after 0.010 seconds.\n"
            )
            fault_scenarios[scenario] = {
                "testName": test_name,
                "command": [
                    "swift",
                    "test",
                    "-c",
                    "release",
                    "--skip-build",
                    "--filter",
                    test_name,
                ],
                "exitCode": 0,
                "status": "pass",
                "log": {
                    "path": log_path.relative_to(fault_root).as_posix(),
                    "sha256": sha256(log_path),
                },
            }
        fault_report = fault_root / "fault-injection-report.json"
        fault_report.write_text(json.dumps({
            "schemaVersion": 1,
            "subjectGitSHA": candidate_subject,
            "sourceWorktreeStatus": [],
            "decision": "pass",
            "scenarios": fault_scenarios,
        }))
        manifest = {
            "schemaVersion": certification.SCHEMA_VERSION,
            "baselineSubjectGitSHA": baseline_subject,
            "candidateSubjectGitSHA": candidate_subject,
            "rounds": rounds,
            "faultInjection": {
                "path": fault_report.relative_to(root).as_posix(),
                "sha256": sha256(fault_report),
            },
            "buildAndTests": {
                "strictReleaseWarnings": 0,
                "allTestsPassed": True,
                "changedCodeCoveragePercent": 80,
                "candidateSubjectGitSHA": candidate_subject,
                "strictReleaseBuildCommand": certification.STRICT_RELEASE_BUILD_COMMAND,
                "strictReleaseTestCommand": certification.STRICT_RELEASE_TEST_COMMAND,
                "strictReleaseBuildLog": build_log.relative_to(root).as_posix(),
                "strictReleaseBuildLogSHA256": sha256(build_log),
                "xunitReport": xunit.relative_to(root).as_posix(),
                "xunitReportSHA256": sha256(xunit),
                "coverageReport": coverage.relative_to(root).as_posix(),
                "coverageReportSHA256": sha256(coverage),
            },
            "visualEvidence": {
                "macOS13": {
                    "decision": "pass",
                    "reviewer": "Release Reviewer",
                    "screenshots": [screenshot.relative_to(root).as_posix()],
                    "recording60Hz": recording.relative_to(root).as_posix(),
                    "mediaAudit": media_audits["macOS13"].relative_to(root).as_posix(),
                },
                "macOS26": {
                    "decision": "pass",
                    "reviewer": "Release Reviewer",
                    "screenshots": [screenshot.relative_to(root).as_posix()],
                    "recording60Hz": recording.relative_to(root).as_posix(),
                    "mediaAudit": media_audits["macOS26"].relative_to(root).as_posix(),
                },
                "macOS26_120Hz": {
                    "decision": "pass",
                    "reviewer": "Release Reviewer",
                    "screenshots": [screenshot.relative_to(root).as_posix()],
                    "recording120Hz": recording.relative_to(root).as_posix(),
                    "mediaAudit": media_audits["macOS26_120Hz"].relative_to(root).as_posix(),
                },
            },
        }
        manifest_path = root / "certification.json"
        manifest_path.write_text(json.dumps(manifest))
        return manifest_path, manifest

    def test_requires_three_passing_rounds_per_certification_os(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            manifest_path, manifest = self.make_manifest(root)

            toc_patch, uuid_patch = self.trace_probe_patches()
            with toc_patch, uuid_patch:
                result = certification.validate_document(manifest_path, manifest)

            self.assertEqual(result["decision"], "pass")
            self.assertEqual(
                result["roundCounts"],
                {"macOS13": 3, "macOS26": 3},
            )
            self.assertFalse(result["baselineAccepted"])

    def test_visual_gate_rejects_fake_media_bytes(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            manifest_path, manifest = self.make_manifest(root)
            screenshot = root / "visual.png"
            recording = root / "visual.mov"
            screenshot.write_bytes(b"png")
            with self.assertRaisesRegex(ValueError, "valid PNG"):
                certification.validate_visual_evidence(
                    manifest_path,
                    manifest["visualEvidence"],
                )

            screenshot.write_bytes(valid_png_bytes())
            (root / "visual.mov").write_bytes(b"mov")
            with self.assertRaisesRegex(ValueError, "QuickTime/ISO|truncated movie atom"):
                certification.validate_visual_evidence(
                    manifest_path,
                    manifest["visualEvidence"],
                )

            screenshot.write_bytes(valid_png_bytes()[:-1] + b"\x00")
            recording.write_bytes(valid_movie_bytes())
            with self.assertRaisesRegex(ValueError, "CRC mismatch"):
                certification.validate_visual_evidence(
                    manifest_path,
                    manifest["visualEvidence"],
                )

            screenshot.write_bytes(valid_png_bytes())
            recording.write_bytes(
                b"\x00\x00\x00\x14ftypqt  \x00\x00\x00\x00qt  "
                b"garbagemoovmdat"
            )
            with self.assertRaisesRegex(ValueError, "atom boundary"):
                certification.validate_visual_evidence(
                    manifest_path,
                    manifest["visualEvidence"],
                )

    def test_visual_gate_binds_media_audit_to_artifact_hashes_and_rate(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            manifest_path, manifest = self.make_manifest(root)
            audit_path = root / "macOS26-media-audit.json"
            audit = json.loads(audit_path.read_text())
            audit["artifactSHA256"]["recording"] = "0" * 64
            audit_path.write_text(json.dumps(audit))
            with self.assertRaisesRegex(ValueError, "recording hash"):
                certification.validate_visual_evidence(
                    manifest_path,
                    manifest["visualEvidence"],
                )

            audit["artifactSHA256"]["recording"] = sha256(root / "visual.mov")
            audit["recordingFrameRateHz"] = 30
            audit_path.write_text(json.dumps(audit))
            with self.assertRaisesRegex(ValueError, "frame rate"):
                certification.validate_visual_evidence(
                    manifest_path,
                    manifest["visualEvidence"],
                )

            audit["recordingFrameRateHz"] = 60
            audit["recordingFrameCount"] = 2
            audit_path.write_text(json.dumps(audit))
            with self.assertRaisesRegex(ValueError, "frame count"):
                certification.validate_visual_evidence(
                    manifest_path,
                    manifest["visualEvidence"],
                )

    def test_certification_envelope_and_rounds_use_exact_key_allowlists(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            manifest_path, manifest = self.make_manifest(root)
            manifest["targetPID"] = 4321

            with self.assertRaisesRegex(ValueError, "top-level fields"):
                certification.validate_document(manifest_path, manifest)

            del manifest["targetPID"]
            manifest["rounds"][0]["hostAbsolutePath"] = "/Users/private"
            with self.assertRaisesRegex(ValueError, "round fields"):
                certification.validate_document(manifest_path, manifest)

    def test_certification_manifest_rejects_absolute_paths_inside_package(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            manifest_path, manifest = self.make_manifest(root)
            manifest["rounds"][0]["baselineReport"] = str(
                certification_artifact_path(
                    manifest_path,
                    manifest["rounds"][0]["baselineReport"],
                ).resolve()
            )

            with self.assertRaisesRegex(ValueError, "must be relative"):
                certification.validate_document(manifest_path, manifest)

    def test_nested_shareable_evidence_uses_exact_key_allowlists(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            manifest_path, manifest = self.make_manifest(root)

            manifest["buildAndTests"]["targetPID"] = 42
            toc_patch, uuid_patch = self.trace_probe_patches()
            with toc_patch, uuid_patch:
                with self.assertRaisesRegex(ValueError, "buildAndTests fields"):
                    certification.validate_document(manifest_path, manifest)

            del manifest["buildAndTests"]["targetPID"]
            visual = manifest["visualEvidence"]
            visual["macOS13"]["hostAbsolutePath"] = "/Users/private"
            with self.assertRaisesRegex(ValueError, "visual evidence fields"):
                certification.validate_visual_evidence(manifest_path, visual)

            baseline_path = certification_artifact_path(
                manifest_path,
                manifest["rounds"][0]["baselineReport"],
            )
            baseline = json.loads(baseline_path.read_text())
            baseline["artifacts"]["hostAbsolutePath"] = "/Users/private"
            with self.assertRaisesRegex(ValueError, "artifact fields"):
                certification.validate_benchmark_report(
                    baseline_path,
                    baseline,
                    "baseline",
                    "baseline",
                )

            fault_path = certification_artifact_path(
                manifest_path,
                manifest["faultInjection"]["path"],
            )
            fault = json.loads(fault_path.read_text())
            fault["targetPID"] = 42
            fault_path.write_text(json.dumps(fault))
            manifest["faultInjection"]["sha256"] = sha256(fault_path)
            with self.assertRaisesRegex(ValueError, "fault report fields"):
                certification.validate_fault_injection(
                    manifest_path,
                    manifest["faultInjection"],
                    manifest["candidateSubjectGitSHA"],
                )

    def test_build_and_tests_bind_subject_commands_and_artifact_hashes(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            manifest_path, manifest = self.make_manifest(root)
            toc_patch, uuid_patch = self.trace_probe_patches()
            with toc_patch, uuid_patch:
                result = certification.validate_document(manifest_path, manifest)
            self.assertEqual(result["decision"], "pass")

            build = manifest["buildAndTests"]
            self.assertEqual(
                build["candidateSubjectGitSHA"],
                manifest["candidateSubjectGitSHA"],
            )

            build["candidateSubjectGitSHA"] = "c" * 40
            with toc_patch, uuid_patch:
                with self.assertRaisesRegex(ValueError, "candidateSubjectGitSHA"):
                    certification.validate_document(manifest_path, manifest)
            build["candidateSubjectGitSHA"] = manifest["candidateSubjectGitSHA"]

            build["strictReleaseBuildCommand"] = "swift build"
            with toc_patch, uuid_patch:
                with self.assertRaisesRegex(ValueError, "build command"):
                    certification.validate_document(manifest_path, manifest)
            build["strictReleaseBuildCommand"] = certification.STRICT_RELEASE_BUILD_COMMAND

            build["strictReleaseBuildLogSHA256"] = "0" * 64
            with toc_patch, uuid_patch:
                with self.assertRaisesRegex(ValueError, "build log hash"):
                    certification.validate_document(manifest_path, manifest)
            build["strictReleaseBuildLogSHA256"] = sha256(root / "strict-release-build.log")

            build_log_path = root / "strict-release-build.log"
            build_log_path.write_text(
                build_log_path.read_text().replace(
                    manifest["candidateSubjectGitSHA"], "c" * 40
                )
            )
            build["strictReleaseBuildLogSHA256"] = sha256(build_log_path)
            with toc_patch, uuid_patch:
                with self.assertRaisesRegex(ValueError, "build log subject"):
                    certification.validate_document(manifest_path, manifest)

    def test_build_and_tests_reject_stale_xunit_and_coverage_artifacts(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            manifest_path, manifest = self.make_manifest(root)
            xunit_path = root / "tests.xml"
            xunit_path.write_text(
                xunit_path.read_text().replace(
                    manifest["candidateSubjectGitSHA"], "c" * 40
                )
            )
            manifest["buildAndTests"]["xunitReportSHA256"] = sha256(xunit_path)
            toc_patch, uuid_patch = self.trace_probe_patches()
            with toc_patch, uuid_patch:
                with self.assertRaisesRegex(ValueError, "xUnit test report subject"):
                    certification.validate_document(manifest_path, manifest)

            root = Path(directory) / "coverage"
            manifest_path, manifest = self.make_manifest(root)
            coverage_path = root / "changed-code-coverage.json"
            coverage = json.loads(coverage_path.read_text())
            coverage["subjectGitSHA"] = "c" * 40
            coverage_path.write_text(json.dumps(coverage))
            manifest["buildAndTests"]["coverageReportSHA256"] = sha256(coverage_path)
            toc_patch, uuid_patch = self.trace_probe_patches()
            with toc_patch, uuid_patch:
                with self.assertRaisesRegex(
                    ValueError, "changed-code coverage report subject"
                ):
                    certification.validate_document(manifest_path, manifest)

    def test_build_and_tests_reject_invalid_coverage_receipt_metadata(self):
        cases = [
            ("baseRef", "c" * 40, "coverage baseline"),
            ("coverageJSONSHA256", "0" * 64, "coverage JSON hash"),
            ("worktreeClean", False, "clean worktree"),
        ]
        for field, invalid_value, message in cases:
            with self.subTest(field=field), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                manifest_path, manifest = self.make_manifest(root)
                coverage_path = root / "changed-code-coverage.json"
                coverage = json.loads(coverage_path.read_text())
                coverage[field] = invalid_value
                coverage_path.write_text(json.dumps(coverage))
                manifest["buildAndTests"]["coverageReportSHA256"] = sha256(
                    coverage_path
                )
                toc_patch, uuid_patch = self.trace_probe_patches()
                with toc_patch, uuid_patch:
                    with self.assertRaisesRegex(ValueError, message):
                        certification.validate_document(manifest_path, manifest)

    def test_build_and_tests_reject_non_xunit_xml_roots_and_children(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            manifest_path, manifest = self.make_manifest(root)
            xunit_path = root / "tests.xml"
            candidate = manifest["candidateSubjectGitSHA"]
            xunit_path.write_text(
                f'<notxunit subjectGitSHA="{candidate}" '
                f'command="{certification.STRICT_RELEASE_TEST_COMMAND}">'
                '<fake tests="323" failures="0" errors="0" /></notxunit>'
            )
            manifest["buildAndTests"]["xunitReportSHA256"] = sha256(xunit_path)
            toc_patch, uuid_patch = self.trace_probe_patches()
            with toc_patch, uuid_patch:
                with self.assertRaisesRegex(ValueError, "xUnit root"):
                    certification.validate_document(manifest_path, manifest)

            root = Path(directory) / "child"
            manifest_path, manifest = self.make_manifest(root)
            xunit_path = root / "tests.xml"
            candidate = manifest["candidateSubjectGitSHA"]
            xunit_path.write_text(
                f'<testsuites subjectGitSHA="{candidate}" '
                f'command="{certification.STRICT_RELEASE_TEST_COMMAND}">'
                '<fake tests="323" failures="0" errors="0" /></testsuites>'
            )
            manifest["buildAndTests"]["xunitReportSHA256"] = sha256(xunit_path)
            toc_patch, uuid_patch = self.trace_probe_patches()
            with toc_patch, uuid_patch:
                with self.assertRaisesRegex(ValueError, "xUnit suite"):
                    certification.validate_document(manifest_path, manifest)

    def test_build_and_tests_reject_xunit_count_or_testcase_shape_mismatches(self):
        cases = [
            (
                '<testsuites subjectGitSHA="{candidate}" '
                'command="{command}" tests="1" failures="0" errors="0">'
                '<testsuite name="fixture" tests="1" failures="0" errors="0" />'
                '</testsuites>',
                "test count",
            ),
            (
                '<testsuites subjectGitSHA="{candidate}" '
                'command="{command}" tests="1" failures="0" errors="0">'
                '<testsuite name="fixture" tests="1" failures="0" errors="0">'
                '<testcase name="" time="0.001" />'
                '</testsuite></testsuites>',
                "testcase name",
            ),
            (
                '<testsuites subjectGitSHA="{candidate}" '
                'command="{command}" tests="1" failures="0" errors="0">'
                '<testsuite name="fixture" tests="1" failures="0" errors="0">'
                '<testcase name="fixture" time="NaN" />'
                '</testsuite></testsuites>',
                "testcase time",
            ),
        ]
        for xml_template, message in cases:
            with self.subTest(message=message), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                manifest_path, manifest = self.make_manifest(root)
                xunit_path = root / "tests.xml"
                xunit_path.write_text(
                    xml_template.format(
                        candidate=manifest["candidateSubjectGitSHA"],
                        command=certification.STRICT_RELEASE_TEST_COMMAND,
                    )
                )
                manifest["buildAndTests"]["xunitReportSHA256"] = sha256(xunit_path)
                toc_patch, uuid_patch = self.trace_probe_patches()
                with toc_patch, uuid_patch:
                    with self.assertRaisesRegex(ValueError, message):
                        certification.validate_document(manifest_path, manifest)

    def test_persisted_failures_never_include_resolved_host_paths(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            manifest_path = root / "certification.json"
            output_path = root / "result.json"
            manifest = {
                "schemaVersion": 1,
                "baselineSubjectGitSHA": (
                    certification.LOCKED_BASELINE_SUBJECT_GIT_SHA
                ),
                "candidateSubjectGitSHA": "b" * 40,
                "rounds": [{
                    "roundID": "macOS13-1",
                    "osTarget": "macOS13",
                    "baselineReport": "missing/baseline.json",
                    "candidateReport": "missing/candidate.json",
                    "comparison": "missing/comparison.json",
                    "runtimeEvidence": {
                        "path": "missing/runtime.json",
                        "sha256": "0" * 64,
                    },
                }],
                "faultInjection": {"path": "missing/fault.json", "sha256": "0" * 64},
                "buildAndTests": {
                    "strictReleaseWarnings": 0,
                    "allTestsPassed": True,
                    "changedCodeCoveragePercent": 80,
                    "strictReleaseBuildLog": "missing/build.log",
                    "xunitReport": "missing/tests.xml",
                    "coverageReport": "missing/coverage.json",
                },
                "visualEvidence": {
                    "macOS13": {
                        "decision": "pass",
                        "reviewer": "Reviewer",
                        "screenshots": ["missing.png"],
                        "recording60Hz": "missing.mov",
                        "mediaAudit": "missing-macOS13-audit.json",
                    },
                    "macOS26": {
                        "decision": "pass",
                        "reviewer": "Reviewer",
                        "screenshots": ["missing.png"],
                        "recording60Hz": "missing.mov",
                        "mediaAudit": "missing-macOS26-audit.json",
                    },
                    "macOS26_120Hz": {
                        "decision": "pass",
                        "reviewer": "Reviewer",
                        "screenshots": ["missing.png"],
                        "recording120Hz": "missing.mov",
                        "mediaAudit": "missing-macOS26-120Hz-audit.json",
                    },
                },
            }
            manifest_path.write_text(json.dumps(manifest))
            original = sys.argv
            self.addCleanup(setattr, sys, "argv", original)
            sys.argv = [
                "validate_release_certification.py",
                "--manifest",
                str(manifest_path),
                "--output",
                str(output_path),
            ]

            with self.assertRaises(SystemExit):
                certification.main()

            serialized = output_path.read_text()
            self.assertNotIn(str(root.resolve()), serialized)

            secret_path = root / "host-private.trace"
            failed_probe = certification.subprocess.CompletedProcess(
                args=[],
                returncode=1,
                stdout="",
                stderr=f"cannot open {secret_path}",
            )
            with patch.object(
                certification.subprocess,
                "run",
                return_value=failed_probe,
            ):
                for probe in (
                    certification.xctrace_toc,
                    certification.mach_o_uuids,
                ):
                    with self.assertRaises(ValueError) as failure:
                        probe(secret_path)
                    self.assertNotIn(str(root.resolve()), str(failure.exception))

    def test_rejects_missing_round_and_runtime_threshold_regression(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            manifest_path, manifest = self.make_manifest(root)
            manifest["rounds"].pop()
            toc_patch, uuid_patch = self.trace_probe_patches()
            with toc_patch, uuid_patch:
                with self.assertRaisesRegex(ValueError, "exactly three rounds"):
                    certification.validate_document(manifest_path, manifest)

            _, manifest = self.make_manifest(root / "second")
            manifest_path = root / "second" / "certification.json"
            runtime_report_path = certification_artifact_path(
                manifest_path,
                manifest["rounds"][0]["runtimeEvidence"]["path"],
            )
            runtime_report = json.loads(runtime_report_path.read_text())
            runtime_raw_path = report_artifact_path(
                runtime_report_path,
                runtime_report["rawSamples"]["path"],
            )
            runtime_rows = [
                json.loads(line)
                for line in runtime_raw_path.read_text().splitlines()
            ]
            for row in runtime_rows:
                row["candidate"]["idleCPUPercent"] = 1.01
            runtime_raw_path.write_text(
                "".join(json.dumps(row) + "\n" for row in runtime_rows)
            )
            first_round = manifest["rounds"][0]
            source_evidence = runtime_report["sourceEvidence"]
            baseline_poi_path = report_artifact_path(
                runtime_report_path,
                source_evidence["baseline"]["poiExport"]["path"],
            )
            candidate_poi_path = report_artifact_path(
                runtime_report_path,
                source_evidence["candidate"]["poiExport"]["path"],
            )
            baseline_diagnostics_path = report_artifact_path(
                runtime_report_path,
                source_evidence["baseline"]["diagnosticsStore"]["path"],
            )
            candidate_diagnostics_path = report_artifact_path(
                runtime_report_path,
                source_evidence["candidate"]["diagnosticsStore"]["path"],
            )
            receipt_path = report_artifact_path(
                runtime_report_path,
                runtime_report["privacyAudit"]["privacyProbeReceipt"]["path"],
            )
            receipt_path.unlink()
            certification.RUNTIME_EVIDENCE.generate_privacy_probe_receipt(
                receipt_path,
                run_id=runtime_report["runID"],
                baseline_subject_git_sha=runtime_report[
                    "baselineSubjectGitSHA"
                ],
                candidate_subject_git_sha=runtime_report[
                    "candidateSubjectGitSHA"
                ],
                probe_artifacts={
                    "runtime-samples": runtime_raw_path,
                    "poi-export": candidate_poi_path,
                    "diagnostics-payload": candidate_diagnostics_path,
                    "diagnostics-search": baseline_diagnostics_path,
                },
                baseline_poi_export_path=baseline_poi_path,
                candidate_poi_export_path=candidate_poi_path,
                baseline_trace_tree_sha256=source_evidence["baseline"][
                    "traceTreeSHA256"
                ],
                candidate_trace_tree_sha256=source_evidence["candidate"][
                    "traceTreeSHA256"
                ],
            )
            privacy_audit = (
                certification.RUNTIME_EVIDENCE.scan_privacy_artifacts(
                    {
                        "runtime-samples": runtime_raw_path,
                        "baseline-poi": baseline_poi_path,
                        "candidate-poi": candidate_poi_path,
                        "baseline-diagnostics": baseline_diagnostics_path,
                        "candidate-diagnostics": candidate_diagnostics_path,
                    },
                    output_root=runtime_report_path.parent,
                    privacy_probe_receipt_path=receipt_path,
                    run_id=runtime_report["runID"],
                    baseline_subject_git_sha=runtime_report[
                        "baselineSubjectGitSHA"
                    ],
                    candidate_subject_git_sha=runtime_report[
                        "candidateSubjectGitSHA"
                    ],
                    baseline_trace_tree_sha256=source_evidence["baseline"][
                        "traceTreeSHA256"
                    ],
                    candidate_trace_tree_sha256=source_evidence["candidate"][
                        "traceTreeSHA256"
                    ],
                )
            )
            runtime_report_path.write_text(json.dumps(
                certification.RUNTIME_EVIDENCE.build_runtime_evidence(
                    runtime_rows,
                    run_id=runtime_report["runID"],
                    baseline_subject_git_sha=runtime_report[
                        "baselineSubjectGitSHA"
                    ],
                    candidate_subject_git_sha=runtime_report[
                        "candidateSubjectGitSHA"
                    ],
                    baseline_source=runtime_source_identity_from_evidence(
                        source_evidence["baseline"]
                    ),
                    candidate_source=runtime_source_identity_from_evidence(
                        source_evidence["candidate"]
                    ),
                    baseline_source_evidence=source_evidence["baseline"],
                    candidate_source_evidence=source_evidence["candidate"],
                    raw_path=runtime_raw_path,
                    raw_sha256=sha256(runtime_raw_path),
                    output_root=runtime_report_path.parent,
                    privacy_audit=privacy_audit,
                )
            ))
            first_round["runtimeEvidence"]["sha256"] = sha256(
                runtime_report_path
            )
            toc_patch, uuid_patch = self.trace_probe_patches()
            with toc_patch, uuid_patch:
                with self.assertRaisesRegex(ValueError, "did not pass"):
                    certification.validate_document(manifest_path, manifest)

    def test_rejects_forged_trace_directory_that_xctrace_cannot_open(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "forged.trace"
            root.mkdir()
            executable = root / "ClipEase-executable"
            executable.write_bytes(b"forged")
            traces = []
            for trace_id, template in self.trace_templates.items():
                artifact = root / f"{trace_id}.trace"
                artifact.mkdir()
                traces.append({
                    "id": trace_id,
                    "template": template,
                    "relativePath": artifact.name,
                    "sharingClassification": "shareable",
                })
            (root / "clipease-trace-manifest.json").write_text(json.dumps({
                "schemaVersion": 2,
                "capturedAt": "2026-07-31T00:00:00Z",
                "runID": "forged:run",
                "subjectGitSHA": "a" * 40,
                "captureHarnessSHA256": "d" * 64,
                "targetProcess": "ClipEase",
                "sourceWorktreeClean": True,
                "sharingClassification": "shareable",
                "pathContentPolicy": "file-activity-excluded",
                "executable": {
                    "relativePath": executable.name,
                    "sha256": sha256(executable),
                    "machOUUIDs": [
                        "11111111-1111-1111-1111-111111111111"
                    ],
                },
                "traces": traces,
            }))

            with patch.object(
                certification,
                "mach_o_uuids",
                return_value=["11111111-1111-1111-1111-111111111111"],
            ):
                with self.assertRaisesRegex(ValueError, "xctrace rejected"):
                    certification.validate_trace_collection(
                        root,
                        "forged",
                        expected_run_id="forged:run",
                        expected_subject_git_sha="a" * 40,
                    )

    def test_rejects_trace_bound_to_a_different_run_or_subject(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            manifest_path, manifest = self.make_manifest(root)
            baseline_report_path = certification_artifact_path(
                manifest_path,
                manifest["rounds"][0]["baselineReport"],
            )
            trace_path = report_artifact_path(
                baseline_report_path,
                json.loads(baseline_report_path.read_text())[
                    "artifacts"
                ]["trace"]["path"],
            )
            toc_patch, uuid_patch = self.trace_probe_patches()
            with toc_patch, uuid_patch:
                with self.assertRaisesRegex(ValueError, "runID"):
                    certification.validate_trace_collection(
                        trace_path,
                        "trace",
                        expected_run_id="different-run",
                        expected_subject_git_sha=certification.LOCKED_BASELINE_SUBJECT_GIT_SHA,
                    )
                with self.assertRaisesRegex(ValueError, "subjectGitSHA"):
                    certification.validate_trace_collection(
                        trace_path,
                        "trace",
                        expected_run_id=manifest["rounds"][0]["roundID"].replace(
                            "macOS", "certification:macOS"
                        ),
                        expected_subject_git_sha="f" * 40,
                    )

    def test_rejects_tampered_raw_samples_and_comparison(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            manifest_path, manifest = self.make_manifest(root)
            first_round = manifest["rounds"][0]
            baseline_report_path = certification_artifact_path(
                manifest_path,
                first_round["baselineReport"],
            )
            baseline_report = json.loads(baseline_report_path.read_text())
            raw_path = report_artifact_path(
                baseline_report_path,
                baseline_report["artifacts"]["rawSamples"]["path"],
            )
            raw_path.write_text(raw_path.read_text() + "{}\n")
            toc_patch, uuid_patch = self.trace_probe_patches()
            with toc_patch, uuid_patch:
                with self.assertRaisesRegex(ValueError, "hash"):
                    certification.validate_document(manifest_path, manifest)

            second_root = root / "comparison"
            second_manifest_path, second_manifest = self.make_manifest(second_root)
            comparison_path = certification_artifact_path(
                second_manifest_path,
                second_manifest["rounds"][0]["comparison"],
            )
            comparison = json.loads(comparison_path.read_text())
            comparison["decision"] = "fail"
            comparison_path.write_text(json.dumps(comparison))
            toc_patch, uuid_patch = self.trace_probe_patches()
            with toc_patch, uuid_patch:
                with self.assertRaisesRegex(ValueError, "fresh recomputation"):
                    certification.validate_document(
                        second_manifest_path,
                        second_manifest,
                    )

    def test_rejects_tampered_runtime_raw_samples_and_report(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            manifest_path, manifest = self.make_manifest(root)
            first_round = manifest["rounds"][0]
            runtime_report_path = certification_artifact_path(
                manifest_path,
                first_round["runtimeEvidence"]["path"],
            )
            runtime_report = json.loads(runtime_report_path.read_text())
            runtime_raw_path = report_artifact_path(
                runtime_report_path,
                runtime_report["rawSamples"]["path"],
            )
            runtime_raw_path.write_text(runtime_raw_path.read_text() + "{}\n")
            toc_patch, uuid_patch = self.trace_probe_patches()
            with toc_patch, uuid_patch:
                with self.assertRaisesRegex(ValueError, "raw sample hash"):
                    certification.validate_document(manifest_path, manifest)

            second_root = root / "runtime-report"
            second_manifest_path, second_manifest = self.make_manifest(second_root)
            runtime_report_path = certification_artifact_path(
                second_manifest_path,
                second_manifest["rounds"][0]["runtimeEvidence"]["path"],
            )
            runtime_report = json.loads(runtime_report_path.read_text())
            runtime_report["runtimeGates"]["idleCPUP95Percent"] = 0.1
            runtime_report_path.write_text(json.dumps(runtime_report))
            second_manifest["rounds"][0]["runtimeEvidence"]["sha256"] = sha256(
                runtime_report_path
            )
            toc_patch, uuid_patch = self.trace_probe_patches()
            with toc_patch, uuid_patch:
                with self.assertRaisesRegex(ValueError, "fresh raw-sample"):
                    certification.validate_document(
                        second_manifest_path,
                        second_manifest,
                    )

    def test_rejects_missing_detailed_local_diagnostics_artifact(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            manifest_path, manifest = self.make_manifest(root)
            runtime_report_path = certification_artifact_path(
                manifest_path,
                manifest["rounds"][0]["runtimeEvidence"]["path"],
            )
            runtime_report = json.loads(runtime_report_path.read_text())
            diagnostics_path = report_artifact_path(
                runtime_report_path,
                runtime_report["sourceEvidence"]["candidate"][
                    "diagnosticsStore"
                ]["path"],
            )
            diagnostics_path.unlink()

            toc_patch, uuid_patch = self.trace_probe_patches()
            with toc_patch, uuid_patch:
                with self.assertRaisesRegex(
                    ValueError,
                    "diagnostics store does not exist",
                ):
                    certification.validate_document(
                        manifest_path,
                        manifest,
                    )

    def test_rejects_reused_runtime_raw_samples_across_rounds(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            manifest_path, manifest = self.make_manifest(root)
            first = manifest["rounds"][0]["runtimeEvidence"]
            second_round = manifest["rounds"][1]
            second_report_path = certification_artifact_path(
                manifest_path,
                second_round["runtimeEvidence"]["path"],
            )
            second_report = json.loads(second_report_path.read_text())
            first_report_path = certification_artifact_path(
                manifest_path,
                first["path"],
            )
            first_report = json.loads(first_report_path.read_text())
            first_raw_path = report_artifact_path(
                first_report_path,
                first_report["rawSamples"]["path"],
            )
            second_raw_path = report_artifact_path(
                second_report_path,
                second_report["rawSamples"]["path"],
            )
            second_raw_path.write_bytes(first_raw_path.read_bytes())
            second_report["rawSamples"]["sha256"] = sha256(second_raw_path)
            second_report_path.write_text(json.dumps(second_report))
            second_round["runtimeEvidence"]["sha256"] = sha256(
                second_report_path
            )
            toc_patch, uuid_patch = self.trace_probe_patches()
            with toc_patch, uuid_patch:
                with self.assertRaisesRegex(
                    ValueError,
                    "source .* does not match|fresh raw-sample recomputation|privacy-probe receipt",
                ):
                    certification.validate_document(manifest_path, manifest)

    def test_rejects_forged_fault_status_without_bound_passing_log(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            manifest_path, manifest = self.make_manifest(root)
            fault_report_path = certification_artifact_path(
                manifest_path,
                manifest["faultInjection"]["path"],
            )
            fault_report = json.loads(fault_report_path.read_text())
            scenario = fault_report["scenarios"]["diskFull"]
            log_path = fault_report_path.parent / scenario["log"]["path"]
            log_path.write_text("claimed pass without a test result\n")
            scenario["log"]["sha256"] = sha256(log_path)
            fault_report_path.write_text(json.dumps(fault_report))
            manifest["faultInjection"]["sha256"] = sha256(fault_report_path)
            toc_patch, uuid_patch = self.trace_probe_patches()
            with toc_patch, uuid_patch:
                with self.assertRaisesRegex(ValueError, "passing test marker"):
                    certification.validate_document(manifest_path, manifest)

    def test_rejects_evidence_paths_outside_the_certification_package(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            package = root / "package"
            package.mkdir()
            outside = root / "outside.png"
            outside.write_bytes(b"png")
            manifest_path = package / "certification.json"

            with self.assertRaisesRegex(ValueError, "must be relative"):
                certification.resolve_path(
                    manifest_path,
                    str(outside),
                    "outside evidence",
                )

    def test_rejects_absolute_paths_inside_benchmark_reports(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            manifest_path, manifest = self.make_manifest(root)
            baseline_path = certification_artifact_path(
                manifest_path,
                manifest["rounds"][0]["baselineReport"],
            )
            baseline = json.loads(baseline_path.read_text())
            raw_path = report_artifact_path(
                baseline_path,
                baseline["artifacts"]["rawSamples"]["path"],
            )
            baseline["artifacts"]["rawSamples"]["path"] = str(raw_path.resolve())

            with self.assertRaisesRegex(ValueError, "must be relative"):
                certification.validate_benchmark_report(
                    baseline_path,
                    baseline,
                    "baseline",
                    "baseline",
                )

    def test_rejects_local_only_file_activity_and_persisted_pid(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            manifest_path, manifest = self.make_manifest(root)
            round_entry = manifest["rounds"][0]
            report_path = certification_artifact_path(
                manifest_path,
                round_entry["baselineReport"],
            )
            report = json.loads(report_path.read_text())
            trace_path = report_artifact_path(
                report_path,
                report["artifacts"]["trace"]["path"],
            )
            trace_manifest_path = trace_path / "clipease-trace-manifest.json"
            trace_manifest = json.loads(trace_manifest_path.read_text())
            original_traces = list(trace_manifest["traces"])
            file_activity = trace_path / "file-activity.trace"
            file_activity.mkdir()
            trace_manifest["sharingClassification"] = (
                "local-only-sensitive-paths"
            )
            trace_manifest["pathContentPolicy"] = (
                "contains-sensitive-path-data"
            )
            trace_manifest["traces"].append({
                "id": "file-activity",
                "template": "File Activity",
                "relativePath": file_activity.name,
                "sharingClassification": "local-only-sensitive-paths",
            })
            trace_manifest_path.write_text(json.dumps(trace_manifest))

            with self.assertRaisesRegex(ValueError, "shareable|File Activity"):
                certification.validate_trace_collection(
                    trace_path,
                    "baseline trace",
                    expected_run_id=report["runID"],
                    expected_subject_git_sha=report["subjectGitSHA"],
                )

            trace_manifest["sharingClassification"] = "shareable"
            trace_manifest["pathContentPolicy"] = "file-activity-excluded"
            trace_manifest["traces"] = original_traces
            trace_manifest["targetPID"] = 123
            trace_manifest_path.write_text(json.dumps(trace_manifest))
            with self.assertRaisesRegex(ValueError, "must not persist targetPID"):
                certification.validate_trace_collection(
                    trace_path,
                    "baseline trace",
                    expected_run_id=report["runID"],
                    expected_subject_git_sha=report["subjectGitSHA"],
                )

            del trace_manifest["targetPID"]
            trace_manifest["hostAbsolutePath"] = "/Users/private/ClipEase"
            trace_manifest_path.write_text(json.dumps(trace_manifest))
            with self.assertRaisesRegex(
                ValueError,
                "must not persist hostAbsolutePath",
            ):
                certification.validate_trace_collection(
                    trace_path,
                    "baseline trace",
                    expected_run_id=report["runID"],
                    expected_subject_git_sha=report["subjectGitSHA"],
                )

    def test_runtime_validator_recomputes_privacy_sentinel_scan(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            manifest_path, manifest = self.make_manifest(root)
            round_entry = manifest["rounds"][0]
            runtime_report_path = certification_artifact_path(
                manifest_path,
                round_entry["runtimeEvidence"]["path"],
            )
            runtime_report = json.loads(runtime_report_path.read_text())
            source_evidence = runtime_report["sourceEvidence"]
            candidate_diagnostics_path = report_artifact_path(
                runtime_report_path,
                source_evidence["candidate"]["diagnosticsStore"]["path"],
            )
            connection = sqlite3.connect(candidate_diagnostics_path)
            payload = json.loads(
                connection.execute(
                    "SELECT payload FROM performance_events LIMIT 1"
                ).fetchone()[0]
            )
            payload["metadata"]["marker"] = (
                "CLIPEASE_PRIVACY_SENTINEL_secret"
            )
            payload_text = json.dumps(payload)
            connection.execute(
                """
                UPDATE performance_events
                SET payload = ?, payload_bytes = ?
                """,
                (payload_text, len(payload_text.encode())),
            )
            connection.commit()
            connection.close()

            sources = {}
            evidence = {}
            for role, subject in (
                ("baseline", certification.LOCKED_BASELINE_SUBJECT_GIT_SHA),
                ("candidate", "b" * 40),
            ):
                sources[role], evidence[role] = (
                    certification.RUNTIME_EVIDENCE.source_identity(
                        trace_path=report_artifact_path(
                            runtime_report_path,
                            source_evidence[role]["trace"]["path"],
                        ),
                        poi_export_path=report_artifact_path(
                            runtime_report_path,
                            source_evidence[role]["poiExport"]["path"],
                        ),
                        diagnostics_export_path=report_artifact_path(
                            runtime_report_path,
                            source_evidence[role]["diagnosticsStore"]["path"],
                        ),
                        run_id=runtime_report["runID"],
                        subject_git_sha=subject,
                        output_root=runtime_report_path.parent,
                    )
                )

            raw_path = report_artifact_path(
                runtime_report_path,
                runtime_report["rawSamples"]["path"],
            )
            rows = certification.RUNTIME_EVIDENCE.load_rows(raw_path)
            for row in rows:
                for role in ("baseline", "candidate"):
                    row[role]["source"] = {
                        **sources[role],
                        "observationID": f"{role}:{row['iteration']}",
                    }
            raw_path.write_text(
                "".join(json.dumps(row) + "\n" for row in rows)
            )
            baseline_poi_path = report_artifact_path(
                runtime_report_path,
                evidence["baseline"]["poiExport"]["path"],
            )
            candidate_poi_path = report_artifact_path(
                runtime_report_path,
                evidence["candidate"]["poiExport"]["path"],
            )
            baseline_diagnostics_path = report_artifact_path(
                runtime_report_path,
                evidence["baseline"]["diagnosticsStore"]["path"],
            )
            receipt_path = report_artifact_path(
                runtime_report_path,
                runtime_report["privacyAudit"]["privacyProbeReceipt"]["path"],
            )
            receipt_path.unlink()
            certification.RUNTIME_EVIDENCE.generate_privacy_probe_receipt(
                receipt_path,
                run_id=runtime_report["runID"],
                baseline_subject_git_sha=(
                    certification.LOCKED_BASELINE_SUBJECT_GIT_SHA
                ),
                candidate_subject_git_sha="b" * 40,
                probe_artifacts={
                    "runtime-samples": raw_path,
                    "poi-export": candidate_poi_path,
                    "diagnostics-payload": candidate_diagnostics_path,
                    "diagnostics-search": baseline_diagnostics_path,
                },
                baseline_poi_export_path=baseline_poi_path,
                candidate_poi_export_path=candidate_poi_path,
                baseline_trace_tree_sha256=sources["baseline"][
                    "traceTreeSHA256"
                ],
                candidate_trace_tree_sha256=sources["candidate"][
                    "traceTreeSHA256"
                ],
            )
            actual_audit = (
                certification.RUNTIME_EVIDENCE.scan_privacy_artifacts(
                    {
                        "runtime-samples": raw_path,
                        "baseline-poi": baseline_poi_path,
                        "candidate-poi": candidate_poi_path,
                        "baseline-diagnostics": baseline_diagnostics_path,
                        "candidate-diagnostics": (
                            candidate_diagnostics_path
                        ),
                    },
                    output_root=runtime_report_path.parent,
                    privacy_probe_receipt_path=receipt_path,
                    run_id=runtime_report["runID"],
                    baseline_subject_git_sha=(
                        certification.LOCKED_BASELINE_SUBJECT_GIT_SHA
                    ),
                    candidate_subject_git_sha="b" * 40,
                    baseline_trace_tree_sha256=sources["baseline"][
                        "traceTreeSHA256"
                    ],
                    candidate_trace_tree_sha256=sources["candidate"][
                        "traceTreeSHA256"
                    ],
                )
            )
            self.assertEqual(actual_audit["status"], "fail")
            forged_passing_audit = {
                **actual_audit,
                "status": "pass",
                "matchedSentinelCount": 0,
            }
            runtime_report = (
                certification.RUNTIME_EVIDENCE.build_runtime_evidence(
                    rows,
                    run_id=runtime_report["runID"],
                    baseline_subject_git_sha=(
                        certification.LOCKED_BASELINE_SUBJECT_GIT_SHA
                    ),
                    candidate_subject_git_sha="b" * 40,
                    baseline_source=sources["baseline"],
                    candidate_source=sources["candidate"],
                    baseline_source_evidence=evidence["baseline"],
                    candidate_source_evidence=evidence["candidate"],
                    raw_path=raw_path,
                    raw_sha256=sha256(raw_path),
                    output_root=runtime_report_path.parent,
                    privacy_audit=forged_passing_audit,
                )
            )
            runtime_report_path.write_text(json.dumps(runtime_report))
            runtime_reference = {
                "path": runtime_report_path.relative_to(
                    manifest_path.parent
                ).as_posix(),
                "sha256": sha256(runtime_report_path),
            }

            with self.assertRaisesRegex(
                ValueError,
                "fresh raw-sample recomputation",
            ):
                certification.validate_runtime_evidence(
                    manifest_path,
                    runtime_reference,
                    expected_run_id=runtime_report["runID"],
                    baseline_subject=(
                        certification.LOCKED_BASELINE_SUBJECT_GIT_SHA
                    ),
                    candidate_subject="b" * 40,
                    baseline_trace_tree_sha256=(
                        sources["baseline"]["traceTreeSHA256"]
                    ),
                    candidate_trace_tree_sha256=(
                        sources["candidate"]["traceTreeSHA256"]
                    ),
                )


if __name__ == "__main__":
    unittest.main()
