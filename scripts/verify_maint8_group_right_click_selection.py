#!/usr/bin/env python3
from pathlib import Path

root = Path(__file__).resolve().parents[1]
view = root / "Sources/ClipEase/Features/HistoryWindow/HistoryWindowView.swift"

view_text = view.read_text(encoding="utf-8")

checks = {
    "group mouse observer monitors right clicks": "matching: [.leftMouseDown, .rightMouseDown]" in view_text
    and "var onRightMouseDown: (() -> Void)?" in view_text
    and "case .rightMouseDown:" in view_text,
    "all history right click selects all": ".onRightMouseDown(selectAllGroupsForContextMenu)" in view_text
    and "func onRightMouseDown(_ action: @escaping () -> Void) -> Self" in view_text
    and "private func selectAllGroupsForContextMenu()" in view_text
    and "guard selectedGroup != .all else" in view_text
    and "selectedGroup = .all\n        showStatus(\"全部剪切板\")" in view_text,
    "user group right click selects the group": "onRightMouseDown: { selectGroup(group.id) }" in view_text,
    "system group right click selects without toggling away": "onRightMouseDown: { selectSystemGroupForContextMenu(group) }" in view_text
    and "private func selectSystemGroupForContextMenu(_ group: SystemHistoryGroup)" in view_text
    and "guard selectedGroup != group.selection else" in view_text,
    "right click selection keeps search group navigation cleanup": "private func selectGroup(_ id: ClipboardGroup.ID)" in view_text
    and "closeSearchForGroupNavigation()\n        selectedGroup = .group(id)" in view_text
    and "private func selectAllGroupsForContextMenu()" in view_text
    and "closeSearchForGroupNavigation()\n        guard selectedGroup != .all else" in view_text
    and "private func selectSystemGroupForContextMenu(_ group: SystemHistoryGroup)" in view_text
    and "closeSearchForGroupNavigation()\n        guard selectedGroup != group.selection else" in view_text,
    "user group context menu remains available": '.contextMenu {\n                    Button("重命名")' in view_text
    and 'Button("颜色与图标")' in view_text
    and 'Button("删除分组", role: .destructive)' in view_text,
    "appearance popovers remain available": "groupAppearancePopover(group)" in view_text
    and "systemGroupAppearancePopover(group)" in view_text,
}

failed = [name for name, passed in checks.items() if not passed]
if failed:
    for name in failed:
        print(f"FAIL: {name}")
    raise SystemExit(1)

for name in checks:
    print(f"PASS: {name}")
