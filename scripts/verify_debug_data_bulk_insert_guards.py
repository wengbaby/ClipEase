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

    failures: list[str] = []

    def optional_function(source: str, signature: str) -> str:
        try:
            return extract_function(source, signature)
        except AssertionError as error:
            failures.append(str(error))
            return ""

    merge_debug = optional_function(store, "private func mergeDebugTextItems(_ newItems: [ClipboardItem])")
    persist_debug = optional_function(store, "private func persistDebugItemsIncrementally(_ items: [ClipboardItem])")
    sqlite_insert_items = optional_function(sqlite_store, "func insertItems(_ items: [ClipboardItem]) throws")

    required = [
        "func insertItems(_ items: [ClipboardItem]) throws",
        "func insertItemsOrThrow(_ items: [ClipboardItem]) throws",
        "func insertItemsAsync(_ items: [ClipboardItem], revision: Int)",
        "private func persistDebugItemsIncrementally(_ items: [ClipboardItem])",
        "history.persistence.insertDebugItems",
        "history.store.addDebugTextItems",
    ]
    scoped_required = [
        ("mergeDebugTextItems", merge_debug, ["persistDebugItemsIncrementally(newItems)"]),
        ("persistDebugItemsIncrementally", persist_debug, ["saveWriter.insertItemsAsync", "itemCount: items.count"]),
        ("SQLite insertItems", sqlite_insert_items, ["BEGIN IMMEDIATE TRANSACTION", "for item in items", "insert(item, in: database)", "COMMIT"]),
    ]
    forbidden = [
        ("mergeDebugTextItems", merge_debug, ["scheduleSave()", "saveImmediately()"]),
    ]

    for snippet in required:
        if snippet not in combined:
            failures.append(f"Missing debug bulk insert guard: {snippet}")

    for label, body, snippets in scoped_required:
        for snippet in snippets:
            if snippet not in body:
                failures.append(f"Missing {label} debug bulk insert guard: {snippet}")

    for label, body, snippets in forbidden:
        for snippet in snippets:
            if snippet in body:
                failures.append(f"Forbidden {label} full-save path: {snippet}")

    if failures:
        print("Debug data bulk insert guard failed:")
        print("\n".join(failures))
        raise SystemExit(1)

    print("OK debug data uses bounded SQLite bulk insert")


if __name__ == "__main__":
    main()
