import importlib.util
import json
import os
import sqlite3
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "run_benchmark_matrix",
    ROOT / "scripts/performance/run_benchmark_matrix.py",
)
run_benchmark_matrix = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(run_benchmark_matrix)


class BenchmarkMatrixTests(unittest.TestCase):
    def test_run_checked_persists_bounded_sanitized_timeout_diagnostics(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve() / "host private worktree"
            root.mkdir()
            failure_log = root / "artifacts" / "prepare-failure.log"
            command = [
                "/usr/bin/swift",
                "test",
                "--package-path",
                str(root),
            ]
            run_benchmark_matrix.persist_command_failure(
                arguments=command,
                status="TIMEOUT AFTER 7 SECONDS",
                stdout=f"working in {root}\n" + ("x" * 100_000),
                stderr=f"failed to open {root / 'private.sqlite'}",
                failure_log=failure_log,
                private_roots=(root, failure_log.parent),
            )

            persisted = failure_log.read_text()
            self.assertNotIn(str(root), persisted)
            self.assertNotIn("private worktree", persisted)
            self.assertIn("<absolute-path>", persisted)
            self.assertLessEqual(
                failure_log.stat().st_size,
                run_benchmark_matrix.PERSISTED_FAILURE_LOG_MAX_BYTES,
            )
            self.assertEqual(failure_log.stat().st_mode & 0o777, 0o600)

    def test_persisted_failure_strips_terminal_controls_and_spaced_paths(self):
        sanitized = run_benchmark_matrix.persisted_failure_text(
            "\x1b[31mcannot open "
            "/Users/reviewer/Library/Application Support/ClipEase/private.sqlite"
            "\x1b[0m",
            (),
        )

        self.assertNotIn("\x1b", sanitized)
        self.assertNotIn("/Users", sanitized)
        self.assertNotIn("Application Support", sanitized)
        self.assertIn("<absolute-path>", sanitized)

    def test_persisted_failure_redacts_absolute_paths_after_colon_labels(self):
        sanitized = run_benchmark_matrix.persisted_failure_text(
            "\n".join(
                [
                    "path:/Users/reviewer/Private/benchmark.sqlite",
                    "cwd:/private/tmp/clipease-benchmark",
                    "HOME:/Users/reviewer",
                ]
            ),
            (),
        )

        self.assertNotIn("/Users", sanitized)
        self.assertNotIn("/private", sanitized)
        self.assertEqual(sanitized.count("<absolute-path>"), 3)

    def test_failure_log_atomically_replaces_symlink_without_touching_target(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            artifact_root = root / "artifacts"
            artifact_root.mkdir()
            victim = root / "victim.txt"
            victim.write_text("untouched")
            failure_log = artifact_root / "failure.log"
            os.symlink(victim, failure_log)

            run_benchmark_matrix.persist_command_failure(
                arguments=["swift", "test"],
                status="EXIT CODE 1",
                stdout="synthetic stdout",
                stderr="synthetic stderr",
                failure_log=failure_log,
                private_roots=(root,),
            )

            self.assertEqual(victim.read_text(), "untouched")
            self.assertFalse(failure_log.is_symlink())
            self.assertEqual(failure_log.stat().st_mode & 0o777, 0o600)
            self.assertEqual(artifact_root.stat().st_mode & 0o777, 0o700)

    def test_run_checked_terminates_the_entire_process_group_on_timeout(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            marker = root / "orphan-marker"
            failure_log = root / "timeout.log"
            grandchild = (
                "import pathlib,sys,time;"
                "time.sleep(0.6);"
                "pathlib.Path(sys.argv[1]).write_text('orphan')"
            )
            parent = (
                "import subprocess,sys,time;"
                "subprocess.Popen([sys.executable,'-c',sys.argv[1],sys.argv[2]]);"
                "time.sleep(30)"
            )

            with self.assertRaisesRegex(RuntimeError, "timed out"):
                run_benchmark_matrix.run_checked(
                    [sys.executable, "-c", parent, grandchild, str(marker)],
                    cwd=root,
                    environment=None,
                    timeout=0.2,
                    failure_log=failure_log,
                )

            time.sleep(0.8)
            self.assertFalse(marker.exists())
            self.assertTrue(failure_log.is_file())

    def test_run_checked_stops_output_flood_with_bounded_valid_utf8_log(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            failure_log = root / "output-limit.log"
            writer = (
                "import os,time;"
                "payload=b'\\xff'+b'x'*65535;"
                f"count={run_benchmark_matrix.SUBPROCESS_OUTPUT_LIMIT_BYTES // 65536 + 4};"
                "[os.write(1,payload) for _ in range(count)];"
                "time.sleep(30)"
            )

            with self.assertRaisesRegex(RuntimeError, "output limit"):
                run_benchmark_matrix.run_checked(
                    [sys.executable, "-c", writer],
                    cwd=root,
                    environment=None,
                    timeout=2,
                    failure_log=failure_log,
                )

            persisted = failure_log.read_text()
            self.assertIn("\ufffd", persisted)
            self.assertLessEqual(
                failure_log.stat().st_size,
                run_benchmark_matrix.PERSISTED_FAILURE_LOG_MAX_BYTES,
            )

    def test_run_checked_can_return_an_explicitly_accepted_nonzero_status(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            failure_log = root / "unexpected.log"

            result = run_benchmark_matrix.run_checked(
                [sys.executable, "-c", "raise SystemExit(2)"],
                cwd=root,
                environment=None,
                timeout=2,
                failure_log=failure_log,
                accepted_returncodes=frozenset({0, 2}),
            )

            self.assertEqual(result, 2)
            self.assertFalse(failure_log.exists())

    def test_interleaved_versions_alternates_first_runner_each_iteration(self):
        self.assertEqual(
            run_benchmark_matrix.interleaved_versions(["baseline", "candidate"], 0),
            ["baseline", "candidate"],
        )
        self.assertEqual(
            run_benchmark_matrix.interleaved_versions(["baseline", "candidate"], 1),
            ["candidate", "baseline"],
        )
        self.assertEqual(
            run_benchmark_matrix.interleaved_versions(["candidate"], 9),
            ["candidate"],
        )

    def test_hardware_probe_is_explicitly_free_of_serial_identifiers(self):
        keys = set(run_benchmark_matrix.hardware_environment())
        self.assertEqual(
            keys,
            {"model", "chip", "memoryBytes", "physicalCPUCount"},
        )
        self.assertNotIn("serial", " ".join(keys).lower())

    def test_power_and_thermal_probes_are_normalized_for_stability_checks(self):
        self.assertEqual(
            run_benchmark_matrix.normalized_power_state(
                "Now drawing from 'AC Power'\n -InternalBattery-0 100%; charged"
            ),
            "AC Power",
        )
        self.assertEqual(
            run_benchmark_matrix.normalized_power_state(
                "Now drawing from 'Battery Power'\n -InternalBattery-0 80%"
            ),
            "Battery Power",
        )
        self.assertEqual(
            run_benchmark_matrix.normalized_thermal_state(
                "Note: No thermal warning level has been recorded\n"
                "Note: No performance warning level has been recorded"
            ),
            "nominal",
        )
        self.assertEqual(
            run_benchmark_matrix.normalized_thermal_state(
                "CPU_Speed_Limit = 80\nScheduler_Limit = 100"
            ),
            "constrained",
        )

    def test_measurement_environment_fails_closed_for_unknown_or_unstable_state(self):
        stable = {
            "hardware": {
                "model": "Mac14,6",
                "chip": "Apple M2 Max",
                "memoryBytes": "103079215104",
                "physicalCPUCount": "12",
            },
            "os": {"productVersion": "26.5", "buildVersion": "25F84"},
            "powerState": "AC Power",
            "thermalState": "nominal",
        }
        run_benchmark_matrix.validate_measurement_environment(stable)

        unavailable = dict(stable, thermalState="unavailable")
        with self.assertRaises(RuntimeError):
            run_benchmark_matrix.validate_measurement_environment(unavailable)

        on_battery = dict(stable, powerState="Battery Power")
        with self.assertRaises(RuntimeError):
            run_benchmark_matrix.validate_measurement_environment(on_battery)

        drifted = dict(stable, thermalState="constrained")
        with self.assertRaises(RuntimeError):
            run_benchmark_matrix.assert_environment_stable(stable, drifted)

    def test_daily_mode_requires_a_baseline_unless_candidate_only_is_explicit(self):
        original = sys.argv
        self.addCleanup(setattr, sys, "argv", original)
        sys.argv = [
            "run_benchmark_matrix.py",
            "--candidate-root",
            str(ROOT),
            "--warmups",
            "5",
            "--sample-count",
            "30",
        ]
        arguments = run_benchmark_matrix.parse_arguments()
        with self.assertRaises(SystemExit):
            run_benchmark_matrix.validate_arguments(arguments)

        arguments.candidate_only = True
        run_benchmark_matrix.validate_arguments(arguments)

    def test_m1_release_profile_requires_both_trace_artifacts_before_running(self):
        original = sys.argv
        self.addCleanup(setattr, sys, "argv", original)
        sys.argv = [
            "run_benchmark_matrix.py",
            "--candidate-root",
            str(ROOT),
            "--baseline-root",
            str(ROOT),
            "--warmups",
            "5",
            "--sample-count",
            "30",
            "--profile",
            "m1-8gb-release",
        ]
        arguments = run_benchmark_matrix.parse_arguments()
        with self.assertRaises(SystemExit):
            run_benchmark_matrix.validate_arguments(arguments)

    def test_release_profile_requires_external_runtime_samples(self):
        original = sys.argv
        self.addCleanup(setattr, sys, "argv", original)
        sys.argv = [
            "run_benchmark_matrix.py",
            "--candidate-root",
            str(ROOT),
            "--baseline-root",
            str(ROOT),
            "--baseline-subject-sha",
            "a" * 40,
            "--candidate-subject-sha",
            "b" * 40,
            "--candidate-trace",
            str(ROOT / "candidate.trace"),
            "--baseline-trace",
            str(ROOT / "baseline.trace"),
            "--run-id",
            "certification:round-1",
            "--warmups",
            "5",
            "--sample-count",
            "30",
            "--profile",
            "m1-8gb-release",
        ]
        arguments = run_benchmark_matrix.parse_arguments()
        with self.assertRaisesRegex(SystemExit, "runtime samples"):
            run_benchmark_matrix.validate_arguments(arguments)

        arguments.runtime_samples = ROOT / "runtime.jsonl"
        with self.assertRaisesRegex(SystemExit, "POI exports"):
            run_benchmark_matrix.validate_arguments(arguments)

        arguments.baseline_poi_export = ROOT / "baseline-poi.xml"
        arguments.candidate_poi_export = ROOT / "candidate-poi.xml"
        with self.assertRaisesRegex(SystemExit, "diagnostics exports"):
            run_benchmark_matrix.validate_arguments(arguments)

    def test_detailed_local_diagnostics_snapshot_is_validated_and_backed_up(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "ClipEaseDiagnostics.sqlite"
            connection = sqlite3.connect(source)
            connection.execute("PRAGMA journal_mode = WAL")
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
                "metadata": {},
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
                    len(payload),
                ),
            )
            connection.commit()
            destination = root / "packaged.sqlite"

            run_benchmark_matrix.snapshot_detailed_local_diagnostics_store(
                source,
                destination,
            )
            connection.close()

            packaged = sqlite3.connect(destination)
            try:
                event_count = packaged.execute(
                    "SELECT COUNT(*) FROM performance_events"
                ).fetchone()[0]
            finally:
                packaged.close()
            self.assertEqual(event_count, 1)

            invalid = root / "not-a-store.sqlite"
            invalid.write_text("not sqlite")
            with self.assertRaisesRegex(RuntimeError, "detailedLocal"):
                run_benchmark_matrix.snapshot_detailed_local_diagnostics_store(
                    invalid,
                    root / "invalid-copy.sqlite",
                )

    def test_trace_bundle_is_copied_as_a_directory_artifact(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            trace = root / "input.trace"
            trace.mkdir()
            (trace / "run_data").write_text("trace")
            (trace / "clipease-trace-manifest.json").write_text(json.dumps({
                "schemaVersion": 2,
                "capturedAt": "2026-07-31T00:00:00Z",
                "runID": "certification:round-1",
                "subjectGitSHA": "a" * 40,
                "captureHarnessSHA256": "c" * 64,
                "targetProcess": "ClipEase",
                "sourceWorktreeClean": True,
                "sharingClassification": "shareable",
                "pathContentPolicy": "file-activity-excluded",
                "executable": {
                    "relativePath": "ClipEase-executable",
                    "sha256": "d" * 64,
                    "machOUUIDs": [
                        "11111111-1111-1111-1111-111111111111"
                    ],
                },
                "traces": [],
            }))
            version = run_benchmark_matrix.VersionRun(
                "candidate",
                ROOT,
                root / "output",
                root / "fixtures",
                root / "fixtures.json",
                trace,
                "a" * 40,
            )

            status, copied = run_benchmark_matrix.collect_trace(
                version,
                "certification:round-1",
            )

            self.assertEqual(status, "available")
            self.assertIsNotNone(copied)
            self.assertTrue((copied / "run_data").is_file())

            manifest_path = trace / "clipease-trace-manifest.json"
            manifest = json.loads(manifest_path.read_text())
            manifest["hostAbsolutePath"] = "/Users/private/ClipEase"
            manifest_path.write_text(json.dumps(manifest))
            with self.assertRaisesRegex(RuntimeError, "forbidden host field"):
                run_benchmark_matrix.collect_trace(
                    version,
                    "certification:round-1",
                )

    def test_report_lives_at_package_root_so_all_paths_are_relocatable(self):
        with tempfile.TemporaryDirectory() as directory:
            package_root = Path(directory) / "package"
            version = run_benchmark_matrix.VersionRun(
                "candidate",
                ROOT,
                package_root,
                package_root / "fixtures",
                package_root / "fixtures.json",
                None,
                "a" * 40,
            )

            self.assertEqual(
                version.report_path,
                package_root / "candidate-benchmark-report.json",
            )
            self.assertEqual(
                version.raw_output,
                package_root / "candidate/raw-samples.jsonl",
            )

    def test_trace_bundle_must_match_the_matrix_run_and_subject(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            trace = root / "input.trace"
            trace.mkdir()
            (trace / "clipease-trace-manifest.json").write_text(json.dumps({
                "schemaVersion": 2,
                "runID": "different-run",
                "subjectGitSHA": "b" * 40,
                "targetProcess": "ClipEase",
            }))
            version = run_benchmark_matrix.VersionRun(
                "candidate",
                ROOT,
                root / "output",
                root / "fixtures",
                root / "fixtures.json",
                trace,
                "a" * 40,
            )

            with self.assertRaisesRegex(RuntimeError, "runID"):
                run_benchmark_matrix.collect_trace(
                    version,
                    "certification:round-1",
                )

    def test_subject_sha_must_match_the_actual_worktree_head(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            version = run_benchmark_matrix.VersionRun(
                "candidate",
                ROOT,
                root / "output",
                root / "fixtures",
                root / "fixtures.json",
                None,
                "f" * 40,
            )
            with self.assertRaisesRegex(RuntimeError, "subject SHA mismatch"):
                run_benchmark_matrix.validate_version_subject(version)

    def test_stdout_summary_contains_only_output_root_relative_paths(self):
        with tempfile.TemporaryDirectory() as directory:
            output_root = Path(directory).resolve() / "host-private-output"
            candidate = run_benchmark_matrix.VersionRun(
                "candidate",
                ROOT,
                output_root,
                output_root / "fixtures",
                output_root / "fixtures.json",
                None,
                "a" * 40,
            )

            summary = run_benchmark_matrix.output_summary(
                output_root=output_root,
                run_id="certification:round-1",
                runs={"candidate": candidate},
                comparison_path=output_root / "comparison.json",
                runtime_evidence_path=output_root / "runtime-evidence.json",
            )

            serialized = json.dumps(summary)
            self.assertNotIn(str(output_root), serialized)
            self.assertEqual(summary["outputRoot"], ".")
            self.assertEqual(
                summary["reports"]["candidate"],
                "candidate-benchmark-report.json",
            )
            self.assertEqual(summary["comparison"], "comparison.json")
            self.assertEqual(
                summary["runtimeEvidence"],
                "runtime-evidence.json",
            )


if __name__ == "__main__":
    unittest.main()
