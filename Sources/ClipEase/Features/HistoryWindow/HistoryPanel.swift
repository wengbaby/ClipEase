import AppKit

@MainActor
final class HistoryPanel: NSPanel {
    var onEscape: (() -> Void)?
    var onSpace: (() -> Bool)?

    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == KeyCode.space,
           onSpace?() == true {
            return
        }

        if event.keyCode == KeyCode.escape {
            onEscape?()
            return
        }

        super.keyDown(with: event)
    }
}
