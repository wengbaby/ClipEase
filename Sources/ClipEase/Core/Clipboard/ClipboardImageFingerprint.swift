import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct ClipboardEncodedImagePayload: Sendable {
    let data: Data
    let declaredTypeIdentifier: String

    static let preferredTypeIdentifiers: [String] = {
        var seen = Set<String>()
        return [
            UTType.png.identifier,
            "public.tiff",
            UTType.tiff.identifier,
            UTType.jpeg.identifier
        ].filter { seen.insert($0).inserted }
    }()

    static func preferred(
        from availableTypeIdentifiers: [String],
        dataForTypeIdentifier: (String) -> Data?
    ) -> ClipboardEncodedImagePayload? {
        let availableTypeIdentifiers = Set(availableTypeIdentifiers)
        for typeIdentifier in preferredTypeIdentifiers
        where availableTypeIdentifiers.contains(typeIdentifier) {
            guard let data = dataForTypeIdentifier(typeIdentifier) else {
                continue
            }
            return ClipboardEncodedImagePayload(
                data: data,
                declaredTypeIdentifier: typeIdentifier
            )
        }
        return nil
    }
}

struct ClipboardImageWriteReceipt: Sendable {
    let changeCount: Int
    let payload: ClipboardEncodedImagePayload

    static func capture(
        changeCount: () -> Int,
        availableTypeIdentifiers: () -> [String],
        dataForTypeIdentifier: (String) -> Data?
    ) -> ClipboardImageWriteReceipt? {
        let changeCountBeforeSnapshot = changeCount()
        let payload = ClipboardEncodedImagePayload.preferred(
            from: availableTypeIdentifiers(),
            dataForTypeIdentifier: dataForTypeIdentifier
        )
        let changeCountAfterSnapshot = changeCount()
        guard changeCountBeforeSnapshot == changeCountAfterSnapshot,
              let payload else {
            return nil
        }
        return ClipboardImageWriteReceipt(
            changeCount: changeCountAfterSnapshot,
            payload: payload
        )
    }
}

struct ClipboardImageFingerprintLimits: Sendable {
    let maximumEncodedBytes: Int
    let maximumSourceEdge: Int
    let maximumSourcePixels: Int

    init(
        maximumEncodedBytes: Int = 64 * 1_024 * 1_024,
        maximumSourceEdge: Int = 16_384,
        maximumSourcePixels: Int = 64_000_000
    ) {
        self.maximumEncodedBytes = max(0, maximumEncodedBytes)
        self.maximumSourceEdge = max(0, maximumSourceEdge)
        self.maximumSourcePixels = max(0, maximumSourcePixels)
    }
}

enum ClipboardImageFingerprintError: Error, Equatable, Sendable {
    case encodedDataTooLarge
    case unsupportedDeclaredType
    case invalidImage
    case unsupportedFrameCount
    case sourceDimensionsTooLarge
    case canonicalizationFailed
}

/// An immutable ImageIO result that lets the importer fingerprint and stage one decode.
struct ClipboardDecodedImageFingerprint: @unchecked Sendable {
    let cgImage: CGImage
    let fingerprint: String
}

enum ClipboardImageFingerprint {
    static let currentVersion = "CEIF1"
    static let maximumSampleEdge = 64

    static func encoded(
        _ payload: ClipboardEncodedImagePayload,
        limits: ClipboardImageFingerprintLimits = ClipboardImageFingerprintLimits()
    ) throws -> String {
        try decode(payload, limits: limits).fingerprint
    }

    static func decode(
        _ payload: ClipboardEncodedImagePayload,
        limits: ClipboardImageFingerprintLimits = ClipboardImageFingerprintLimits()
    ) throws -> ClipboardDecodedImageFingerprint {
        guard payload.data.count <= limits.maximumEncodedBytes else {
            throw ClipboardImageFingerprintError.encodedDataTooLarge
        }
        guard isImageType(identifier: payload.declaredTypeIdentifier) else {
            throw ClipboardImageFingerprintError.unsupportedDeclaredType
        }

        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(
            payload.data as CFData,
            sourceOptions
        ),
        let detectedTypeIdentifier = CGImageSourceGetType(source),
        isImageType(identifier: detectedTypeIdentifier as String) else {
            throw ClipboardImageFingerprintError.invalidImage
        }

        let frameCount = CGImageSourceGetCount(source)
        guard frameCount > 0 else {
            throw ClipboardImageFingerprintError.invalidImage
        }
        guard frameCount == 1 else {
            throw ClipboardImageFingerprintError.unsupportedFrameCount
        }
        guard let properties = CGImageSourceCopyPropertiesAtIndex(
            source,
            0,
            nil
        ) as NSDictionary?,
        let sourceWidth = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
        let sourceHeight = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
        sourceWidth > 0,
        sourceHeight > 0 else {
            throw ClipboardImageFingerprintError.invalidImage
        }

        let sourcePixels = sourceWidth.multipliedReportingOverflow(by: sourceHeight)
        guard sourceWidth <= limits.maximumSourceEdge,
              sourceHeight <= limits.maximumSourceEdge,
              !sourcePixels.overflow,
              sourcePixels.partialValue <= limits.maximumSourcePixels else {
            throw ClipboardImageFingerprintError.sourceDimensionsTooLarge
        }

        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        let swapsDimensions = (5...8).contains(orientation)
        let orientedWidth = swapsDimensions ? sourceHeight : sourceWidth
        let orientedHeight = swapsDimensions ? sourceWidth : sourceHeight
        let decodeOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(sourceWidth, sourceHeight),
            kCGImageSourceShouldCache: false,
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary
        guard let image = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            decodeOptions
        ),
        image.width == orientedWidth,
        image.height == orientedHeight else {
            throw ClipboardImageFingerprintError.invalidImage
        }

