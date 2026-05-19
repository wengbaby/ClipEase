#!/usr/bin/env python3
from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
group = root / "Sources/ClipEase/Core/Models/ClipboardGroup.swift"
color_well = root / "Sources/ClipEase/Features/HistoryWindow/GroupColorWell.swift"
panel_controller = root / "Sources/ClipEase/Features/HistoryWindow/GroupColorPanelController.swift"
history = root / "Sources/ClipEase/Features/HistoryWindow/HistoryWindowView.swift"
settings = root / "Sources/ClipEase/Features/Settings/SettingsView.swift"
settings_window = root / "Sources/ClipEase/Features/Settings/SettingsWindowController.swift"
persistent_popover = root / "Sources/ClipEase/Features/HistoryWindow/PersistentPopoverPresenter.swift"

group_text = group.read_text(encoding="utf-8")
color_well_text = color_well.read_text(encoding="utf-8")
panel_controller_text = panel_controller.read_text(encoding="utf-8")
history_text = history.read_text(encoding="utf-8")
settings_text = settings.read_text(encoding="utf-8")
settings_window_text = settings_window.read_text(encoding="utf-8")
persistent_popover_text = persistent_popover.read_text(encoding="utf-8")

default_color_match = re.search(
    r"static let defaultColors = \[(.*?)\]",
    group_text,
    re.DOTALL,
)
default_color_count = len(re.findall(r'"#[0-9A-Fa-f]{6}"', default_color_match.group(1))) if default_color_match else 0

