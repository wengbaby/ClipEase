#!/usr/bin/env python3
"""Run the locked ClipEase Release fault-injection suite and bind its logs."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Callable


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
CommandRunner = Callable[..., Any]


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def test_command(test_name: str) -> list[str]:
    return [
        "swift",
        "test",
        "-c",
        "release",
        "--skip-build",
        "--filter",
        test_name,
    ]


def test_log_passed(test_name: str, text: str) -> bool:
    return (
        re.search(
            rf"Test\s+{re.escape(test_name)}\(\)\s+passed\b",
            text,
        )
        is not None
        and re.search(
            r"Test run with 1 test(?: in \d+ suites?)? passed\b",
            text,
        )
        is not None
        and re.search(
            r"(?:✘\s+Test .*\bfailed\b|Test run with .* tests?.*\bfailed\b)",
            text,
            re.IGNORECASE,
        )
        is None
    )


def inspect_source(
    source_root: Path,
    subject_git_sha: str,
    command_runner: CommandRunner,
) -> list[str]:
    head = command_runner(
        ["/usr/bin/git", "-C", str(source_root), "rev-parse", "HEAD"],
        capture_output=True,
        text=True,
        timeout=30,
    )
    if head.returncode != 0 or head.stdout.strip().lower() != subject_git_sha:
        raise RuntimeError("fault injection source subject does not match")
    status = command_runner(
        [
            "/usr/bin/git",
            "-C",
            str(source_root),
            "status",
            "--porcelain",
            "--untracked-files=all",
        ],
        capture_output=True,
        text=True,
        timeout=30,
    )
    if status.returncode != 0:
        raise RuntimeError("could not inspect fault injection source worktree")
    values = [line for line in status.stdout.splitlines() if line]
    if values:
        raise RuntimeError("fault injection requires a clean source worktree")
    return values


def run_suite(
    *,
    source_root: Path,
    output_path: Path,
    subject_git_sha: str,
    command_runner: CommandRunner = subprocess.run,
) -> str:
    source_root = source_root.resolve()
    output_path = output_path.resolve()
    subject_git_sha = subject_git_sha.lower()
    if not source_root.is_dir():
        raise RuntimeError("fault injection source root does not exist")
    if re.fullmatch(r"[0-9a-f]{40,64}", subject_git_sha) is None:
        raise RuntimeError("fault injection subject must be a full Git object ID")
    if output_path.exists():
        raise RuntimeError(f"fault injection report already exists: {output_path}")
    source_status = inspect_source(
        source_root,
        subject_git_sha,
        command_runner,
    )

    log_root = output_path.parent / f"{output_path.name}.logs"
    log_root.mkdir(parents=True, exist_ok=False)
    scenarios: dict[str, Any] = {}
    decision = "pass"
    for scenario, test_name in REQUIRED_FAULT_TESTS.items():
        command = test_command(test_name)
        try:
            result = command_runner(
                command,
                cwd=source_root,
                capture_output=True,
                text=True,
                timeout=300,
            )
            exit_code = int(result.returncode)
            log_text = result.stdout + result.stderr
        except (FileNotFoundError, subprocess.TimeoutExpired) as error:
            exit_code = -1
            log_text = f"fault injection command could not complete: {error}\n"
        passed = exit_code == 0 and test_log_passed(test_name, log_text)
        if not passed:
            decision = "fail"
        log_path = log_root / f"{scenario}.log"
        log_path.write_text(log_text)
        scenarios[scenario] = {
            "testName": test_name,
            "command": command,
            "exitCode": exit_code,
            "status": "pass" if passed else "fail",
            "log": {
                "path": log_path.relative_to(output_path.parent).as_posix(),
                "sha256": file_sha256(log_path),
            },
        }

    inspect_source(source_root, subject_git_sha, command_runner)
    report = {
        "schemaVersion": 1,
        "capturedAt": datetime.now(timezone.utc).isoformat(),
        "subjectGitSHA": subject_git_sha,
        "sourceWorktreeStatus": source_status,
        "decision": decision,
        "scenarios": scenarios,
    }
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    return decision


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-root", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--subject-git-sha", required=True)
    return parser.parse_args()


def main() -> None:
    args = parse_arguments()
    decision = run_suite(
        source_root=args.source_root,
        output_path=args.output,
        subject_git_sha=args.subject_git_sha,
    )
    if decision != "pass":
        raise SystemExit(2)


if __name__ == "__main__":
    main()