        return ClipboardDecodedImageFingerprint(
            cgImage: image,
            fingerprint: try decoded(image)
        )
    }

    private static func isImageType(identifier: String) -> Bool {
        if UTType(identifier)?.conforms(to: .image) == true {
            return true
        }
        return [
            UTType.png,
            UTType.tiff,
            UTType.jpeg,
            UTType.gif,
        ].contains(where: { $0.identifier == identifier })
    }

    static func decoded(_ image: CGImage) throws -> String {
        let orientedWidth = image.width
        let orientedHeight = image.height
        guard orientedWidth > 0,
              orientedHeight > 0,
              orientedWidth <= UInt32.max,
              orientedHeight <= UInt32.max else {
            throw ClipboardImageFingerprintError.sourceDimensionsTooLarge
        }

        let sampleDimensions = sampleDimensions(
            width: orientedWidth,
            height: orientedHeight
        )
        let sampleWidth = sampleDimensions.width
        let sampleHeight = sampleDimensions.height
        let byteCount = sampleWidth * sampleHeight * 4
        var rgba = [UInt8](repeating: 0, count: byteCount)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            throw ClipboardImageFingerprintError.canonicalizationFailed
        }
        let bitmapInfo = CGBitmapInfo(
            rawValue: CGImageAlphaInfo.premultipliedLast.rawValue
                | CGBitmapInfo.byteOrder32Big.rawValue
        )
        let rendered = rgba.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(
                data: bytes.baseAddress,
                width: sampleWidth,
                height: sampleHeight,
                bitsPerComponent: 8,
                bytesPerRow: sampleWidth * 4,
                space: colorSpace,
                bitmapInfo: bitmapInfo.rawValue
            ) else {
                return false
            }

            let bounds = CGRect(
                x: 0,
                y: 0,
                width: sampleWidth,
                height: sampleHeight
            )
            context.clear(bounds)
            context.interpolationQuality = .high
            context.draw(image, in: bounds)
            return true
        }
        guard rendered else {
            throw ClipboardImageFingerprintError.canonicalizationFailed
        }

        var preimage = Data(currentVersion.utf8)
        append(UInt32(orientedWidth), to: &preimage)
        append(UInt32(orientedHeight), to: &preimage)
        append(UInt16(sampleWidth), to: &preimage)
        append(UInt16(sampleHeight), to: &preimage)
        preimage.reserveCapacity(preimage.count + (sampleWidth * sampleHeight * 2))

        for pixelOffset in stride(from: 0, to: rgba.count, by: 4) {
            let alpha = rgba[pixelOffset + 3]
            if alpha == 0 {
                preimage.append(0)
                preimage.append(0)
                continue
            }

            let red = quantizedNibble(rgba[pixelOffset])
            let green = quantizedNibble(rgba[pixelOffset + 1])
            let blue = quantizedNibble(rgba[pixelOffset + 2])
            let quantizedAlpha = quantizedNibble(alpha)
            preimage.append((red << 4) | green)
            preimage.append((blue << 4) | quantizedAlpha)
        }

        return SHA256.hash(data: preimage)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func sampleDimensions(
        width: Int,
        height: Int
    ) -> (width: Int, height: Int) {
        let scale = min(
            CGFloat(maximumSampleEdge) / CGFloat(width),
            CGFloat(maximumSampleEdge) / CGFloat(height),
            1
        )
        return (
            max(1, Int(floor(CGFloat(width) * scale))),
            max(1, Int(floor(CGFloat(height) * scale)))
        )
    }

    /// Maps 8-bit sRGB values to the nearest of 16 levels (ties cannot occur: 255 / 15 = 17).
    private static func quantizedNibble(_ value: UInt8) -> UInt8 {
        UInt8(min(15, (Int(value) + 8) / 17))
    }

    private static func append(_ value: UInt32, to data: inout Data) {
        data.append(UInt8(truncatingIfNeeded: value >> 24))
        data.append(UInt8(truncatingIfNeeded: value >> 16))
        data.append(UInt8(truncatingIfNeeded: value >> 8))
        data.append(UInt8(truncatingIfNeeded: value))
    }

    private static func append(_ value: UInt16, to data: inout Data) {
        data.append(UInt8(truncatingIfNeeded: value >> 8))
        data.append(UInt8(truncatingIfNeeded: value))
    }
}
