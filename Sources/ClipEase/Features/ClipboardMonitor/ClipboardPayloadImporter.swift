import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct ClipboardPayloadImportLimits: Sendable {
    let maximumImageInputBytes: Int
    let maximumImageSourceEdge: Int
    let maximumImageSourcePixels: Int
    let maximumPNGOutputBytes: Int
    let maximumRTFInputBytes: Int
    let maximumHTMLInputBytes: Int
    let maximumRichTextOutputBytes: Int

    init(
        maximumImageInputBytes: Int = 64 * 1_024 * 1_024,
        maximumImageSourceEdge: Int = 16_384,
        maximumImageSourcePixels: Int = 64_000_000,
        maximumPNGOutputBytes: Int = 128 * 1_024 * 1_024,
        maximumRTFInputBytes: Int = 16 * 1_024 * 1_024,
        maximumHTMLInputBytes: Int = 16 * 1_024 * 1_024,
        maximumRichTextOutputBytes: Int = 16 * 1_024 * 1_024
    ) {
        self.maximumImageInputBytes = max(0, maximumImageInputBytes)
        self.maximumImageSourceEdge = max(0, maximumImageSourceEdge)
        self.maximumImageSourcePixels = max(0, maximumImageSourcePixels)
        self.maximumPNGOutputBytes = max(0, maximumPNGOutputBytes)
        self.maximumRTFInputBytes = max(0, maximumRTFInputBytes)
        self.maximumHTMLInputBytes = max(0, maximumHTMLInputBytes)
        self.maximumRichTextOutputBytes = max(0, maximumRichTextOutputBytes)
    }
}

enum ClipboardPayloadImportError: Error, Equatable {
    case imageInputTooLarge
    case unsupportedImageType
    case invalidImage
    case imageDimensionsTooLarge
    case pngOutputTooLarge
    case rtfInputTooLarge
    case htmlInputTooLarge
    case richTextOutputTooLarge
}

struct ClipboardImportedImage: @unchecked Sendable {
    let storedImage: StoredClipboardImage
    let fingerprint: String?
}

struct ClipboardPayloadImporter: Sendable {
    typealias ImageDecoder = @Sendable (
        Data,
        String,
        ClipboardPayloadImportLimits
    ) throws -> ClipboardDecodedImageFingerprint

    private let persistence: ClipboardHistoryPersistence
    private let limits: ClipboardPayloadImportLimits
    private let imageDecoder: ImageDecoder
    private let beforeRichTextParse: @Sendable () -> Void

    init(
        persistence: ClipboardHistoryPersistence,
        limits: ClipboardPayloadImportLimits = ClipboardPayloadImportLimits(),
        imageDecoder: ImageDecoder? = nil,
        beforeImageDecode: @escaping @Sendable () -> Void = {},
        onImageDecode: @escaping @Sendable () -> Void = {},
        beforeRichTextParse: @escaping @Sendable () -> Void = {}
    ) {
        self.persistence = persistence
        self.limits = limits
        self.imageDecoder = imageDecoder ?? { data, typeIdentifier, limits in
            try Self.decodeImage(
                data,
                typeIdentifier,
                limits,
                beforeImageDecode: beforeImageDecode,
                onImageDecode: onImageDecode
            )
        }
        self.beforeRichTextParse = beforeRichTextParse
    }

    func importImage(
        _ data: Data,
        declaredTypeIdentifier: String
    ) async throws -> StoredClipboardImage {
        try await importImageForMonitor(
            data,
            declaredTypeIdentifier: declaredTypeIdentifier
        ).storedImage
    }

    func importImageForMonitor(
        _ data: Data,
        declaredTypeIdentifier: String
    ) async throws -> ClipboardImportedImage {
        let imageDecoder = self.imageDecoder
        let limits = self.limits
        let decodeTask = Task.detached(priority: .utility) {
            try Task.checkCancellation()
            let decoded = try imageDecoder(data, declaredTypeIdentifier, limits)
            try Task.checkCancellation()
            return decoded
        }
        let decoded = try await withTaskCancellationHandler {
            try await decodeTask.value
        } onCancel: {
            decodeTask.cancel()
        }

        try Task.checkCancellation()
        do {
            let storedImage = try await persistence.stageImage(
                ClipboardImageStagingSource(cgImage: decoded.cgImage),
                maximumPNGBytes: limits.maximumPNGOutputBytes
            )
            return ClipboardImportedImage(
                storedImage: storedImage,
                fingerprint: decoded.fingerprint
            )
        } catch ClipboardImageStagingError.outputTooLarge {
            throw ClipboardPayloadImportError.pngOutputTooLarge
        }
    }

