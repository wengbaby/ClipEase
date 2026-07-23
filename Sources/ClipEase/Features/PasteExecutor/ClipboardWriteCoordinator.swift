import AppKit

struct ClipboardWriteCoordinator {
    private let backend: ClipboardPasteboardWriteBackend
    private let registerSelfWrite: PasteboardWriter.SelfWriteRegistration
    private let registerPendingImageSelfWrite: PasteboardWriter.PendingImageSelfWriteRegistration

    @MainActor
    init(
        pasteboard: NSPasteboard,
        registerSelfWrite: @escaping PasteboardWriter.SelfWriteRegistration = { _, _ in },
        registerPendingImageSelfWrite: @escaping PasteboardWriter.PendingImageSelfWriteRegistration = { _, _ in }
    ) {
        self.init(
            backend: .live(pasteboard),
            registerSelfWrite: registerSelfWrite,
            registerPendingImageSelfWrite: registerPendingImageSelfWrite
        )
    }

    init(
        backend: ClipboardPasteboardWriteBackend,
        registerSelfWrite: @escaping PasteboardWriter.SelfWriteRegistration = { _, _ in },
        registerPendingImageSelfWrite: @escaping PasteboardWriter.PendingImageSelfWriteRegistration = { _, _ in }
    ) {
        self.backend = backend
        self.registerSelfWrite = registerSelfWrite
        self.registerPendingImageSelfWrite = registerPendingImageSelfWrite
    }

    @discardableResult
    @MainActor
    func writeText(_ text: String, richTextData: Data? = nil) -> Bool {
        PasteboardWriter.writeText(
            text,
            backend: backend,
            richTextData: richTextData,
            registerSelfWrite: registerSelfWrite
        )
    }

    @discardableResult
    @MainActor
    func writeFileURLs(_ urls: [URL]) -> Bool {
        guard !urls.isEmpty,
              backend.clearContents(),
              backend.writeFileURLs(urls) else {
            return false
        }

        registerSelfWrite(backend.changeCount(), .files(urls))
        return true
    }

    @discardableResult
    @MainActor
    func writeImage(_ image: NSImage, item _: ClipboardItem) -> Bool {
        writeImage(image, imageHash: nil)
    }

    @discardableResult
    @MainActor
    func writeImage(
        _ image: NSImage,
        imageHash _: String?,
        supplementalText: String? = nil
    ) -> Bool {
        guard backend.clearContents(),
              backend.writeImage(image) else {
            return false
        }

        if let receipt = backend.imageWriteReceiptAfterWrite() {
            if let supplementalText {
                registerSelfWrite(receipt.changeCount, .text(supplementalText))
            }
            registerPendingImageSelfWrite(
                receipt.changeCount,
                receipt.payload
            )
        } else if let supplementalText {
            registerSelfWrite(backend.changeCount(), .text(supplementalText))
        }
        return true
    }
}

extension ClipboardWriteCoordinator {
    @MainActor
    static func generalTextWriter(
        registerSelfWrite: @escaping PasteboardWriter.SelfWriteRegistration = { _, _ in }
    ) -> ClipboardWriteCoordinator {
        ClipboardWriteCoordinator(
            pasteboard: .general,
            registerSelfWrite: registerSelfWrite
        )
    }
}