checks = {
    "new groups randomize color and icon": (
        "colorHex: defaultColors.randomElement()" in group_text
        and "iconName: defaultIcons.randomElement()" in group_text
        and default_color_count >= 20
    ),
    "group color square opens system color panel": (
        "struct GroupColorWell" in color_well_text
        and "NSColorWell" not in color_well_text
        and "final class ColorButtonView: NSView" in color_well_text
        and "override func acceptsFirstMouse(for event: NSEvent?) -> Bool" in color_well_text
        and "override func mouseDown(with event: NSEvent)" in color_well_text
        and "GroupColorPanelController.shared.toggle(" in color_well_text
        and "static func dismantleNSView" in color_well_text
        and "close(source: view)" not in color_well_text
        and "source: view" in color_well_text
        and "activeSource === source" in panel_controller_text
        and "var isVisible: Bool" in panel_controller_text
        and "func closeIfVisible()" in panel_controller_text
        and "func toggle(source: NSView" in panel_controller_text
        and "position(panel, near: source)" in panel_controller_text
        and "panel.setFrameTopLeftPoint" in panel_controller_text
        and "sourceWindow.convertToScreen" in panel_controller_text
        and "panel.level = NSWindow.Level" in panel_controller_text
        and "NSColorPanel.shared.close()" in panel_controller_text
    ),
    "history appearance popovers use main color square, default swatches, and close color panel": (
        history_text.count("groupColorPanelSquare(") >= 3
        and "GroupColorWell(" in history_text
        and "private func groupColorPanelSquare(" in history_text
        and "private func smallGroupColorPanelSquare(" not in history_text
        and "private func groupColorSwatches(" in history_text
        and "ClipboardGroup.defaultColors" in history_text
        and "GridItem(.adaptive(minimum: 18, maximum: 18), spacing: 8)" in history_text
        and "private func closeGroupColorPanel()" in history_text
        and "GroupColorPanelController.closeSharedColorPanel()" in history_text
        and "closeGroupAppearancePopover()" in history_text
        and "closeSystemGroupAppearancePopover()" in history_text
        and history_text.count("PersistentPopoverPresenter(") >= 2
        and "popover.behavior = .applicationDefined" in persistent_popover_text
        and "func reposition()" in persistent_popover_text
        and "scheduleReposition()" in persistent_popover_text
        and "override func setFrameOrigin" in persistent_popover_text
        and "override func setFrameSize" in persistent_popover_text
        and ".popover(\n                    isPresented" not in history_text
    ),
    "settings appearance picker uses main color square, default swatches, and closes color panel": (
        "GroupColorWell(" in settings_text
        and "private let groupAppearancePopoverWidth: CGFloat = 304" in settings_text
        and "private let groupAppearanceIconGridHeight: CGFloat = 178" in settings_text
        and "LazyVGrid(columns: Array(repeating: GridItem(.fixed(38), spacing: 8), count: 6)" in settings_text
        and ".frame(width: 268, height: groupAppearanceIconGridHeight)" in settings_text
        and "private func groupColorPanelSquare(" in settings_text
        and "private func smallGroupColorPanelSquare(" not in settings_text
        and "private func groupColorSwatches(" in settings_text
        and "ClipboardGroup.defaultColors" in settings_text
        and "GridItem(.adaptive(minimum: 18, maximum: 18), spacing: 8)" in settings_text
        and "private func closeGroupAppearancePicker()" in settings_text
        and "PersistentPopoverPresenter(" in settings_text
        and "popover.behavior = .applicationDefined" in persistent_popover_text
        and ".popover(\n                isPresented" not in settings_text
        and "GroupColorPanelController.closeSharedColorPanel()" in settings_text
        and "GroupColorPanelController.closeSharedColorPanel()" in settings_window_text
    ),
    "history group text inputs keep keyboard editing local": (
        "private struct GroupInlineTextField" in history_text
        and "override func performKeyEquivalent(with event: NSEvent) -> Bool" in history_text
        and "override func keyDown(with event: NSEvent)" in history_text
        and "event.keyCode == 53" in history_text
        and "case \"a\":" in history_text
        and "case \"v\":" in history_text
        and "GroupInlineTextField(\n                text: $groupIconSearchText" in history_text
        and "GroupInlineTextField(\n                        text: $groupRenameText" in history_text
        and "isGroupRenameField: true" in history_text
        and "focusRequestID: groupRenameFocusRequestID" in history_text
        and "context.coordinator.focus(textField)" in history_text
        and "onDoubleMouseDown: { beginRenameGroupAfterCurrentMouseEvent(group) }" in history_text
        and "private func beginRenameGroupAfterCurrentMouseEvent" in history_text
        and "DispatchQueue.main.async" in history_text
        and "GroupRenameOutsideMouseDownObserver(" in history_text
        and "GroupRenameInputFrameReader" in history_text
        and "excludedScreenFrame: groupRenameInputScreenFrame" in history_text
        and "isExcludedScreenFrameHit(event, in: activeHostWindow)" in history_text
        and "private func cancelRenameGroup()" in history_text
        and "handleRenameEscape()" in history_text
        and "inputState.setTextInputFocused(true)" in history_text
    ),
    "history appearance edits are draft until confirmed": (
        "groupAppearanceOriginalColor" in history_text
        and "groupAppearanceOriginalIconName" in history_text
        and "private func commitGroupAppearancePopover" in history_text
        and "private func commitSystemGroupAppearancePopover" in history_text
        and "store.updateGroupAppearance(" in history_text
        and "updateSystemGroupAppearance(" in history_text
        and "handleGroupIconSearchEscape()" in history_text
        and "NSColorPanel.shared.isVisible" in panel_controller_text
        and "closeGroupColorPanel()" in history_text
    ),
    "settings group name and icon search fields request focus on first click": (
        "focusedSettingsGroupNameID" in settings_text
        and "editingSettingsGroupNames" in settings_text
        and "SettingsTextField(\n                text: Binding(" in settings_text
        and "focusedID: $focusedSettingsGroupNameID" in settings_text
        and "onCommit: { name in" in settings_text
        and "commitSettingsGroupName(group.id, name: name)" in settings_text
        and "SettingsTextField(\n                text: $groupIconSearchText" in settings_text
        and "List(selection: $groupSelection)" not in settings_text
        and "toggleGroupSelection(group.id)" in settings_text
        and "override func mouseDown(with event: NSEvent)" in settings_text
        and "coordinator?.focus(self)" in settings_text
        and "textField.window?.makeFirstResponder(textField)" in settings_text
        and "func controlTextDidChange(_ notification: Notification)" in settings_text
        and "parent.onCommit?(textField.stringValue)" in settings_text
        and "parent.onCommit?(sender.stringValue)" in settings_text
    ),
    "settings retention and login item changes show detailed global status": (
        "showStatus(\"保存期限已改为：\\(policy.title)\")" in settings_text
        and "loginItemStatusMessage(requestedEnabled: enabled)" in settings_text
        and "开机自启动已开启，登录 macOS 后会自动打开轻贴" in settings_text
        and "开机自启动已关闭，登录 macOS 后不会自动打开轻贴" in settings_text
    ),
}

failed = [name for name, passed in checks.items() if not passed]
if failed:
    for name in failed:
        print(f"FAIL: {name}")
    raise SystemExit(1)

for name in checks:
    print(f"PASS: {name}")
