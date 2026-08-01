#!/usr/bin/env python3
"""Convert Swift Testing console events into a fail-closed xUnit report."""

from __future__ import annotations

import argparse
import os
import re
import tempfile
import xml.etree.ElementTree as ElementTree
from pathlib import Path


EVENT_PATTERN = re.compile(
    r"^(?P<marker>[◇✔✘]) Test (?P<name>.+?)\(\) "
    r"(?P<event>started|passed|failed)(?: after (?P<duration>[0-9]+(?:\.[0-9]+)?) seconds)?\.$"
)
SUMMARY_PATTERN = re.compile(
    r"^[✔✘] Test run with (?P<count>[0-9]+) tests? in .+ "
    r"(?P<result>passed|failed) after [0-9]+(?:\.[0-9]+)? seconds\.$"
)
PARAMETERIZED_PATTERN = re.compile(
    r"^[✔✘] Test (?P<name>.+?) with (?P<count>[0-9]+) test cases "
    r"(?P<result>passed|failed) after [0-9]+(?:\.[0-9]+)? seconds\.$"
)
SUBJECT_PATTERN = re.compile(r"[0-9a-fA-F]{40,64}")


class TestCase:
    __slots__ = ("name", "status", "duration_seconds")

    def __init__(self, name: str, status: str, duration_seconds: float) -> None:
        self.name = name
        self.status = status
        self.duration_seconds = duration_seconds


def _validate_identity(subject_git_sha: str, command: str) -> None:
    if SUBJECT_PATTERN.fullmatch(subject_git_sha) is None:
        raise ValueError("subject Git SHA must be a full hexadecimal object ID")
    if not command.strip():
        raise ValueError("test command must not be empty")


def parse_swift_testing_log(text: str) -> list[TestCase]:
    pending: dict[str, int] = {}
    cases: list[TestCase] = []
    summary_count: int | None = None
    summary_result: str | None = None

    for raw_line in text.splitlines():
        line = raw_line.strip()
        parameterized = PARAMETERIZED_PATTERN.match(line)
        if parameterized is not None:
            if int(parameterized.group("count")) <= 0:
                raise ValueError("parameterized Swift Testing group has no cases")
            cases.append(
                TestCase(
                    name=parameterized.group("name"),
                    status=parameterized.group("result"),
                    duration_seconds=0.0,
                )
            )
            continue
        event = EVENT_PATTERN.match(line)
        if event is not None:
            name = event.group("name")
            event_name = event.group("event")
            if event_name == "started":
                if name in pending:
                    raise ValueError(f"duplicate Swift Testing start event: {name}")
                pending[name] = len(cases)
                continue
            if name not in pending:
                raise ValueError(f"Swift Testing completion has no start: {name}")
            pending.pop(name)
            duration = float(event.group("duration") or 0.0)
            cases.append(
                TestCase(
                    name=name,
                    status="passed" if event_name == "passed" else "failed",
                    duration_seconds=duration,
                )
            )
            continue

        summary = SUMMARY_PATTERN.match(line)
        if summary is not None:
            if summary_count is not None:
                raise ValueError("duplicate Swift Testing summary")
            summary_count = int(summary.group("count"))
            summary_result = summary.group("result")

    if summary_count is None or summary_result is None:
        raise ValueError("Swift Testing log is missing its summary")
    if pending:
        raise ValueError("Swift Testing log has unfinished test events")
    if summary_count != len(cases):
        raise ValueError(
            f"Swift Testing summary count {summary_count} does not match "
            f"parsed test count {len(cases)}"
        )
    if not cases:
        raise ValueError("Swift Testing log contains no test cases")
    actual_result = "passed" if all(case.status == "passed" for case in cases) else "failed"
    if summary_result != actual_result:
        raise ValueError(
            f"Swift Testing summary result {summary_result} does not match parsed result {actual_result}"
        )
    return cases


def build_xunit_document(
    text: str,
    *,
    subject_git_sha: str,
    command: str,
) -> bytes:
    _validate_identity(subject_git_sha, command)
    cases = parse_swift_testing_log(text)
    failure_count = sum(case.status == "failed" for case in cases)
    root = ElementTree.Element(
        "testsuites",
        {
            "subjectGitSHA": subject_git_sha,
            "command": command,
            "tests": str(len(cases)),
            "failures": str(failure_count),
            "errors": "0",
        },
    )
    suite = ElementTree.SubElement(
        root,
        "testsuite",
        {
            "name": "SwiftTesting",
            "tests": str(len(cases)),
            "failures": str(failure_count),
            "errors": "0",
        },
    )
    for case in cases:
        testcase = ElementTree.SubElement(
            suite,
            "testcase",
            {
                "name": case.name,
                "time": f"{case.duration_seconds:.6f}",
            },
        )
        if case.status == "failed":
            ElementTree.SubElement(
                testcase,
                "failure",
                {"message": "Swift Testing case failed"},
            )
    return ElementTree.tostring(root, encoding="utf-8", xml_declaration=True)


def write_xunit_report(
    text: str,
    output: Path,
    *,
    subject_git_sha: str,
    command: str,
) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    data = build_xunit_document(
        text,
        subject_git_sha=subject_git_sha,
        command=command,
    )
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=f".{output.name}.",
        dir=output.parent,
    )
    temporary_path = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "wb") as stream:
            descriptor = -1
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary_path, output)
    finally:
        if descriptor >= 0:
            os.close(descriptor)
        temporary_path.unlink(missing_ok=True)


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--subject-git-sha", required=True)
    parser.add_argument("--command", required=True)
    return parser.parse_args()


def main() -> None:
    args = parse_arguments()
    try:
        text = args.input.read_text()
    except OSError as error:
        raise SystemExit(f"cannot read Swift Testing log: {error}") from error
    try:
        write_xunit_report(
            text,
            args.output,
            subject_git_sha=args.subject_git_sha,
            command=args.command,
        )
    except ValueError as error:
        raise SystemExit(str(error)) from error


if __name__ == "__main__":
    main()
