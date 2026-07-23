import AppKit
import Foundation
import SwiftUI

struct FileTextPreviewDocument: Equatable, Sendable {
    let text: String
    let isTruncated: Bool
}

enum FileTextPreviewLoadResult: Equatable, Sendable {
    case document(FileTextPreviewDocument)
    case unreadable
}

struct FileTextPreviewLoader: Sendable {
    typealias ReadChunk = @Sendable (FileHandle, Int) async throws -> Data?

    private static let chunkSize = 64 * 1_024

    private let maximumEncodedBytes: Int
    private let maximumRenderedUTF16Units: Int
    private let readChunk: ReadChunk

    init(
        maximumEncodedBytes: Int = 1_048_576,
        maximumRenderedUTF16Units: Int = 524_288,
        readChunk: @escaping ReadChunk = { fileHandle, maximumCount in
            try fileHandle.read(upToCount: maximumCount)
        }
    ) {
        self.maximumEncodedBytes = max(0, maximumEncodedBytes)
        self.maximumRenderedUTF16Units = max(0, maximumRenderedUTF16Units)
        self.readChunk = readChunk
    }

    func load(from url: URL) async throws -> FileTextPreviewLoadResult {
        do {
            try Task.checkCancellation()
            let fileHandle = try FileHandle(forReadingFrom: url)
            defer { try? fileHandle.close() }

            let readLimit = maximumEncodedBytes == Int.max
                ? Int.max
                : maximumEncodedBytes + 1
            var data = Data()
            while data.count < readLimit {
                try Task.checkCancellation()
                let requestedCount = min(Self.chunkSize, readLimit - data.count)
                guard let chunk = try await readChunk(fileHandle, requestedCount),
                      !chunk.isEmpty else {
                    break
                }
                try Task.checkCancellation()
                data.append(chunk.prefix(requestedCount))
            }
            try Task.checkCancellation()

            let isEncodedDataTruncated = data.count > maximumEncodedBytes
            let boundedData = Data(data.prefix(maximumEncodedBytes))
            return decode(
                boundedData,
                isEncodedDataTruncated: isEncodedDataTruncated
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return .unreadable
        }
    }

    private func decode(
        _ data: Data,
        isEncodedDataTruncated: Bool
    ) -> FileTextPreviewLoadResult {
        if !isEncodedDataTruncated, hasRTFSignature(data) {
            guard let attributedString = try? NSAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.rtf],
                documentAttributes: nil
            ) else {
                return .unreadable
            }
            return document(
                text: attributedString.string,
                wasAlreadyTruncated: false
            )
        }

