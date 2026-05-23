#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
REPOSITORY = ROOT / "Sources/ClipEase/Core/Storage/ClipboardHistoryRepository.swift"
PERSISTENCE = ROOT / "Sources/ClipEase/Core/Storage/ClipboardHistoryPersistence.swift"
SQLITE_STORE = ROOT / "Sources/ClipEase/Core/Storage/SQLiteClipboardStore.swift"
STORE = ROOT / "Sources/ClipEase/Core/Storage/ClipboardHistoryStore.swift"


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
    combined = "\n".join([repository, persistence, sqlite_store, store])

    delete_item = extract_function(store, "func deleteItem(with id: ClipboardItem.ID?)")
    clear_all = extract_function(store, "func clearAllItems()")
    delete_group = extract_function(store, "func deleteGroup(_ id: ClipboardGroup.ID) -> Int")
    delete_groups = extract_function(store, "func deleteGroups(_ ids: Set<ClipboardGroup.ID>) -> Int")
    clear_debug = extract_function(store, "func clearDebugTextItems() -> Int")
    save_writer_delete = extract_function(store, "private func deleteIfCurrent(")
    save_writer_delete_all = extract_function(store, "private func deleteAllIfCurrent(revision: Int) throws")

    required = [
        "func loadItems(limit: Int, offset: Int) throws -> [ClipboardItem]",
        "func deleteItems(with ids: Set<ClipboardItem.ID>, deletingGroups groupIDs: Set<ClipboardGroup.ID>) throws",
        "func deleteAllItemsAndGroups() throws",
        "func deleteItemsOrThrow(with ids: Set<ClipboardItem.ID>, deletingGroups groupIDs: Set<ClipboardGroup.ID>) throws",
        "func deleteAllItemsAndGroupsOrThrow() throws",
        "private func persistIncrementalDelete(",
        "private func persistDeleteAll()",
        "func deleteAsync(",
        "func deleteAllAsync(revision: Int)",
        "try persistence.deleteItemsOrThrow(with: itemIDs, deletingGroups: groupIDs)",
        "try persistence.deleteAllItemsAndGroupsOrThrow()",
        "history.persistence.delete",
        "history.persistence.deleteAll",
        "private func loadItems(",
        "private func loadAssetsByItemID(for ids: Set<UUID>, in database: SQLiteDatabase)",
        "private func loadFileReferencesByItemID(",
        "private func loadGroupedItems(for ids: Set<UUID>, in database: SQLiteDatabase)",
        "private func loadOCRResultsByItemID(for ids: Set<UUID>, in database: SQLiteDatabase)",
        "LIMIT ? OFFSET ?",
        "BEGIN IMMEDIATE TRANSACTION",
        "DELETE FROM clipboard_items WHERE id IN",
        "DELETE FROM groups WHERE id IN",
    ]

    scoped_required = [
        ("deleteItem", delete_item, ["items.remove(at: deletedIndex)", "persistIncrementalDelete(itemIDs: [id])"]),
        ("clearAllItems", clear_all, ["items.removeAll()", "persistDeleteAll()"]),
        ("deleteGroup", delete_group, ["persistIncrementalDelete(", "groupIDs: [id]"]),
        ("deleteGroups", delete_groups, ["persistIncrementalDelete(", "groupIDs: ids"]),
        ("clearDebugTextItems", clear_debug, ["persistIncrementalDelete(itemIDs: Set(removedItems.map(\\.id)))"]),
        ("deleteIfCurrent", save_writer_delete, ["itemCount: itemIDs.count", "resultCount: groupIDs.count"]),
        ("deleteAllIfCurrent", save_writer_delete_all, ["history.persistence.deleteAll"]),
    ]

    forbidden_scoped = [
        ("deleteItem", delete_item, "saveImmediately()"),
        ("clearAllItems", clear_all, "saveImmediately()"),
        ("deleteGroup", delete_group, "saveImmediately()"),
        ("deleteGroups", delete_groups, "saveImmediately()"),
        ("clearDebugTextItems", clear_debug, "saveImmediately()"),
    ]

    failures: list[str] = []
    for snippet in required:
        if snippet not in combined:
            failures.append(f"Missing incremental delete guard: {snippet}")

    for label, body, snippets in scoped_required:
        for snippet in snippets:
            if snippet not in body:
                failures.append(f"Missing {label} incremental guard: {snippet}")

    for label, body, snippet in forbidden_scoped:
        if snippet in body:
            failures.append(f"{label} must not persist by full saveImmediately")

    if failures:
        print("SQLite incremental delete guard failed:")
        print("\n".join(failures))
        raise SystemExit(1)

    print("OK SQLite deletes and paged loads use bounded incremental paths")


if __name__ == "__main__":
    main()
