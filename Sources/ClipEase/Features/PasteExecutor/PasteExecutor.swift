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

    func copyToPasteboard(_ item: ClipboardItem) -> PasteboardCopyResult {
        pasteboard.clearContents()

        switch item.type {
        case .text, .link, .color:
            if let richTextData = store.richTextData(for: item) {
                pasteboard.setData(richTextData, forType: .rtf)
            }
            guard pasteboard.setString(item.text, forType: .string) else {
                return .failed("无法写入剪贴板")
            }
            store.skipNextClipboardText(item.text)
            return .copied
        case .image:
            guard let data = store.imageData(for: item) else {
                return .failed("未找到图片文件")
            }

            guard let image = NSImage(data: data) else {
                return .failed("图片文件无法读取")
            }

            guard pasteboard.writeObjects([image]) else {
                return .failed("无法写入图片到剪贴板")
            }
            store.skipNextClipboardImage(item)
            return .copied
        }
    }

    func copyPlainTextToPasteboard(_ item: ClipboardItem) -> PasteboardCopyResult {
        pasteboard.clearContents()
        guard pasteboard.setString(item.text, forType: .string) else {
            return .failed("无法写入剪贴板")
        }
        store.skipNextClipboardText(item.text)
        return .copied
    }

    func pastePlainTextToFrontmostApp(_ item: ClipboardItem) -> PasteResult {
        switch copyPlainTextToPasteboard(item) {
        case .copied:
            break
        case .failed(let reason):
            return .failed(reason)
        }

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
        switch copyToPasteboard(item) {
        case .copied:
            break
        case .failed(let reason):
            return .failed(reason)
        }

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

enum PasteboardCopyResult {
    case copied
    case failed(String)
}

enum PasteResult {
    case copiedOnly
    case pasted
    case failed(String)
}
