import Foundation

struct HistoryKeyboardActionRouter {
    func actionForTextInput(
        keyCode: UInt16,
        hasTextEditingModifier: Bool,
        isShiftPressed: Bool,
        cursorIsAtEnd: Bool
    ) -> HistoryKeyboardAction? {
        HistoryKeyboardInputPolicy.actionForTextInput(
            keyCode: keyCode,
            hasTextEditingModifier: hasTextEditingModifier,
            isShiftPressed: isShiftPressed,
            cursorIsAtEnd: cursorIsAtEnd
        )
    }

    func allowsHistoryCommand(
        _ action: HistoryKeyboardAction,
        isTextInputActive: Bool,
        isPreviewContentActive: Bool
    ) -> Bool {
        HistoryKeyboardShortcutPolicy.allowsHistoryCommand(
            action,
            isTextInputActive: isTextInputActive,
            isPreviewContentActive: isPreviewContentActive
        )
    }

    func shouldTogglePreviewFromPanelSpace(
        isHistoryTextInputActive: Bool,
        isPreviewActive: Bool
    ) -> Bool {
        HistoryPanelSpaceKeyPolicy.shouldTogglePreview(
            isHistoryTextInputActive: isHistoryTextInputActive,
            isPreviewActive: isPreviewActive
        )
    }
}

