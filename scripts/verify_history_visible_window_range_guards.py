#!/usr/bin/env python3
from pathlib import Path


root = Path(__file__).resolve().parents[1]
view = root / "Sources/ClipEase/Features/HistoryWindow/HistoryWindowView.swift"
view_text = view.read_text(encoding="utf-8")


required = [
    "private func clampedHistoryRailWindow(",
    "itemCount: Int,",
    "visibleRect: CGRect,",
    "bufferItemCount: Int",
    "let clampedStart = min(max(0, rawStart), max(itemCount - 1, 0))",
    "let clampedEnd = min(itemCount, max(clampedStart + 1, rawEnd))",
    "return clampedStart..<clampedEnd",
    "clampedHistoryRailWindow(",
    "itemCount: renderedItems.count,",
    "itemCount: sourceItems.count,",
    "bufferItemCount: historyRailWindowBufferItemCount",
    "bufferItemCount: previewItemCacheRetainedItemCount / 2",
]

forbidden = [
    "let start = max(0, rawStart)\n        let end = min(renderedItems.count, max(start + 1, rawEnd))",
    "let start = max(0, rawStart)\n            let end = min(sourceItems.count, max(start + 1, rawEnd))",
]


def simulated_window(
    item_count: int,
    visible_min_x: float,
    visible_max_x: float,
    horizontal_content_padding: float = 22,
    item_stride: float = 280,
    buffer_item_count: int = 36,
) -> range:
    if item_count <= 0:
        return range(0, 0)

    from math import ceil, floor

    min_x = max(visible_min_x - horizontal_content_padding, 0)
    max_x = max(visible_max_x - horizontal_content_padding, min_x)
    raw_start = int(floor(min_x / item_stride)) - buffer_item_count
    raw_end = int(ceil(max_x / item_stride)) + buffer_item_count + 1
    clamped_start = min(max(0, raw_start), max(item_count - 1, 0))
    clamped_end = min(item_count, max(clamped_start + 1, raw_end))
    return range(clamped_start, clamped_end)


failures: list[str] = []

for snippet in required:
    if snippet not in view_text:
        failures.append(f"Missing visible window range guard: {snippet}")

for snippet in forbidden:
    if snippet in view_text:
        failures.append(f"Forbidden unbounded visible window range calculation: {snippet}")

stale_offset_window = simulated_window(
    item_count=1,
    visible_min_x=29_000_000,
    visible_max_x=29_001_000,
)
if stale_offset_window.start != 0 or stale_offset_window.stop != 1:
    failures.append(
        "Simulated stale-offset single-item window must clamp to 0..<1, "
        f"got {stale_offset_window.start}..<{stale_offset_window.stop}"
    )

empty_window = simulated_window(
    item_count=0,
    visible_min_x=29_000_000,
    visible_max_x=29_001_000,
)
if empty_window.start != 0 or empty_window.stop != 0:
    failures.append(
        "Simulated empty window must clamp to 0..<0, "
        f"got {empty_window.start}..<{empty_window.stop}"
    )

if failures:
    print("History visible window range guard failed:")
    print("\n".join(failures))
    raise SystemExit(1)

print("OK history visible window range guards present")
