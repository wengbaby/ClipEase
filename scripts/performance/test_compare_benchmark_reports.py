import json
import importlib.util
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "compare_benchmark_reports",
    ROOT / "scripts/performance/compare_benchmark_reports.py",
)
compare_benchmark_reports = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(compare_benchmark_reports)


def metric(p50, p95, p99, rss_p50, ci_p95, raw=None):
    if raw is None:
        raw = [
            {
                "iteration": index,
                "durationMS": p50,
                "rssMiB": rss_p50,
                "cpuTimeMS": p50,
            }
            for index in range(30)
        ]
    return {
        "durationMS": {
            "p50": p50,
            "p95": p95,
            "p99": p99,
            "max": p99,
            "bootstrap95CI": {
                "p50": [p50, p50],
                "p95": ci_p95,
                "p99": [p99, p99],
            },
        },
        "rssMiB": {
            "p50": rss_p50,
            "p95": rss_p50,
            "p99": rss_p50,
            "max": rss_p50,
            "bootstrap95CI": {
                "p50": [rss_p50, rss_p50],
                "p95": [rss_p50, rss_p50],
                "p99": [rss_p50, rss_p50],
            },
        },
        "cpuTimeMS": {
            "p50": p50,
            "p95": p95,
            "p99": p99,
            "max": p99,
            "bootstrap95CI": {
                "p50": [p50, p50],
                "p95": ci_p95,
                "p99": [p99, p99],
            },
        },
        "rawSamples": raw,
    }


