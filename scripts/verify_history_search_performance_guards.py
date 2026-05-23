#!/usr/bin/env python3
from pathlib import Path


root = Path(__file__).resolve().parents[1]
view = root / "Sources/ClipEase/Features/HistoryWindow/HistoryWindowView.swift"
preview_item = root / "Sources/ClipEase/Features/HistoryWindow/HistoryPreviewItem.swift"

view_text = view.read_text(encoding="utf-8")
preview_item_text = preview_item.read_text(encoding="utf-8")


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
    filter_items = extract_function(
        view_text,
        "nonisolated private static func filterItems("
    )
    schedule_preview = extract_function(
        view_text,
        "private func schedulePreviewItemsRebuild(from sourceItems: [ClipboardItem])"
    )
except AssertionError as error:
    print(f"History search performance guard failed:\n{error}")
    raise SystemExit(1)

required_schedule_search = [
    "searchTask?.cancel()",
    "searchGeneration &+= 1",
    "let generation = searchGeneration",
    "HistorySearchRequestSignature(",
    "guard requestSignature != lastSearchRequestSignature else",
    "lastSearchRequestSignature = requestSignature",
    "Task(priority: .userInitiated)",
    "try? await Task.sleep(nanoseconds: debounceNanoseconds)",
    "guard !Task.isCancelled else",
    "Task.detached(priority: .userInitiated)",
    "try Self.filterItems(",
    "return HistorySearchFilterResult(items: filteredItems)",
    "try await withTaskCancellationHandler",
    "filterTask.cancel()",
    "catch is CancellationError",
    "await MainActor.run",
    "guard searchGeneration == generation else",
    "withTransaction(transaction)",
    "try await filterTask.value",
    "applyFilteredPreviewResult(result)",
    "schedulePreheatVisibleAssets()",
]

required_filter_items = [
    "throws -> [HistoryPreviewItem]",
    "result.reserveCapacity(items.count)",
    "for item in items",
    "try Task.checkCancellation()",
    "item.normalizedSearchText.contains(normalizedQuery)",
    "result.sort(by:",
    "return result",
]

required_preview_rebuild = [
    "previewBuildTask?.cancel()",
    "previewBuildGeneration &+= 1",
    "Task.detached(priority: .userInitiated)",
    "try Task.checkCancellation()",
    "try await withTaskCancellationHandler",
    "buildTask.cancel()",
    "guard !Task.isCancelled, previewBuildGeneration == generation else",
    "scheduleSearchUpdate(sourceItems: previewItemsForSearch, immediate: true)",
]

required_preview_item = [
    "let normalizedSearchText: String",
    "let searchFingerprint: Int",
    "private static func normalizedSearchText(",
    "private static func searchFingerprint(for normalizedSearchText: String) -> Int",
    ".folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)",
    "hasher.combine(normalizedSearchText)",
]

required_search_signature = [
    "let searchFingerprint: Int",
    "searchFingerprint = item.searchFingerprint",
]

forbidden_view = [
    ".filter { item in",
    "filteredPreviewItems = filterItems(",
    "Task.detached(priority: .background)",
    "try? Self.filterItems(",
    "HistorySearchFilterResult(items: try await filterTask.value)",
    "await MainActor.run {\n                filteredPreviewItems = result",
    "searchGeneration == generation else {\n                    filteredPreviewItems = result",
    "let normalizedSearchText: String\n    let isPinned",
    "normalizedSearchText = item.normalizedSearchText",
]

checks = [
    ("scheduleSearchUpdate required", required_schedule_search, schedule_search, True),
    ("filterItems required", required_filter_items, filter_items, True),
    ("preview rebuild required", required_preview_rebuild, schedule_preview, True),
    ("preview item normalized search required", required_preview_item, preview_item_text, True),
    ("search signature fingerprint required", required_search_signature, view_text, True),
    ("view forbidden", forbidden_view, view_text, False),
]

failures: list[str] = []
for label, snippets, text, should_exist in checks:
    for snippet in snippets:
        present = snippet in text
        if should_exist and not present:
            failures.append(f"Missing {label}: {snippet}")
        if not should_exist and present:
            failures.append(f"Forbidden {label}: {snippet}")

if failures:
    print("History search performance guard failed:")
    print("\n".join(failures))
    raise SystemExit(1)

print("OK history search performance guards present")
