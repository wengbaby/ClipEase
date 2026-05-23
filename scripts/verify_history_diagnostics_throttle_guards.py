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
    note_hidden = extract_function(view_text, "private func noteHistoryWindowHidden()")
except AssertionError as error:
    print(f"History diagnostics throttle guard failed:\n{error}")
    raise SystemExit(1)

required_view = [
    "@State private var lastHiddenResourceCheckpointAt: CFAbsoluteTime = 0",
    "@State private var hiddenResourceCheckpointTask: Task<Void, Never>?",
    "private let hiddenResourceCheckpointMinimumInterval: CFTimeInterval = 10",
]

required_function = [
    "let now = CFAbsoluteTimeGetCurrent()",
    "if now - lastHiddenResourceCheckpointAt >= hiddenResourceCheckpointMinimumInterval {",
    "lastHiddenResourceCheckpointAt = now",
    "hiddenResourceCheckpointTask?.cancel()",
    "try? await Task.sleep(nanoseconds: 750_000_000)",
    "PerformanceDiagnosticsService.shared.recordResourceCheckpoint(\"history.hidden.keepWarm.deferred\")",
]

failures: list[str] = []
for snippet in required_view:
    if snippet not in view_text:
        failures.append(f"Missing diagnostics throttle state: {snippet}")

for snippet in required_function:
    if snippet not in note_hidden:
        failures.append(f"Missing hidden diagnostics throttle guard: {snippet}")

checkpoint_index = note_hidden.find("PerformanceDiagnosticsService.shared.recordResourceCheckpoint(\"history.hidden.keepWarm.deferred\")")
throttle_index = note_hidden.find("if now - lastHiddenResourceCheckpointAt >= hiddenResourceCheckpointMinimumInterval {")
if checkpoint_index != -1 and throttle_index != -1 and checkpoint_index < throttle_index:
    failures.append("Hidden resource checkpoint runs before the throttle guard")

if "PerformanceDiagnosticsService.shared.recordResourceCheckpoint(\"history.hidden.keepWarm\")" in note_hidden:
    failures.append("Hidden resource checkpoint must use the deferred keep-warm reason")

if failures:
    print("History diagnostics throttle guard failed:")
    print("\n".join(failures))
    raise SystemExit(1)

print("OK history diagnostics throttle guards present")
