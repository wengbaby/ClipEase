#!/usr/bin/env python3
import re
from pathlib import Path

root = Path(__file__).resolve().parents[1]
view = root / "Sources/ClipEase/Features/HistoryWindow/HistoryWindowView.swift"
text = view.read_text(encoding="utf-8")

checks = {
    "snapshot stores menu-only value type": "private struct MoveToGroupMenuEntry: Identifiable, Equatable" in text
    and "@State private var moveToGroupMenuSnapshot: [MoveToGroupMenuEntry]" in text
    and "let id: ClipboardGroup.ID" in text
    and "let name: String" in text
    and "let iconName: String" in text,
    "snapshot ignores non-menu group fields": "colorHex" not in text.split("private struct MoveToGroupMenuEntry", 1)[1].split("private struct", 1)[0]
    and "updatedAt" not in text.split("private struct MoveToGroupMenuEntry", 1)[1].split("private struct", 1)[0]
    and "sortOrder" not in text.split("private struct MoveToGroupMenuEntry", 1)[1].split("private struct", 1)[0],
    "snapshot refresh is guarded": "private func refreshMoveToGroupMenuSnapshot()" in text
    and "if moveToGroupMenuSnapshot != snapshot" in text
    and "moveToGroupMenuSnapshot = snapshot" in text,
    "store group changes refresh through helper": ".onChange(of: store.groups)" in text
    and "refreshMoveToGroupMenuSnapshot()" in text.split(".onChange(of: store.groups)", 1)[1].split(".onChange(of:", 1)[0],
    "context menu opens stable picker instead of submenu": 'Button(item.groupID == nil ? "加入分组..." : "移动到分组...")' in text
    and "presentMoveToGroupPicker(for: item)" in text
    and ".sheet(item: $moveToGroupPickerTarget)" in text,
    "picker target keeps item and current group ids": "private struct MoveToGroupPickerTarget: Identifiable, Equatable" in text
    and "let itemID: ClipboardItem.ID" in text
    and "let currentGroupID: ClipboardGroup.ID?" in text,
    "picker freezes snapshot locally": "let groupEntries = moveToGroupMenuSnapshot" in text,
    "picker uses stable group id": r"ForEach(groupEntries, id: \.id)" in text,
    "move action keeps group id semantics": "addItem(target.itemID, toGroup: group.id, named: group.name)" in text,
    "picker label uses snapshotted identity": "Image(systemName: group.iconName)" in text
    and "Text(group.name)" in text,
}

card_menu_body = text.split("private func cardContextMenu", 1)[1].split("private func typeSpecificContextMenu", 1)[0]
picker_body = text.split("private func moveToGroupPicker(for target:", 1)[1].split("private func searchFilterChipIcon", 1)[0]
forbidden_in_menu_body = [
    r"\bMenu\s*\(",
    r"\bPicker\s*\(",
]
forbidden_in_picker_body = [
    "moveToGroupMenuSnapshot =",
    "refreshMoveToGroupMenuSnapshot()",
    "store.groups",
    "onAppear",
    "onHover",
]

failed = [name for name, passed in checks.items() if not passed]
failed.extend(
    f"forbidden card menu pattern present: {pattern}"
    for pattern in forbidden_in_menu_body
    if re.search(pattern, card_menu_body)
)
failed.extend(
    f"forbidden picker-body token present: {token}"
    for token in forbidden_in_picker_body
    if token in picker_body
)

if failed:
    for message in failed:
        print(f"FAIL: {message}")
    raise SystemExit(1)

for name in checks:
    print(f"PASS: {name}")
print("PASS: move-to-group uses a stable sheet picker instead of a hover submenu")
