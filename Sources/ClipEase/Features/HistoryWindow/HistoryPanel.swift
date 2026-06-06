import AppKit

@MainActor
final class HistoryPanel: NSPanel {
    var onEscape: (() -> Void)?
    var onSpace: (() -> Bool)?
    var onDelete: (() -> Void)?
    var onSearchText: ((String) -> Void)?
    var onTextFirstResponderChanged: ((Bool) -> Void)?

    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }

    override func keyDown(with event: NSEvent) {
        let isTextFirstResponderActive = firstResponder is NSTextView
        onTextFirstResponderChanged?(isTextFirstResponderActive)

        if isTextFirstResponderActive {
            super.keyDown(with: event)
            return
        }

        if event.keyCode == KeyCode.space,
           onSpace?() == true {
            return
        }

        if event.keyCode == KeyCode.escape {
            onEscape?()
            return
        }

        if event.keyCode == KeyCode.delete {
            onDelete?()
            return
        }

        if let searchText = HistoryKeyboardCharacterPolicy.searchText(from: event.characters) {
            onSearchText?(searchText)
            return
        }

        super.keyDown(with: event)
    }
}
