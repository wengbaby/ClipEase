import AppKit

@MainActor
final class HistoryPanel: NSPanel {
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        true
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == KeyCode.escape {
            orderOut(nil)
            return
        }

        super.keyDown(with: event)
    }
}
