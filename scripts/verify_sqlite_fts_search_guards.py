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

    create_schema = extract_function(sqlite_store, "private func createSchema(in database: SQLiteDatabase) throws")
    search_items = extract_function(sqlite_store, "func searchItems(_ query: ClipboardSearchQuery) throws -> [ClipboardItem]")
    insert_item = extract_function(sqlite_store, "private func insert(_ item: ClipboardItem, in database: SQLiteDatabase) throws")
    delete_items = extract_function(sqlite_store, "private func deleteItems(with ids: Set<ClipboardItem.ID>, in database: SQLiteDatabase) throws")
    schedule_search = extract_function(view, "private func scheduleSearchUpdate(\n        sourceItems: [HistoryPreviewItem],")

    required = [
        "struct ClipboardSearchQuery: Sendable, Equatable",
        "func searchItems(_ query: ClipboardSearchQuery) throws -> [ClipboardItem]",
        "func searchItems(_ query: ClipboardSearchQuery) -> [ClipboardItem]",
        "CREATE VIRTUAL TABLE IF NOT EXISTS clipboard_items_fts USING fts5",
        "tokenize='unicode61'",
        "CREATE TABLE IF NOT EXISTS clipboard_search_index_state",
        "private func ensureSearchIndexReady(in database: SQLiteDatabase) throws",
        "private func insertSearchIndex(for item: ClipboardItem, in database: SQLiteDatabase) throws",
        "private func deleteSearchIndex(with ids: Set<ClipboardItem.ID>, in database: SQLiteDatabase) throws",
        "static func searchText(for item: ClipboardItem) -> String",
        "static func escapedFTS5Query(",
        "MATCH ?",
        "ORDER BY rank,",
        "LIMIT ?",
        "history.store.searchAll",
        "searchStore.searchItems(",
        "mode\": \"sqliteFTS",
    ]

    scoped_required = [
        ("createSchema", create_schema, ["CREATE VIRTUAL TABLE IF NOT EXISTS clipboard_items_fts USING fts5"]),
        ("searchItems", search_items, ["ensureSearchIndexReady(in: database)", "ORDER BY rank,", "LIMIT ?"]),
        ("insert item", insert_item, ["insertSearchIndex(for: item, in: database)"]),
        ("delete items", delete_items, ["deleteSearchIndex(with: ids, in: database)"]),
        ("schedule search", schedule_search, ["let repositorySearchTask = Task.detached", "searchStore.searchItems(", "HistoryPreviewItem(item: item)"]),
    ]

    forbidden = [
        "searchItems(_ query: ClipboardSearchQuery) throws -> [ClipboardItem] {\n        try loadSnapshot().items.filter",
        "fts5(plain_text)",
    ]

    failures: list[str] = []
    for snippet in required:
        if snippet not in combined:
            failures.append(f"Missing FTS search guard: {snippet}")

    for label, body, snippets in scoped_required:
        for snippet in snippets:
            if snippet not in body:
                failures.append(f"Missing {label} FTS guard: {snippet}")

    for snippet in forbidden:
        if snippet in combined:
            failures.append(f"Forbidden FTS search regression: {snippet}")

    if failures:
        print("SQLite FTS search guard failed:")
        print("\n".join(failures))
        raise SystemExit(1)

    print("OK SQLite FTS search guards present")


if __name__ == "__main__":
    main()