    func importRichText(
        _ payload: ClipboardRichTextPasteboardPayload
    ) async throws -> ClipboardRichTextImportResult? {
        let limits = self.limits
        let beforeRichTextParse = self.beforeRichTextParse
        let importTask = Task.detached(priority: .utility) {
            try Task.checkCancellation()
            beforeRichTextParse()
            try Task.checkCancellation()
            let result = try Self.convertRichText(payload, limits: limits)
            try Task.checkCancellation()
            return result
        }
        return try await withTaskCancellationHandler {
            try await importTask.value
        } onCancel: {
            importTask.cancel()
        }
    }

    private static func decodeImage(
        _ data: Data,
        _ declaredTypeIdentifier: String,
        _ limits: ClipboardPayloadImportLimits,
        beforeImageDecode: @Sendable () -> Void,
        onImageDecode: @Sendable () -> Void
    ) throws -> ClipboardDecodedImageFingerprint {
        beforeImageDecode()
        try Task.checkCancellation()
        onImageDecode()
        do {
            return try ClipboardImageFingerprint.decode(
                ClipboardEncodedImagePayload(
                    data: data,
                    declaredTypeIdentifier: declaredTypeIdentifier
                ),
                limits: ClipboardImageFingerprintLimits(
                    maximumEncodedBytes: limits.maximumImageInputBytes,
                    maximumSourceEdge: limits.maximumImageSourceEdge,
                    maximumSourcePixels: limits.maximumImageSourcePixels
                )
            )
        } catch let error as ClipboardImageFingerprintError {
            switch error {
            case .encodedDataTooLarge:
                throw ClipboardPayloadImportError.imageInputTooLarge
            case .unsupportedDeclaredType:
                throw ClipboardPayloadImportError.unsupportedImageType
            case .sourceDimensionsTooLarge:
                throw ClipboardPayloadImportError.imageDimensionsTooLarge
            case .invalidImage, .unsupportedFrameCount, .canonicalizationFailed:
                throw ClipboardPayloadImportError.invalidImage
            }
        }
    }

    private static func convertRichText(
        _ payload: ClipboardRichTextPasteboardPayload,
        limits: ClipboardPayloadImportLimits
    ) throws -> ClipboardRichTextImportResult? {
        switch payload {
        case .rtf(let data, let fallbackPlainText):
            guard data.count <= limits.maximumRTFInputBytes else {
                throw ClipboardPayloadImportError.rtfInputTooLarge
            }
            guard data.count <= limits.maximumRichTextOutputBytes else {
                throw ClipboardPayloadImportError.richTextOutputTooLarge
            }
            guard let plainText = attributedString(from: data, documentType: .rtf)?.string
                ?? fallbackPlainText,
                !plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            return ClipboardRichTextImportResult(data: data, plainText: plainText)

        case .html(let data, let fallbackPlainText):
            guard data.count <= limits.maximumHTMLInputBytes else {
                throw ClipboardPayloadImportError.htmlInputTooLarge
            }
            guard let attributedString = attributedString(from: data, documentType: .html) else {
                guard let fallbackPlainText,
                      !fallbackPlainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    return nil
                }
                return ClipboardRichTextImportResult(data: Data(), plainText: fallbackPlainText)
            }

            let plainText = attributedString.string
            guard !plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let rtfData = try? attributedString.data(
                    from: NSRange(location: 0, length: attributedString.length),
                    documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
                  ) else {
                return nil
            }
            guard rtfData.count <= limits.maximumRichTextOutputBytes else {
                throw ClipboardPayloadImportError.richTextOutputTooLarge
            }
            return ClipboardRichTextImportResult(data: rtfData, plainText: plainText)
        }
    }

    private static func attributedString(
        from data: Data,
        documentType: NSAttributedString.DocumentType
    ) -> NSAttributedString? {
        try? NSAttributedString(
            data: data,
            options: [.documentType: documentType],
            documentAttributes: nil
        )
    }
}
