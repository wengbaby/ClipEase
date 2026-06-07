import AppKit
import ApplicationServices

@MainActor
final class PasteExecutor {
    private let pasteboard: NSPasteboard
    private let store: ClipboardHistoryStore
    private let permissionState: AccessibilityPermissionState
    private let soundPlayer: ClipEaseSoundPlayer
    var beforeAutoPaste: (() -> Void)?

    init(
        store: ClipboardHistoryStore,
        permissionState: AccessibilityPermissionState,
        pasteboard: NSPasteboard = .general,
        soundPlayer: ClipEaseSoundPlayer = .shared
    ) {
        self.store = store
        self.permissionState = permissionState
        self.pasteboard = pasteboard
        self.soundPlayer = soundPlayer
    }

    var canAutoPaste: Bool {
        permissionState.isTrusted
    }

    private var clipboardWriter: ClipboardWriteCoordinator {
        ClipboardWriteCoordinator(
            pasteboard: pasteboard,
            skipText: store.skipNextClipboardText,
            skipImage: store.skipNextClipboardImage,
            skipImageHash: store.skipNextClipboardImageHash,
            skipFiles: store.skipNextClipboardFiles
        )
    }

    func refreshAccessibilityPermission(promptIfNeeded: Bool = false) -> Bool {
        permissionState.refresh(promptIfNeeded: promptIfNeeded)
    }

    func openAccessibilitySettings() {
        permissionState.openSystemSettings()
    }

    func copyToPasteboard(_ item: ClipboardItem) -> PasteboardCopyResult {
        switch item.type {
        case .text, .link, .color:
            let text = pasteboardString(for: item)
            guard clipboardWriter.writeText(
                text,
                richTextData: store.richTextData(for: item)
            ) else {
                return .failed("无法写入剪贴板")
            }
            return .copied
        case .file:
            let fileURLs = validLocalFileURLs(for: item)
            if !fileURLs.isEmpty {
                guard clipboardWriter.writeFileURLs(fileURLs) else {
                    return .failed("无法写入文件引用到剪贴板")
                }
                return .copied
            }

            guard let fallbackText = fileFallbackText(for: item) else {
                return .failed("未找到文件")
            }

            guard clipboardWriter.writeText(fallbackText) else {
                return .failed("无法写入文件路径到剪贴板")
            }
            return .copiedFallbackText
        case .image:
            guard let data = store.imageData(for: item) else {
                return .failed("未找到图片文件")
            }

            guard let image = NSImage(data: data) else {
                return .failed("图片文件无法读取")
            }

            guard clipboardWriter.writeImage(image, item: item) else {
                return .failed("无法写入图片到剪贴板")
            }
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
        let text = pasteboardString(for: item)
        guard clipboardWriter.writeText(text) else {
            return .failed("无法写入剪贴板")
        }
        return .copied
    }

    func copyTextToPasteboard(_ text: String) -> PasteboardCopyResult {
        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedText.isEmpty else {
            return .failed("没有可复制的文本")
        }

        guard clipboardWriter.writeText(normalizedText) else {
            return .failed("无法写入剪贴板")
        }
        return .copied
    }

    func copyImageToPasteboard(_ image: NSImage, skipText: String?) -> PasteboardCopyResult {
        if let skipText {
            store.skipNextClipboardText(skipText)
        }
        let imageHash = StoredClipboardImage.hash(for: image)
        guard clipboardWriter.writeImage(image, imageHash: imageHash) else {
            return .failed("无法写入图片到剪贴板")
        }
        return .copied
    }

    func copyFileURLToPasteboard(_ url: URL) -> PasteboardCopyResult {
        guard clipboardWriter.writeFileURLs([url]) else {
            return .failed("无法写入文件引用到剪贴板")
        }
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
            soundPlayer.playCopyFeedback()
            return .copiedOnly
        }

        beforeAutoPaste?()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 120_000_000)
            sendCommandV()
            soundPlayer.playPasteFeedback()
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
            soundPlayer.playCopyFeedback()
            return copiedFallbackText ? .copiedFallbackTextOnly : .copiedOnly
        }

        beforeAutoPaste?()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 120_000_000)
            sendCommandV()
            soundPlayer.playPasteFeedback()
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
