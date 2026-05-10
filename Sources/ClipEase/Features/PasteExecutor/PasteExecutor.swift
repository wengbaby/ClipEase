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

    var canAutoPaste: Bool {
        AXIsProcessTrusted()
    }

    func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    func copyToPasteboard(_ item: ClipboardItem) {
        pasteboard.clearContents()

        switch item.type {
        case .text, .link, .color:
            if let richTextData = store.richTextData(for: item) {
                pasteboard.setData(richTextData, forType: .rtf)
            }
            pasteboard.setString(item.text, forType: .string)
            store.skipNextClipboardText(item.text)
        case .image:
            guard let data = store.imageData(for: item),
                  let image = NSImage(data: data) else {
                return
            }

            pasteboard.writeObjects([image])
            store.skipNextClipboardImage(item)
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
