#!/usr/bin/env python3
from pathlib import Path


root = Path(__file__).resolve().parents[1]
view = root / "Sources/ClipEase/Features/HistoryWindow/HistoryWindowView.swift"
store = root / "Sources/ClipEase/Core/Storage/ClipboardHistoryStore.swift"
view_text = view.read_text(encoding="utf-8")
store_text = store.read_text(encoding="utf-8")


required = [
    "@State private var filteredPreviewItemIDs: Set<HistoryPreviewItem.ID> = []",
    "@State private var filteredPreviewItemIndexByID: [HistoryPreviewItem.ID: Int] = [:]",
    "@State private var isUsingUnfilteredPreviewResult = true",
    "private struct HistorySearchFilterResult: Sendable",
    "private func applyUnfilteredPreviewResult()",
    "private func applyFilteredPreviewResult(_ result: HistorySearchFilterResult)",
    "guard isUsingUnfilteredPreviewResult || filteredPreviewItems != result.items else",
    "isUsingUnfilteredPreviewResult = false",
    "filteredPreviewItems = result.items",
    "filteredPreviewItemIDs = result.itemIDs",
    "filteredPreviewItemIndexByID = result.itemIndexByID",
    "isUsingUnfilteredPreviewResult = true",
    "filteredPreviewItems.removeAll(keepingCapacity: false)",
    "return store.cachedItemIndex(with: id)",
    "itemIDs = Set(items.map(\\.id))",
    "var itemIndexByID: [HistoryPreviewItem.ID: Int] = [:]",
    "private func containsFilteredItem(_ id: HistoryPreviewItem.ID?) -> Bool",
    "private func filteredItemIndex(for id: HistoryPreviewItem.ID?) -> Int?",
    "private func filteredItem(for id: HistoryPreviewItem.ID?) -> HistoryPreviewItem?",
    "return store.cachedItemIndex(with: id) != nil",
    "return HistorySearchFilterResult(items: filteredItems)",
    "try await filterTask.value",
    "applyFilteredPreviewResult(result)",
    "applyUnfilteredPreviewResult()",
]

required_store = [
    "func cachedItemIndex(with id: ClipboardItem.ID?) -> Int?",
    "let index = itemIndexByID[id]",
    "items[index].id == id",
    "return index",
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
    "HistorySearchFilterResult(items: try await filterTask.value)",
    "filteredPreviewItems = allPreviewItems\n        filteredPreviewItemIDs = Set(allPreviewItems.map(\\.id))",
    "return store.itemIndex(with: id)",
    "return store.item(with: id) != nil",
]

failures: list[str] = []
for snippet in required:
    if snippet not in view_text:
        failures.append(f"Missing filtered index guard: {snippet}")

for snippet in required_store:
    if snippet not in store_text:
        failures.append(f"Missing store cached index guard: {snippet}")

for snippet in hot_path_forbidden:
    if snippet in view_text:
        failures.append(f"Forbidden linear filtered/store lookup: {snippet}")

if failures:
    print("History filtered index guard failed:")
    print("\n".join(failures))
    raise SystemExit(1)

print("OK history filtered index guards present")
