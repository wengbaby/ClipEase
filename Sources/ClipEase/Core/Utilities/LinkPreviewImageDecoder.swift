import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct LinkPreviewDecodedImage: @unchecked Sendable {
    let cgImage: CGImage

    var pixelWidth: Int {
        cgImage.width
    }

    var pixelHeight: Int {
        cgImage.height
    }
}

struct LinkPreviewImageDecoderLimits: Sendable {
    let maximumEncodedBytes: Int
    let maximumSourceEdge: Int
    let maximumSourcePixels: Int
    let maximumOutputEdge: Int

    init(
        maximumEncodedBytes: Int = 5_000_000,
        maximumSourceEdge: Int = 8_192,
        maximumSourcePixels: Int = 32_000_000,
        maximumOutputEdge: Int = 512
    ) {
        self.maximumEncodedBytes = max(0, maximumEncodedBytes)
        self.maximumSourceEdge = max(0, maximumSourceEdge)
        self.maximumSourcePixels = max(0, maximumSourcePixels)
        self.maximumOutputEdge = max(0, maximumOutputEdge)
    }
}

enum LinkPreviewImageDecoderError: Error, Equatable {
    case encodedDataTooLarge
    case invalidImage
    case sourceDimensionsTooLarge
    case unsupportedFrameCount
    case unsupportedMIMEType
}

struct LinkPreviewImageDecoder: Sendable {
    private let limits: LinkPreviewImageDecoderLimits

    init(limits: LinkPreviewImageDecoderLimits = LinkPreviewImageDecoderLimits()) {
        self.limits = limits
    }

    func decode(
        _ data: Data,
        declaredMIMEType: String
    ) throws -> LinkPreviewDecodedImage {
        guard Self.isImageMIMEType(declaredMIMEType) else {
            throw LinkPreviewImageDecoderError.unsupportedMIMEType
        }
        guard data.count <= limits.maximumEncodedBytes else {
            throw LinkPreviewImageDecoderError.encodedDataTooLarge
        }

        let sourceOptions = [
            kCGImageSourceShouldCache: false
        ] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions),
              let sourceTypeIdentifier = CGImageSourceGetType(source),
              let sourceType = UTType(sourceTypeIdentifier as String),
              sourceType.conforms(to: .image) else {
            throw LinkPreviewImageDecoderError.invalidImage
        }
        guard CGImageSourceGetCount(source) == 1 else {
            throw LinkPreviewImageDecoderError.unsupportedFrameCount
        }
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as NSDictionary?,
              let pixelWidth = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let pixelHeight = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              pixelWidth > 0,
              pixelHeight > 0 else {
            throw LinkPreviewImageDecoderError.invalidImage
        }
        guard pixelWidth <= limits.maximumSourceEdge,
              pixelHeight <= limits.maximumSourceEdge,
              pixelWidth <= limits.maximumSourcePixels / pixelHeight,
              limits.maximumOutputEdge > 0 else {
            throw LinkPreviewImageDecoderError.sourceDimensionsTooLarge
        }

        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: limits.maximumOutputEdge,
            kCGImageSourceShouldCache: false,
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary
        guard let image = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            thumbnailOptions
        ) else {
            throw LinkPreviewImageDecoderError.invalidImage
        }

        return LinkPreviewDecodedImage(cgImage: image)
    }

    private static func isImageMIMEType(_ rawValue: String) -> Bool {
        guard let mimeType = rawValue
            .split(separator: ";", maxSplits: 1, omittingEmptySubsequences: true)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() else {
            return false
        }
        return mimeType.hasPrefix("image/") && mimeType.count > "image/".count
    }
}
