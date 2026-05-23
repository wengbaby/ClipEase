#!/usr/bin/env python3
from pathlib import Path


root = Path(__file__).resolve().parents[1]
view = root / "Sources/ClipEase/Features/HistoryWindow/HistoryWindowView.swift"
view_text = view.read_text(encoding="utf-8")


required = [
    "@State private var filteredPreviewItemIDs: Set<HistoryPreviewItem.ID> = []",
    "@State private var filteredPreviewItemIndexByID: [HistoryPreviewItem.ID: Int] = [:]",
    "private struct HistorySearchFilterResult: Sendable",
    "private func applyFilteredPreviewResult(_ result: HistorySearchFilterResult)",
    "filteredPreviewItems = result.items",
    "filteredPreviewItemIDs = result.itemIDs",
    "filteredPreviewItemIndexByID = result.itemIndexByID",
    "itemIDs = Set(items.map(\\.id))",
    "var itemIndexByID: [HistoryPreviewItem.ID: Int] = [:]",
    "private func containsFilteredItem(_ id: HistoryPreviewItem.ID?) -> Bool",
    "private func filteredItemIndex(for id: HistoryPreviewItem.ID?) -> Int?",
    "private func filteredItem(for id: HistoryPreviewItem.ID?) -> HistoryPreviewItem?",
    "HistorySearchFilterResult(items: try await filterTask.value)",
    "applyFilteredPreviewResult(result)",
]

hot_path_forbidden = [
    "filteredItems.contains(where: { $0.id == selectedItemID })",
    "filteredItems.contains(where: { $0.id == id })",
    "filteredItems.contains(where: { $0.id == pendingLatestFocusItemID })",
    "filteredItems.contains(where: { $0.id == rememberedID })",
    "filteredItems.contains(where: { $0.id == preferredID })",
    "filteredItems.firstIndex(where: { $0.id == currentSelectedID })",
    "filteredItems.firstIndex(where: { $0.id == id })",
    "filteredItems.first(where: { $0.id == pendingLatestFocusItemID })",
    "store.items.contains(where: { $0.id == id })",
    "store.items.firstIndex(where: { $0.id == id })",
    "filteredPreviewItemIDs = Set(nextItems.map(\\.id))",
    "nextIndexByID.reserveCapacity(nextItems.count)",
]

failures: list[str] = []
for snippet in required:
    if snippet not in view_text:
        failures.append(f"Missing filtered index guard: {snippet}")

for snippet in hot_path_forbidden:
    if snippet in view_text:
        failures.append(f"Forbidden linear filtered/store lookup: {snippet}")

if failures:
    print("History filtered index guard failed:")
    print("\n".join(failures))
    raise SystemExit(1)

print("OK history filtered index guards present")
