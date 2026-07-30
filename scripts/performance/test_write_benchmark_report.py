import hashlib
import importlib.util
import json
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "write_benchmark_report",
    ROOT / "scripts/performance/write_benchmark_report.py",
)
report_writer = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(report_writer)


def make_fixture_document(root: Path):
    fixtures = []
    for identifier, count in (
        ("S1K", 1_000),
        ("T10K", 10_000),
        ("M100K", 100_000),
        ("A3K", 3_000),
    ):
        fixture_root = root / identifier
        fixture_root.mkdir(parents=True)
        payload = fixture_root / "payload"
        payload.write_bytes(identifier.encode())
        file_digest = hashlib.sha256(payload.read_bytes()).digest()
        tree_digest = hashlib.sha256()
        relative = b"payload"
        tree_digest.update(len(relative).to_bytes(4, "big"))
        tree_digest.update(relative)
        tree_digest.update(payload.stat().st_size.to_bytes(8, "big"))
        tree_digest.update(file_digest)
        fixtures.append({
            "id": identifier,
            "itemCount": count,
            "relativePath": identifier,
            "fileCount": 1,
            "payloadByteCount": payload.stat().st_size,
            "treeSHA256": tree_digest.hexdigest(),
        })
    return {"schemaVersion": 2, "fixtures": fixtures}


