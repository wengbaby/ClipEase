import AppKit
import Foundation

@MainActor
final class ClipboardMonitor {
    private static let filenamesPasteboardType = NSPasteboard.PasteboardType("NSFilenamesPboardType")
    private static let publicFileURLPasteboardType = NSPasteboard.PasteboardType("public.file-url")
    private static let fileURLPromisePasteboardType = NSPasteboard.PasteboardType("com.apple.pasteboard.promised-file-url")
    private static let filePromiseContentPasteboardType = NSPasteboard.PasteboardType("com.apple.pasteboard.promised-file-content-type")
    private static let filePromiseMetadataPasteboardType = NSPasteboard.PasteboardType("com.apple.NSFilePromiseItemMetaData")

    private let pasteboard: NSPasteboard
    private let store: ClipboardHistoryStore
    private let recordingController: RecordingController
    private let ignoredAppSettings: IgnoredAppSettings
    private var timer: Timer?
    private var lastChangeCount: Int

    init(
        store: ClipboardHistoryStore,
        recordingController: RecordingController,
        ignoredAppSettings: IgnoredAppSettings,
        pasteboard: NSPasteboard = .general
    ) {
        self.store = store
        self.recordingController = recordingController
        self.ignoredAppSettings = ignoredAppSettings
        self.pasteboard = pasteboard
        self.lastChangeCount = pasteboard.changeCount
    }

    func start() {
        guard timer == nil else {
            return
        }

        timer = Timer.scheduledTimer(
            withTimeInterval: 0.75,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                self?.poll()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        guard pasteboard.changeCount != lastChangeCount else {
            return
        }

        lastChangeCount = pasteboard.changeCount
        guard !recordingController.isPaused else {
            return
        }

        let sourceApp = monitoredSourceApp
        guard !ignoredAppSettings.contains(bundleID: sourceApp.bundleID) else {
            return
        }

        let fileURLs = localFileURLsFromPasteboard()
        if !fileURLs.isEmpty {
            guard !store.consumeSkippedClipboardFiles(fileURLs) else {
                return
            }

            store.addFiles(fileURLs, sourceApp: sourceApp)
            return
        }

        if let richText = rtfRichTextFromPasteboard() {
            if ColorParser.hexColor(from: richText.plainText) != nil {
                store.addText(richText.plainText, sourceApp: sourceApp)
                return
            }

            store.addRichText(
                richText.data,
                plainText: richText.plainText,
                sourceApp: sourceApp
            )
            return
        }

        if let image = pasteboard.readObjects(
            forClasses: [NSImage.self],
            options: nil
        )?.first as? NSImage {
            store.addImage(image, sourceApp: sourceApp)
            return
        }

        if let richText = htmlRichTextFromPasteboard() {
            if ColorParser.hexColor(from: richText.plainText) != nil {
                store.addText(richText.plainText, sourceApp: sourceApp)
                return
            }

            store.addRichText(
                richText.data,
                plainText: richText.plainText,
                sourceApp: sourceApp
            )
            return
        }

        if let text = pasteboard.string(forType: .string) {
            store.addText(text, sourceApp: sourceApp)
        }
    }

    private func rtfRichTextFromPasteboard() -> (data: Data, plainText: String)? {
        guard let rtfData = pasteboard.data(forType: .rtf),
              let plainText = plainTextForRichTextData(
            rtfData,
            documentType: .rtf
           ) ?? pasteboard.string(forType: .string),
              !plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        return (rtfData, plainText)
    }

    private func htmlRichTextFromPasteboard() -> (data: Data, plainText: String)? {
        guard let htmlData = pasteboard.data(forType: .html),
              let attributedString = attributedString(
                from: htmlData,
                documentType: .html
              ) else {
            return nil
        }

        let plainText = attributedString.string
        guard !plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let rtfData = try? attributedString.data(
                from: NSRange(location: 0, length: attributedString.length),
                documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
              ) else {
            return nil
        }

        return (rtfData, plainText)
    }

    private func plainTextForRichTextData(
        _ data: Data,
        documentType: NSAttributedString.DocumentType
    ) -> String? {
        attributedString(from: data, documentType: documentType)?.string
    }

    private func attributedString(
        from data: Data,
        documentType: NSAttributedString.DocumentType
    ) -> NSAttributedString? {
        try? NSAttributedString(
            data: data,
            options: [.documentType: documentType],
            documentAttributes: nil
        )
    }

    private func localFileURLsFromPasteboard() -> [URL] {
        guard pasteboardHasFileSemanticTypes else {
            return []
        }

        var urls = fileURLsFromReadObjects(options: [.urlReadingFileURLsOnly: true])
        urls.append(contentsOf: fileURLsFromFilenamesPropertyList())
        urls.append(contentsOf: fileURLs(fromPasteboardString: pasteboard.string(forType: .fileURL)))

        for item in pasteboard.pasteboardItems ?? [] {
            urls.append(contentsOf: fileURLs(from: item))
        }

        var seenPaths = Set<String>()
        return urls.filter { url in
            guard url.isFileURL else {
                return false
            }

            return seenPaths.insert(url.standardizedFileURL.path).inserted
        }
    }

    private var monitoredSourceApp: SourceAppInfo {
        let current = SourceAppInfo.current
        return current.isClipEase ? .clipease : current
    }

    private func fileURLsFromReadObjects(options: [NSPasteboard.ReadingOptionKey: Any]) -> [URL] {
        pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: options
        )?.compactMap { object -> URL? in
            let url: URL?
            if let swiftURL = object as? URL {
                url = swiftURL
            } else if let nsURL = object as? NSURL {
                url = nsURL as URL
            } else {
                url = nil
            }

            guard let url, url.isFileURL else {
                return nil
            }

            return url.standardizedFileURL
        } ?? []
    }