        guard let text = decodePlainText(
            data,
            isEncodedDataTruncated: isEncodedDataTruncated
        ) else {
            return .unreadable
        }
        return document(
            text: text,
            wasAlreadyTruncated: isEncodedDataTruncated
        )
    }

    private func document(
        text: String,
        wasAlreadyTruncated: Bool
    ) -> FileTextPreviewLoadResult {
        let rendered = Self.prefixPreservingUTF16ScalarBoundary(
            text,
            maximumUnits: maximumRenderedUTF16Units
        )
        return .document(
            FileTextPreviewDocument(
                text: rendered.text,
                isTruncated: wasAlreadyTruncated || rendered.isTruncated
            )
        )
    }

    private func decodePlainText(
        _ data: Data,
        isEncodedDataTruncated: Bool
    ) -> String? {
        if data.isEmpty {
            return ""
        }

        let encoding = Self.detectEncoding(in: data)
        let payload = data.dropFirst(encoding.byteOrderMarkLength)
        return Self.strictString(
            from: Data(payload),
            encoding: encoding.stringEncoding,
            codeUnitWidth: encoding.codeUnitWidth,
            isTruncated: isEncodedDataTruncated
        )
    }

    private func hasRTFSignature(_ data: Data) -> Bool {
        data.starts(with: Data("{\\rtf".utf8))
    }

    private static func detectEncoding(in data: Data) -> DetectedEncoding {
        if data.starts(with: [0x00, 0x00, 0xFE, 0xFF]) {
            return .utf32BigEndian
        }
        if data.starts(with: [0xFF, 0xFE, 0x00, 0x00]) {
            return .utf32LittleEndian
        }
        if data.starts(with: [0xFE, 0xFF]) {
            return .utf16BigEndian
        }
        if data.starts(with: [0xFF, 0xFE]) {
            return .utf16LittleEndian
        }
        if data.starts(with: [0xEF, 0xBB, 0xBF]) {
            return .utf8WithBOM
        }
        return compatibleUTF16Encoding(for: data) ?? .utf8
    }

    private static func compatibleUTF16Encoding(for data: Data) -> DetectedEncoding? {
        guard data.count >= 4, data.count.isMultiple(of: 2) else {
            return nil
        }

        var evenNulls = 0
        var oddNulls = 0
        let pairCount = data.count / 2
        for pairIndex in 0..<pairCount {
            if data[pairIndex * 2] == 0 {
                evenNulls += 1
            }
            if data[pairIndex * 2 + 1] == 0 {
                oddNulls += 1
            }
        }

        let strongNullThreshold = max(2, (pairCount * 3 + 3) / 4)
        let weakNullThreshold = pairCount / 8
        if oddNulls >= strongNullThreshold, evenNulls <= weakNullThreshold {
            return .utf16LittleEndianWithoutBOM
        }
        if evenNulls >= strongNullThreshold, oddNulls <= weakNullThreshold {
            return .utf16BigEndianWithoutBOM
        }
        return nil
    }

    private static func strictString(
        from data: Data,
        encoding: String.Encoding,
        codeUnitWidth: Int,
        isTruncated: Bool
    ) -> String? {
        var candidate = data
        let incompleteUnitCount = candidate.count % codeUnitWidth
        if incompleteUnitCount > 0 {
            guard isTruncated else {
                return nil
            }
            candidate.removeLast(incompleteUnitCount)
        }

        let maximumBoundaryTrim = encoding == .utf8 ? 3 : codeUnitWidth * 2
        var trimmedBytes = 0
        while true {
            if let text = String(data: candidate, encoding: encoding),
               !containsBinaryControlCharacters(text) {
                return text
            }
            guard isTruncated,
                  !candidate.isEmpty,
                  trimmedBytes < maximumBoundaryTrim,
                  candidate.count >= codeUnitWidth else {
                return nil
            }
            candidate.removeLast(codeUnitWidth)
            trimmedBytes += codeUnitWidth
        }
    }

    private static func containsBinaryControlCharacters(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            scalar.value < 0x20
                && scalar != "\t"
                && scalar != "\n"
                && scalar != "\r"
        }
    }

    private static func prefixPreservingUTF16ScalarBoundary(
        _ text: String,
        maximumUnits: Int
    ) -> (text: String, isTruncated: Bool) {
        let utf16 = Array(text.utf16)
        guard utf16.count > maximumUnits else {
            return (text, false)
        }

        var prefix = Array(utf16.prefix(maximumUnits))
        if let last = prefix.last,
           (0xD800...0xDBFF).contains(last) {
            prefix.removeLast()
        }
        return (String(decoding: prefix, as: UTF16.self), true)
    }

    private enum DetectedEncoding {
        case utf8
        case utf8WithBOM
        case utf16LittleEndian
        case utf16BigEndian
        case utf16LittleEndianWithoutBOM
        case utf16BigEndianWithoutBOM
        case utf32LittleEndian
        case utf32BigEndian

        var byteOrderMarkLength: Int {
            switch self {
            case .utf8:
                0
            case .utf8WithBOM:
                3
            case .utf16LittleEndian, .utf16BigEndian:
                2
            case .utf16LittleEndianWithoutBOM, .utf16BigEndianWithoutBOM:
                0
            case .utf32LittleEndian, .utf32BigEndian:
                4
            }
        }

        var codeUnitWidth: Int {
            switch self {
            case .utf8, .utf8WithBOM:
                1
            case .utf16LittleEndian, .utf16BigEndian,
                 .utf16LittleEndianWithoutBOM, .utf16BigEndianWithoutBOM:
                2
            case .utf32LittleEndian, .utf32BigEndian:
                4
            }
        }

        var stringEncoding: String.Encoding {
            switch self {
            case .utf8, .utf8WithBOM:
                .utf8
            case .utf16LittleEndian, .utf16LittleEndianWithoutBOM:
                .utf16LittleEndian
            case .utf16BigEndian, .utf16BigEndianWithoutBOM:
                .utf16BigEndian
            case .utf32LittleEndian:
                .utf32LittleEndian
            case .utf32BigEndian:
                .utf32BigEndian
            }
        }
    }
}

