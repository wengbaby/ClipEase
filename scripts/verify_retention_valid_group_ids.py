#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
STORE_PATH = ROOT / "Sources/ClipEase/Core/Storage/ClipboardHistoryStore.swift"


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
prune_body = function_body(store_text, "private func pruneExpiredItems(now: Date = Date())")

require(
    "let validGroupIDs = Set(groups.map(\\.id))" in prune_body,
    "retention pruning builds current valid groupID set from groups",
)
require(
    "item.groupID.map(validGroupIDs.contains) ?? false" in prune_body
    and "!hasValidGroup" in prune_body,
    "orphan groupID items are treated like ordinary ungrouped history",
)
require(
    "!item.isPinned" in prune_body
    and "item.createdAt < cutoffDate" in prune_body,
    "retention pruning still respects pinned items and cutoff date",
)
require(
    "item.groupID == nil" not in prune_body,
    "retention pruning no longer exempts every non-nil groupID",
)
require(
    "let removedItems = items.filter(shouldPrune)" in prune_body
    and "items.removeAll(where: shouldPrune)" in prune_body
    and "deleteExternalFiles(for: removedItems)" in prune_body,
    "pruned attachments still use the existing removedItems deletion path",
)

print("OK retention valid groupID checks passed")
