#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
REPOSITORY = ROOT / "Sources/ClipEase/Core/Storage/ClipboardHistoryRepository.swift"
PERSISTENCE = ROOT / "Sources/ClipEase/Core/Storage/ClipboardHistoryPersistence.swift"
SQLITE_STORE = ROOT / "Sources/ClipEase/Core/Storage/SQLiteClipboardStore.swift"
STORE = ROOT / "Sources/ClipEase/Core/Storage/ClipboardHistoryStore.swift"
VIEW = ROOT / "Sources/ClipEase/Features/HistoryWindow/HistoryWindowView.swift"


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


def main() -> None:
    repository = REPOSITORY.read_text(encoding="utf-8")
    persistence = PERSISTENCE.read_text(encoding="utf-8")
    sqlite_store = SQLITE_STORE.read_text(encoding="utf-8")
    store = STORE.read_text(encoding="utf-8")
    view = VIEW.read_text(encoding="utf-8")
    combined = "\n".join([repository, persistence, sqlite_store, store, view])

    store_init = extract_function(store, "init(\n        persistence: ClipboardHistoryPersistence = ClipboardHistoryPersistence(),")
    load_next_page = extract_function(store, "private func loadNextItemPage(reason: String)")
    merge_page = extract_function(store, "private func mergeLoadedPage(")
    upsert_item = extract_function(store, "private func upsertClipboardItem(")
    save_immediately = extract_function(store, "private func saveImmediatelyOrThrow() throws")
    schedule_save = extract_function(store, "private func scheduleSave()")
    view_request = extract_function(view, "private func requestNextHistoryPageIfNeeded()")

    required = [
        "nonisolated private static let startupItemPageSize = 1_000",
        "nonisolated private static let incrementalItemPageSize = 1_000",
        "func loadSnapshot(itemLimit: Int, offset: Int) throws -> ClipboardHistorySnapshot",
        "func loadItems(limit: Int, offset: Int) throws -> [ClipboardItem]",
        "func loadItems(contentHash: String, sourceBundleID: String?) throws -> [ClipboardItem]",
        "private func loadItems(",
        "private func persistedDuplicateItems(for item: ClipboardItem) -> [ClipboardItem]",
        "private func mergeDuplicateItems(",
        "clipboard_items.content_hash = ?",
        "LIMIT ? OFFSET ?",
        "var hasLoadedAllPersistedItems: Bool",
        "func loadMoreItemsIfNeeded(visibleUpperBound: Int, preloadMargin: Int = 160)",
        "private func scheduleInitialBackgroundPageLoadIfNeeded()",
        "private func loadAllPersistedItemsBeforeFullSave()",
        "history.store.loadStartupPage",
        "history.store.loadNextPage",
        "history.store.loadAllBeforeFullSave",
        "requestNextHistoryPageIfNeeded()",
        "store.loadMoreItemsIfNeeded(visibleUpperBound: historyRailVisibleWindow.upperBound)",
    ]

    scoped_required = [
        ("store init", store_init, ["persistence.loadSnapshot(itemLimit: Self.startupItemPageSize)", "scheduleInitialBackgroundPageLoadIfNeeded()"]),
        ("loadNextItemPage", load_next_page, ["let offset = items.count", "Task.detached(priority: .utility)", "persistence.loadItems(limit: limit, offset: offset)"]),
        ("mergeLoadedPage", merge_page, ["guard offset == items.count else", "appendLoadedItems(page)", "didLoadAllPersistedItems = page.count < limit"]),
        ("upsertClipboardItem", upsert_item, ["persistedDuplicateItems(for: item)", "mergeDuplicateItems(cachedDuplicateItems, persistedDuplicateItems)"]),
        ("saveImmediatelyOrThrow", save_immediately, ["loadAllPersistedItemsBeforeFullSave()", "saveWriter.saveSync"]),
        ("scheduleSave", schedule_save, ["loadAllPersistedItemsBeforeFullSave()", "ClipboardHistorySnapshot(items: items, groups: groups)"]),
        ("requestNextHistoryPageIfNeeded", view_request, ["store.loadMoreItemsIfNeeded(visibleUpperBound: historyRailVisibleWindow.upperBound)"]),
    ]

    forbidden = [
        "let snapshot = persistence.loadSnapshot()\n",
        "nextPageOffset",
    ]

    failures: list[str] = []
    for snippet in required:
        if snippet not in combined:
            failures.append(f"Missing startup paged load guard: {snippet}")

    for label, body, snippets in scoped_required:
        for snippet in snippets:
            if snippet not in body:
                failures.append(f"Missing {label} paged load guard: {snippet}")

    for snippet in forbidden:
        if snippet in store:
            failures.append(f"Forbidden startup paging regression in store: {snippet}")

    if failures:
        print("Startup paged history load guard failed:")
        print("\n".join(failures))
        raise SystemExit(1)

    print("OK startup history load is paged and full saves hydrate missing pages first")


if __name__ == "__main__":
    main()
