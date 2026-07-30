#!/usr/bin/env python3
"""Compare paired ClipEase benchmark reports without accepting a slower baseline."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import random
import re
from pathlib import Path
from typing import Any


REPORT_SCHEMA_VERSION = 3
LOCKED_BASELINE_SUBJECT_GIT_SHA = "ad4013cce2a4e0a1648de2277126c736c0700b39"
BOOTSTRAP_ROUNDS = 2_000
M1_RELEASE_DURATION_THRESHOLDS_MS = {
    "listeners_ready": (("p95", 500.0),),
    "cold_start": (("p95", 1_500.0),),
    "first_window_usable": (("p95", 350.0),),
    "repeat_window_usable": (("p95", 180.0),),
    "capture_text": (("p95", 300.0),),
    "capture_payload_placeholder": (("p95", 300.0),),
    "search_t10k_key_to_visible": (("p95", 300.0),),
    "fts_hot_m100k": (("p95", 150.0),),
    "fts_cold_m100k": (("p95", 300.0),),
    "page_1k_m100k": (("p95", 150.0),),
    "upsert_t10k": (("p95", 10.0), ("p99", 25.0)),
    "exit_drain": (("p95", 300.0),),
    "thumbnail_cold": (("p95", 150.0),),
    "thumbnail_hot": (("p95", 16.67),),
}


def percentile(values: list[float], fraction: float) -> float:
    if not values:
        raise ValueError("cannot calculate a percentile for an empty sample")
    ordered = sorted(values)
    position = (len(ordered) - 1) * fraction
    lower = math.floor(position)
    upper = math.ceil(position)
    return ordered[lower] + (ordered[upper] - ordered[lower]) * (position - lower)


def percent_change(baseline: float, candidate: float) -> float:
    if baseline == 0:
        return 0.0 if candidate == 0 else float("inf")
    return ((candidate - baseline) / baseline) * 100


def maximum_decision(lhs: str, rhs: str) -> str:
    severity = {"pass": 0, "warning": 1, "fail": 2}
    return lhs if severity[lhs] >= severity[rhs] else rhs


def paired_samples(
    baseline: dict[str, Any],
    candidate: dict[str, Any],
    field: str,
) -> tuple[list[float], list[float]]:
    baseline_rows = baseline.get("rawSamples", [])
    candidate_rows = candidate.get("rawSamples", [])
    if len(baseline_rows) != 30:
        raise ValueError(f"baseline {field} must contain exactly 30 raw samples")
    if len(candidate_rows) != 30:
        raise ValueError(f"candidate {field} must contain exactly 30 raw samples")
    baseline_by_iteration = {
        int(sample["iteration"]): float(sample[field])
        for sample in baseline_rows
    }
    candidate_by_iteration = {
        int(sample["iteration"]): float(sample[field])
        for sample in candidate_rows
    }
    if len(baseline_by_iteration) != len(baseline_rows):
        raise ValueError(f"baseline {field} contains duplicate iterations")
    if len(candidate_by_iteration) != len(candidate_rows):
        raise ValueError(f"candidate {field} contains duplicate iterations")
    if set(baseline_by_iteration) != set(range(30)):
        raise ValueError(f"baseline {field} samples must contain iterations 0...29")
    if set(candidate_by_iteration) != set(range(30)):
        raise ValueError(f"candidate {field} samples must contain iterations 0...29")
    return (
        [baseline_by_iteration[index] for index in range(30)],
        [candidate_by_iteration[index] for index in range(30)],
    )


def paired_bootstrap_regression_ci(
    baseline_values: list[float],
    candidate_values: list[float],
    fraction: float,
    rounds: int = BOOTSTRAP_ROUNDS,
) -> list[float]:
    if len(baseline_values) != len(candidate_values) or not baseline_values:
        raise ValueError("paired bootstrap requires equal non-empty samples")
    if (
        len(set(baseline_values)) == 1
        and len(set(candidate_values)) == 1
    ):
        regression = percent_change(baseline_values[0], candidate_values[0])
        return [regression, regression]
    randomizer = random.Random(73_000 + int(fraction * 10_000) + len(baseline_values))
    estimates: list[float] = []
    indexes = list(range(len(baseline_values)))
    for _ in range(rounds):
        sample_indexes = [randomizer.choice(indexes) for _ in indexes]
        baseline_percentile = percentile(
            [baseline_values[index] for index in sample_indexes],
            fraction,
        )
        candidate_percentile = percentile(
            [candidate_values[index] for index in sample_indexes],
            fraction,
        )
        estimates.append(percent_change(baseline_percentile, candidate_percentile))
    return [percentile(estimates, 0.025), percentile(estimates, 0.975)]


def compare_metric(
    baseline: dict[str, Any],
    candidate: dict[str, Any],
) -> dict[str, Any]:
    baseline_duration = baseline["durationMS"]
    candidate_duration = candidate["durationMS"]
    p50_regression = percent_change(
        float(baseline_duration["p50"]),
        float(candidate_duration["p50"]),
    )
    p95_regression = percent_change(
        float(baseline_duration["p95"]),
        float(candidate_duration["p95"]),
    )
    p99_regression = percent_change(
        float(baseline_duration["p99"]),
        float(candidate_duration["p99"]),
    )
    max_regression = percent_change(
        float(baseline_duration["max"]),
        float(candidate_duration["max"]),
    )
    rss_baseline = float(baseline["rssMiB"]["p50"])
    rss_candidate = float(candidate["rssMiB"]["p50"])
    rss_percent = percent_change(rss_baseline, rss_candidate)
    rss_absolute = rss_candidate - rss_baseline

    decision = "pass"
    reasons: list[str] = []
    if p50_regression > 10:
        decision = "fail"
        reasons.append(f"p50 regression {p50_regression:.2f}% exceeds 10% stop threshold")
    elif p50_regression > 5:
        decision = maximum_decision(decision, "warning")
        reasons.append(f"p50 regression {p50_regression:.2f}% exceeds 5% warning threshold")

    if p95_regression > 15:
        decision = "fail"
        reasons.append(f"p95 regression {p95_regression:.2f}% exceeds 15% stop threshold")
    elif p95_regression > 10:
        decision = maximum_decision(decision, "warning")
        reasons.append(f"p95 regression {p95_regression:.2f}% exceeds 10% warning threshold")

    if p99_regression > 15:
        decision = "fail"
        reasons.append(f"p99 regression {p99_regression:.2f}% exceeds 15% stop threshold")
    elif p99_regression > 10:
        decision = maximum_decision(decision, "warning")
        reasons.append(f"p99 regression {p99_regression:.2f}% exceeds 10% warning threshold")

    max_absolute_regression = (
        float(candidate_duration["max"]) - float(baseline_duration["max"])
    )
    if max_regression > 25 and max_absolute_regression > 5:
        decision = "fail"
        reasons.append(
            "max latency regressed by both "
            f"{max_regression:.2f}% and {max_absolute_regression:.2f} ms"
        )

    baseline_samples, candidate_samples = paired_samples(
        baseline,
        candidate,
        "durationMS",
    )
    paired_duration_ci = {
        "p50": paired_bootstrap_regression_ci(
            baseline_samples,
            candidate_samples,
            0.50,
        ),
        "p95": paired_bootstrap_regression_ci(
            baseline_samples,
            candidate_samples,
            0.95,
        ),
        "p99": paired_bootstrap_regression_ci(
            baseline_samples,
            candidate_samples,
            0.99,
        ),
    }
    if any(interval[0] > 5 for interval in paired_duration_ci.values()):
        decision = "fail"
        reasons.append(
            "paired bootstrap proves more than 5% latency regression "
            f"(p50={paired_duration_ci['p50']}, p95={paired_duration_ci['p95']})"
        )

    baseline_cpu, candidate_cpu = paired_samples(
        baseline,
        candidate,
        "cpuTimeMS",
    )
    paired_cpu_ci = {
        "p50": paired_bootstrap_regression_ci(baseline_cpu, candidate_cpu, 0.50),
        "p95": paired_bootstrap_regression_ci(baseline_cpu, candidate_cpu, 0.95),
        "p99": paired_bootstrap_regression_ci(baseline_cpu, candidate_cpu, 0.99),
    }
    if any(interval[0] > 5 for interval in paired_cpu_ci.values()):
        decision = "fail"
        reasons.append(
            "paired bootstrap proves more than 5% CPU regression "
            f"(p50={paired_cpu_ci['p50']}, p95={paired_cpu_ci['p95']})"
        )

    if rss_percent > 5 and rss_absolute > 10:
        decision = "fail"
        reasons.append(
            "RSS p50 increased by both "
            f"{rss_percent:.2f}% and {rss_absolute:.2f} MiB"
        )

    return {
        "decision": decision,
        "p50RegressionPercent": p50_regression,
        "p95RegressionPercent": p95_regression,
        "p99RegressionPercent": p99_regression,
        "maxRegressionPercent": max_regression,
        "pairedLatencyRegressionBootstrap95CI": paired_duration_ci,
        "pairedCPURegressionBootstrap95CI": paired_cpu_ci,
        "rssRegressionPercent": rss_percent,
        "rssRegressionMiB": rss_absolute,
        "reasons": reasons,
    }


def fixture_hashes(report: dict[str, Any]) -> dict[str, str]:
    return {
        str(fixture.get("id")): str(fixture.get("treeSHA256"))
        for fixture in report.get("fixtures", [])
    }


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def contract_errors(
    baseline: dict[str, Any],
    candidate: dict[str, Any],
    *,
    profile: str,
    require_trace: bool,
) -> dict[str, Any]:
    errors: dict[str, Any] = {}
    if (
        baseline.get("benchmarkKind") != "micro"
        or candidate.get("benchmarkKind") != "micro"
    ):
        errors["invalidBenchmarkKind"] = {
            "expected": "micro",
            "baseline": baseline.get("benchmarkKind"),
            "candidate": candidate.get("benchmarkKind"),
        }
    for name, report in (("baseline", baseline), ("candidate", candidate)):
        git_sha = report.get("gitSHA")
        subject_git_sha = report.get("subjectGitSHA")
        if not isinstance(git_sha, str) or re.fullmatch(r"[0-9a-fA-F]{40,64}", git_sha) is None:
            errors[f"{name}GitSHA"] = git_sha
        if (
            not isinstance(subject_git_sha, str)
            or re.fullmatch(r"[0-9a-fA-F]{40,64}", subject_git_sha) is None
        ):
            errors[f"{name}SubjectGitSHA"] = subject_git_sha
    if baseline.get("subjectGitSHA") != LOCKED_BASELINE_SUBJECT_GIT_SHA:
        errors["unlockedBaseline"] = {
            "expected": LOCKED_BASELINE_SUBJECT_GIT_SHA,
            "actual": baseline.get("subjectGitSHA"),
        }
    if baseline.get("environment") != candidate.get("environment"):
        errors["environmentMismatch"] = {
            "baseline": baseline.get("environment"),
            "candidate": candidate.get("environment"),
        }
    if fixture_hashes(baseline) != fixture_hashes(candidate):
        errors["fixtureMismatch"] = {
            "baseline": fixture_hashes(baseline),
            "candidate": fixture_hashes(candidate),
        }
    if require_trace or profile == "m1-8gb-release":
        missing_trace = [
            name
            for name, report in (("baseline", baseline), ("candidate", candidate))
            if report.get("artifacts", {}).get("trace", {}).get("status") != "available"
        ]
        if missing_trace:
            errors["missingTrace"] = missing_trace
    hardware = candidate.get("environment", {}).get("hardware", {})
    if profile == "daily-relative" and hardware.get("chip") != "Apple M2 Max":
        errors["invalidDailyHardware"] = hardware
    if profile == "m1-8gb-release":
        chip = str(hardware.get("chip", ""))
        try:
            memory_bytes = int(hardware.get("memoryBytes", 0))
        except (TypeError, ValueError):
            memory_bytes = 0
        if chip != "Apple M1" or memory_bytes != 8 * 1_024**3:
            errors["invalidCertificationHardware"] = hardware
    return errors


def absolute_metric_failures(
    candidate_metrics: dict[str, Any],
    profile: str,
) -> dict[str, Any]:
    if profile != "m1-8gb-release":
        return {}
    failures: dict[str, Any] = {}
    for name, thresholds in M1_RELEASE_DURATION_THRESHOLDS_MS.items():
        metric = candidate_metrics.get(name)
        if metric is None:
            continue
        for statistic, threshold in thresholds:
            actual = float(metric["durationMS"][statistic])
            if actual > threshold:
                failures.setdefault(name, {})[statistic] = {
                    "actualMS": actual,
                    "thresholdMS": threshold,
                }
    return failures


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--baseline", required=True, type=Path)
    parser.add_argument("--candidate", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument(
        "--profile",
        choices=("daily-relative", "m1-8gb-release"),
        default="daily-relative",
    )
    parser.add_argument("--require-trace", action="store_true")
    return parser.parse_args()


def build_comparison(
    baseline: dict[str, Any],
    candidate: dict[str, Any],
    *,
    baseline_path: Path,
    candidate_path: Path,
    profile: str,
    require_trace: bool,
) -> dict[str, Any]:
    errors: dict[str, Any] = {}
    if (
        baseline.get("schemaVersion") != REPORT_SCHEMA_VERSION
        or candidate.get("schemaVersion") != REPORT_SCHEMA_VERSION
    ):
        errors["schemaVersion"] = {
            "expected": REPORT_SCHEMA_VERSION,
            "baseline": baseline.get("schemaVersion"),
            "candidate": candidate.get("schemaVersion"),
        }
    else:
        errors.update(
            contract_errors(
                baseline,
                candidate,
                profile=profile,
                require_trace=require_trace,
            )
        )

    baseline_metrics = baseline.get("metrics", {})
    candidate_metrics = candidate.get("metrics", {})
    if set(baseline_metrics) != set(candidate_metrics):
        errors["missingCandidateMetrics"] = sorted(
            set(baseline_metrics) - set(candidate_metrics)
        )
        errors["extraCandidateMetrics"] = sorted(
            set(candidate_metrics) - set(baseline_metrics)
        )

    metric_results: dict[str, Any] = {}
    if not errors:
        try:
            metric_results = {
                name: compare_metric(baseline_metrics[name], candidate_metrics[name])
                for name in sorted(baseline_metrics)
            }
        except (KeyError, TypeError, ValueError) as error:
            errors["invalidPairedSamples"] = str(error)

    decision = "fail" if errors else "pass"
    if not errors:
        for result in metric_results.values():
            decision = maximum_decision(decision, result["decision"])

    return {
        "schemaVersion": 2,
        "profile": profile,
        "decision": decision,
        "baselineAccepted": False,
        "metrics": metric_results,
        "contractErrors": errors,
        "evidence": {
            "baselineReportSHA256": file_sha256(baseline_path),
            "candidateReportSHA256": file_sha256(candidate_path),
            "baselineSubjectGitSHA": baseline.get("subjectGitSHA"),
            "candidateSubjectGitSHA": candidate.get("subjectGitSHA"),
        },
    }


def main() -> None:
    args = parse_arguments()
    baseline = json.loads(args.baseline.read_text())
    candidate = json.loads(args.candidate.read_text())
    comparison = build_comparison(
        baseline,
        candidate,
        baseline_path=args.baseline,
        candidate_path=args.candidate,
        profile=args.profile,
        require_trace=args.require_trace,
    )
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(comparison, indent=2, sort_keys=True) + "\n")
    if comparison["decision"] == "fail":
        raise SystemExit(2)


if __name__ == "__main__":
    main()
