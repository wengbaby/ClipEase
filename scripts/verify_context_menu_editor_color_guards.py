#!/usr/bin/env python3
from pathlib import Path

root = Path(__file__).resolve().parents[1]
view = root / "Sources/ClipEase/Features/HistoryWindow/HistoryWindowView.swift"
editor = root / "Sources/ClipEase/Features/RichTextEditor/RichTextEditorController.swift"
monitor = root / "Sources/ClipEase/Features/ClipboardMonitor/ClipboardMonitor.swift"
store = root / "Sources/ClipEase/Core/Storage/ClipboardHistoryStore.swift"

view_text = view.read_text(encoding="utf-8")
editor_text = editor.read_text(encoding="utf-8")
monitor_text = monitor.read_text(encoding="utf-8")
store_text = store.read_text(encoding="utf-8")

checks = {
    "context menu edit opens independent editor and hides history window": (
        "appMenuController.editItem(item)" in view_text
        and "onClose()" in view_text.split("private func beginEditItem", 1)[1].split("private func togglePreviewForSelectedItem", 1)[0]
        and "if editTargetID != nil" not in view_text.split("private func closePresentedLayers", 1)[1].split("private func createTextFromShortcut", 1)[0]
    ),
    "context menu open/copy actions close history window": (
        "private func closeAfterContextMenuCommand()" in view_text
        and view_text.count("closeAfterContextMenuCommand()") >= 12
    ),
    "hex rich text clipboard becomes color card": (
        "private func shouldCaptureRichTextAsPlainText(_ text: String) -> Bool" in monitor_text
        and "ColorParser.hexColor(from: text) != nil" in monitor_text
        and "self.shouldCaptureRichTextAsPlainText(result.plainText)" in monitor_text
        and "self.store.addText(result.plainText, sourceApp: sourceApp)" in monitor_text
    ),
    "color editor has color well and hex/rgb readouts": (
        "private let colorWell: NSColorWell" in editor_text
        and "private func makeColorEditorView() -> NSView?" in editor_text
        and "@objc private func colorWellChanged()" in editor_text
        and "hexColorLabel.stringValue = \"HEX \\(hex)\"" in editor_text
        and "rgbColorLabel.stringValue = \"RGB \\(rgbString(from: color))\"" in editor_text
    ),
    "editor supports command shortcuts and escape close": (
        "override func performKeyEquivalent(with event: NSEvent) -> Bool" in editor_text
        and "case \"a\":" in editor_text
        and "case \"c\":" in editor_text
        and "case \"v\":" in editor_text
        and "case \"z\":" in editor_text
        and "case \"s\":" in editor_text
        and "event.keyCode == 53" in editor_text
        and "onEscape?()" in editor_text
    ),
    "rich text editor is independent app window": (
        "private final class RichTextEditorWindow: NSWindow" in editor_text
        and "styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]" in editor_text
        and "panel.hidesOnDeactivate = false" in editor_text
        and "panel.collectionBehavior = [.managed, .moveToActiveSpace]" in editor_text
        and "RichTextEditorPanel" not in editor_text
    ),
    "rich text selection syncs toolbar state": (
        "func textViewDidChangeSelection(_ notification: Notification)" in editor_text
        and "syncStyleStateFromSelection()" in editor_text
        and "private func representativeTypingAttributes()" in editor_text
        and "refreshStyleButtonsOnly()" in editor_text
        and "NSFontManager.shared.traits(of: font)" in editor_text
    ),
    "rich text editor toolbar uses right-side cancel and common actions": (
        "contentRect: NSRect(x: 0, y: 0, width: 680, height: 440)" in editor_text
        and "toolbar.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: 78)" in editor_text
        and "trailingGroup.addArrangedSubview(createButton)" in editor_text
        and "trailingGroup.addArrangedSubview(plainTextButton)" in editor_text
        and "trailingGroup.addArrangedSubview(cancelButton)" in editor_text
        and "toolbar.addView(titleLabel, in: .leading)" in editor_text
        and "toolbar.addView(cancelButton, in: .leading)" not in editor_text
        and "clearFormattingAction" in editor_text
        and "configureFontSizePopUpButton" in editor_text
    ),
    "rich text editor prevents accidental close loss": (
        "func windowShouldClose(_ sender: NSWindow) -> Bool" in editor_text
        and "private var hasUnsavedChanges: Bool" in editor_text
        and "private func requestCloseEditor()" in editor_text
        and "保存更改？" in editor_text
        and "alert.beginSheetModal(for: panel)" in editor_text
    ),
    "rich text editor supports command formatting shortcuts": (
        "var onCommandB" in editor_text
        and "var onCommandI" in editor_text
        and "var onCommandU" in editor_text
        and "case \"b\":" in editor_text
        and "case \"i\":" in editor_text
        and "case \"u\":" in editor_text
    ),
    "rich text editor preserves selection for toolbar formatting": (
        "private var lastKnownSelectedRange" in editor_text
        and "restoreLastSelectionIfNeeded()" in editor_text
        and "if selectedRange.length > 0" in editor_text
        and "textView.setSelectedRange(lastKnownSelectedRange)" in editor_text
        and "button.refusesFirstResponder = true" in editor_text
        and "applyToSelection { text, range in" in editor_text
    ),
    "multiple card editors are allowed": (
        "editTargetID" not in view_text
        and "resetEditState" not in view_text
        and "richTextEditorControllers.append(editorController)" in (root / "Sources/ClipEase/App/AppMenuController.swift").read_text(encoding="utf-8")
    ),
    "plain text save can downgrade rich text card": (
        "guard !normalizedText.isEmpty else" in store_text
        and "items[index] = item.updatingEditableContent(text: normalizedText)" in store_text
        and "persistence.deleteRichText(fileName: richTextFileName)" in store_text
    ),
    "color editor closes system color panel after save or discard": (
        "private func closeColorPanelIfNeeded()" in editor_text
        and "colorWell.deactivate()" in editor_text
        and "NSColorPanel.shared.close()" in editor_text
    ),
    "rich text editor detects italic and save refocuses card": (
        "font.fontDescriptor.symbolicTraits" in editor_text
        and "symbolicTraits.contains(.bold)" in editor_text
        and "symbolicTraits.contains(.italic)" in editor_text
        and "setting: .bold" in editor_text
        and "setting: .italic" in editor_text
        and "fallbackSystemFont" in editor_text
        and "self.font(convertedFont, has: trait) == enabled" in editor_text
        and "self.font(managerFont, has: trait) == enabled" in editor_text
        and "items[index].createdAt = Date()" in store_text
        and "latestItemFocusRequest = ClipboardItemFocusRequest(itemID: updatedItem.id, reason: .refreshed)" in store_text
    ),
    "text card rich text edit preserves formatting and can upgrade plain text": (
        "if item.type == .text {\n            commitRichTextEdit(item: item, plainText: plainText)" in editor_text
        and "guard item.type == .text,\n              !normalizedText.isEmpty else" in store_text
        and "richTextFileName: storedRichText.fileName" in store_text
        and "let storedRichText = try persistence.saveRichTextOrThrow(data)" in store_text
    ),
}

failed = [name for name, passed in checks.items() if not passed]
if failed:
    for name in failed:
        print(f"FAIL: {name}")
    raise SystemExit(1)

for name in checks:
    print(f"PASS: {name}")
