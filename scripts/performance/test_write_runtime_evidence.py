import importlib.util
import json
import sqlite3
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "write_runtime_evidence",
    ROOT / "scripts/performance/write_runtime_evidence.py",
)
runtime = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(runtime)


def source_identity(role: str) -> dict:
    subject = "a" * 40 if role == "baseline" else "b" * 40
    return {
        "runID": "certification:macOS13-1",
        "subjectGitSHA": subject,
        "targetProcess": "ClipEase",
        "executableSHA256": ("c" if role == "baseline" else "d") * 64,
        "machOUUIDs": [
            (
                "11111111-1111-1111-1111-111111111111"
                if role == "baseline"
                else "22222222-2222-2222-2222-222222222222"
            )
        ],
        "traceTreeSHA256": ("e" if role == "baseline" else "f") * 64,
        "poiExportSHA256": ("1" if role == "baseline" else "2") * 64,
        "diagnosticsStoreSHA256": (
            "5" if role == "baseline" else "6"
        ) * 64,
        "poiEventIDs": runtime.RUNTIME_POI_EVENT_IDS,
    }


def source_evidence(role: str) -> dict:
    identity = source_identity(role)
    return {
        **identity,
        "trace": {
            "path": f"{role}.trace",
            "treeSHA256": identity["traceTreeSHA256"],
            "manifestSHA256": "3" * 64,
        },
        "poiExport": {
            "path": f"{role}-poi.xml",
            "sha256": identity["poiExportSHA256"],
        },
        "diagnosticsStore": {
            "path": f"{role}-diagnostics.sqlite",
            "sha256": identity["diagnosticsStoreSHA256"],
            "format": "clipease-detailed-local-sqlite",
            "eventCount": 1,
        },
    }


def metric_values(duration_ms: float = 1.0) -> dict:
    return {
        metric_name: {
            "durationMS": duration_ms,
            "rssMiB": 100.0,
            "cpuTimeMS": 0.5,
        }
        for metric_name in runtime.ABSOLUTE_METRICS
    }


def sample_row(iteration: int, candidate_gpu_ms: float = 10.0) -> dict:
    baseline_source = {
        **source_identity("baseline"),
        "observationID": f"baseline:{iteration}",
    }
    candidate_source = {
        **source_identity("candidate"),
        "observationID": f"candidate:{iteration}",
    }
    return {
        "iteration": iteration,
        "baseline": {
            "source": baseline_source,
            "metrics": metric_values(),
            "gpuTimeMS": 10.0,
        },
        "candidate": {
            "source": candidate_source,
            "metrics": metric_values(),
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
            "gpuTimeMS": candidate_gpu_ms,
        },
    }


def passing_privacy_audit() -> dict:
    return {
        "schemaVersion": 1,
        "status": "pass",
        "matchedSentinelCount": 0,
        "privacyProbeReceipt": {
            "path": "privacy-probe-receipt.json",
            "sha256": "7" * 64,
        },
        "scannedArtifacts": [
            {
                "kind": "runtime-samples",
                "path": "runtime.jsonl",
                "sha256": "4" * 64,
            },
            {
                "kind": "baseline-poi",
                "path": "baseline-poi.xml",
                "sha256": "1" * 64,
            },
            {
                "kind": "candidate-poi",
                "path": "candidate-poi.xml",
                "sha256": "2" * 64,
            },
            {
                "kind": "baseline-diagnostics",
                "path": "baseline-diagnostics.sqlite",
                "sha256": "5" * 64,
            },
            {
                "kind": "candidate-diagnostics",
                "path": "candidate-diagnostics.sqlite",
                "sha256": "6" * 64,
            },
        ],
    }


