import AppKit
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

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
    private let payloadStager: ClipboardPayloadStager?

    init(
        persistence: ClipboardHistoryPersistence,
        limits: ClipboardPayloadImportLimits = ClipboardPayloadImportLimits(),
        imageDecoder: ImageDecoder? = nil,
        beforeImageDecode: @escaping @Sendable () -> Void = {},
        onImageDecode: @escaping @Sendable () -> Void = {},
        beforeRichTextParse: @escaping @Sendable () -> Void = {},
        payloadStager: ClipboardPayloadStager? = nil
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
        self.payloadStager = payloadStager
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

    func importImageForMonitor(
        _ stagedPayload: ClipboardStagedPayload,
        declaredTypeIdentifier: String
    ) async throws -> ClipboardImportedImage {
        let limits = self.limits
        let inspectionOperation: @Sendable () async throws -> EncodedImageInspection = {
            let inspectionTask = Task.detached(priority: .utility) {
                try Self.inspectEncodedImage(
                    at: stagedPayload.fileURL,
                    byteCount: stagedPayload.byteCount,
                    declaredTypeIdentifier: declaredTypeIdentifier,
                    limits: limits
                )
            }
            return try await withTaskCancellationHandler {
                try await inspectionTask.value
            } onCancel: {
                inspectionTask.cancel()
            }
        }
        let inspection: EncodedImageInspection
        if let payloadStager {
            inspection = try await payloadStager.withWorkingSet(
                byteCount: min(max(0, stagedPayload.byteCount), 1 * 1_024 * 1_024),
                operation: inspectionOperation
            )
        } else {
            inspection = try await inspectionOperation()
        }
        let workingSetBytes = Self.estimatedImageWorkingSetBytes(inspection: inspection)
        let operation: @Sendable () async throws -> ClipboardImportedImage = {
            let previewTask = Task.detached(priority: .utility) {
                try Self.deriveEncodedImagePreview(
                    at: stagedPayload.fileURL,
                    inspection: inspection,
                    limits: limits
                )
            }
            let derived = try await withTaskCancellationHandler {
                try await previewTask.value
            } onCancel: {
                previewTask.cancel()
            }
            try Task.checkCancellation()
            let promotion = try await persistence.promoteEncodedImage(
                stagedPayload,
                width: inspection.orientedWidth,
                height: inspection.orientedHeight,
                hash: inspection.contentHash,
                thumbnailPNGData: derived.thumbnailPNGData
            )
            return ClipboardImportedImage(
                storedImage: promotion.storedImage,
                fingerprint: derived.fingerprint,
                previewSkipReason: promotion.previewSkipReason ?? derived.skipReason
            )
        }
        if let payloadStager {
            return try await payloadStager.withWorkingSet(
                byteCount: workingSetBytes,
                operation: operation
            )
        }
        return try await operation()
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

    func importRichText(
        _ stagedPayload: ClipboardStagedPayload,
        fallbackPlainText: String? = nil
    ) async throws -> ClipboardRichTextImportResult? {
        let limits = self.limits
        let beforeRichTextParse = self.beforeRichTextParse
        let operation: @Sendable () async throws -> ClipboardRichTextImportResult? = {
            let importTask = Task.detached(priority: .utility) {
                try Task.checkCancellation()
                let fallback = Self.nonEmptyFallback(fallbackPlainText)
                switch stagedPayload.contentKind {
                case .richTextRTF:
                    let rawAsset = ClipboardRichTextRawAsset(
                        stagedPayload: stagedPayload,
                        storage: .primaryRTF
                    )
                    guard stagedPayload.byteCount <= limits.maximumRTFInputBytes else {
                        return ClipboardRichTextImportResult(
                            data: Data(),
                            plainText: fallback ?? Self.richTextPlaceholder(
                                byteCount: stagedPayload.byteCount
                            ),
                            rawAsset: rawAsset,
                            previewSkipReason: .previewLimitExceeded
                        )
                    }
                    let stagedData = try stagedPayload.readData()
                    beforeRichTextParse()
                    let plainText = Self.attributedString(
                        from: stagedData,
                        documentType: .rtf
                    )?.string
                    try Task.checkCancellation()
                    return ClipboardRichTextImportResult(
                        data: Data(),
                        plainText: Self.nonEmptyFallback(plainText)
                            ?? fallback
                            ?? Self.richTextPlaceholder(byteCount: stagedPayload.byteCount),
                        rawAsset: rawAsset,
                        previewSkipReason: plainText == nil ? .previewLimitExceeded : nil
                    )
                case .richTextHTML:
                    let rawAsset = ClipboardRichTextRawAsset(
                        stagedPayload: stagedPayload,
                        storage: .htmlCompanion
                    )
                    guard stagedPayload.byteCount <= limits.maximumHTMLInputBytes else {
                        let placeholder = fallback ?? Self.richTextPlaceholder(
                            byteCount: stagedPayload.byteCount
                        )
                        return ClipboardRichTextImportResult(
                            data: try Self.rtfData(forPlainText: placeholder),
                            plainText: placeholder,
                            rawAsset: rawAsset,
                            previewSkipReason: .previewLimitExceeded
                        )
                    }
                    let stagedData = try stagedPayload.readData()
                    beforeRichTextParse()
                    guard let attributedString = Self.attributedString(
                        from: stagedData,
                        documentType: .html
                    ),
                    let plainText = Self.nonEmptyFallback(attributedString.string),
                    let rtfData = try? attributedString.data(
                        from: NSRange(location: 0, length: attributedString.length),
                        documentAttributes: [
                            .documentType: NSAttributedString.DocumentType.rtf
                        ]
                    ),
                    rtfData.count <= limits.maximumRichTextOutputBytes else {
                        try Task.checkCancellation()
                        let placeholder = fallback ?? Self.richTextPlaceholder(
                            byteCount: stagedPayload.byteCount
                        )
                        return ClipboardRichTextImportResult(
                            data: try Self.rtfData(forPlainText: placeholder),
                            plainText: placeholder,
                            rawAsset: rawAsset,
                            previewSkipReason: .previewLimitExceeded
                        )
                    }
                    try Task.checkCancellation()
                    return ClipboardRichTextImportResult(
                        data: rtfData,
                        plainText: plainText,
                        rawAsset: rawAsset
                    )
                case .image, .pdf:
                    throw ClipboardPayloadStagingError.stagedFileUnreadable
                }
            }
            return try await withTaskCancellationHandler {
                try await importTask.value
            } onCancel: {
                importTask.cancel()
            }
        }
        if let payloadStager {
            return try await payloadStager.withWorkingSet(
                byteCount: Self.estimatedRichTextWorkingSetBytes(
                    stagedPayload,
                    limits: limits
                ),
                operation: operation
            )
        }
        return try await operation()
    }

    func importPDF(
        _ stagedPayload: ClipboardStagedPayload
    ) async throws -> ClipboardImportedPDF {
        let operation: @Sendable () async throws -> ClipboardImportedPDF = {
            let maximumPDFBytes = 50 * 1_024 * 1_024
            let automaticPageLimit = 25
            let inspection = await Task.detached(priority: .utility) {
                Self.inspectPDF(at: stagedPayload.fileURL)
            }.value
            try Task.checkCancellation()
            let isWithinAutomaticPageLimit = inspection.pageCount.map {
                (1...automaticPageLimit).contains($0)
            } ?? false
            let skipReason: ClipboardPayloadProcessingReason? =
                stagedPayload.byteCount > maximumPDFBytes
                    || !isWithinAutomaticPageLimit
                    ? .ocrLimitExceeded
                    : nil
            let storedFile = try await persistence.promoteOwnedPDF(stagedPayload)
            return ClipboardImportedPDF(
                storedFile: storedFile,
                previewSkipReason: skipReason
            )
        }
        if let payloadStager {
            return try await payloadStager.withWorkingSet(
                byteCount: min(max(0, stagedPayload.byteCount), 1 * 1_024 * 1_024),
                operation: operation
            )
        }
        return try await operation()
    }

    private struct EncodedImageInspection: Sendable {
        let orientedWidth: Int
        let orientedHeight: Int
        let isValidImage: Bool
        let isWithinAutomaticLimits: Bool
        let contentHash: String
    }

    private struct EncodedImageDerivedPreview: Sendable {
        let thumbnailPNGData: Data?
        let fingerprint: String?
        let skipReason: ClipboardPayloadProcessingReason?
    }

    private struct PDFInspection: Sendable {
        let pageCount: Int?
    }

    private static func inspectEncodedImage(
        at fileURL: URL,
        byteCount: Int,
        declaredTypeIdentifier: String,
        limits: ClipboardPayloadImportLimits
    ) throws -> EncodedImageInspection {
        let contentHash = try streamingSHA256(at: fileURL)
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard UTType(declaredTypeIdentifier)?.conforms(to: .image) == true,
              let source = CGImageSourceCreateWithURL(fileURL as CFURL, sourceOptions),
              let detectedType = CGImageSourceGetType(source),
              UTType(detectedType as String)?.conforms(to: .image) == true,
              let properties = CGImageSourceCopyPropertiesAtIndex(
                source,
                0,
                sourceOptions
              ) as NSDictionary?,
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              width > 0,
              height > 0 else {
            return EncodedImageInspection(
                orientedWidth: 0,
                orientedHeight: 0,
                isValidImage: false,
                isWithinAutomaticLimits: false,
                contentHash: contentHash
            )
        }
        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        let swapsDimensions = (5...8).contains(orientation)
        let orientedWidth = swapsDimensions ? height : width
        let orientedHeight = swapsDimensions ? width : height
        let pixels = orientedWidth.multipliedReportingOverflow(by: orientedHeight)
        let frameCount = CGImageSourceGetCount(source)
        let withinLimits = byteCount <= limits.maximumImageInputBytes
            && frameCount == 1
            && !pixels.overflow
            && pixels.partialValue <= limits.maximumImageSourcePixels
        return EncodedImageInspection(
            orientedWidth: orientedWidth,
            orientedHeight: orientedHeight,
            isValidImage: frameCount > 0,
            isWithinAutomaticLimits: withinLimits,
            contentHash: contentHash
        )
    }

    private static func deriveEncodedImagePreview(
        at fileURL: URL,
        inspection: EncodedImageInspection,
        limits: ClipboardPayloadImportLimits
    ) throws -> EncodedImageDerivedPreview {
        guard inspection.isValidImage,
              inspection.isWithinAutomaticLimits else {
            return EncodedImageDerivedPreview(
                thumbnailPNGData: skippedPreviewPNGData,
                fingerprint: nil,
                skipReason: .previewLimitExceeded
            )
        }
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, sourceOptions) else {
            return EncodedImageDerivedPreview(
                thumbnailPNGData: nil,
                fingerprint: nil,
                skipReason: .previewLimitExceeded
            )
        }
        let previewMaximumEdge = max(
            1,
            min(500, limits.maximumImageSourceEdge)
        )
        let previewOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: previewMaximumEdge,
            kCGImageSourceShouldCache: false,
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary
        guard let previewImage = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            previewOptions
        ),
        let pngData = pngData(for: previewImage),
        pngData.count <= limits.maximumPNGOutputBytes else {
            return EncodedImageDerivedPreview(
                thumbnailPNGData: nil,
                fingerprint: nil,
                skipReason: .previewLimitExceeded
            )
        }

        let sampleOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: ClipboardImageFingerprint.maximumSampleEdge,
            kCGImageSourceShouldCache: false,
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary
        let fingerprint = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            sampleOptions
        ).flatMap {
            try? streamedFingerprint(
                sampleImage: $0,
                originalWidth: inspection.orientedWidth,
                originalHeight: inspection.orientedHeight
            )
        }
        return EncodedImageDerivedPreview(
            thumbnailPNGData: pngData,
            fingerprint: fingerprint,
            skipReason: nil
        )
    }

    private static func estimatedImageWorkingSetBytes(
        inspection: EncodedImageInspection
    ) -> Int {
        guard inspection.isWithinAutomaticLimits else {
            return skippedPreviewPNGData.count
        }
        let maximumPreviewPixels = 500 * 500
        let sourcePixels = inspection.orientedWidth.multipliedReportingOverflow(
            by: inspection.orientedHeight
        )
        let previewPixels = sourcePixels.overflow
            ? maximumPreviewPixels
            : min(maximumPreviewPixels, max(0, sourcePixels.partialValue))
        let previewRGBABytes = previewPixels.multipliedReportingOverflow(by: 4)
        let boundedPreviewBytes = previewRGBABytes.overflow
            ? Int.max
            : previewRGBABytes.partialValue
        return saturatingSum([
            boundedPreviewBytes,
            boundedPreviewBytes,
            64 * 64 * 4
        ])
    }

    private static func estimatedRichTextWorkingSetBytes(
        _ stagedPayload: ClipboardStagedPayload,
        limits: ClipboardPayloadImportLimits
    ) -> Int {
        let parsesPayload: Bool
        switch stagedPayload.contentKind {
        case .richTextRTF:
            parsesPayload = stagedPayload.byteCount <= limits.maximumRTFInputBytes
        case .richTextHTML:
            parsesPayload = stagedPayload.byteCount <= limits.maximumHTMLInputBytes
        case .image, .pdf:
            parsesPayload = false
        }
        guard parsesPayload else {
            return 1 * 1_024 * 1_024
        }
        let expandedTextBytes = stagedPayload.byteCount.multipliedReportingOverflow(by: 4)
        return saturatingSum([
            stagedPayload.byteCount,
            expandedTextBytes.overflow ? Int.max : expandedTextBytes.partialValue,
            limits.maximumRichTextOutputBytes
        ])
    }

    private static func saturatingSum(_ values: [Int]) -> Int {
        values.reduce(0) { partial, value in
            let sum = partial.addingReportingOverflow(max(0, value))
            return sum.overflow ? Int.max : sum.partialValue
        }
    }

    private static func streamingSHA256(at fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 * 1_024 * 1_024),
              !chunk.isEmpty {
            try Task.checkCancellation()
            hasher.update(data: chunk)
        }
        return hasher.finalize()
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func pngData(for image: CGImage) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            return nil
        }
        return output as Data
    }

    // A durable thumbnail marker prevents automatic card preheating from falling
    // back to decoding an over-limit original. Explicit user previews can still
    // access the preserved source file.
    private static let skippedPreviewPNGData = Data([
        0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d,
        0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
        0x08, 0x06, 0x00, 0x00, 0x00, 0x1f, 0x15, 0xc4, 0x89, 0x00, 0x00, 0x00,
        0x0d, 0x49, 0x44, 0x41, 0x54, 0x08, 0x1d, 0x63, 0xf8, 0xcf, 0xc0, 0xf0,
        0x1f, 0x00, 0x05, 0x80, 0x02, 0x3f, 0x49, 0xc2, 0xf9, 0x59, 0x00, 0x00,
        0x00, 0x00, 0x49, 0x45, 0x4e, 0x44, 0xae, 0x42, 0x60, 0x82
    ])

    private static func streamedFingerprint(
        sampleImage: CGImage,
        originalWidth: Int,
        originalHeight: Int
    ) throws -> String {
        guard originalWidth > 0,
              originalHeight > 0,
              originalWidth <= UInt32.max,
              originalHeight <= UInt32.max else {
            throw ClipboardImageFingerprintError.sourceDimensionsTooLarge
        }
        let scale = min(
            Double(ClipboardImageFingerprint.maximumSampleEdge) / Double(originalWidth),
            Double(ClipboardImageFingerprint.maximumSampleEdge) / Double(originalHeight),
            1
        )
        let sampleWidth = max(1, Int(floor(Double(originalWidth) * scale)))
        let sampleHeight = max(1, Int(floor(Double(originalHeight) * scale)))
        var rgba = [UInt8](repeating: 0, count: sampleWidth * sampleHeight * 4)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            throw ClipboardImageFingerprintError.canonicalizationFailed
        }
        let bitmapInfo = CGBitmapInfo(
            rawValue: CGImageAlphaInfo.premultipliedLast.rawValue
                | CGBitmapInfo.byteOrder32Big.rawValue
        )
        let didRender = rgba.withUnsafeMutableBytes { bytes -> Bool in
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
            context.interpolationQuality = .high
            context.draw(
                sampleImage,
                in: CGRect(x: 0, y: 0, width: sampleWidth, height: sampleHeight)
            )
            return true
        }
        guard didRender else {
            throw ClipboardImageFingerprintError.canonicalizationFailed
        }

        var preimage = Data(ClipboardImageFingerprint.currentVersion.utf8)
        appendBigEndian(UInt32(originalWidth), to: &preimage)
        appendBigEndian(UInt32(originalHeight), to: &preimage)
        appendBigEndian(UInt16(sampleWidth), to: &preimage)
        appendBigEndian(UInt16(sampleHeight), to: &preimage)
        for offset in stride(from: 0, to: rgba.count, by: 4) {
            let alpha = rgba[offset + 3]
            guard alpha > 0 else {
                preimage.append(contentsOf: [0, 0])
                continue
            }
            let red = quantizedNibble(rgba[offset])
            let green = quantizedNibble(rgba[offset + 1])
            let blue = quantizedNibble(rgba[offset + 2])
            preimage.append((red << 4) | green)
            preimage.append((blue << 4) | quantizedNibble(alpha))
        }
        return SHA256.hash(data: preimage)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func appendBigEndian<T: FixedWidthInteger>(
        _ value: T,
        to data: inout Data
    ) {
        var bigEndian = value.bigEndian
        withUnsafeBytes(of: &bigEndian) {
            data.append(contentsOf: $0)
        }
    }

    private static func quantizedNibble(_ value: UInt8) -> UInt8 {
        UInt8(min(15, (Int(value) + 8) / 17))
    }

    private static func inspectPDF(at fileURL: URL) -> PDFInspection {
        guard let document = CGPDFDocument(fileURL as CFURL) else {
            return PDFInspection(pageCount: nil)
        }
        return PDFInspection(pageCount: document.numberOfPages)
    }

    private static func nonEmptyFallback(_ text: String?) -> String? {
        guard let normalized = text?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ),
        !normalized.isEmpty else {
            return nil
        }
        return normalized
    }

    private static func richTextPlaceholder(byteCount: Int) -> String {
        "Rich text payload (\(max(0, byteCount)) bytes)"
    }

    private static func rtfData(forPlainText plainText: String) throws -> Data {
        let attributedString = NSAttributedString(string: plainText)
        guard let data = try? attributedString.data(
            from: NSRange(location: 0, length: attributedString.length),
            documentAttributes: [
                .documentType: NSAttributedString.DocumentType.rtf
            ]
        ) else {
            throw ClipboardPayloadImportError.richTextOutputTooLarge
        }
        return data
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
