#!/usr/bin/env python3
from pathlib import Path

root = Path(__file__).resolve().parents[1]
view = root / "Sources/ClipEase/Features/HistoryWindow/HistoryWindowView.swift"
render_state = root / "Sources/ClipEase/Features/HistoryWindow/HistoryWindowRenderState.swift"
view_text = view.read_text(encoding="utf-8")
render_text = render_state.read_text(encoding="utf-8")
text = view_text + "\n" + render_text

required = [
    "static let preheatBatchSize = 18",
    "let itemsToPreheat = filteredItems",
    "for batchStart in stride(from: 0, to: itemsToPreheat.count, by: batchSize)",
    "let batchEnd = min(batchStart + batchSize, itemsToPreheat.count)",
    "for item in itemsToPreheat[batchStart..<batchEnd]",
    "Task.detached(priority: .utility)",
    "guard !Task.isCancelled else",
    "try? await Task.sleep(nanoseconds: 80_000_000)",
]

forbidden = [
    "preheatItemLimit",
    "prefix(HistoryWindowRenderState.preheatBatchSize)",
    "prefix(batchSize)",
    "itemsToPreheat.prefix",
]

missing = [snippet for snippet in required if snippet not in text]
present_forbidden = [snippet for snippet in forbidden if snippet in text]

if missing or present_forbidden:
    if missing:
        print("Missing preheat-all guard(s):")
        print("\n".join(missing))
    if present_forbidden:
        print("Forbidden first-batch-only preheat pattern present:")
        print("\n".join(present_forbidden))
    raise SystemExit(1)

print("OK history preheat covers all filtered items in cancellable batches")
