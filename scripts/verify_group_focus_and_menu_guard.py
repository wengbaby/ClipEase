#!/usr/bin/env python3
from pathlib import Path

root = Path(__file__).resolve().parents[1]
view = root / "Sources/ClipEase/Features/HistoryWindow/HistoryWindowView.swift"
keyboard = root / "Sources/ClipEase/Features/HistoryWindow/HistoryKeyboardEventTap.swift"

view_text = view.read_text(encoding="utf-8")
keyboard_text = keyboard.read_text(encoding="utf-8")

checks = {
    "rename participates in presented input guard": "groupRenameTargetID != nil" in view_text
    and ".background(GroupTextInputFocusObserver(isFocused: Binding(" in view_text,
    "icon search participates in presented input guard": "isGroupIconSearchFocused" in view_text
    and 'TextField("搜索图标", text: $groupIconSearchText)' in view_text
    and ".background(GroupTextInputFocusObserver(isFocused: $isGroupIconSearchFocused))" in view_text,
    "appearance popover is treated as an input layer": "groupAppearanceTarget != nil" in view_text
    and "systemGroupAppearanceTarget != nil" in view_text,
    "move-to-group picker participates in presented input guard": "moveToGroupPickerTarget != nil" in view_text
    and ".sheet(item: $moveToGroupPickerTarget)" in view_text,
    "typed characters suppressed while presented input active": "case .appendSearchText:" in keyboard_text
    and "return true" in keyboard_text.split("case .appendSearchText:", 1)[1].split("\n", 2)[1],
    "move-to-group card action uses stable picker snapshot": "@State private var moveToGroupMenuSnapshot: [MoveToGroupMenuEntry]" in view_text
    and "presentMoveToGroupPicker(for: item)" in view_text
    and "let groupEntries = moveToGroupMenuSnapshot" in view_text
    and r"ForEach(groupEntries, id: \.id)" in view_text
    and "addItem(target.itemID, toGroup: group.id, named: group.name)" in view_text,
    "move-to-group card menu avoids hover submenu": 'Button(item.groupID == nil ? "加入分组..." : "移动到分组...")' in view_text
    and 'Menu(item.groupID == nil ? "加入分组" : "移动到分组")' not in view_text,
}

failed = [name for name, passed in checks.items() if not passed]
if failed:
    for name in failed:
        print(f"FAIL: {name}")
    raise SystemExit(1)

for name in checks:
    print(f"PASS: {name}")