struct FileTextPreviewView: NSViewRepresentable {
    typealias LoadDocument = @Sendable (URL) async -> FileTextPreviewLoadResult

    static let loadingPlaceholder = "正在读取文件内容..."
    static let unreadablePlaceholder = "无法读取文件内容"
    static let truncationMarker = "[内容已截断]"

    let url: URL
    private let loadDocument: LoadDocument

    init(
        url: URL,
        loadDocument: @escaping LoadDocument = { url in
            do {
                return try await FileTextPreviewLoader().load(from: url)
            } catch {
                return .unreadable
            }
        }
    ) {
        self.url = url
        self.loadDocument = loadDocument
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = FileInteractiveTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 16, height: 16)
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textColor = NSColor.labelColor
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.autoresizingMask = [.width]

        let scrollView = NSScrollView()
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .white
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.documentView = textView
        context.coordinator.load(url: url, in: textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? FileInteractiveTextView,
              context.coordinator.url != url || context.coordinator.textView !== textView else {
            return
        }
        context.coordinator.load(url: url, in: textView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url, loadDocument: loadDocument)
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        coordinator.dismantle()
        scrollView.documentView = nil
    }

    @MainActor
    final class Coordinator {
        private(set) var url: URL
        private(set) weak var textView: NSTextView?
        private(set) var loadTask: Task<Void, Never>?

        private let loadDocument: LoadDocument
        private var generation = 0
        private var viewIdentity: ObjectIdentifier?
        private var isDismantled = false

        init(url: URL, loadDocument: @escaping LoadDocument) {
            self.url = url
            self.loadDocument = loadDocument
        }

        @discardableResult
        func load(url: URL, in textView: NSTextView) -> Task<Void, Never> {
            loadTask?.cancel()
            generation &+= 1
            let expectedGeneration = generation
            let expectedViewIdentity = ObjectIdentifier(textView)
            self.url = url
            self.textView = textView
            viewIdentity = expectedViewIdentity
            textView.string = FileTextPreviewView.loadingPlaceholder

            guard !isDismantled else {
                let task = Task<Void, Never> {}
                return task
            }

            let loadDocument = self.loadDocument
            let task = Task { @MainActor [weak self, weak textView] in
                let result = await loadDocument(url)
                guard let self else {
                    return
                }
                defer {
                    if self.generation == expectedGeneration {
                        self.loadTask = nil
                    }
                }
                guard !Task.isCancelled,
                      !self.isDismantled,
                      self.generation == expectedGeneration,
                      self.url == url,
                      self.viewIdentity == expectedViewIdentity,
                      self.textView === textView,
                      let textView else {
                    return
                }
                textView.string = FileTextPreviewView.displayText(for: result)
            }
            loadTask = task
            return task
        }

        func dismantle() {
            if !isDismantled {
                isDismantled = true
                generation &+= 1
            }
            loadTask?.cancel()
            loadTask = nil
            textView = nil
            viewIdentity = nil
        }

        deinit {
            loadTask?.cancel()
        }
    }

    private static func displayText(for result: FileTextPreviewLoadResult) -> String {
        switch result {
        case .unreadable:
            return unreadablePlaceholder
        case .document(let document):
            guard document.isTruncated else {
                return document.text
            }
            guard !document.text.isEmpty else {
                return truncationMarker
            }
            return document.text + "\n\n" + truncationMarker
        }
    }
}

final class FileInteractiveTextView: NSTextView {
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.rightMouseDown(with: event)
    }
}