class BenchmarkComparisonTests(unittest.TestCase):
    def run_comparison(
        self,
        baseline_metric,
        candidate_metric,
        *,
        candidate_environment=None,
        trace_status="available",
        extra_arguments=None,
    ):
        root = Path(__file__).resolve().parents[2]
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        directory = Path(temporary.name)
        baseline = directory / "baseline.json"
        candidate = directory / "candidate.json"
        output = directory / "comparison.json"
        environment = {
            "hardware": {
                "model": "Mac14,6",
                "chip": "Apple M2 Max",
                "memoryBytes": "103079215104",
                "physicalCPUCount": "12",
            },
            "os": {"productVersion": "26.5", "buildVersion": "25F90"},
            "powerState": "AC Power",
            "thermalState": "nominal",
        }
        fixtures = [{"id": "S1K", "treeSHA256": "a" * 64}]
        baseline.write_text(json.dumps({
            "schemaVersion": 3,
            "benchmarkKind": "micro",
            "gitSHA": "a" * 40,
            "subjectGitSHA": compare_benchmark_reports.LOCKED_BASELINE_SUBJECT_GIT_SHA,
            "environment": environment,
            "fixtures": fixtures,
            "artifacts": {"trace": {"status": trace_status}},
            "metrics": {"capture": baseline_metric},
        }))
        candidate.write_text(json.dumps({
            "schemaVersion": 3,
            "benchmarkKind": "micro",
            "gitSHA": "c" * 40,
            "subjectGitSHA": "d" * 40,
            "environment": candidate_environment or environment,
            "fixtures": fixtures,
            "artifacts": {"trace": {"status": "available"}},
            "metrics": {"capture": candidate_metric},
        }))
        arguments = [
            "python3",
            str(root / "scripts/performance/compare_benchmark_reports.py"),
            "--baseline",
            str(baseline),
            "--candidate",
            str(candidate),
            "--output",
            str(output),
        ]
        if extra_arguments:
            arguments.extend(extra_arguments)
        result = subprocess.run(
            arguments,
            capture_output=True,
            text=True,
        )
        return result, json.loads(output.read_text())

    def test_warns_for_daily_m2_regression_without_rebasing(self):
        baseline_raw = [
            {
                "iteration": index,
                "durationMS": 100.0 if index < 20 else 200.0,
                "rssMiB": 100,
                "cpuTimeMS": 50.0,
            }
            for index in range(30)
        ]
        candidate_raw = [
            {
                "iteration": index,
                "durationMS": 204.0 if index < 10 else 106.0,
                "rssMiB": 104,
                "cpuTimeMS": 50.0,
            }
            for index in range(30)
        ]
        result, report = self.run_comparison(
            metric(100, 200, 200, 100, [100, 200], baseline_raw),
            metric(106, 204, 204, 104, [106, 204], candidate_raw),
        )
        self.assertEqual(result.returncode, 0)
        self.assertEqual(report["decision"], "warning")
        self.assertFalse(report["baselineAccepted"])
        self.assertEqual(
            report["evidence"]["baselineSubjectGitSHA"],
            compare_benchmark_reports.LOCKED_BASELINE_SUBJECT_GIT_SHA,
        )
        self.assertEqual(len(report["evidence"]["candidateReportSHA256"]), 64)

    def test_fails_for_median_or_p95_stop_threshold(self):
        result, report = self.run_comparison(
            metric(100, 100, 100, 100, [99, 101]),
            metric(111, 116, 116, 104, [114, 117]),
        )
        self.assertEqual(result.returncode, 2)
        self.assertEqual(report["decision"], "fail")
        self.assertFalse(report["baselineAccepted"])

    def test_fails_for_p99_or_max_tail_regression(self):
        baseline_raw = [
            {
                "iteration": index,
                "durationMS": 100.0,
                "rssMiB": 100,
                "cpuTimeMS": 50.0,
            }
            for index in range(30)
        ]
        candidate_raw = [dict(sample) for sample in baseline_raw]
        candidate_raw[-1]["durationMS"] = 1_000.0
        result, report = self.run_comparison(
            metric(100, 100, 100, 100, [100, 100], baseline_raw),
            metric(100, 100, 739, 100, [100, 739], candidate_raw),
        )
        self.assertEqual(result.returncode, 2)
        reasons = " ".join(report["metrics"]["capture"]["reasons"])
        self.assertTrue("p99 regression" in reasons or "max latency" in reasons)

    def test_fails_when_bootstrap_interval_proves_over_five_percent_regression(self):
        baseline_raw = [
            {"iteration": index, "durationMS": float(100 + index * 10), "rssMiB": 100, "cpuTimeMS": 50}
            for index in range(30)
        ]
        candidate_raw = [
            {
                "iteration": sample["iteration"],
                "durationMS": sample["durationMS"] * 1.06,
                "rssMiB": 104,
                "cpuTimeMS": 53,
            }
            for sample in baseline_raw
        ]
        result, report = self.run_comparison(
            metric(100, 100, 100, 100, [50, 500], baseline_raw),
            metric(106, 106, 106, 104, [50, 500], candidate_raw),
        )
        self.assertEqual(result.returncode, 2)
        self.assertIn("bootstrap", " ".join(report["metrics"]["capture"]["reasons"]))

    def test_fails_rss_only_when_both_relative_and_absolute_thresholds_are_exceeded(self):
        result, report = self.run_comparison(
            metric(100, 100, 100, 200, [99, 101]),
            metric(100, 100, 100, 211, [99, 101]),
        )
        self.assertEqual(result.returncode, 2)
        self.assertIn("rss", " ".join(report["metrics"]["capture"]["reasons"]).lower())

    def test_fails_closed_when_environment_does_not_match(self):
        mismatched = {
            "hardware": {
                "model": "Mac15,1",
                "chip": "Apple M3",
                "memoryBytes": "17179869184",
                "physicalCPUCount": "8",
            },
            "os": {"productVersion": "26.5", "buildVersion": "25F90"},
            "powerState": "AC Power",
            "thermalState": "nominal",
        }
        result, report = self.run_comparison(
            metric(100, 100, 100, 100, [99, 101]),
            metric(100, 100, 100, 100, [99, 101]),
            candidate_environment=mismatched,
        )
        self.assertEqual(result.returncode, 2)
        self.assertIn("environmentMismatch", report["contractErrors"])

    def test_daily_profile_rejects_non_m2_max_hardware(self):
        m2_pro = {
            "hardware": {
                "model": "Mac14,9",
                "chip": "Apple M2 Pro",
                "memoryBytes": "34359738368",
                "physicalCPUCount": "10",
            },
            "os": {"productVersion": "26.5", "buildVersion": "25F90"},
            "powerState": "AC Power",
            "thermalState": "nominal",
        }
        result, report = self.run_comparison(
            metric(100, 100, 100, 100, [99, 101]),
            metric(100, 100, 100, 100, [99, 101]),
            candidate_environment=m2_pro,
        )
        self.assertEqual(result.returncode, 2)
        self.assertIn("invalidDailyHardware", report["contractErrors"])

    def test_duplicate_raw_iteration_is_rejected_before_pairing(self):
        raw = [
            {
                "iteration": min(index, 28),
                "durationMS": 100.0,
                "rssMiB": 100,
                "cpuTimeMS": 50.0,
            }
            for index in range(30)
        ]
        result, report = self.run_comparison(
            metric(100, 100, 100, 100, [99, 101], raw),
            metric(100, 100, 100, 100, [99, 101], raw),
        )
        self.assertEqual(result.returncode, 2)
        self.assertIn("invalidPairedSamples", report["contractErrors"])

    def test_rejects_any_baseline_other_than_locked_ad4013c(self):
        result, report = self.run_comparison(
            metric(100, 100, 100, 100, [99, 101]),
            metric(100, 100, 100, 100, [99, 101]),
        )
        self.assertEqual(result.returncode, 0)
        self.assertNotIn("unlockedBaseline", report["contractErrors"])

        # Prove the contract function itself does not accept a self-consistent,
        # slower replacement baseline.
        baseline = {
            "gitSHA": "e" * 40,
            "subjectGitSHA": "e" * 40,
            "environment": {},
            "fixtures": [],
        }
        candidate = {
            "gitSHA": "f" * 40,
            "subjectGitSHA": "f" * 40,
            "environment": {},
            "fixtures": [],
        }
        errors = compare_benchmark_reports.contract_errors(
            baseline,
            candidate,
            profile="daily-relative",
            require_trace=False,
        )
        self.assertIn("unlockedBaseline", errors)

    def test_release_micro_comparison_does_not_claim_runtime_absolute_metrics(self):
        result, report = self.run_comparison(
            metric(100, 100, 100, 100, [99, 101]),
            metric(100, 100, 100, 100, [99, 101]),
            extra_arguments=["--profile", "m1-8gb-release", "--require-trace"],
        )
        self.assertEqual(result.returncode, 2)
        self.assertNotIn("missingAbsoluteMetrics", report["contractErrors"])
        self.assertNotIn("absoluteThresholdFailures", report["contractErrors"])
        self.assertIn("invalidCertificationHardware", report["contractErrors"])

    def test_comparison_rejects_non_micro_benchmark_reports(self):
        baseline = {
            "benchmarkKind": "release-runtime",
            "subjectGitSHA": compare_benchmark_reports.LOCKED_BASELINE_SUBJECT_GIT_SHA,
            "environment": {},
            "fixtures": [],
        }
        candidate = {
            "benchmarkKind": "release-runtime",
            "subjectGitSHA": "f" * 40,
            "environment": {},
            "fixtures": [],
        }

        errors = compare_benchmark_reports.contract_errors(
            baseline,
            candidate,
            profile="daily-relative",
            require_trace=False,
        )

        self.assertIn("invalidBenchmarkKind", errors)

    def test_release_profile_requires_trace_even_without_optional_flag(self):
        result, report = self.run_comparison(
            metric(100, 100, 100, 100, [99, 101]),
            metric(100, 100, 100, 100, [99, 101]),
            trace_status="not-collected",
            extra_arguments=["--profile", "m1-8gb-release"],
        )
        self.assertEqual(result.returncode, 2)
        self.assertIn("missingTrace", report["contractErrors"])

    def test_release_upsert_gate_checks_both_p95_and_p99(self):
        candidate_metrics = {}
        for name, thresholds in (
            compare_benchmark_reports.M1_RELEASE_DURATION_THRESHOLDS_MS.items()
        ):
            maximum = max(value for _, value in thresholds)
            candidate_metrics[name] = {
                "durationMS": {
                    "p50": maximum / 2,
                    "p95": maximum / 2,
                    "p99": maximum / 2,
                    "max": maximum / 2,
                }
            }
        candidate_metrics["upsert_t10k"]["durationMS"]["p95"] = 9.0
        candidate_metrics["upsert_t10k"]["durationMS"]["p99"] = 26.0

        failures = compare_benchmark_reports.absolute_metric_failures(
            candidate_metrics,
            "m1-8gb-release",
        )

        self.assertEqual(
            failures["upsert_t10k"]["p99"]["thresholdMS"],
            25.0,
        )


if __name__ == "__main__":
    unittest.main()