class BenchmarkReportTests(unittest.TestCase):
    def test_writes_versioned_report_with_per_metric_percentile_confidence_intervals(self):
        root = ROOT
        with tempfile.TemporaryDirectory() as directory:
            temp = Path(directory)
            samples = temp / "samples.jsonl"
            samples.write_text(
                "".join(
                    json.dumps(
                        {
                            "iteration": index,
                            "metrics": {
                                "startup_s1k": {
                                    "durationMS": float(index + 1),
                                    "rssMiB": float(100 + index),
                                    "cpuTimeMS": float(index + 0.5),
                                },
                                "search_m100k": {
                                    "durationMS": float((index + 1) * 2),
                                    "rssMiB": float(150 + index),
                                    "cpuTimeMS": float(index + 1),
                                },
                            },
                        }
                    )
                    + "\n"
                    for index in range(30)
                )
            )
            fixtures = temp / "fixtures.json"
            fixture_root = temp / "fixture-payloads"
            fixtures.write_text(json.dumps(make_fixture_document(fixture_root)))
            output = temp / "benchmark-report.json"
            subprocess.run(
                [
                    "python3",
                    str(root / "scripts/performance/write_benchmark_report.py"),
                    "--samples",
                    str(samples),
                    "--fixtures",
                    str(fixtures),
                    "--fixture-root",
                    str(fixture_root),
                    "--output",
                    str(output),
                    "--run-id",
                    "test",
                    "--git-sha",
                    "a" * 40,
                    "--subject-git-sha",
                    "b" * 40,
                    "--harness-sha256",
                    "c" * 64,
                    "--worktree-status",
                    "[]",
                    "--hardware",
                    '{"model":"Mac","chip":"Apple M2 Max","memoryBytes":"103079215104","physicalCPUCount":"12"}',
                    "--os",
                    '{"productVersion":"26.5","buildVersion":"25F90"}',
                    "--power-state",
                    "AC Power",
                    "--thermal-state",
                    "nominal",
                    "--warmups",
                    "5",
                    "--sample-count",
                    "30",
                    "--raw-artifact",
                    str(samples),
                    "--trace-status",
                    "missing",
                ],
                check=True,
            )
            report = json.loads(output.read_text())
            self.assertEqual(report["schemaVersion"], 3)
            self.assertEqual(report["benchmarkKind"], "micro")
            self.assertEqual(report["sampleCount"], 30)
            self.assertEqual(report["subjectGitSHA"], "b" * 40)
            self.assertEqual(report["environment"]["hardware"]["chip"], "Apple M2 Max")
            self.assertEqual(set(report["metrics"]), {"startup_s1k", "search_m100k"})
            startup = report["metrics"]["startup_s1k"]
            self.assertEqual(len(startup["rawSamples"]), 30)
            self.assertEqual(set(startup["durationMS"]["bootstrap95CI"]), {"p50", "p95", "p99"})
            self.assertEqual(len(startup["durationMS"]["bootstrap95CI"]["p95"]), 2)
            self.assertEqual(startup["durationMS"]["max"], 30.0)
            self.assertEqual(startup["cpuTimeMS"]["max"], 29.5)
            self.assertEqual(report["artifacts"]["trace"]["status"], "missing")
            self.assertEqual(
                report["artifacts"]["fixtureRoot"],
                "fixture-payloads",
            )
            self.assertEqual(report["artifacts"]["rawSamples"]["path"], "samples.jsonl")
            self.assertEqual(report["artifacts"]["fixtureManifest"]["path"], "fixtures.json")
            self.assertEqual(
                report["sourceEvidence"]["worktree"],
                {"entryCount": 0, "state": "clean"},
            )
            self.assertNotIn("worktreeStatus", report["sourceEvidence"])
            self.assertNotIn(str(temp.resolve()), output.read_text())

    def test_rejects_duplicate_or_missing_iterations(self):
        root = ROOT
        with tempfile.TemporaryDirectory() as directory:
            temp = Path(directory)
            samples = temp / "samples.jsonl"
            samples.write_text(
                "\n".join(
                    json.dumps(
                        {
                            "iteration": 0,
                            "metrics": {
                                "startup_s1k": {"durationMS": 1.0, "rssMiB": 100.0}
                            },
                        }
                    )
                    for _ in range(30)
                )
                + "\n"
            )
            fixtures = temp / "fixtures.json"
            fixtures.write_text(json.dumps({"fixtures": []}))
            fixture_root = temp / "fixtures"
            fixture_root.mkdir()
            output = temp / "report.json"
            result = subprocess.run(
                [
                    "python3",
                    str(root / "scripts/performance/write_benchmark_report.py"),
                    "--samples",
                    str(samples),
                    "--fixtures",
                    str(fixtures),
                    "--fixture-root",
                    str(fixture_root),
                    "--output",
                    str(output),
                    "--run-id",
                    "test",
                    "--git-sha",
                    "a" * 40,
                    "--subject-git-sha",
                    "a" * 40,
                    "--harness-sha256",
                    "c" * 64,
                    "--worktree-status",
                    "[]",
                    "--hardware",
                    '{"model":"Mac","chip":"Apple","memoryBytes":"1","physicalCPUCount":"1"}',
                    "--os",
                    '{"productVersion":"26","buildVersion":"test"}',
                    "--power-state",
                    "AC Power",
                    "--thermal-state",
                    "nominal",
                    "--warmups",
                    "5",
                    "--sample-count",
                    "30",
                    "--raw-artifact",
                    str(samples),
                    "--trace-status",
                    "missing",
                ],
                capture_output=True,
                text=True,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("iterations", result.stderr + result.stdout)

    def test_worktree_summary_does_not_persist_changed_filenames(self):
        baseline_path = (
            "?? Tests/ClipEaseTests/"
            "EnterprisePerformanceBenchmarkDriverTests.swift"
        )

        summary = report_writer.summarize_worktree_status([baseline_path])

        self.assertEqual(
            summary,
            {"entryCount": 1, "state": "baseline-harness-only"},
        )
        self.assertNotIn("EnterprisePerformanceBenchmarkDriverTests", json.dumps(summary))

    def test_report_artifact_must_be_inside_output_root(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            output_root = root / "output"
            output_root.mkdir()
            outside = root / "outside.json"
            outside.write_text("{}")

            with self.assertRaisesRegex(ValueError, "outside output root"):
                report_writer.relative_artifact_path(
                    outside,
                    output_root,
                    "raw samples",
                )


if __name__ == "__main__":
    unittest.main()
