import AppKit
import ApplicationServices

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

    func pasteToFrontmostApp(_ item: ClipboardItem) -> PasteResult {
        copyToPasteboard(item)

        guard AXIsProcessTrusted() else {
            return .copiedOnly
        }

        sendCommandV()
        return .pasted
    }

    private func sendCommandV() {
        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(
            keyboardEventSource: source,
            virtualKey: KeyCode.v,
            keyDown: true
        )
        let keyUp = CGEvent(
            keyboardEventSource: source,
            virtualKey: KeyCode.v,
            keyDown: false
        )

        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}

enum PasteResult {
    case copiedOnly
    case pasted
}
