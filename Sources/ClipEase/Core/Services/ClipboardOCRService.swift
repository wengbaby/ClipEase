import AppKit
import Foundation
import ImageIO
import PDFKit
import Vision

enum ClipboardOCRSkipReason: String, Sendable, Equatable {
    case imageByteLimit
    case imagePixelLimit
    case pdfByteLimit
    case pdfPageLimit
    case unsupportedItem
}

enum ClipboardOCRFailureReason: String, Sendable, Equatable {
    case sourceUnavailable
    case recognitionFailed
    case timedOut
    case pageTimedOut
}

enum ClipboardOCRExecutionOutcome: Sendable, Equatable {
    case completed
    case deferred
    case skipped(ClipboardOCRSkipReason)
    case failed(ClipboardOCRFailureReason)
}

enum ClipboardOCRInputDecision: Sendable, Equatable {
    case accepted
    case skipped(ClipboardOCRSkipReason)
}

enum ClipboardOCRServiceResult: Sendable, Equatable {
    case completed(ClipboardOCRMatch)
    case skipped(ClipboardOCRSkipReason)
    case failed(ClipboardOCRFailureReason)
}

enum ClipboardOCRInputPolicy {
    static let maximumImageBytes = 32 * 1_024 * 1_024
    static let maximumImagePixels = 32_000_000
    static let downsampleMaxPixelEdge = 4_096
    static let maximumPDFBytes = 50 * 1_024 * 1_024
    static let maximumPDFPages = 25
    static let itemTimeoutNanoseconds: UInt64 = 10_000_000_000
    static let pageTimeoutNanoseconds: UInt64 = 2_000_000_000

    static func imageDecision(
        byteCount: Int,
        pixelWidth: Int,
        pixelHeight: Int
    ) -> ClipboardOCRInputDecision {
        guard byteCount <= maximumImageBytes else {
            return .skipped(.imageByteLimit)
        }
        let (pixelCount, overflow) = max(0, pixelWidth).multipliedReportingOverflow(
            by: max(0, pixelHeight)
        )
        guard !overflow, pixelCount <= maximumImagePixels else {
            return .skipped(.imagePixelLimit)
        }
        return .accepted
    }

    static func pdfDecision(
        byteCount: Int,
        pageCount: Int
    ) -> ClipboardOCRInputDecision {
        guard byteCount <= maximumPDFBytes else {
            return .skipped(.pdfByteLimit)
        }
        guard pageCount <= maximumPDFPages else {
            return .skipped(.pdfPageLimit)
        }
        return .accepted
    }
}

