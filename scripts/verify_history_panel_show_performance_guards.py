#!/usr/bin/env python3
from pathlib import Path


root = Path(__file__).resolve().parents[1]
controller = root / "Sources/ClipEase/Features/HistoryWindow/HistoryWindowController.swift"
text = controller.read_text(encoding="utf-8")

required = [
    "panel.setFrame(hiddenFrame(for: targetFrame), display: false)",
    "panel.orderFrontRegardless()",
    "renderState.mark(\"panel-ordered\")",
]

forbidden = [
    "panel.setFrame(hiddenFrame(for: targetFrame), display: true)",
]

failures: list[str] = []
for snippet in required:
    if snippet not in text:
        failures.append(f"Missing panel show performance guard: {snippet}")

for snippet in forbidden:
    if snippet in text:
        failures.append(f"Forbidden hidden-frame synchronous display: {snippet}")

if failures:
    print("History panel show performance guard failed:")
    print("\n".join(failures))
    raise SystemExit(1)

print("OK history panel show performance guards present")
