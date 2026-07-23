import AppKit

struct ClipboardPasteboardWriteBackend {
    let changeCount: @MainActor () -> Int
    let clearContents: @MainActor () -> Bool
    let setData: @MainActor (Data, NSPasteboard.PasteboardType) -> Bool
    let setString: @MainActor (String, NSPasteboard.PasteboardType) -> Bool
    let writeImage: @MainActor (NSImage) -> Bool
    let writeFileURLs: @MainActor ([URL]) -> Bool
    let imageWriteReceiptAfterWrite: @MainActor () -> ClipboardImageWriteReceipt?

    init(
        changeCount: @escaping @MainActor () -> Int,
        clearContents: @escaping @MainActor () -> Bool,
        setData: @escaping @MainActor (Data, NSPasteboard.PasteboardType) -> Bool,
        setString: @escaping @MainActor (String, NSPasteboard.PasteboardType) -> Bool,
        writeImage: @escaping @MainActor (NSImage) -> Bool,
        writeFileURLs: @escaping @MainActor ([URL]) -> Bool,
        imageWriteReceiptAfterWrite: @escaping @MainActor () -> ClipboardImageWriteReceipt? = { nil }
    ) {
        self.changeCount = changeCount
        self.clearContents = clearContents
        self.setData = setData
        self.setString = setString
        self.writeImage = writeImage
        self.writeFileURLs = writeFileURLs
        self.imageWriteReceiptAfterWrite = imageWriteReceiptAfterWrite
    }

    @MainActor
    static func live(_ pasteboard: NSPasteboard) -> ClipboardPasteboardWriteBackend {
        ClipboardPasteboardWriteBackend(
            changeCount: { pasteboard.changeCount },
            clearContents: {
                pasteboard.clearContents()
                return true
            },
            setData: { pasteboard.setData($0, forType: $1) },
            setString: { pasteboard.setString($0, forType: $1) },
            writeImage: { pasteboard.writeObjects([$0]) },
            writeFileURLs: { urls in
                pasteboard.writeObjects(urls.map { $0 as NSURL })
            },
            imageWriteReceiptAfterWrite: {
                ClipboardImageWriteReceipt.capture(
                    changeCount: { pasteboard.changeCount },
                    availableTypeIdentifiers: {
                        pasteboard.types?.map(\.rawValue) ?? []
                    },
                    dataForTypeIdentifier: { typeIdentifier in
                        pasteboard.data(
                            forType: NSPasteboard.PasteboardType(typeIdentifier)
                        )
                    }
                )
            }
        )
    }
}

enum PasteboardWriter {
    typealias SelfWriteRegistration = (Int, ClipboardSelfWritePayload) -> Void
    typealias PendingImageSelfWriteRegistration = (
        Int,
        ClipboardEncodedImagePayload
    ) -> Void

    @discardableResult
    @MainActor
    static func writeText(
        _ text: String,
        to pasteboard: NSPasteboard = .general,
        richTextData: Data? = nil,
        registerSelfWrite: @escaping SelfWriteRegistration = { _, _ in }
    ) -> Bool {
        writeText(
            text,
            backend: .live(pasteboard),
            richTextData: richTextData,
            registerSelfWrite: registerSelfWrite
        )
    }

    @discardableResult
    @MainActor
    static func writeText(
        _ text: String,
        backend: ClipboardPasteboardWriteBackend,
        richTextData: Data? = nil,
        registerSelfWrite: @escaping SelfWriteRegistration = { _, _ in }
    ) -> Bool {
        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedText.isEmpty,
              backend.clearContents() else {
            return false
        }

        let richTextSucceeded: Bool
        if let richTextData {
            richTextSucceeded = backend.setData(richTextData, .rtf)
        } else {
            richTextSucceeded = true
        }
        let plainTextSucceeded = backend.setString(normalizedText, .string)
        guard richTextSucceeded, plainTextSucceeded else {
            _ = backend.clearContents()
            return false
        }

        let payload: ClipboardSelfWritePayload = richTextData == nil
            ? .text(normalizedText)
            : .richText(normalizedText)
        registerSelfWrite(backend.changeCount(), payload)
        return true
    }
}
