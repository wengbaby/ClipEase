import AppKit
import Foundation
import ImageIO
import PDFKit
import Vision

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
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }

        let orientation = Self.imageOrientation(from: source)
        return await recognize(cgImage: cgImage, orientation: orientation)
    }

    func recognizePDF(at url: URL) async -> ClipboardOCRMatch? {
        guard let pdfDocument = PDFDocument(url: url) else {
            return nil
        }

        var recognizedTexts: [String] = []
        var emails: Set<String> = []
        var phoneNumbers: Set<String> = []
        var urls: Set<String> = []

        let pageCount = pdfDocument.pageCount
        guard pageCount > 0 else {
            return nil
        }

        for index in 0..<pageCount {
            guard let page = pdfDocument.page(at: index) else {
                continue
            }

            if let pageImage = page.thumbnail(of: NSSize(width: 2048, height: 2048), for: .mediaBox).cgImage(forProposedRect: nil, context: nil, hints: nil),
               let pageMatch = await recognize(cgImage: pageImage, orientation: .up) {
                if !pageMatch.text.isEmpty {
                    recognizedTexts.append(pageMatch.text)
                }
                emails.formUnion(pageMatch.emails)
                phoneNumbers.formUnion(pageMatch.phoneNumbers)
                urls.formUnion(pageMatch.urls)
            }
        }

        let text = recognizedTexts.joined(separator: "\n")
        guard !text.isEmpty || !emails.isEmpty || !phoneNumbers.isEmpty || !urls.isEmpty else {
            return nil
        }

        return ClipboardOCRMatch(
            text: text,
            emails: Array(emails).sorted(),
            phoneNumbers: Array(phoneNumbers).sorted(),
            urls: Array(urls).sorted(),
            textRegions: []
        )
    }

    private func recognize(cgImage: CGImage, orientation: CGImagePropertyOrientation) async -> ClipboardOCRMatch? {
        await withCheckedContinuation { (continuation: CheckedContinuation<ClipboardOCRMatch?, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest { request, error in
                    guard error == nil,
                          let observations = request.results as? [VNRecognizedTextObservation] else {
                        continuation.resume(returning: nil)
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
                    continuation.resume(returning: matches.text.isEmpty && matches.emails.isEmpty && matches.phoneNumbers.isEmpty && matches.urls.isEmpty ? nil : matches)
                }

                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = false
                request.recognitionLanguages = ["zh-Hans", "en-US"]

                let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(returning: nil)
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
