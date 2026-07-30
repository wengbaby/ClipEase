#!/usr/bin/env python3
"""Enforce executable changed-line coverage for ClipEase production Swift files."""

from __future__ import annotations

import argparse
import json
import re
import subprocess
from pathlib import Path
from typing import Any


HUNK_PATTERN = re.compile(
    r"^@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@"
)


def changed_lines_from_diff(diff: str) -> dict[str, set[int]]:
    changed: dict[str, set[int]] = {}
    current_path: str | None = None
    for line in diff.splitlines():
        if line.startswith("+++ b/"):
            current_path = line[6:]
            continue
        match = HUNK_PATTERN.match(line)
        if match is None or current_path is None:
            continue
        start = int(match.group(1))
        count = int(match.group(2) or "1")
        if count <= 0:
            continue
        changed.setdefault(current_path, set()).update(
            range(start, start + count)
        )
    return changed


def executable_line_counts(
    coverage: dict[str, Any],
    repository_root: Path,
) -> dict[str, dict[int, int]]:
    result: dict[str, dict[int, int]] = {}
    for data_set in coverage.get("data", []):
        for file in data_set.get("files", []):
            filename = file.get("filename")
            if not isinstance(filename, str):
                continue
            path = Path(filename)
            if not path.is_absolute():
                path = repository_root / path
            try:
                relative = path.resolve().relative_to(repository_root.resolve())
            except ValueError:
                continue
            relative_path = relative.as_posix()
            if not relative_path.startswith("Sources/") or path.suffix != ".swift":
                continue
            line_counts = result.setdefault(relative_path, {})
            for segment in file.get("segments", []):
                if not isinstance(segment, list) or len(segment) < 6:
                    continue
                line, _, count, has_count, _, is_gap = segment[:6]
                if (
                    isinstance(line, int)
                    and line > 0
                    and has_count is True
                    and is_gap is False
                    and isinstance(count, (int, float))
                ):
                    line_counts[line] = max(line_counts.get(line, 0), int(count))
    return result


def build_report(
    changed_lines: dict[str, set[int]],
    coverage_lines: dict[str, dict[int, int]],
    minimum_percent: float,
) -> dict[str, Any]:
    files: dict[str, Any] = {}
    executable_total = 0
    covered_total = 0
    for path in sorted(changed_lines):
        if not path.startswith("Sources/") or not path.endswith(".swift"):
            continue
        executable = sorted(
            changed_lines[path] & set(coverage_lines.get(path, {}))
        )
        covered = [
            line
            for line in executable
            if coverage_lines[path][line] > 0
        ]
        executable_total += len(executable)
        covered_total += len(covered)
        if executable:
            files[path] = {
                "changedExecutableLineCount": len(executable),
                "coveredChangedExecutableLineCount": len(covered),
                "uncoveredLines": sorted(set(executable) - set(covered)),
            }
    percentage = (
        covered_total / executable_total * 100
        if executable_total > 0
        else 0.0
    )
    return {
        "schemaVersion": 1,
        "minimumPercent": minimum_percent,
        "changedExecutableLineCount": executable_total,
        "coveredChangedExecutableLineCount": covered_total,
        "changedCodeCoveragePercent": percentage,
        "decision": (
            "pass"
            if executable_total > 0 and percentage >= minimum_percent
            else "fail"
        ),
        "files": files,
    }


def git_diff(repository_root: Path, base_ref: str) -> str:
    result = subprocess.run(
        [
            "/usr/bin/git",
            "-C",
            str(repository_root),
            "diff",
            "--unified=0",
            "--no-color",
            base_ref,
            "--",
            "Sources",
        ],
        capture_output=True,
        text=True,
        timeout=60,
    )
    if result.returncode != 0:
        raise SystemExit(result.stderr.strip() or "git diff failed")
    untracked = subprocess.run(
        [
            "/usr/bin/git",
            "-C",
            str(repository_root),
            "ls-files",
            "--others",
            "--exclude-standard",
            "-z",
            "--",
            "Sources",
        ],
        capture_output=True,
        timeout=60,
    )
    if untracked.returncode != 0:
        raise SystemExit(
            untracked.stderr.decode(errors="replace").strip()
            or "git untracked source discovery failed"
        )

    synthetic_diffs: list[str] = []
    for encoded_path in untracked.stdout.split(b"\0"):
        if not encoded_path:
            continue
        relative_path = encoded_path.decode(errors="surrogateescape")
        if not relative_path.endswith(".swift") or "\n" in relative_path:
            continue
        source_path = repository_root / relative_path
        line_count = len(source_path.read_bytes().splitlines())
        if line_count == 0:
            continue
        synthetic_diffs.append(
            "\n".join([
                f"diff --git a/{relative_path} b/{relative_path}",
                "new file mode 100644",
                "--- /dev/null",
                f"+++ b/{relative_path}",
                f"@@ -0,0 +1,{line_count} @@",
            ])
        )

    return "\n".join([result.stdout, *synthetic_diffs])


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repository-root", required=True, type=Path)
    parser.add_argument("--coverage-json", required=True, type=Path)
    parser.add_argument("--base-ref", default="ad4013c")
    parser.add_argument("--minimum-percent", type=float, default=80.0)
    parser.add_argument("--output", required=True, type=Path)
    return parser.parse_args()


def main() -> None:
    args = parse_arguments()
    if not 0 < args.minimum_percent <= 100:
        raise SystemExit("--minimum-percent must be in (0, 100]")
    repository_root = args.repository_root.resolve()
    if not (repository_root / ".git").exists():
        raise SystemExit("repository root is not a Git worktree")
    coverage = json.loads(args.coverage_json.read_text())
    report = build_report(
        changed_lines_from_diff(git_diff(repository_root, args.base_ref)),
        executable_line_counts(coverage, repository_root),
        args.minimum_percent,
    )
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    if report["decision"] != "pass":
        raise SystemExit(2)


if __name__ == "__main__":
    main()
