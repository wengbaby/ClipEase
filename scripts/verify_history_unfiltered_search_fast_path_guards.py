#!/usr/bin/env python3
from pathlib import Path


root = Path(__file__).resolve().parents[1]
view = root / "Sources/ClipEase/Features/HistoryWindow/HistoryWindowView.swift"
view_text = view.read_text(encoding="utf-8")


def extract_function(source: str, signature: str) -> str:
    start = source.find(signature)
    if start == -1:
        raise AssertionError(f"Missing function signature: {signature}")

    brace = source.find("{", start)
    if brace == -1:
        raise AssertionError(f"Missing function body: {signature}")

    depth = 0
    for index in range(brace, len(source)):
        character = source[index]
        if character == "{":
            depth += 1
        elif character == "}":
            depth -= 1
            if depth == 0:
                return source[start:index + 1]

    raise AssertionError(f"Unclosed function body: {signature}")


try:
    schedule_search = extract_function(
        view_text,
        "private func scheduleSearchUpdate(\n        sourceItems: [HistoryPreviewItem],"
    )
except AssertionError as error:
    print(f"History unfiltered search fast-path guard failed:\n{error}")
    raise SystemExit(1)

unfiltered_start = schedule_search.find("if usesUnfilteredSource {")
task_start = schedule_search.find("searchTask = Task(priority: .userInitiated)")

failures: list[str] = []
if unfiltered_start == -1:
    failures.append("Missing direct unfiltered source branch")
if task_start == -1:
    failures.append("Missing filtered async search task")
if unfiltered_start != -1 and task_start != -1 and unfiltered_start > task_start:
    failures.append("Unfiltered search still enters the async search task")

unfiltered_branch = schedule_search[unfiltered_start:task_start] if unfiltered_start != -1 and task_start != -1 else ""
required_unfiltered_branch = [
    "searchTask = nil",
    "let applyStartedAt = CFAbsoluteTimeGetCurrent()",
    "applyUnfilteredPreviewResult()",
    "ensureSelectionInFilteredItems()",
    "\"mode\": \"unfilteredSource\"",
    "renderState.mark(\"filtered-items-ready count=\\(allPreviewItems.count)\")",
    "restoreRememberedViewportIfNeeded()",
    "schedulePreheatVisibleAssets()",
    "return",
]

for snippet in required_unfiltered_branch:
    if snippet not in unfiltered_branch:
        failures.append(f"Missing unfiltered fast-path guard: {snippet}")

for forbidden in [
    "await MainActor.run",
    "Task.sleep",
    "Task.detached",
    "recordResourceCheckpoint",
]:
    if forbidden in unfiltered_branch:
        failures.append(f"Forbidden async work in unfiltered fast path: {forbidden}")

filtered_task_body = schedule_search[task_start:] if task_start != -1 else ""
if "if usesUnfilteredSource {" in filtered_task_body:
    failures.append("Async search task still contains an unfiltered source branch")

if failures:
    print("History unfiltered search fast-path guard failed:")
    print("\n".join(failures))
    raise SystemExit(1)

print("OK history unfiltered search fast-path guards present")
