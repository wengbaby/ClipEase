import AppKit

@MainActor
final class HistoryPanel: NSPanel {
    var onEscape: (() -> Void)?
    var allowsKeyboardFocus = false

    override var canBecomeKey: Bool {
        allowsKeyboardFocus
    }

    override var canBecomeMain: Bool {
        allowsKeyboardFocus
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == KeyCode.escape {
            onEscape?()
            return
        }

        super.keyDown(with: event)
    }
}
