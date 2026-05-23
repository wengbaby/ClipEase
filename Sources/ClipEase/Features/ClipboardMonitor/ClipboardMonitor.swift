import AppKit
import Foundation

private enum RichTextPasteboardPayload: Sendable {
    case rtf(data: Data, fallbackPlainText: String?)
    case html(data: Data, fallbackPlainText: String?)
}

private struct RichTextImportResult: Sendable {
    let data: Data
    let plainText: String
}

@MainActor
final class ClipboardMonitor {
    private static let filenamesPasteboardType = NSPasteboard.PasteboardType("NSFilenamesPboardType")
    private static let publicFileURLPasteboardType = NSPasteboard.PasteboardType("public.file-url")
    private static let fileURLPromisePasteboardType = NSPasteboard.PasteboardType("com.apple.pasteboard.promised-file-url")
    private static let filePromiseContentPasteboardType = NSPasteboard.PasteboardType("com.apple.pasteboard.promised-file-content-type")
    private static let filePromiseMetadataPasteboardType = NSPasteboard.PasteboardType("com.apple.NSFilePromiseItemMetaData")
    private static let publicPNGType = NSPasteboard.PasteboardType("public.png")
    private static let publicTIFFType = NSPasteboard.PasteboardType("public.tiff")
    private static let publicJPEGType = NSPasteboard.PasteboardType("public.jpeg")