    private func fileURLsFromFilenamesPropertyList() -> [URL] {
        guard let propertyList = pasteboard.propertyList(forType: Self.filenamesPasteboardType) else {
            return []
        }

        return fileURLs(fromFilenamesPropertyList: propertyList)
    }

    private func fileURLs(from item: NSPasteboardItem) -> [URL] {
        var urls: [URL] = []

        for type in fileURLTypes {
            urls.append(contentsOf: fileURLs(fromPasteboardString: item.string(forType: type)))
            urls.append(contentsOf: fileURLs(fromPasteboardData: item.data(forType: type)))
        }

        if itemHasPathBackedFileSemanticTypes(item) {
            urls.append(contentsOf: fileURLs(fromFilenamesPropertyList: item.propertyList(forType: Self.filenamesPasteboardType)))
            urls.append(contentsOf: fileURLs(fromPathText: item.string(forType: .string)))
        }

        return urls
    }

    private var fileURLTypes: [NSPasteboard.PasteboardType] {
        [
            .fileURL,
            Self.publicFileURLPasteboardType,
            .URL,
            Self.fileURLPromisePasteboardType,
        ]
    }

    private var fileSemanticTypes: [NSPasteboard.PasteboardType] {
        fileURLTypes + [
            Self.filenamesPasteboardType,
            Self.filePromiseContentPasteboardType,
            Self.filePromiseMetadataPasteboardType,
        ]
    }

    private var pasteboardHasFileSemanticTypes: Bool {
        pasteboard.types?.contains { fileSemanticTypes.contains($0) } ?? false
    }

    private func itemHasPathBackedFileSemanticTypes(_ item: NSPasteboardItem) -> Bool {
        item.types.contains { pathBackedFileSemanticTypes.contains($0) }
    }

    private var pathBackedFileSemanticTypes: [NSPasteboard.PasteboardType] {
        [
            Self.filenamesPasteboardType,
            Self.filePromiseContentPasteboardType,
            Self.filePromiseMetadataPasteboardType,
        ]
    }

    private func fileURLs(fromFilenamesPropertyList propertyList: Any?) -> [URL] {
        if let paths = propertyList as? [String] {
            return paths.compactMap(fileURLFromExistingPath)
        }

        if let paths = propertyList as? NSArray {
            return paths.compactMap { value in
                guard let path = value as? String else {
                    return nil
                }

                return fileURLFromExistingPath(path)
            }
        }

        if let path = propertyList as? String {
            return fileURLs(fromPathText: path)
        }

        return []
    }

    private func fileURLs(fromPasteboardData data: Data?) -> [URL] {
        guard let data else {
            return []
        }

        if let url = URL(dataRepresentation: data, relativeTo: nil), url.isFileURL {
            return [url.standardizedFileURL]
        }

        return fileURLs(fromPasteboardString: String(data: data, encoding: .utf8))
    }

    private func fileURLs(fromPasteboardString text: String?) -> [URL] {
        guard let text else {
            return []
        }

        return fileURLStrings(from: text).compactMap { value in
            guard let url = URL(string: value), url.isFileURL else {
                return nil
            }

            return url.standardizedFileURL
        }
    }

    private func fileURLs(fromPathText text: String?) -> [URL] {
        guard let text else {
            return []
        }

        let paths = pathStrings(from: text)
        guard !paths.isEmpty else {
            return []
        }

        let urls = paths.compactMap(fileURLFromExistingPath)
        guard urls.count == paths.count else {
            return []
        }

        return urls
    }

    private func fileURLStrings(from text: String) -> [String] {
        text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.lowercased().hasPrefix("file://") }
    }

    private func pathStrings(from text: String) -> [String] {
        text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func fileURLFromExistingPath(_ path: String) -> URL? {
        let normalizedPath = NSString(string: path).expandingTildeInPath
        guard normalizedPath.hasPrefix("/"),
              FileManager.default.fileExists(atPath: normalizedPath) else {
            return nil
        }

        return URL(fileURLWithPath: normalizedPath).standardizedFileURL
    }
}
