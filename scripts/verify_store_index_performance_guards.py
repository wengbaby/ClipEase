#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
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
    source = STORE.read_text(encoding="utf-8")

    item_lookup = extract_function(source, "func item(with id: ClipboardItem.ID?) -> ClipboardItem?")
    item_count = extract_function(source, "func itemCount(inGroup id: ClipboardGroup.ID) -> Int")
    delete_item = extract_function(source, "func deleteItem(with id: ClipboardItem.ID?)")
    sort_items = extract_function(source, "private func sortItems()")
    sort_groups = extract_function(source, "private func sortGroups()")
    add_item = extract_function(source, "func addItem(_ id: ClipboardItem.ID?, toGroup groupID: ClipboardGroup.ID)")
    remove_item_from_group = extract_function(source, "func removeItemFromGroup(_ id: ClipboardItem.ID?)")
    update_link_metadata = extract_function(source, "private func updateLinkMetadata(")

    required = [
        "private var itemIndexByID: [ClipboardItem.ID: Int] = [:]",
        "private var groupIndexByID: [ClipboardGroup.ID: Int] = [:]",
        "private var itemCountByGroupID: [ClipboardGroup.ID: Int] = [:]",
        "private func itemIndex(for id: ClipboardItem.ID) -> Int?",
        "private func groupIndex(for id: ClipboardGroup.ID) -> Int?",
        "private func rebuildItemIndexes()",
        "private func rebuildGroupIndex()",
        "private func removeRecentHashes(for removedItems: [ClipboardItem])",
        "private func updateGroupCountOnMove(from oldGroupID: ClipboardGroup.ID?, to newGroupID: ClipboardGroup.ID?)",
    ]

    scoped_required = [
        ("item lookup", item_lookup, ["itemIndex(for: id)", "return items[index]"]),
        ("item count", item_count, ["itemCountByGroupID[id] ?? 0"]),
        ("delete item", delete_item, ["itemIndex(for: id)", "items.remove(at: deletedIndex)", "removeRecentHashes(for: deletedItems)"]),
        ("sort items", sort_items, ["rebuildItemIndexes()"]),
        ("sort groups", sort_groups, ["rebuildGroupIndex()"]),
        ("add item to group", add_item, ["itemIndex(for: id)", "groupIndexByID[groupID] != nil", "updateGroupCountOnMove(from: oldGroupID, to: groupID)"]),
        ("remove item from group", remove_item_from_group, ["itemIndex(for: id)", "updateGroupCountOnMove(from: oldGroupID, to: nil)"]),
        ("link metadata update", update_link_metadata, ["itemIndex(for: id)"]),
    ]

    forbidden_global = [
        "items.lazy.filter { $0.groupID == id }.count",
        "return groups.first { $0.id == id }",
        "guard let index = groups.firstIndex(where: { $0.id == id }) else",
        "guard let id,\n              let index = items.firstIndex(where: { $0.id == id })",
        "let deletedItems = items.filter { $0.id == id }",
    ]

    failures: list[str] = []
    for snippet in required:
        if snippet not in source:
            failures.append(f"Missing store index guard: {snippet}")

    for label, body, snippets in scoped_required:
        for snippet in snippets:
            if snippet not in body:
                failures.append(f"Missing {label} guard: {snippet}")

    for snippet in forbidden_global:
        if snippet in source:
            failures.append(f"Forbidden store index regression: {snippet}")

    if failures:
        print("Store index performance guard failed:")
        print("\n".join(failures))
        raise SystemExit(1)

    print("OK store index performance guards present")


if __name__ == "__main__":
    main()
