import Foundation

struct ClipboardPayloadImportLimits: Sendable {
    let maximumImageInputBytes: Int
    let maximumImageSourceEdge: Int
    let maximumImageSourcePixels: Int
    let maximumPNGOutputBytes: Int
    let maximumRTFInputBytes: Int
    let maximumHTMLInputBytes: Int
    let maximumRichTextOutputBytes: Int

    init(
        maximumImageInputBytes: Int = 32 * 1_024 * 1_024,
        maximumImageSourceEdge: Int = 4_096,
        maximumImageSourcePixels: Int = 32_000_000,
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
    let previewSkipReason: ClipboardPayloadProcessingReason?

    init(
        storedImage: StoredClipboardImage,
        fingerprint: String?,
        previewSkipReason: ClipboardPayloadProcessingReason? = nil
    ) {
        self.storedImage = storedImage
        self.fingerprint = fingerprint
        self.previewSkipReason = previewSkipReason
    }
}

struct ClipboardImportedPDF: Sendable {
    let storedFile: StoredOwnedClipboardFile
    let previewSkipReason: ClipboardPayloadProcessingReason?
}
