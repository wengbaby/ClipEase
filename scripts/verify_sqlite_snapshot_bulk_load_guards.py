#!/usr/bin/env python3
from pathlib import Path


root = Path(__file__).resolve().parents[1]
sqlite_store = root / "Sources/ClipEase/Core/Storage/SQLiteClipboardStore.swift"
history_store = root / "Sources/ClipEase/Core/Storage/ClipboardHistoryStore.swift"

sqlite_text = sqlite_store.read_text(encoding="utf-8")
history_text = history_store.read_text(encoding="utf-8")


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
    load_snapshot = extract_function(sqlite_text, "func loadSnapshot() throws -> ClipboardHistorySnapshot")
except AssertionError as error:
    print(f"SQLite snapshot bulk load guard failed:\n{error}")
    raise SystemExit(1)

required_sqlite = [
    "let assetsByItemID = try loadAssetsByItemID(in: database)",
    "let fileReferencesByItemID = try loadFileReferencesByItemID(in: database)",
    "let ocrResultsByItemID = try loadOCRResultsByItemID(in: database)",
    "private func loadAssetsByItemID(in database: SQLiteDatabase) throws -> [UUID: [SQLiteAssetRow]]",
    "private func loadFileReferencesByItemID(in database: SQLiteDatabase) throws -> [UUID: [ClipboardFileReference]]",
    "private func loadOCRResultsByItemID(in database: SQLiteDatabase) throws -> [UUID: SQLiteOCRResultRow]",
    "INNER JOIN clipboard_items ON clipboard_items.id = item_assets.item_id",
    "INNER JOIN clipboard_items ON clipboard_items.id = clipboard_item_files.item_id",
    "INNER JOIN clipboard_items ON clipboard_items.id = item_ocr_results.item_id",
    "WHERE clipboard_items.is_deleted = 0",
]

required_history_store = [
    '"history.store.loadSnapshot"',
    '"history.store.sort"',
    '"history.store.rebuildHashes"',
    '"history.store.initialize"',
    "let didPruneExpiredItems = pruneExpiredItems()",
    "if didPruneExpiredItems {",
    "private func pruneExpiredItems(now: Date = Date()) -> Bool",
]

forbidden_load_snapshot = [
    "loadAssets(for:",
    "loadFileReferences(for:",
    "loadOCRResult(for:",
]

failures: list[str] = []
for snippet in required_sqlite:
    if snippet not in sqlite_text:
        failures.append(f"Missing SQLite bulk load guard: {snippet}")

for snippet in required_history_store:
    if snippet not in history_text:
        failures.append(f"Missing store timing guard: {snippet}")

for snippet in forbidden_load_snapshot:
    if snippet in load_snapshot:
        failures.append(f"Forbidden N+1 snapshot query in loadSnapshot: {snippet}")

if failures:
    print("SQLite snapshot bulk load guard failed:")
    print("\n".join(failures))
    raise SystemExit(1)

print("OK SQLite snapshot bulk load guards present")
