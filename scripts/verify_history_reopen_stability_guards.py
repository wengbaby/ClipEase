#!/usr/bin/env python3
from pathlib import Path


root = Path(__file__).resolve().parents[1]
view = root / "Sources/ClipEase/Features/HistoryWindow/HistoryWindowView.swift"
store = root / "Sources/ClipEase/Core/Storage/ClipboardHistoryStore.swift"
view_text = view.read_text(encoding="utf-8")
store_text = store.read_text(encoding="utf-8")


required = [
    "private let selectedCardTopContentInset: CGFloat = 0",
    "private var focusedHistoryRailVisibleWindow: Range<Int>?",
    "pendingLatestFocusItemID ?? pendingProgrammaticJumpItemID ?? pendingItemScrollID ?? selectedItemID",
    "private func historyRailWindow(aroundFocusedIndex focusedIndex: Int, itemCount: Int) -> Range<Int>",
    "private func resetVisibleRailWindowForLatestFocus(_ id: HistoryPreviewItem.ID)",
    "cardRailVisibleRect = CGRect(",
    "x: targetOffset,",
    "private func cardDocumentX(for id: HistoryPreviewItem.ID) -> CGFloat",
    ".offset(x: cardDocumentX(for: item.id))",
    "PerformanceDiagnosticsService.shared.record(",
    "\"preview.rebuild.skip\"",
    "@State private var appliedPreviewItemsMutationGeneration: UInt64 = 0",
    "private func canSkipPreviewRebuild(",
    "sourceGeneration: UInt64",
    "appliedPreviewItemsMutationGeneration == sourceGeneration",
    "appliedPreviewItemsMutationGeneration = sourceGeneration",
    "schedulePreviewItemsRebuild(from: store.items)",
]

required_store = [
    "@Published private(set) var items: [ClipboardItem] = [] {",
    "didSet {",
    "itemsMutationGeneration &+= 1",
    "private(set) var itemsMutationGeneration: UInt64 = 0",
]

forbidden = [
    "private let selectedCardTopContentInset: CGFloat = 14",
    ".offset(x: cardDocumentFrame(for: item.id)?.minX ?? 0)",
    "previewItemsSourceSignature = sourceSignature\n        previewBuildTask?.cancel()",
    "let sourceItems = store.items\n        deferredStartupTask = Task",
]


failures: list[str] = []

for snippet in required:
    if snippet not in view_text:
        failures.append(f"Missing reopen stability guard: {snippet}")

for snippet in required_store:
    if snippet not in store_text:
        failures.append(f"Missing store mutation generation guard: {snippet}")

for snippet in forbidden:
    if snippet in view_text:
        failures.append(f"Forbidden reopen instability pattern: {snippet}")

if failures:
    print("History reopen stability guard failed:")
    print("\n".join(failures))
    raise SystemExit(1)

print("OK history reopen stability guards present")
