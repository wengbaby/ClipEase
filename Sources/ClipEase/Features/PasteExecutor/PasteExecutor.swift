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
            guard pasteboard.setString(pasteboardString(for: item), forType: .string) else {
                return .failed("无法写入剪贴板")
            }
            store.addText(pasteboardString(for: item), sourceApp: .clipease)
            return .copied
        case .file:
            let fileURLs = validLocalFileURLs(for: item)
            if !fileURLs.isEmpty {
                guard pasteboard.writeObjects(fileURLs.map { $0 as NSURL }) else {
                    return .failed("无法写入文件引用到剪贴板")
                }
                store.addFiles(fileURLs, sourceApp: .clipease)
                return .copied
            }

            guard let fallbackText = fileFallbackText(for: item) else {
                return .failed("未找到文件")
            }

            guard pasteboard.setString(fallbackText, forType: .string) else {
                return .failed("无法写入文件路径到剪贴板")
            }
            store.addText(fallbackText, sourceApp: .clipease)
            return .copiedFallbackText
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
            store.addImage(image, sourceApp: .clipease)
            return .copied
        }
    }

    private func pasteboardString(for item: ClipboardItem) -> String {
        guard item.type == .file,
              !item.fileReferences.isEmpty else {
            return item.text
        }

        return item.fileReferences
            .map { reference in
                let path = reference.path.trimmingCharacters(in: .whitespacesAndNewlines)
                if !path.isEmpty {
                    return path
                }
                return reference.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .joined(separator: "\n")
    }

    private func fileFallbackText(for item: ClipboardItem) -> String? {
        let referenceText = item.fileReferences
            .map { reference in
                let path = reference.path.trimmingCharacters(in: .whitespacesAndNewlines)
                if !path.isEmpty {
                    return path
                }
                return reference.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

        if !referenceText.isEmpty {
            return referenceText
        }

        let itemText = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return itemText.isEmpty ? nil : itemText
    }

    private func validLocalFileURLs(for item: ClipboardItem) -> [URL] {
        guard item.type == .file else {
            return []
        }

        return item.fileReferences.compactMap { reference in
            let path = reference.path.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !path.isEmpty else {
                return nil
            }

            let url = URL(fileURLWithPath: path).standardizedFileURL
            guard url.isFileURL,
                  FileManager.default.fileExists(atPath: url.path) else {
                return nil
            }

            return url
        }
    }

    func copyPlainTextToPasteboard(_ item: ClipboardItem) -> PasteboardCopyResult {
        pasteboard.clearContents()
        guard pasteboard.setString(pasteboardString(for: item), forType: .string) else {
            return .failed("无法写入剪贴板")
        }
        store.addText(pasteboardString(for: item), sourceApp: .clipease)
        return .copied
    }

    func pastePlainTextToFrontmostApp(_ item: ClipboardItem) -> PasteResult {
        switch copyPlainTextToPasteboard(item) {
        case .copied, .copiedFallbackText:
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
        let copiedFallbackText: Bool
        switch copyToPasteboard(item) {
        case .copied:
            copiedFallbackText = false
        case .copiedFallbackText:
            copiedFallbackText = true
        case .failed(let reason):
            return .failed(reason)
        }

        guard refreshAccessibilityPermission() else {
            return copiedFallbackText ? .copiedFallbackTextOnly : .copiedOnly
        }

        beforeAutoPaste?()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 120_000_000)
            sendCommandV()
        }
        return copiedFallbackText ? .pastedFallbackText : .pasted
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
    case copiedFallbackText
    case failed(String)
}

enum PasteResult {
    case copiedOnly
    case copiedFallbackTextOnly
    case pasted
    case pastedFallbackText
    case failed(String)
}