struct ClipboardOCRTextRegion: Codable, Sendable, Equatable {
    let text: String
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

struct ClipboardOCRMatch: Sendable, Equatable {
    let text: String
    let emails: [String]
    let phoneNumbers: [String]
    let urls: [String]
    let textRegions: [ClipboardOCRTextRegion]
}

actor ClipboardOCRService {
    static let shared = ClipboardOCRService()

    func recognizeImage(at url: URL) async -> ClipboardOCRMatch? {
        guard case .completed(let match) = await recognizeImageResult(at: url) else {
            return nil
        }
        return match
    }

    func recognizeImageResult(at url: URL) async -> ClipboardOCRServiceResult {
        guard let byteCount = Self.fileByteCount(at: url),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let pixelWidth = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let pixelHeight = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue else {
            return .failed(.sourceUnavailable)
        }

        switch ClipboardOCRInputPolicy.imageDecision(
            byteCount: byteCount,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight
        ) {
        case .accepted:
            break
        case .skipped(let reason):
            return .skipped(reason)
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: ClipboardOCRInputPolicy.downsampleMaxPixelEdge,
            kCGImageSourceShouldCacheImmediately: false
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              let match = await recognize(cgImage: cgImage, orientation: .up) else {
            return .failed(.recognitionFailed)
        }
        return .completed(match)
    }

    func recognizePDF(at url: URL) async -> ClipboardOCRMatch? {
        guard case .completed(let match) = await recognizePDFResult(at: url) else {
            return nil
        }
        return match
    }

    func recognizePDFResult(at url: URL) async -> ClipboardOCRServiceResult {
        guard let byteCount = Self.fileByteCount(at: url),
              let pdfDocument = PDFDocument(url: url) else {
            return .failed(.sourceUnavailable)
        }
        var recognizedTexts: [String] = []
        var emails: Set<String> = []
        var phoneNumbers: Set<String> = []
        var urls: Set<String> = []

        let pageCount = pdfDocument.pageCount
        guard pageCount > 0 else {
            return .failed(.recognitionFailed)
        }
        switch ClipboardOCRInputPolicy.pdfDecision(
            byteCount: byteCount,
            pageCount: pageCount
        ) {
        case .accepted:
            break
        case .skipped(let reason):
            return .skipped(reason)
        }

        for index in 0..<pageCount {
            guard !Task.isCancelled else {
                return .failed(.recognitionFailed)
            }
            guard let page = pdfDocument.page(at: index) else {
                continue
            }

            if let pageImage = page.thumbnail(
                of: NSSize(width: 2048, height: 2048),
                for: .mediaBox
            ).cgImage(forProposedRect: nil, context: nil, hints: nil) {
                let pageTask = Task {
                    await self.recognize(cgImage: pageImage, orientation: .up)
                }
                let pageResult = await ClipboardOCRTimeout.wait(
                    for: pageTask,
                    nanoseconds: ClipboardOCRInputPolicy.pageTimeoutNanoseconds
                )
                let pageMatch: ClipboardOCRMatch?
                switch pageResult {
                case .value(let match):
                    pageMatch = match
                case .timedOut:
                    pageTask.cancel()
                    return .failed(.pageTimedOut)
                case .cancelled:
                    pageTask.cancel()
                    return .failed(.recognitionFailed)
                }
                if let pageMatch {
                if !pageMatch.text.isEmpty {
                    recognizedTexts.append(pageMatch.text)
                }
                emails.formUnion(pageMatch.emails)
                phoneNumbers.formUnion(pageMatch.phoneNumbers)
                urls.formUnion(pageMatch.urls)
                }
            }
        }

        let text = recognizedTexts.joined(separator: "\n")
        guard !text.isEmpty || !emails.isEmpty || !phoneNumbers.isEmpty || !urls.isEmpty else {
            return .failed(.recognitionFailed)
        }

        return .completed(
            ClipboardOCRMatch(
                text: text,
                emails: Array(emails).sorted(),
                phoneNumbers: Array(phoneNumbers).sorted(),
                urls: Array(urls).sorted(),
                textRegions: []
            )
        )
    }

    private func recognize(cgImage: CGImage, orientation: CGImagePropertyOrientation) async -> ClipboardOCRMatch? {
        await withCheckedContinuation { (continuation: CheckedContinuation<ClipboardOCRMatch?, Never>) in
            let resolution = ClipboardOCROneShotContinuation(continuation)
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest { request, error in
                    guard error == nil,
                          let observations = request.results as? [VNRecognizedTextObservation] else {
                        resolution.resolve(nil)
                        return
                    }

                    let recognized = observations.compactMap { observation -> (String, CGRect)? in
                        guard let text = observation.topCandidates(1).first?.string.trimmingCharacters(in: .whitespacesAndNewlines),
                              !text.isEmpty else {
                            return nil
                        }

                        return (text, observation.boundingBox)
                    }
                    let texts = recognized.map(\.0)
                    let combinedText = texts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                    let matches = Self.extractMatches(
                        from: combinedText,
                        textRegions: recognized.map { text, box in
                        ClipboardOCRTextRegion(
                            text: text,
                            x: box.minX,
                            y: box.minY,
                            width: box.width,
                            height: box.height
                        )
                        }
                    )
                    resolution.resolve(
                        matches.text.isEmpty
                            && matches.emails.isEmpty
                            && matches.phoneNumbers.isEmpty
                            && matches.urls.isEmpty
                            ? nil
                            : matches
                    )
                }

                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = false
                request.recognitionLanguages = ["zh-Hans", "en-US"]

                let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
                do {
                    try handler.perform([request])
                } catch {
                    resolution.resolve(nil)
                }
            }
        }
    }

    nonisolated private static func imageOrientation(from source: CGImageSource) -> CGImagePropertyOrientation {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let rawValue = properties[kCGImagePropertyOrientation] as? UInt32,
              let orientation = CGImagePropertyOrientation(rawValue: rawValue) else {
            return .up
        }

        return orientation
    }

    nonisolated private static func fileByteCount(at url: URL) -> Int? {
        try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize
    }

    nonisolated static func extractMatches(
        from text: String,
        textRegions: [ClipboardOCRTextRegion] = []
    ) -> ClipboardOCRMatch {
        let lines = text
            .split(whereSeparator: \.isNewline)
            .map(String.init)

        let emails = Set(matches(in: text, pattern: "[A-Z0-9a-z._%+-]+@[A-Z0-9a-z.-]+\\.[A-Za-z]{2,}"))
        let urls = Set(matches(in: text, pattern: "https?://[^\\s]+"))
        let phoneNumbers = Set(matches(in: text, types: [.phoneNumber]))

        return ClipboardOCRMatch(
            text: lines.joined(separator: "\n"),
            emails: emails.sorted(),
            phoneNumbers: phoneNumbers.sorted(),
            urls: urls.sorted(),
            textRegions: textRegions
        )
    }

    nonisolated private static func matches(in text: String, pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return []
        }

        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, options: [], range: range).compactMap { match in
            guard let range = Range(match.range, in: text) else {
                return nil
            }

            return String(text[range])
        }
    }

    nonisolated private static func matches(in text: String, types: NSTextCheckingResult.CheckingType) -> [String] {
        guard let detector = try? NSDataDetector(types: types.rawValue) else {
            return []
        }

        let range = NSRange(text.startIndex..., in: text)
        return detector.matches(in: text, options: [], range: range).compactMap { result in
            guard let range = Range(result.range, in: text) else {
                return nil
            }

            return String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}

final class ClipboardOCROneShotContinuation<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Never>?

    init(_ continuation: CheckedContinuation<Value, Never>) {
        self.continuation = continuation
    }

    @discardableResult
    func resolve(_ value: sending Value) -> Bool {
        let continuation = lock.withLock {
            () -> CheckedContinuation<Value, Never>? in
            defer { self.continuation = nil }
            return self.continuation
        }
        guard let continuation else {
            return false
        }
        continuation.resume(returning: value)
        return true
    }
}

