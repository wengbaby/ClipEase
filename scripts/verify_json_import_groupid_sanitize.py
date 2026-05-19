#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
STORE_PATH = ROOT / "Sources/ClipEase/Core/Storage/ClipboardHistoryStore.swift"
SETTINGS_PATH = ROOT / "Sources/ClipEase/Features/Settings/SettingsView.swift"
EXPORT_PATH = ROOT / "Sources/ClipEase/Core/Utilities/HistoryExportService.swift"


def fail(message: str) -> None:
    print(f"FAIL: {message}")
    raise SystemExit(1)


def require(condition: bool, message: str) -> None:
    if not condition:
        fail(message)
    print(f"PASS: {message}")


def function_body(text: str, signature: str) -> str:
    start = text.find(signature)
    if start == -1:
        fail(f"missing function signature: {signature}")

    brace_start = text.find("{", start)
    if brace_start == -1:
        fail(f"missing function body for: {signature}")

    depth = 0
    for index in range(brace_start, len(text)):
        char = text[index]
        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return text[brace_start + 1:index]

    fail(f"unterminated function body for: {signature}")
    return ""


store_text = STORE_PATH.read_text(encoding="utf-8")
settings_text = SETTINGS_PATH.read_text(encoding="utf-8")
export_text = EXPORT_PATH.read_text(encoding="utf-8")

import_items_body = function_body(
    store_text,
    "func importItems(_ importedItems: [ClipboardItem]) -> Int",
)
sanitized_items_body = function_body(
    store_text,
    "private func sanitizedImportedItems(_ importedItems: [ClipboardItem]) -> [ClipboardItem]",
)
sanitized_item_body = function_body(
    store_text,
    "private func sanitizedImportedItem(",
)
prune_body = function_body(store_text, "private func pruneExpiredItems(now: Date = Date())")
settings_import_body = function_body(settings_text, "private func importHistory()")
export_import_body = function_body(export_text, "static func importItems(from url: URL) throws -> [ClipboardItem]")

require(
    "sanitizedImportedItems(importedItems)" in import_items_body
    and "nonDuplicateItems(from: sanitizedItems)" in import_items_body,
    "ordinary importItems sanitizes JSON-imported items before duplicate filtering",
)
require(
    "Set(groups.map(\\.id))" in sanitized_items_body
    and "sanitizedImportedItem(item, validGroupIDs: validGroupIDs)" in sanitized_items_body,
    "ordinary import sanitizer validates against current store.groups",
)
require(
    "sanitizedItem.groupID = nil" in sanitized_item_body
    and "sanitizedItem.groupedAt = nil" in sanitized_item_body,
    "ordinary import sanitizer clears invalid groupID and groupedAt",
)
require(
    "sanitizedItem.groupedAt = item.groupedAt ?? item.createdAt" in sanitized_item_body,
    "ordinary import sanitizer normalizes groupedAt for valid grouped items",
)
require(
    "let validGroupIDs = Set(groups.map(\\.id))" in prune_body
    and "let hasValidGroup = item.groupID.map(validGroupIDs.contains) ?? false" in prune_body
    and "return !item.isPinned && !hasValidGroup && item.createdAt < cutoffDate" in prune_body
    and "item.groupID == nil" not in prune_body,
    "retention pruning preserves pinned items and items with a current valid groupID only",
)
require(
    "try HistoryExportService.importItems(from: url)" in settings_import_body
    and "store.importItems(importedItems)" in settings_import_body,
    "settings ordinary JSON import still flows through ClipboardHistoryStore.importItems",
)
require(
    "return export.items.compactMap(\\.clipboardItem)" in export_import_body
    and ".decode([ExportedClipboardItem].self, from: data)" in export_import_body,
    "ordinary JSON import remains item-only and does not restore legacy JSON persistence",
)
require(
    "JSONClipboardHistory" + "Repository" not in store_text + export_text + settings_text
    and "SQLiteHistory" + "Migration" not in store_text + export_text + settings_text,
    "JSON import fix does not reintroduce JSON repository or migration compatibility layer",
)

print("OK JSON import groupID sanitization checks passed")
