import AppKit
import ApplicationServices

@MainActor
final class PasteExecutor {
    private let pasteboard: NSPasteboard
    private let store: ClipboardHistoryStore
    private let permissionState: AccessibilityPermissionState
    var beforeAutoPaste: (() -> Void)?

    init(
        store: ClipboardHistoryStore,
        permissionState: AccessibilityPermissionState,
        pasteboard: NSPasteboard = .general
    ) {
        self.store = store
        self.permissionState = permissionState
        self.pasteboard = pasteboard
    }

    var canAutoPaste: Bool {
        permissionState.isTrusted
    }

    func refreshAccessibilityPermission(promptIfNeeded: Bool = false) -> Bool {
        permissionState.refresh(promptIfNeeded: promptIfNeeded)
    }

    func openAccessibilitySettings() {
        permissionState.openSystemSettings()
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

    func copyPlainTextToPasteboard(_ item: ClipboardItem) {
        pasteboard.clearContents()
        pasteboard.setString(item.text, forType: .string)
        store.skipNextClipboardText(item.text)
    }

    func pastePlainTextToFrontmostApp(_ item: ClipboardItem) -> PasteResult {
        copyPlainTextToPasteboard(item)

        guard refreshAccessibilityPermission() else {
            return .copiedOnly
        }

        beforeAutoPaste?()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 120_000_000)
            sendCommandV()
        }
        return .pasted
    }

    func pasteToFrontmostApp(_ item: ClipboardItem) -> PasteResult {
        copyToPasteboard(item)

        guard refreshAccessibilityPermission() else {
            return .copiedOnly
        }

        beforeAutoPaste?()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 120_000_000)
            sendCommandV()
        }
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