enum ClipboardOCRTimeoutResult<Value: Sendable>: Sendable {
    case value(Value)
    case timedOut
    case cancelled
}

enum ClipboardOCRTimeout {
    static func wait<Value: Sendable>(
        for task: Task<Value, Never>,
        nanoseconds: UInt64
    ) async -> ClipboardOCRTimeoutResult<Value> {
        let driver = ClipboardOCRTimeoutDriver<Value>()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                driver.install(continuation)
                Task {
                    driver.resolve(.value(await task.value))
                }
                Task {
                    do {
                        try await Task.sleep(nanoseconds: nanoseconds)
                        driver.resolve(.timedOut)
                    } catch {
                        // The result task or caller cancellation owns completion.
                    }
                }
            }
        } onCancel: {
            task.cancel()
            driver.resolve(.cancelled)
        }
    }
}

private final class ClipboardOCRTimeoutDriver<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<ClipboardOCRTimeoutResult<Value>, Never>?
    private var pendingResult: ClipboardOCRTimeoutResult<Value>?
    private var isResolved = false

    func install(
        _ continuation: CheckedContinuation<ClipboardOCRTimeoutResult<Value>, Never>
    ) {
        lock.lock()
        if let pendingResult {
            lock.unlock()
            continuation.resume(returning: pendingResult)
            return
        }
        self.continuation = continuation
        lock.unlock()
    }

    func resolve(_ result: ClipboardOCRTimeoutResult<Value>) {
        lock.lock()
        guard !isResolved else {
            lock.unlock()
            return
        }
        isResolved = true
        guard let continuation else {
            pendingResult = result
            lock.unlock()
            return
        }
        self.continuation = nil
        lock.unlock()
        continuation.resume(returning: result)
    }
}
