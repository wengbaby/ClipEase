#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SQLITE_STORE = ROOT / "Sources/ClipEase/Core/Storage/SQLiteClipboardStore.swift"


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
    sqlite_store = SQLITE_STORE.read_text(encoding="utf-8")
    delete_all = extract_function(sqlite_store, "func deleteAllItemsAndGroups() throws")
    delete_files = extract_function(sqlite_store, "private func removeExistingDatabaseFiles() throws")
    sidecars = extract_function(sqlite_store, "private func databaseSidecarURLs() -> [URL]")
    delete_history_files = extract_function(sqlite_store, "private func deleteHistoryStorageDirectories() throws")

    required = [
        (
            "deleteAllItemsAndGroups",
            delete_all,
            ["removeExistingDatabaseFiles()", "deleteHistoryStorageDirectories()", "initialize()"],
        ),
        (
            "removeExistingDatabaseFiles",
            delete_files,
            [
                "databaseSidecarURLs()",
                "fileManager.removeItem(at: url)",
            ],
        ),
        (
            "databaseSidecarURLs",
            sidecars,
            [
                "databaseURL",
                "\"-wal\"",
                "\"-shm\"",
                "\"-journal\"",
            ],
        ),
        (
            "deleteHistoryStorageDirectories",
            delete_history_files,
            [
                "ClipEaseStoragePaths.imagesDirectory",
                "ClipEaseStoragePaths.thumbnailsDirectory",
                "ClipEaseStoragePaths.richTextsDirectory",
                "ClipEaseStoragePaths.appIconsDirectory",
                "ClipEaseStoragePaths.sqliteStoreURL",
                "databaseURL.standardizedFileURL == liveStoreURL.standardizedFileURL",
                "fileManager.removeItem(at: directoryURL)",
            ],
        ),
    ]
    forbidden = [
        ("deleteAllItemsAndGroups", delete_all, ["DELETE FROM clipboard_items", "DELETE FROM clipboard_items_fts", "VACUUM"]),
    ]

    failures: list[str] = []
    for label, body, snippets in required:
        for snippet in snippets:
            if snippet not in body:
                failures.append(f"Missing {label} recreate-database guard: {snippet}")

    for label, body, snippets in forbidden:
        for snippet in snippets:
            if snippet in body:
                failures.append(f"Forbidden {label} old clear path: {snippet}")

    if failures:
        print("Clear history recreate database guard failed:")
        print("\n".join(failures))
        raise SystemExit(1)

    print("OK clear history deletes and recreates SQLite database plus history caches")


if __name__ == "__main__":
    main()