    private let pasteboard: NSPasteboard
    private let store: ClipboardHistoryStore
    private let recordingController: RecordingController
    private let ignoredAppSettings: IgnoredAppSettings
    var shouldSuppressRecording: (() -> Bool)?
    private var timer: Timer?
    private var lastChangeCount: Int
    private var richTextImportTask: Task<Void, Never>?

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
        richTextImportTask?.cancel()
        richTextImportTask = nil
    }

    private func poll() {
        let startedAt = CFAbsoluteTimeGetCurrent()
        let currentChangeCount = pasteboard.changeCount
        guard currentChangeCount != lastChangeCount else {
            return
        }

        lastChangeCount = currentChangeCount
        richTextImportTask?.cancel()
        richTextImportTask = nil
        let changeDetectedAt = CFAbsoluteTimeGetCurrent()
        guard shouldSuppressRecording?() != true else {
            return
        }
        guard !recordingController.isPaused else {
            return
        }

        let sourceApp = monitoredSourceApp
        let sourceResolvedAt = CFAbsoluteTimeGetCurrent()
        guard !ignoredAppSettings.contains(bundleID: sourceApp.bundleID) else {
            return
        }

        let availableTypes = Set(pasteboard.types ?? [])
        let typesLoadedAt = CFAbsoluteTimeGetCurrent()
        if shouldCapturePlainTextFirst(availableTypes),
           let text = pasteboard.string(forType: .string) {
            let payloadLoadedAt = CFAbsoluteTimeGetCurrent()
            store.addText(text, sourceApp: sourceApp)
            recordPollDuration(
                startedAt: startedAt,
                changeDetectedAt: changeDetectedAt,
                sourceResolvedAt: sourceResolvedAt,
                typesLoadedAt: typesLoadedAt,
                payloadLoadedAt: payloadLoadedAt,
                capturedType: "text.fastPath"
            )
            return
        }

        let fileURLs = localFileURLsFromPasteboard(availableTypes: availableTypes)
        if !fileURLs.isEmpty {
            guard !store.consumeSkippedClipboardFiles(fileURLs) else {
                return
            }

            store.addFiles(fileURLs, sourceApp: sourceApp)
            recordPollDuration(startedAt: startedAt, capturedType: "file")
            return
        }

        if pasteboardHasRichTextTypes(availableTypes),
           let rtfData = pasteboard.data(forType: .rtf) {
            scheduleRichTextImport(
                payload: .rtf(data: rtfData, fallbackPlainText: pasteboard.string(forType: .string)),
                sourceApp: sourceApp,
                changeCount: currentChangeCount,
                startedAt: startedAt,
                capturedType: "rtf"
            )
            recordPollDuration(startedAt: startedAt, capturedType: "rtf.scheduled")
            return
        }

        if pasteboardHasImageTypes(availableTypes),
           let image = pasteboard.readObjects(
            forClasses: [NSImage.self],
            options: nil
        )?.first as? NSImage {
            store.addImage(image, sourceApp: sourceApp)
            recordPollDuration(startedAt: startedAt, capturedType: "image")
            return
        }

        if pasteboardHasRichTextTypes(availableTypes),
           let htmlData = pasteboard.data(forType: .html) {
            scheduleRichTextImport(
                payload: .html(data: htmlData, fallbackPlainText: pasteboard.string(forType: .string)),
                sourceApp: sourceApp,
                changeCount: currentChangeCount,
                startedAt: startedAt,
                capturedType: "html"
            )
            recordPollDuration(startedAt: startedAt, capturedType: "html.scheduled")
            return
        }

        if let text = pasteboard.string(forType: .string) {
            store.addText(text, sourceApp: sourceApp)
            recordPollDuration(startedAt: startedAt, capturedType: "text")
        }
    }

    private func recordPollDuration(startedAt: CFAbsoluteTime, capturedType: String) {
        PerformanceDiagnosticsService.shared.record(
            "clipboard.poll",
            category: "clipboard",
            durationMS: (CFAbsoluteTimeGetCurrent() - startedAt) * 1_000,
            metadata: ["capturedType": capturedType]
        )
    }

    private func recordPollDuration(
        startedAt: CFAbsoluteTime,
        changeDetectedAt: CFAbsoluteTime,
        sourceResolvedAt: CFAbsoluteTime,
        typesLoadedAt: CFAbsoluteTime,
        payloadLoadedAt: CFAbsoluteTime,
        capturedType: String
    ) {
        let finishedAt = CFAbsoluteTimeGetCurrent()
        PerformanceDiagnosticsService.shared.record(
            "clipboard.poll",
            category: "clipboard",
            durationMS: (finishedAt - startedAt) * 1_000,
            metadata: [
                "capturedType": capturedType,
                "changeMS": Self.formatStageMS(changeDetectedAt - startedAt),
                "sourceMS": Self.formatStageMS(sourceResolvedAt - changeDetectedAt),
                "typesMS": Self.formatStageMS(typesLoadedAt - sourceResolvedAt),
                "payloadMS": Self.formatStageMS(payloadLoadedAt - typesLoadedAt),
                "storeMS": Self.formatStageMS(finishedAt - payloadLoadedAt)
            ]
        )
    }

    nonisolated private static func formatStageMS(_ seconds: CFAbsoluteTime) -> String {
        String(format: "%.3f", seconds * 1_000)
    }

    private func scheduleRichTextImport(
        payload: RichTextPasteboardPayload,
        sourceApp: SourceAppInfo,
        changeCount: Int,
        startedAt: CFAbsoluteTime,
        capturedType: String
    ) {
        richTextImportTask?.cancel()
        richTextImportTask = Task.detached(priority: .utility) { [weak self] in
            let parseStartedAt = CFAbsoluteTimeGetCurrent()
            let result: RichTextImportResult?
            switch payload {
            case .rtf(let data, let fallbackPlainText):
                result = Self.richTextFromRTFData(data, fallbackPlainText: fallbackPlainText)
            case .html(let data, let fallbackPlainText):
                result = Self.richTextFromHTMLData(data, fallbackPlainText: fallbackPlainText)
            }

            guard !Task.isCancelled,
                  let result else {
                return
            }

            let parsedAt = CFAbsoluteTimeGetCurrent()
            await MainActor.run { [weak self] in
                guard let self,
                      !Task.isCancelled,
                      self.lastChangeCount == changeCount else {
                    return
                }

                let storedType: String
                if result.data.isEmpty || self.shouldCaptureRichTextAsPlainText(result.plainText) {
                    self.store.addText(result.plainText, sourceApp: sourceApp)
                    storedType = "\(capturedType)AsText"
                } else {
                    self.store.addRichText(
                        result.data,
                        plainText: result.plainText,
                        sourceApp: sourceApp
                    )
                    storedType = capturedType
                }

                self.recordRichTextImportDuration(
                    startedAt: startedAt,
                    parseStartedAt: parseStartedAt,
                    parsedAt: parsedAt,
                    capturedType: storedType,
                    payloadByteCount: result.data.count
                )
                self.richTextImportTask = nil
            }
        }
    }

    private func recordRichTextImportDuration(
        startedAt: CFAbsoluteTime,
        parseStartedAt: CFAbsoluteTime,
        parsedAt: CFAbsoluteTime,
        capturedType: String,
        payloadByteCount: Int
    ) {
        let finishedAt = CFAbsoluteTimeGetCurrent()
        PerformanceDiagnosticsService.shared.record(
            "clipboard.richText.import",
            category: "clipboard",
            durationMS: (finishedAt - startedAt) * 1_000,
            metadata: [
                "capturedType": capturedType,
                "mode": "background",
                "payloadBytes": "\(payloadByteCount)",
                "parseMS": Self.formatStageMS(parsedAt - parseStartedAt),
                "storeMS": Self.formatStageMS(finishedAt - parsedAt)
            ]
        )
    }

    private func shouldCapturePlainTextFirst(_ types: Set<NSPasteboard.PasteboardType>) -> Bool {
        types.contains(.string) &&
            !pasteboardHasFileSemanticTypes(types) &&
            !pasteboardHasRichTextTypes(types) &&
            !pasteboardHasImageTypes(types)
    }

    private func shouldCaptureRichTextAsPlainText(_ text: String) -> Bool {
        ColorParser.hexColor(from: text) != nil || URLParser.url(from: text) != nil
    }

    nonisolated private static func richTextFromRTFData(
        _ data: Data,
        fallbackPlainText: String?
    ) -> RichTextImportResult? {
        guard let plainText = plainTextForRichTextData(
            data,
            documentType: .rtf
        ) ?? fallbackPlainText,
              !plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        return RichTextImportResult(data: data, plainText: plainText)
    }

    nonisolated private static func richTextFromHTMLData(
        _ data: Data,
        fallbackPlainText: String?
    ) -> RichTextImportResult? {
        guard let attributedString = attributedString(from: data, documentType: .html) else {
            if let fallbackPlainText,
               !fallbackPlainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return RichTextImportResult(data: Data(), plainText: fallbackPlainText)
            }
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

        return RichTextImportResult(data: rtfData, plainText: plainText)
    }

    nonisolated private static func plainTextForRichTextData(
        _ data: Data,
        documentType: NSAttributedString.DocumentType
    ) -> String? {
        attributedString(from: data, documentType: documentType)?.string
    }

    nonisolated private static func attributedString(
        from data: Data,
        documentType: NSAttributedString.DocumentType
    ) -> NSAttributedString? {
        try? NSAttributedString(
            data: data,
            options: [.documentType: documentType],
            documentAttributes: nil
        )
    }

    private func localFileURLsFromPasteboard(availableTypes: Set<NSPasteboard.PasteboardType>) -> [URL] {
        guard pasteboardHasFileSemanticTypes(availableTypes) else {
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

    private func pasteboardHasFileSemanticTypes(_ types: Set<NSPasteboard.PasteboardType>) -> Bool {
        types.contains { fileSemanticTypes.contains($0) }
    }

    private func pasteboardHasRichTextTypes(_ types: Set<NSPasteboard.PasteboardType>) -> Bool {
        types.contains(.rtf) || types.contains(.html)
    }

    private func pasteboardHasImageTypes(_ types: Set<NSPasteboard.PasteboardType>) -> Bool {
        types.contains(.tiff) ||
            types.contains(Self.publicPNGType) ||
            types.contains(Self.publicTIFFType) ||
            types.contains(Self.publicJPEGType)
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
