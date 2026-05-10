import AppKit

@MainActor
final class PasteExecutor {
    private let pasteboard: NSPasteboard
    private let store: ClipboardHistoryStore

    init(
        store: ClipboardHistoryStore,
        pasteboard: NSPasteboard = .general
    ) {
        self.store = store
        self.pasteboard = pasteboard
    }

    func copyToPasteboard(_ item: ClipboardItem) {
        pasteboard.clearContents()

        switch item.type {
        case .text, .link, .color:
            pasteboard.setString(item.text, forType: .string)
            store.skipNextClipboardText(item.text)
        case .image:
            break
        }
    }
}

