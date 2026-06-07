import AppKit

struct ClipboardWriteCoordinator {
    let pasteboard: NSPasteboard
    let skipText: (String) -> Void
    let skipImage: (ClipboardItem) -> Void
    let skipImageHash: (String) -> Void
    let skipFiles: ([URL]) -> Void

    @discardableResult
    func writeText(_ text: String, richTextData: Data? = nil) -> Bool {
        PasteboardWriter.writeText(
            text,
            to: pasteboard,
            richTextData: richTextData,
            skipRecording: skipText
        )
    }

    @discardableResult
    func writeFileURLs(_ urls: [URL]) -> Bool {
        guard !urls.isEmpty else {
            return false
        }

        skipFiles(urls)
        pasteboard.clearContents()
        return pasteboard.writeObjects(urls.map { $0 as NSURL })
    }

    @discardableResult
    func writeImage(_ image: NSImage, item: ClipboardItem) -> Bool {
        skipImage(item)
        pasteboard.clearContents()
        return pasteboard.writeObjects([image])
    }

    @discardableResult
    func writeImage(_ image: NSImage, imageHash: String?) -> Bool {
        if let imageHash {
            skipImageHash(imageHash)
        }
        pasteboard.clearContents()
        return pasteboard.writeObjects([image])
    }
}

extension ClipboardWriteCoordinator {
    static func generalTextWriter(skipText: @escaping (String) -> Void = { _ in }) -> ClipboardWriteCoordinator {
        ClipboardWriteCoordinator(
            pasteboard: .general,
            skipText: skipText,
            skipImage: { _ in },
            skipImageHash: { _ in },
            skipFiles: { _ in }
        )
    }
}
