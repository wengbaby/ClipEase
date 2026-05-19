#!/usr/bin/env python3
from pathlib import Path

root = Path(__file__).resolve().parents[1]

files = {
    "HistoryWindowView": root / "Sources/ClipEase/Features/HistoryWindow/HistoryWindowView.swift",
    "HistoryCardView": root / "Sources/ClipEase/Features/HistoryWindow/HistoryCardView.swift",
    "HistoryCommand": root / "Sources/ClipEase/Features/HistoryWindow/HistoryCommand.swift",
    "HistoryWindowInputState": root / "Sources/ClipEase/Features/HistoryWindow/HistoryWindowInputState.swift",
    "HistoryKeyboardEventTap": root / "Sources/ClipEase/Features/HistoryWindow/HistoryKeyboardEventTap.swift",
    "HistoryPreviewItem": root / "Sources/ClipEase/Features/HistoryWindow/HistoryPreviewItem.swift",
    "SettingsView": root / "Sources/ClipEase/Features/Settings/SettingsView.swift",
    "ClipboardHistoryStore": root / "Sources/ClipEase/Core/Storage/ClipboardHistoryStore.swift",
    "ClipboardGroup": root / "Sources/ClipEase/Core/Models/ClipboardGroup.swift",
}

texts = {name: path.read_text(encoding="utf-8") for name, path in files.items()}
combined_ui_text = "\n".join(
    texts[name]
    for name in [
        "HistoryWindowView",
        "HistoryCardView",
        "HistoryCommand",
        "HistoryWindowInputState",
        "HistoryKeyboardEventTap",
        "HistoryPreviewItem",
        "SettingsView",
        "ClipboardGroup",
    ]
)

forbidden_tokens = [
    "isManagementMode",
    "selectedItemIDs",
    "toggleManagement",
    "toggleManagementMode",
    "managementBar",
    "toggleMultiSelection",
    "selectAllVisibleItems",
    "moveBatchToGroup",
    "finishBatchOperation",
    "reconcileMultiSelectionWithVisibleItems",
    "Command+M",
    "Command + M",
    "KeyCode.m",
    "管理模式",
    "收藏",
    "取消收藏",
    "收藏到分组",
    "星标",
    "Favo" + "rite",
    "favo" + "rite",
    "isFavo" + "rite",
    "favo" + "rited",
    '"star"',
    '"star.fill"',
]

required_tokens = {
    "single delete shortcut remains": ".keyboardShortcut(.delete, modifiers: [])" in texts["HistoryWindowView"]
    and "deleteItem(selectedItemID)" in texts["HistoryWindowView"],
    "pin command remains": "case .togglePinned:" in texts["HistoryWindowView"]
    and 'Button(item.isPinned ? "取消置顶" : "置顶")' in texts["HistoryWindowView"],
    "move group picker uses group id and label": 'Button(item.groupID == nil ? "加入分组..." : "移动到分组...")' in texts["HistoryWindowView"]
    and ".sheet(item: $moveToGroupPickerTarget)" in texts["HistoryWindowView"]
    and "addItem(target.itemID, toGroup: group.id, named: group.name)" in texts["HistoryWindowView"]
    and "Text(group.name)" in texts["HistoryWindowView"],
    "group badge is folder": '"folder.fill"' in texts["HistoryCardView"],
    "default group name constant": 'static let defaultName = "新分组"' in texts["ClipboardGroup"],
    "default group creation uses unique name": "uniqueGroupName(baseName: ClipboardGroup.defaultName)" in texts["ClipboardHistoryStore"],
    "rename duplicate guard": "case duplicate" in texts["ClipboardHistoryStore"]
    and "isGroupNameAvailable(trimmedName, excluding: id)" in texts["ClipboardHistoryStore"],
    "case-insensitive normalized group names": "localizedLowercase" in texts["ClipboardHistoryStore"],
    "history window duplicate feedback": 'showStatus("已有同名分组")' in texts["HistoryWindowView"],
    "settings duplicate feedback": 'showStatus("已有同名分组")' in texts["SettingsView"],
}

failed = []
for token in forbidden_tokens:
    if token in combined_ui_text:
        failed.append(f"forbidden token still present: {token}")

for name, passed in required_tokens.items():
    if not passed:
        failed.append(f"missing required guard: {name}")

if failed:
    for message in failed:
        print(f"FAIL: {message}")
    raise SystemExit(1)

for name in required_tokens:
    print(f"PASS: {name}")
print("PASS: no management mode or removed saved-item UI tokens")
