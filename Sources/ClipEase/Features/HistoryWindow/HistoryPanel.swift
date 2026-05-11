import AppKit

@MainActor
final class HistoryPanel: NSPanel {
    var onEscape: (() -> Void)?

    override var canBecomeKey: Bool {
        false
    }

    override var canBecomeMain: Bool {
        false
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == KeyCode.escape {
            onEscape?()
            return
        }

        super.keyDown(with: event)
    }
}