def poi_xml(
    *,
    run_id: str,
    subject_git_sha: str,
    trace_tree_sha256: str,
    event_ids: list[str] | None = None,
) -> str:
    events = "".join(
        f'<event id="{event_id}" />'
        for event_id in (
            runtime.RUNTIME_POI_EVENT_IDS if event_ids is None else event_ids
        )
    )
    probes = "".join(
        '<probe '
        f'scenarioSHA256="{scenario_hash}" '
        f'sentinelSHA256="{sentinel_hash}" />'
        for scenario_hash, sentinel_hash in runtime.privacy_probe_hash_pairs()
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


def build_report(rows: list[dict]) -> dict:
    return runtime.build_runtime_evidence(
        rows,
        run_id="certification:macOS13-1",
        baseline_subject_git_sha="a" * 40,
        candidate_subject_git_sha="b" * 40,
        baseline_source=source_identity("baseline"),
        candidate_source=source_identity("candidate"),
        baseline_source_evidence=source_evidence("baseline"),
        candidate_source_evidence=source_evidence("candidate"),
        raw_path=Path("/tmp/runtime.jsonl"),
        raw_sha256="4" * 64,
        output_root=Path("/tmp"),
        privacy_audit=passing_privacy_audit(),
    )


class RuntimeEvidenceTests(unittest.TestCase):
    @staticmethod
    def make_diagnostics_store(path: Path, payload_marker: str = "") -> None:
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
            "id": "event-id",
            "timestamp": "2026-07-31T00:00:00Z",
            "name": "diagnostics.session.start",
            "category": "diagnostics",
            "durationMS": 1,
            "metadata": {"marker": payload_marker} if payload_marker else {},
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
                "event-id",
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

    def test_runtime_and_absolute_gates_are_derived_from_bound_samples(self):
        rows = [sample_row(index) for index in range(30)]

        report = build_report(rows)

        self.assertEqual(report["schemaVersion"], 2)
        self.assertEqual(report["decision"], "pass")
        self.assertEqual(report["sampleCount"], 30)
        self.assertEqual(
            set(report["absoluteMetrics"]["candidate"]),
            runtime.ABSOLUTE_METRICS,
        )
        self.assertFalse(report["absoluteThresholdFailures"])
        self.assertTrue(
            all(
                result["decision"] == "pass"
                for result in report["absoluteMetricComparison"].values()
            )
        )
        gates = report["runtimeGates"]
        self.assertEqual(gates["idleCPUP95Percent"], 0.9)
        self.assertEqual(gates["captureMissRate"], 0)
        self.assertEqual(gates["captureDuplicateRate"], 0)
        self.assertEqual(gates["hitchRatio"], 0)
        self.assertEqual(gates["windowCycleSlopeMiB"], 0)
        self.assertEqual(gates["diagnosticsPrivacyAudit"], "pass")

    def test_runtime_evidence_fails_when_paired_gpu_regression_is_proven(self):
        rows = [
            sample_row(index, candidate_gpu_ms=11.0)
            for index in range(30)
        ]

        report = build_report(rows)

        self.assertEqual(report["decision"], "fail")
        self.assertTrue(
            any(
                "gpuRegressionBootstrap95CILowerPercent" in error
                for error in report["errors"]
            )
        )

    def test_absolute_duration_threshold_is_not_satisfied_by_micro_metrics(self):
        rows = [sample_row(index) for index in range(30)]
        for row in rows:
            row["candidate"]["metrics"]["cold_start"]["durationMS"] = 1_501

        report = build_report(rows)

        self.assertEqual(report["decision"], "fail")
        self.assertIn("cold_start", report["absoluteThresholdFailures"])

    def test_runtime_samples_reject_missing_metrics_and_trace_identity_mismatch(self):
        rows = [sample_row(index) for index in range(30)]
        del rows[0]["candidate"]["metrics"]["listeners_ready"]
        with self.assertRaisesRegex(ValueError, "14 absolute metrics"):
            build_report(rows)

        rows = [sample_row(index) for index in range(30)]
        rows[0]["candidate"]["source"]["executableSHA256"] = "9" * 64
        with self.assertRaisesRegex(ValueError, "executableSHA256"):
            build_report(rows)

    def test_runtime_samples_reject_missing_iterations_and_too_few_captures(self):
        rows = [sample_row(index) for index in range(30)]
        rows[-1]["iteration"] = 28
        with self.assertRaisesRegex(ValueError, "iterations"):
            build_report(rows)

        rows = [sample_row(index) for index in range(30)]
        rows[0]["candidate"]["captureAttemptCount"] = 9_999
        with self.assertRaisesRegex(ValueError, "10,000"):
            build_report(rows)

    def test_poi_export_must_contain_every_required_metric_and_gate_event(self):
        with tempfile.TemporaryDirectory() as directory:
            trace = Path(directory) / "sample.trace"
            trace.mkdir()
            (trace / "executable").write_bytes(b"binary")
            (trace / "clipease-trace-manifest.json").write_text(
                json.dumps({
                    "schemaVersion": 2,
                    "capturedAt": "2026-07-31T00:00:00Z",
                    "runID": "certification:macOS13-1",
                    "subjectGitSHA": "a" * 40,
                    "captureHarnessSHA256": "9" * 64,
                    "targetProcess": "ClipEase",
                    "sourceWorktreeClean": True,
                    "sharingClassification": "shareable",
                    "pathContentPolicy": "file-activity-excluded",
                    "executable": {
                        "relativePath": "executable",
                        "sha256": "c" * 64,
                        "machOUUIDs": [
                            "11111111-1111-1111-1111-111111111111"
                        ],
                    },
                    "traces": [],
                })
            )
            export = Path(directory) / "poi.xml"
            diagnostics = Path(directory) / "diagnostics.sqlite"
            self.make_diagnostics_store(diagnostics)
            export.write_text(poi_xml(
                run_id="certification:macOS13-1",
                subject_git_sha="a" * 40,
                trace_tree_sha256=runtime.tree_sha256(trace),
                event_ids=["listeners_ready"],
            ))
            with self.assertRaisesRegex(ValueError, "missing required event IDs"):
                runtime.source_identity(
                    trace_path=trace,
                    poi_export_path=export,
                    diagnostics_export_path=diagnostics,
                    run_id="certification:macOS13-1",
                    subject_git_sha="a" * 40,
                    output_root=Path(directory),
                )

    def test_poi_export_rejects_unstructured_text_even_with_every_event_id(self):
        with tempfile.TemporaryDirectory() as directory:
            export = Path(directory) / "renamed.xml"
            export.write_text("\n".join(runtime.RUNTIME_POI_EVENT_IDS))

            with self.assertRaisesRegex(ValueError, "structured XML"):
                runtime.validate_poi_export(
                    export,
                    run_id="certification:macOS13-1",
                    subject_git_sha="a" * 40,
                    trace_tree_sha256="e" * 64,
                )

    def test_poi_export_is_bound_to_run_and_subject_not_just_extension(self):
        with tempfile.TemporaryDirectory() as directory:
            export = Path(directory) / "poi.xml"
            export.write_text(poi_xml(
                run_id="different-run",
                subject_git_sha="a" * 40,
                trace_tree_sha256="e" * 64,
            ))

            with self.assertRaisesRegex(ValueError, "runID"):
                runtime.validate_poi_export(
                    export,
                    run_id="certification:macOS13-1",
                    subject_git_sha="a" * 40,
                    trace_tree_sha256="e" * 64,
                )

            renamed = Path(directory) / "poi.txt"
            renamed.write_text(poi_xml(
                run_id="certification:macOS13-1",
                subject_git_sha="a" * 40,
                trace_tree_sha256="e" * 64,
            ))
            with self.assertRaisesRegex(ValueError, r"\.xml suffix"):
                runtime.validate_poi_export(
                    renamed,
                    run_id="certification:macOS13-1",
                    subject_git_sha="a" * 40,
                    trace_tree_sha256="e" * 64,
                )

    def test_xctrace_poi_normalizer_requires_real_hash_only_probe_records(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            raw = root / "xctrace.xml"
            normalized = root / "normalized.xml"
            exported_tokens = [
                "clipboard.capture",
                "storage.operation",
                "history.window",
                "history.search",
                "asset.image-decode",
                "asset.ocr",
                "maintenance.cleanup",
            ]
            raw.write_text(
                "<trace-query-result>"
                + "".join(
                    f'<row signpost-name="{token}" />'
                    for token in exported_tokens
                )
                + "</trace-query-result>"
            )

            runtime.normalize_poi_export(
                raw,
                normalized,
                run_id="certification:macOS13-1",
                subject_git_sha="a" * 40,
                trace_tree_sha256="e" * 64,
            )
            runtime.validate_poi_export(
                normalized,
                run_id="certification:macOS13-1",
                subject_git_sha="a" * 40,
                trace_tree_sha256="e" * 64,
            )
            normalized_root = runtime.ElementTree.parse(normalized).getroot()
            self.assertEqual(
                normalized_root.attrib["captureMode"],
                "steady-state-attach",
            )
            self.assertNotIn("app.startup", runtime.RUNTIME_POI_EVENT_IDS)
            self.assertNotIn(
                "application.exit-drain",
                runtime.RUNTIME_POI_EVENT_IDS,
            )
            self.assertIn("cold_start", runtime.ABSOLUTE_METRICS)
            self.assertIn("exit_drain", runtime.ABSOLUTE_METRICS)
            trace_source = (
                ROOT
                / "Sources/ClipEase/Core/Utilities/HistoryPerformanceTrace.swift"
            ).read_text()
            self.assertIn('beginInterval("app.startup"', trace_source)
            self.assertIn(
                'beginInterval("application.exit-drain"',
                trace_source,
            )

            missing_probe = root / "missing-probe.xml"
            missing_probe.write_text(
                "<trace-query-result><row>"
                + " ".join(runtime.RUNTIME_POI_EVENT_IDS[:-1])
                + "</row></trace-query-result>"
            )
            with self.assertRaisesRegex(ValueError, "missing required event IDs"):
                runtime.normalize_poi_export(
                    missing_probe,
                    root / "must-not-exist.xml",
                    run_id="certification:macOS13-1",
                    subject_git_sha="a" * 40,
                    trace_tree_sha256="e" * 64,
                )

    def test_privacy_scan_reads_artifacts_instead_of_trusting_reported_count(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            runtime_samples = root / "runtime.jsonl"
            baseline_poi = root / "baseline-poi.xml"
            candidate_poi = root / "candidate-poi.xml"
            baseline_diagnostics = root / "baseline-diagnostics.sqlite"
            candidate_diagnostics = root / "candidate-diagnostics.sqlite"
            runtime_samples.write_text('{"diagnosticsForbiddenFieldCount": 0}\n')
            baseline_trace_hash = "e" * 64
            candidate_trace_hash = "f" * 64
            baseline_poi.write_text(poi_xml(
                run_id="certification:macOS13-1",
                subject_git_sha="a" * 40,
                trace_tree_sha256=baseline_trace_hash,
            ))
            candidate_poi.write_text(poi_xml(
                run_id="certification:macOS13-1",
                subject_git_sha="b" * 40,
                trace_tree_sha256=candidate_trace_hash,
            ))
            self.make_diagnostics_store(baseline_diagnostics)
            self.make_diagnostics_store(
                candidate_diagnostics,
                "CLIPEASE_PRIVACY_SENTINEL_secret",
            )
            receipt = root / "privacy-probe-receipt.json"
            probe_artifacts = {
                "runtime-samples": runtime_samples,
                "poi-export": candidate_poi,
                "diagnostics-payload": candidate_diagnostics,
                "diagnostics-search": baseline_diagnostics,
            }
            runtime.generate_privacy_probe_receipt(
                receipt,
                run_id="certification:macOS13-1",
                baseline_subject_git_sha="a" * 40,
                candidate_subject_git_sha="b" * 40,
                probe_artifacts=probe_artifacts,
                baseline_poi_export_path=baseline_poi,
                candidate_poi_export_path=candidate_poi,
                baseline_trace_tree_sha256=baseline_trace_hash,
                candidate_trace_tree_sha256=candidate_trace_hash,
            )

            audit = runtime.scan_privacy_artifacts(
                {
                    "runtime-samples": runtime_samples,
                    "baseline-poi": baseline_poi,
                    "candidate-poi": candidate_poi,
                    "baseline-diagnostics": baseline_diagnostics,
                    "candidate-diagnostics": candidate_diagnostics,
                },
                output_root=root,
                privacy_probe_receipt_path=receipt,
                run_id="certification:macOS13-1",
                baseline_subject_git_sha="a" * 40,
                candidate_subject_git_sha="b" * 40,
                baseline_trace_tree_sha256=baseline_trace_hash,
                candidate_trace_tree_sha256=candidate_trace_hash,
            )

            self.assertEqual(audit["status"], "fail")
            self.assertEqual(audit["matchedSentinelCount"], 1)
            self.assertTrue(
                all(not Path(item["path"]).is_absolute() for item in audit["scannedArtifacts"])
            )
            self.assertNotIn("secret", str(audit))

    def test_generated_privacy_receipt_proves_injection_using_hashes_only(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            runtime_samples = root / "runtime.jsonl"
            baseline_poi = root / "baseline-poi.xml"
            candidate_poi = root / "candidate-poi.xml"
            baseline_diagnostics = root / "baseline.sqlite"
            candidate_diagnostics = root / "candidate.sqlite"
            runtime_samples.write_text("{}\n")
            baseline_trace_hash = "e" * 64
            candidate_trace_hash = "f" * 64
            baseline_poi.write_text(poi_xml(
                run_id="certification:macOS13-1",
                subject_git_sha="a" * 40,
                trace_tree_sha256=baseline_trace_hash,
            ))
            candidate_poi.write_text(poi_xml(
                run_id="certification:macOS13-1",
                subject_git_sha="b" * 40,
                trace_tree_sha256=candidate_trace_hash,
            ))
            self.make_diagnostics_store(baseline_diagnostics)
            self.make_diagnostics_store(candidate_diagnostics)
            receipt_path = root / "privacy-probe-receipt.json"
            runtime.generate_privacy_probe_receipt(
                receipt_path,
                run_id="certification:macOS13-1",
                baseline_subject_git_sha="a" * 40,
                candidate_subject_git_sha="b" * 40,
                probe_artifacts={
                    "runtime-samples": runtime_samples,
                    "poi-export": candidate_poi,
                    "diagnostics-payload": candidate_diagnostics,
                    "diagnostics-search": baseline_diagnostics,
                },
                baseline_poi_export_path=baseline_poi,
                candidate_poi_export_path=candidate_poi,
                baseline_trace_tree_sha256=baseline_trace_hash,
                candidate_trace_tree_sha256=candidate_trace_hash,
            )

            receipt = json.loads(receipt_path.read_text())
            serialized = receipt_path.read_text()
            self.assertEqual(len(receipt["injections"]), 4)
            self.assertTrue(
                all(
                    injection["detectedSentinelCount"] > 0
                    for injection in receipt["injections"]
                )
            )
            for scenario, sentinel in runtime.PRIVACY_PROBE_SCENARIOS.items():
                self.assertNotIn(scenario, serialized)
                self.assertNotIn(sentinel.decode(), serialized)

            mismatched = json.loads(json.dumps(receipt))
            mismatched["runID"] = "different-run"
            with self.assertRaisesRegex(ValueError, "runID does not match"):
                runtime.validate_privacy_probe_receipt(
                    mismatched,
                    run_id="certification:macOS13-1",
                    baseline_subject_git_sha="a" * 40,
                    candidate_subject_git_sha="b" * 40,
                    probe_artifacts={
                        "runtime-samples": runtime_samples,
                        "poi-export": candidate_poi,
                        "diagnostics-payload": candidate_diagnostics,
                        "diagnostics-search": baseline_diagnostics,
                    },
                    baseline_poi_export_path=baseline_poi,
                    candidate_poi_export_path=candidate_poi,
                    baseline_trace_tree_sha256=baseline_trace_hash,
                    candidate_trace_tree_sha256=candidate_trace_hash,
                )

            incomplete = json.loads(json.dumps(receipt))
            incomplete["injections"].pop()
            with self.assertRaisesRegex(ValueError, "exact required"):
                runtime.validate_privacy_probe_receipt(
                    incomplete,
                    run_id="certification:macOS13-1",
                    baseline_subject_git_sha="a" * 40,
                    candidate_subject_git_sha="b" * 40,
                    probe_artifacts={
                        "runtime-samples": runtime_samples,
                        "poi-export": candidate_poi,
                        "diagnostics-payload": candidate_diagnostics,
                        "diagnostics-search": baseline_diagnostics,
                    },
                    baseline_poi_export_path=baseline_poi,
                    candidate_poi_export_path=candidate_poi,
                    baseline_trace_tree_sha256=baseline_trace_hash,
                    candidate_trace_tree_sha256=candidate_trace_hash,
                )

            forged_probe_hash = json.loads(json.dumps(receipt))
            forged_probe_hash["injections"][0]["probeArtifactSHA256"] = "0" * 64
            with self.assertRaisesRegex(ValueError, "positive-control replay"):
                runtime.validate_privacy_probe_receipt(
                    forged_probe_hash,
                    run_id="certification:macOS13-1",
                    baseline_subject_git_sha="a" * 40,
                    candidate_subject_git_sha="b" * 40,
                    probe_artifacts={
                        "runtime-samples": runtime_samples,
                        "poi-export": candidate_poi,
                        "diagnostics-payload": candidate_diagnostics,
                        "diagnostics-search": baseline_diagnostics,
                    },
                    baseline_poi_export_path=baseline_poi,
                    candidate_poi_export_path=candidate_poi,
                    baseline_trace_tree_sha256=baseline_trace_hash,
                    candidate_trace_tree_sha256=candidate_trace_hash,
                )

            forged_count = json.loads(json.dumps(receipt))
            forged_count["injections"][0]["detectedSentinelCount"] = 999_999
            with self.assertRaisesRegex(ValueError, "positive-control replay"):
                runtime.validate_privacy_probe_receipt(
                    forged_count,
                    run_id="certification:macOS13-1",
                    baseline_subject_git_sha="a" * 40,
                    candidate_subject_git_sha="b" * 40,
                    probe_artifacts={
                        "runtime-samples": runtime_samples,
                        "poi-export": candidate_poi,
                        "diagnostics-payload": candidate_diagnostics,
                        "diagnostics-search": baseline_diagnostics,
                    },
                    baseline_poi_export_path=baseline_poi,
                    candidate_poi_export_path=candidate_poi,
                    baseline_trace_tree_sha256=baseline_trace_hash,
                    candidate_trace_tree_sha256=candidate_trace_hash,
                )

    def test_privacy_scan_cannot_pass_without_a_bound_injection_receipt(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            artifact = root / "runtime.jsonl"
            artifact.write_text("{}\n")

            with self.assertRaisesRegex(ValueError, "privacy-probe receipt"):
                runtime.scan_privacy_artifacts(
                    {"runtime-samples": artifact},
                    output_root=root,
                    run_id="certification:macOS13-1",
                    baseline_subject_git_sha="a" * 40,
                    candidate_subject_git_sha="b" * 40,
                    baseline_trace_tree_sha256="e" * 64,
                    candidate_trace_tree_sha256="f" * 64,
                )

    def test_privacy_probe_receipt_rejects_extra_leak_fields_and_plaintext(self):
        receipt = {
            "schemaVersion": 1,
            "runID": "certification:macOS13-1",
            "baselineSubjectGitSHA": "a" * 40,
            "candidateSubjectGitSHA": "b" * 40,
            "injections": [],
            "hostAbsolutePath": "/Users/private/ClipboardHistory",
        }

        with self.assertRaisesRegex(ValueError, "fields do not match schema"):
            runtime.validate_privacy_probe_receipt(
                receipt,
                run_id="certification:macOS13-1",
                baseline_subject_git_sha="a" * 40,
                candidate_subject_git_sha="b" * 40,
            )

    def test_runtime_report_omits_target_pid_and_uses_relative_paths(self):
        report = build_report([sample_row(index) for index in range(30)])

        serialized = str(report)
        self.assertNotIn("targetPID", serialized)
        self.assertEqual(report["rawSamples"]["path"], "runtime.jsonl")
        self.assertEqual(
            report["sourceEvidence"]["baseline"]["trace"]["path"],
            "baseline.trace",
        )
        self.assertEqual(
            report["sourceEvidence"]["candidate"]["diagnosticsStore"]["path"],
            "candidate-diagnostics.sqlite",
        )

    def test_rejects_a_file_that_is_not_a_detailed_local_store(self):
        with tempfile.TemporaryDirectory() as directory:
            invalid = Path(directory) / "diagnostics.sqlite"
            invalid.write_text("not a SQLite store")

            with self.assertRaisesRegex(ValueError, "detailedLocal"):
                runtime.validate_detailed_local_diagnostics_store(invalid)

    def test_packaged_diagnostics_store_must_not_depend_on_wal_sidecars(self):
        with tempfile.TemporaryDirectory() as directory:
            diagnostics = Path(directory) / "diagnostics.sqlite"
            self.make_diagnostics_store(diagnostics)
            Path(str(diagnostics) + "-wal").write_bytes(b"unbound WAL")

            with self.assertRaisesRegex(ValueError, "standalone snapshot"):
                runtime.validate_detailed_local_diagnostics_store(diagnostics)


if __name__ == "__main__":
    unittest.main()
