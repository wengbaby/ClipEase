import AppKit
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct StoredClipboardImage: Sendable {
    let fileName: String
    let width: Int
    let height: Int
    let hash: String
    let reservation: ClipboardAttachmentReservation?

    init(
        fileName: String,
        width: Int,
        height: Int,
        hash: String,
        reservation: ClipboardAttachmentReservation? = nil
    ) {
        self.fileName = fileName
        self.width = width
        self.height = height
        self.hash = hash
        self.reservation = reservation
    }

    static func hash(for imageData: Data) -> String {
        SHA256.hash(data: imageData)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    static func hash(for image: NSImage) -> String? {
        image.pngData().map(hash(for:))
    }
}

struct StoredRichText: Sendable {
    let fileName: String
    let reservation: ClipboardAttachmentReservation?

    init(fileName: String, reservation: ClipboardAttachmentReservation? = nil) {
        self.fileName = fileName
        self.reservation = reservation
    }
}

enum ClipboardRichTextRawStorage: Sendable {
    case primaryRTF
    case htmlCompanion
}

struct ClipboardRichTextRawAsset: @unchecked Sendable {
    let stagedPayload: ClipboardStagedPayload
    let storage: ClipboardRichTextRawStorage
}

struct StoredOwnedClipboardFile: Sendable {
    let fileName: String
    let fileURL: URL
    let byteCount: Int
    let reservation: ClipboardAttachmentReservation?
}

struct ClipboardEncodedImagePromotion: Sendable {
    let storedImage: StoredClipboardImage
    let previewSkipReason: ClipboardPayloadProcessingReason?
}

struct RichTextStagingHandle: @unchecked Sendable {
    let fileName: String
    let fileURL: URL
}

struct ClipboardImageStagingSource: @unchecked Sendable {
    let cgImage: CGImage
}

enum ClipboardImageStagingError: Error, Equatable {
    case encodingFailed
    case outputTooLarge
    case writeFailed
    case thumbnailFailed
    case diskFull
}

private final class ClipboardHistoryFileManagerReference: @unchecked Sendable {
    let value: FileManager

    init(_ value: FileManager) {
        self.value = value
    }
}

struct ClipboardAttachmentCleanup: Equatable, Sendable {
    static let empty = ClipboardAttachmentCleanup()

    let imageFileNames: Set<String>
    let richTextFileNames: Set<String>

    init(
        imageFileNames: Set<String> = [],
        richTextFileNames: Set<String> = []
    ) {
        self.imageFileNames = imageFileNames
        self.richTextFileNames = richTextFileNames
    }

    init(
        items: [ClipboardItem],
        preservingImageFileNames: Set<String> = [],
        preservingRichTextFileNames: Set<String> = []
    ) {
        imageFileNames = Set(items.compactMap(\.imageFileName))
            .subtracting(preservingImageFileNames)
        richTextFileNames = Set(items.compactMap(\.richTextFileName))
            .subtracting(preservingRichTextFileNames)
    }

    var isEmpty: Bool {
        imageFileNames.isEmpty && richTextFileNames.isEmpty
    }

    func union(_ other: ClipboardAttachmentCleanup) -> ClipboardAttachmentCleanup {
        ClipboardAttachmentCleanup(
            imageFileNames: imageFileNames.union(other.imageFileNames),
            richTextFileNames: richTextFileNames.union(other.richTextFileNames)
        )
    }

    func subtracting(_ other: ClipboardAttachmentCleanup) -> ClipboardAttachmentCleanup {
        ClipboardAttachmentCleanup(
            imageFileNames: imageFileNames.subtracting(other.imageFileNames),
            richTextFileNames: richTextFileNames.subtracting(other.richTextFileNames)
        )
    }
}

// The repository existential is not Sendable. Existing repository calls retain
// their caller-owned serialization; detached image staging captures only the
// file manager, reservation registry, and staging hook, and never the repository.
struct ClipboardHistoryPersistence: @unchecked Sendable {
    private static let thumbnailMaxPixelSize = CGSize(width: 500, height: 360)

    private let fileManager: FileManager
    private let repository: any ClipboardHistoryRepository
    private let richTextWriter: @Sendable (Data, RichTextStagingHandle) async throws -> Void
    private let richTextFileName: @Sendable () -> String
    private let imageStagingWillWrite: @Sendable () -> Void
    private let encodedImageThumbnailWriter: @Sendable (Data, URL) throws -> Void
    private let attachmentCleanupRetryLedger: ClipboardAttachmentCleanupRetryLedger?
    private let attachmentCleanupRetryWasRequested: Bool
    private let attachmentCleanupRetryNow: @Sendable () -> Date
    let attachmentReservations: ClipboardAttachmentReservationRegistry

    init(
        fileManager: FileManager = .default,
        attachmentCleanupRetryPolicy: ClipboardAttachmentCleanupRetryPolicy = .enterpriseDefault,
        attachmentCleanupRetryLedgerURL: URL? = nil,
        attachmentCleanupRetryNow: @escaping @Sendable () -> Date = { Date() },
        richTextWriter: (@Sendable (Data, RichTextStagingHandle) async throws -> Void)? = nil,
        richTextFileName: @escaping @Sendable () -> String = { "\(UUID().uuidString).rtf" },
        imageStagingWillWrite: @escaping @Sendable () -> Void = {},
        encodedImageThumbnailWriter: @escaping @Sendable (Data, URL) throws -> Void = {
            try $0.write(to: $1, options: .atomic)
        },
        attachmentReservations: ClipboardAttachmentReservationRegistry? = nil
    ) {
        self.fileManager = fileManager
        let retryLedgerURL = attachmentCleanupRetryLedgerURL
            ?? (try? ClipEaseStoragePaths.applicationSupportDirectory(fileManager: fileManager)
                .appendingPathComponent(
                    "attachment-cleanup-retry-v1.json",
                    isDirectory: false
                ))
        self.attachmentCleanupRetryLedger = retryLedgerURL.map {
            ClipboardAttachmentCleanupRetryLedger(
                ledgerURL: $0,
                fileManager: fileManager,
                policy: attachmentCleanupRetryPolicy
            )
        }
        self.attachmentCleanupRetryWasRequested = true
        self.attachmentCleanupRetryNow = attachmentCleanupRetryNow
        let attachmentReservations = attachmentReservations ?? ClipboardAttachmentReservationRegistry()
        self.attachmentReservations = attachmentReservations
        let sqliteURL = (try? ClipEaseStoragePaths.sqliteStoreURL(fileManager: fileManager))
            ?? URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("ClipEase.sqlite")
        self.repository = SQLiteClipboardStore(databaseURL: sqliteURL, fileManager: fileManager)
        let fileManagerReference = ClipboardHistoryFileManagerReference(fileManager)
        self.richTextWriter = richTextWriter ?? { data, handle in
            try await Task.detached(priority: .utility) {
                try fileManagerReference.value.createDirectory(
                    at: handle.fileURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try data.write(to: handle.fileURL, options: [.atomic])
            }.value
        }
        self.richTextFileName = richTextFileName
        self.imageStagingWillWrite = imageStagingWillWrite
        self.encodedImageThumbnailWriter = encodedImageThumbnailWriter
    }

    init(
        fileManager: FileManager = .default,
        repository: any ClipboardHistoryRepository,
        attachmentCleanupRetryPolicy: ClipboardAttachmentCleanupRetryPolicy? = nil,
        attachmentCleanupRetryLedgerURL: URL? = nil,
        attachmentCleanupRetryNow: @escaping @Sendable () -> Date = { Date() },
        richTextWriter: (@Sendable (Data, RichTextStagingHandle) async throws -> Void)? = nil,
        richTextFileName: @escaping @Sendable () -> String = { "\(UUID().uuidString).rtf" },
        imageStagingWillWrite: @escaping @Sendable () -> Void = {},
        encodedImageThumbnailWriter: @escaping @Sendable (Data, URL) throws -> Void = {
            try $0.write(to: $1, options: .atomic)
        },
        attachmentReservations: ClipboardAttachmentReservationRegistry? = nil
    ) {
        self.fileManager = fileManager
        self.repository = repository
        let retryLedgerURL = attachmentCleanupRetryLedgerURL
            ?? (attachmentCleanupRetryPolicy.flatMap { _ in
                try? ClipEaseStoragePaths.applicationSupportDirectory(fileManager: fileManager)
                    .appendingPathComponent(
                        "attachment-cleanup-retry-v1.json",
                        isDirectory: false
                    )
            })
        self.attachmentCleanupRetryLedger = attachmentCleanupRetryPolicy.flatMap { policy in
            retryLedgerURL.map {
                ClipboardAttachmentCleanupRetryLedger(
                    ledgerURL: $0,
                    fileManager: fileManager,
                    policy: policy
                )
            }
        }
        self.attachmentCleanupRetryWasRequested = attachmentCleanupRetryPolicy != nil
        self.attachmentCleanupRetryNow = attachmentCleanupRetryNow
        let attachmentReservations = attachmentReservations ?? ClipboardAttachmentReservationRegistry()
        self.attachmentReservations = attachmentReservations
        let fileManagerReference = ClipboardHistoryFileManagerReference(fileManager)
        self.richTextWriter = richTextWriter ?? { data, handle in
            try await Task.detached(priority: .utility) {
                try fileManagerReference.value.createDirectory(
                    at: handle.fileURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try data.write(to: handle.fileURL, options: [.atomic])
            }.value
        }
        self.richTextFileName = richTextFileName
        self.imageStagingWillWrite = imageStagingWillWrite
        self.encodedImageThumbnailWriter = encodedImageThumbnailWriter
    }

    func loadSnapshot() -> ClipboardHistorySnapshot {
        do {
            return try loadSnapshotOrThrow()
        } catch {
            NSLog("ClipEase failed to load clipboard history: \(error.localizedDescription)")
            return ClipboardHistorySnapshot(items: [], groups: [])
        }
    }

    func loadSnapshotOrThrow() throws -> ClipboardHistorySnapshot {
        try repository.loadSnapshot()
    }

    func loadSnapshot(itemLimit: Int, offset: Int = 0) -> ClipboardHistorySnapshot {
        do {
            return try repository.loadSnapshot(itemLimit: itemLimit, offset: offset)
        } catch {
            NSLog("ClipEase failed to load clipboard history page snapshot: \(error.localizedDescription)")
            return ClipboardHistorySnapshot(items: [], groups: [])
        }
    }

    func loadItems() -> [ClipboardItem] {
        loadSnapshot().items
    }

    func loadItems(limit: Int, offset: Int = 0) -> [ClipboardItem] {
        do {
            return try repository.loadItems(limit: limit, offset: offset)
        } catch {
            NSLog("ClipEase failed to load clipboard history page: \(error.localizedDescription)")
            return []
        }
    }

    func loadItemPage(
        limit: Int,
        after cursor: HistoryPagingService.ItemCursor?
    ) -> HistoryPagingService.ItemPage {
        do {
            return try repository.loadItemPage(limit: limit, after: cursor)
        } catch {
            NSLog("ClipEase failed to load clipboard history cursor page: \(error.localizedDescription)")
            return HistoryPagingService.ItemPage(items: [])
        }
    }

    func loadItems(contentHash: String, sourceBundleID: String?) -> [ClipboardItem] {
        do {
            return try repository.loadItems(contentHash: contentHash, sourceBundleID: sourceBundleID)
        } catch {
            NSLog("ClipEase failed to load clipboard history duplicates: \(error.localizedDescription)")
            return []
        }
    }

    func backfillContentDigests(limit: Int = SQLiteContentDigest.batchSize) -> Int {
        do {
            return try backfillContentDigestsOrThrow(limit: limit)
        } catch {
            NSLog("ClipEase failed to backfill clipboard content digests: \(error.localizedDescription)")
            return 0
        }
    }

    /// Background maintenance uses this boundary so a failed batch cannot be
    /// mistaken for an already-complete migration. The compatibility wrapper
    /// above intentionally retains its non-throwing UI-facing contract.
    func backfillContentDigestsOrThrow(
        limit: Int = SQLiteContentDigest.batchSize
    ) throws -> Int {
        try backfillContentDigestsResultOrThrow(limit: limit).backfilledCount
    }

    func backfillContentDigestsResultOrThrow(
        limit: Int = SQLiteContentDigest.batchSize
    ) throws -> ClipboardDigestBackfillResult {
        try repository.backfillContentDigestsResult(limit: limit)
    }

    func prepareSearchIndex() {
        do {
            try prepareSearchIndexOrThrow()
        } catch {
            NSLog("ClipEase failed to prepare clipboard search index: \(error.localizedDescription)")
        }
    }

    func prepareSearchIndexOrThrow() throws {
        try repository.prepareSearchIndex()
    }

    func searchItems(_ query: ClipboardSearchQuery) -> [ClipboardItem] {
        do {
            return try repository.searchItems(query)
        } catch {
            NSLog("ClipEase failed to search clipboard history: \(error.localizedDescription)")
            return []
        }
    }

    func searchPage(
        _ query: ClipboardSearchQuery,
        after cursor: ClipboardSearchCursor?,
        cancellation: ClipboardSearchCancellationToken
    ) throws -> ClipboardSearchPage {
        try repository.searchPage(
            query,
            after: cursor,
            cancellation: cancellation
        )
    }

    func saveSnapshot(_ snapshot: ClipboardHistorySnapshot) {
        do {
            try saveSnapshotOrThrow(snapshot)
        } catch {
            NSLog("ClipEase failed to save clipboard history: \(error.localizedDescription)")
        }
    }

    func saveSnapshotOrThrow(_ snapshot: ClipboardHistorySnapshot) throws {
        try repository.saveSnapshot(snapshot)
    }

    func insertItemsOrThrow(_ items: [ClipboardItem]) throws {
        try repository.insertItems(items)
    }

    func upsertGroupsOrThrow(_ groups: [ClipboardGroup]) throws {
        try repository.upsertGroups(groups)
    }

    func upsertItemOrThrow(_ item: ClipboardItem, deleting deletedIDs: Set<ClipboardItem.ID>, groups: [ClipboardGroup]) throws {
        try repository.upsertItem(item, deleting: deletedIDs, groups: groups)
    }

    func applyMutationsOrThrow(_ mutations: [ClipboardHistoryRepositoryMutation]) throws {
        guard !mutations.isEmpty else {
            return
        }
        try repository.applyMutations(mutations)
    }

    @discardableResult
    func compensateImportedItemOrThrow(
        insertedItemID: ClipboardItem.ID,
        restoring displacedItems: [ClipboardItem]
    ) throws -> ClipboardAttachmentCleanup {
        try repository.compensateImportedItem(
            insertedItemID: insertedItemID,
            restoring: displacedItems
        )
    }

    @discardableResult
    func deleteItemsOrThrow(
        with ids: Set<ClipboardItem.ID>,
        deletingGroups groupIDs: Set<ClipboardGroup.ID>
    ) throws -> ClipboardAttachmentCleanup {
        try repository.deleteItems(with: ids, deletingGroups: groupIDs)
    }

    @discardableResult
    func deleteAllItemsOrThrow(
        preserving groups: [ClipboardGroup]
    ) throws -> ClipboardAttachmentCleanup {
        try repository.deleteAllItems(preserving: groups)
    }

    @discardableResult
    func deleteExpiredItemsOrThrow(before cutoff: Date) throws -> ClipboardAttachmentCleanup {
        try repository.deleteExpiredItems(before: cutoff)
    }

    func deleteExpiredItemsWithResultOrThrow(
        before cutoff: Date
    ) throws -> ClipboardHistoryRetentionDeletionResult {
        try repository.deleteExpiredItemsWithResult(before: cutoff)
    }

    func compactDatabaseIfNeededOrThrow(
        policy: ClipboardDatabaseCompactionPolicy = .automatic
    ) throws -> ClipboardDatabaseCompactionResult {
        try repository.compactIfNeeded(policy: policy)
    }

    func saveItems(_ items: [ClipboardItem]) {
        saveSnapshot(ClipboardHistorySnapshot(items: items, groups: []))
    }

    func saveImage(_ image: NSImage) -> StoredClipboardImage? {
        guard let imageData = image.pngData(),
              let bitmap = NSBitmapImageRep(data: imageData) else {
            return nil
        }

        let hash = StoredClipboardImage.hash(for: imageData)
        let fileName = "\(UUID().uuidString).png"
        let reservation = attachmentReservations.reserve(
            ClipboardAttachmentCleanup(imageFileNames: [fileName])
        )

        do {
            let directoryURL = try ClipEaseStoragePaths.imagesDirectory(fileManager: fileManager)
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
            let imageURL = directoryURL.appendingPathComponent(fileName)
            try imageData.write(to: imageURL, options: [.atomic])
            saveThumbnail(for: image, fileName: fileName)
            return StoredClipboardImage(
                fileName: fileName,
                width: bitmap.pixelsWide,
                height: bitmap.pixelsHigh,
                hash: hash,
                reservation: reservation
            )
        } catch {
            reservation?.release()
            NSLog("ClipEase failed to save clipboard image: \(error.localizedDescription)")
            return nil
        }
    }

    func stageImage(
        _ source: ClipboardImageStagingSource,
        maximumPNGBytes: Int
    ) async throws -> StoredClipboardImage {
        let fileManager = self.fileManager
        let attachmentReservations = self.attachmentReservations
        let imageStagingWillWrite = self.imageStagingWillWrite
        let operation = Task.detached(priority: .utility) {
            let fileName = "\(UUID().uuidString).png"
            var reservation: ClipboardAttachmentReservation?
            do {
                try Task.checkCancellation()
                reservation = attachmentReservations.reserve(
                    ClipboardAttachmentCleanup(imageFileNames: [fileName])
                )
                try Task.checkCancellation()
                guard let imageData = Self.pngData(for: source.cgImage) else {
                    throw ClipboardImageStagingError.encodingFailed
                }
                guard imageData.count <= max(0, maximumPNGBytes) else {
                    throw ClipboardImageStagingError.outputTooLarge
                }
                let hash = StoredClipboardImage.hash(for: imageData)
                try Task.checkCancellation()
                guard let thumbnail = Self.thumbnail(
                    for: source.cgImage,
                    maxPixelSize: Self.thumbnailMaxPixelSize
                ),
                let thumbnailData = Self.pngData(for: thumbnail) else {
                    throw ClipboardImageStagingError.thumbnailFailed
                }

                imageStagingWillWrite()
                try Task.checkCancellation()

                do {
                    let directoryURL = try ClipEaseStoragePaths.imagesDirectory(fileManager: fileManager)
                    try fileManager.createDirectory(
                        at: directoryURL,
                        withIntermediateDirectories: true
                    )
                    try imageData.write(
                        to: directoryURL.appendingPathComponent(fileName),
                        options: .atomic
                    )
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    throw Self.isDiskFull(error)
                        ? ClipboardImageStagingError.diskFull
                        : ClipboardImageStagingError.writeFailed
                }

                try Task.checkCancellation()
                do {
                    let directoryURL = try ClipEaseStoragePaths.thumbnailsDirectory(fileManager: fileManager)
                    try fileManager.createDirectory(
                        at: directoryURL,
                        withIntermediateDirectories: true
                    )
                    try thumbnailData.write(
                        to: directoryURL.appendingPathComponent(fileName),
                        options: .atomic
                    )
                } catch is CancellationError {
                    throw CancellationError()
                } catch let error as ClipboardImageStagingError {
                    throw error
                } catch {
                    throw Self.isDiskFull(error)
                        ? ClipboardImageStagingError.diskFull
                        : ClipboardImageStagingError.thumbnailFailed
                }

                try Task.checkCancellation()
                return StoredClipboardImage(
                    fileName: fileName,
                    width: source.cgImage.width,
                    height: source.cgImage.height,
                    hash: hash,
                    reservation: reservation
                )
            } catch {
                Self.rollbackOwnedStagedImage(
                    fileName: fileName,
                    fileManager: fileManager,
                    reservation: reservation
                )
                throw error
            }
        }

        return try await withTaskCancellationHandler {
            try await operation.value
        } onCancel: {
            operation.cancel()
        }
    }

    func promoteEncodedImage(
        _ stagedPayload: ClipboardStagedPayload,
        width: Int,
        height: Int,
        hash: String,
        thumbnailPNGData: Data?
    ) async throws -> ClipboardEncodedImagePromotion {
        let fileManager = self.fileManager
        let attachmentReservations = self.attachmentReservations
        let encodedImageThumbnailWriter = self.encodedImageThumbnailWriter
        return try await Task.detached(priority: .utility) {
            let fileExtension = stagedPayload.preferredFileExtension ?? "image"
            let fileName = "\(UUID().uuidString).\(fileExtension)"
            let reservation = attachmentReservations.reserve(
                ClipboardAttachmentCleanup(imageFileNames: [fileName])
            )
            do {
                try Task.checkCancellation()
                let imageURL = try ClipEaseStoragePaths.imageFileURL(
                    fileName: fileName,
                    fileManager: fileManager
                )
                try stagedPayload.promote(to: imageURL)

                var previewSkipReason: ClipboardPayloadProcessingReason?
                if let thumbnailPNGData {
                    do {
                        let thumbnailURL = try ClipEaseStoragePaths.thumbnailFileURL(
                            fileName: fileName,
                            fileManager: fileManager
                        )
                        try fileManager.createDirectory(
                            at: thumbnailURL.deletingLastPathComponent(),
                            withIntermediateDirectories: true
                        )
                        try encodedImageThumbnailWriter(
                            thumbnailPNGData,
                            thumbnailURL
                        )
                    } catch {
                        previewSkipReason = Self.isDiskFull(error)
                            ? .diskFull
                            : .previewLimitExceeded
                    }
                } else {
                    previewSkipReason = .previewLimitExceeded
                }

                return ClipboardEncodedImagePromotion(
                    storedImage: StoredClipboardImage(
                        fileName: fileName,
                        width: max(0, width),
                        height: max(0, height),
                        hash: hash,
                        reservation: reservation
                    ),
                    previewSkipReason: previewSkipReason
                )
            } catch {
                reservation?.release()
                throw error
            }
        }.value
    }

    func promoteOwnedPDF(
        _ stagedPayload: ClipboardStagedPayload
    ) async throws -> StoredOwnedClipboardFile {
        let fileManager = self.fileManager
        let attachmentReservations = self.attachmentReservations
        return try await Task.detached(priority: .utility) {
            let fileName = "\(UUID().uuidString).pdf"
            let reservation = attachmentReservations.reserve(
                ClipboardAttachmentCleanup(richTextFileNames: [fileName])
            )
            do {
                let fileURL = try ClipEaseStoragePaths.richTextFileURL(
                    fileName: fileName,
                    fileManager: fileManager
                )
                try stagedPayload.promote(to: fileURL)
                return StoredOwnedClipboardFile(
                    fileName: fileName,
                    fileURL: fileURL,
                    byteCount: stagedPayload.byteCount,
                    reservation: reservation
                )
            } catch {
                reservation?.release()
                throw error
            }
        }.value
    }

    private static func rollbackOwnedStagedImage(
        fileName: String,
        fileManager: FileManager,
        reservation: ClipboardAttachmentReservation?
    ) {
        defer { reservation?.release() }
        if let imageURL = try? ClipEaseStoragePaths.imageFileURL(
            fileName: fileName,
            fileManager: fileManager
        ) {
            try? fileManager.removeItem(at: imageURL)
        }
        if let thumbnailURL = try? ClipEaseStoragePaths.thumbnailFileURL(
            fileName: fileName,
            fileManager: fileManager
        ) {
            try? fileManager.removeItem(at: thumbnailURL)
        }
    }

    func saveLinkPreviewImage(
        _ image: LinkPreviewDecodedImage
    ) -> StoredClipboardImage? {
        guard let imageData = Self.pngData(for: image.cgImage) else {
            return nil
        }

        let hash = StoredClipboardImage.hash(for: imageData)
        let fileName = "\(UUID().uuidString).png"
        let reservation = attachmentReservations.reserve(
            ClipboardAttachmentCleanup(imageFileNames: [fileName])
        )
        do {
            let directoryURL = try ClipEaseStoragePaths.imagesDirectory(fileManager: fileManager)
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
            try imageData.write(
                to: directoryURL.appendingPathComponent(fileName),
                options: .atomic
            )
            saveThumbnail(for: image.cgImage, fileName: fileName)
            return StoredClipboardImage(
                fileName: fileName,
                width: image.pixelWidth,
                height: image.pixelHeight,
                hash: hash,
                reservation: reservation
            )
        } catch {
            reservation?.release()
            NSLog("ClipEase failed to save link preview image: \(error.localizedDescription)")
            return nil
        }
    }

    func imageData(fileName: String) -> Data? {
        guard let imageURL = try? ClipEaseStoragePaths.imageFileURL(
            fileName: fileName,
            fileManager: fileManager
        ) else {
            return nil
        }

        return try? Data(contentsOf: imageURL)
    }

    func deleteImage(fileName: String) {
        guard let imageURL = try? ClipEaseStoragePaths.imageFileURL(
            fileName: fileName,
            fileManager: fileManager
        ) else {
            return
        }

        try? fileManager.removeItem(at: imageURL)
        deleteThumbnail(fileName: fileName)
    }

    func thumbnailImage(fileName: String) -> NSImage? {
        if let thumbnailURL = try? ClipEaseStoragePaths.thumbnailFileURL(
            fileName: fileName,
            fileManager: fileManager
        ),
           fileManager.fileExists(atPath: thumbnailURL.path),
           let image = NSImage(contentsOf: thumbnailURL) {
            return image
        }

        guard let imageURL = try? ClipEaseStoragePaths.imageFileURL(
            fileName: fileName,
            fileManager: fileManager
        ),
              let image = NSImage(contentsOf: imageURL) else {
            return nil
        }

        saveThumbnail(for: image, fileName: fileName)
        return NSImage(
            contentsOf: (try? ClipEaseStoragePaths.thumbnailFileURL(
                fileName: fileName,
                fileManager: fileManager
            )) ?? imageURL
        ) ?? image
    }

    func deleteThumbnail(fileName: String) {
        guard let thumbnailURL = try? ClipEaseStoragePaths.thumbnailFileURL(
            fileName: fileName,
            fileManager: fileManager
        ) else {
            return
        }

        try? fileManager.removeItem(at: thumbnailURL)
    }

    static func clearThumbnailCache(fileManager: FileManager = .default) {
        guard let directoryURL = try? ClipEaseStoragePaths.thumbnailsDirectory(fileManager: fileManager) else {
            return
        }

        try? fileManager.removeItem(at: directoryURL)
    }

    func saveRichText(_ data: Data) async -> StoredRichText? {
        do {
            return try await saveRichTextOrThrow(data)
        } catch {
            NSLog("ClipEase failed to save rich text: \(error.localizedDescription)")
            return nil
        }
    }

    func saveRichTextOrThrow(
        _ data: Data,
        rawAsset: ClipboardRichTextRawAsset? = nil
    ) async throws -> StoredRichText {
        let fileName = richTextFileName()
        let reservation = attachmentReservations.reserve(ClipboardAttachmentCleanup(richTextFileNames: [fileName]))
        do {
            let stored = StoredRichText(fileName: fileName, reservation: reservation)
            let fileURL = try ClipEaseStoragePaths.richTextFileURL(
                fileName: fileName,
                fileManager: fileManager
            )
            switch rawAsset?.storage {
            case .primaryRTF:
                try rawAsset?.stagedPayload.promote(to: fileURL)
            case .htmlCompanion:
                try await richTextWriter(
                    data,
                    RichTextStagingHandle(fileName: fileName, fileURL: fileURL)
                )
                if let stagedPayload = rawAsset?.stagedPayload {
                    try stagedPayload.promote(
                        to: Self.rawHTMLCompanionURL(
                            forRichTextFileName: fileName,
                            fileManager: fileManager
                        )
                    )
                }
            case nil:
                try await richTextWriter(
                    data,
                    RichTextStagingHandle(fileName: fileName, fileURL: fileURL)
                )
            }
            return stored
        } catch {
            discardStagedAttachment(reservation)
            throw error
        }
    }

    func overwriteRichText(fileName: String, data: Data) -> Bool {
        do {
            let directoryURL = try ClipEaseStoragePaths.richTextsDirectory(fileManager: fileManager)
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
            let fileURL = try ClipEaseStoragePaths.richTextFileURL(
                fileName: fileName,
                fileManager: fileManager
            )
            try data.write(to: fileURL, options: [.atomic])
            return true
        } catch {
            NSLog("ClipEase failed to overwrite rich text: \(error.localizedDescription)")
            return false
        }
    }

    func richTextData(fileName: String) -> Data? {
        guard let fileURL = try? ClipEaseStoragePaths.richTextFileURL(
            fileName: fileName,
            fileManager: fileManager
        ) else {
            return nil
        }

        return try? Data(contentsOf: fileURL)
    }

    func deleteRichText(fileName: String) {
        guard let fileURL = try? ClipEaseStoragePaths.richTextFileURL(
            fileName: fileName,
            fileManager: fileManager
        ) else {
            return
        }

        try? fileManager.removeItem(at: fileURL)
        if let rawHTMLURL = try? Self.rawHTMLCompanionURL(
            forRichTextFileName: fileName,
            fileManager: fileManager
        ) {
            try? fileManager.removeItem(at: rawHTMLURL)
        }
    }

    private func deleteAttachments(_ cleanup: ClipboardAttachmentCleanup) {
        cleanup.imageFileNames.forEach(deleteImage)
        cleanup.richTextFileNames.forEach(deleteRichText)
    }

    @discardableResult
    func deleteUnreferencedAttachments(
        _ candidates: ClipboardAttachmentCleanup
    ) -> OrphanedAttachmentCleanupResult {
        guard !candidates.isEmpty else {
            return OrphanedAttachmentCleanupResult(removedFiles: 0, removedBytes: 0)
        }

        do {
            return try scheduleAttachmentCleanupWithResultOrThrow(candidates).cleanupResult
        } catch {
            let nsError = error as NSError
            NSLog(
                "ClipEase failed to schedule attachment cleanup retry; errorType=%@ code=%d",
                String(describing: type(of: error)),
                nsError.code
            )
            return OrphanedAttachmentCleanupResult(removedFiles: 0, removedBytes: 0)
        }
    }

    var hasPersistentAttachmentCleanupRetryLedger: Bool {
        attachmentCleanupRetryWasRequested
    }

    func scheduleAttachmentCleanupOrThrow(
        _ candidates: ClipboardAttachmentCleanup
    ) throws -> ClipboardAttachmentCleanupRetryStatus {
        try scheduleAttachmentCleanupWithResultOrThrow(candidates).status
    }

    func replayPendingAttachmentCleanupOrThrow()
        throws -> ClipboardAttachmentCleanupRetryStatus {
        try replayPendingAttachmentCleanupWithResultOrThrow().status
    }

    func attachmentCleanupRetryStatusOrThrow()
        throws -> ClipboardAttachmentCleanupRetryStatus {
        guard attachmentCleanupRetryWasRequested else {
            return .empty
        }
        guard let attachmentCleanupRetryLedger else {
            throw ClipboardAttachmentCleanupRetryError.ledgerUnavailable
        }
        return try attachmentCleanupRetryLedger.status(now: attachmentCleanupRetryNow())
    }

    private func scheduleAttachmentCleanupWithResultOrThrow(
        _ candidates: ClipboardAttachmentCleanup
    ) throws -> (
        cleanupResult: OrphanedAttachmentCleanupResult,
        status: ClipboardAttachmentCleanupRetryStatus
    ) {
        guard attachmentCleanupRetryWasRequested else {
            return (
                try deleteUnreferencedAttachmentCandidatesOrThrow(candidates),
                .empty
            )
        }
        guard let attachmentCleanupRetryLedger else {
            throw ClipboardAttachmentCleanupRetryError.ledgerUnavailable
        }

        try attachmentCleanupRetryLedger.enqueue(
            candidates,
            now: attachmentCleanupRetryNow()
        )
        return try replayPendingAttachmentCleanupWithResultOrThrow()
    }

    private func replayPendingAttachmentCleanupWithResultOrThrow()
        throws -> (
            cleanupResult: OrphanedAttachmentCleanupResult,
            status: ClipboardAttachmentCleanupRetryStatus
        ) {
        guard attachmentCleanupRetryWasRequested else {
            return (
                OrphanedAttachmentCleanupResult(removedFiles: 0, removedBytes: 0),
                .empty
            )
        }
        guard let attachmentCleanupRetryLedger else {
            throw ClipboardAttachmentCleanupRetryError.ledgerUnavailable
        }

        let now = attachmentCleanupRetryNow()
        let claims = try attachmentCleanupRetryLedger.claimDueEntries(now: now)
        var completions: [ClipboardAttachmentCleanupRetryCompletion] = []
        completions.reserveCapacity(claims.count)
        var removedFiles = 0
        var removedBytes: UInt64 = 0

        for claim in claims {
            do {
                let result = try deleteUnreferencedAttachmentCandidatesOrThrow(
                    claim.candidates
                )
                removedFiles += result.removedFiles
                removedBytes += result.removedBytes
                completions.append(
                    ClipboardAttachmentCleanupRetryCompletion(
                        id: claim.id,
                        outcome: .succeeded
                    )
                )
            } catch {
                completions.append(
                    ClipboardAttachmentCleanupRetryCompletion(
                        id: claim.id,
                        outcome: .failed(errorCode: (error as NSError).code)
                    )
                )
            }
        }

        do {
            try attachmentCleanupRetryLedger.apply(completions, now: now)
        } catch {
            attachmentCleanupRetryLedger.releaseClaims(claims)
            throw error
        }
        return (
            OrphanedAttachmentCleanupResult(
                removedFiles: removedFiles,
                removedBytes: removedBytes
            ),
            try attachmentCleanupRetryLedger.status(now: attachmentCleanupRetryNow())
        )
    }

    func deleteUnreferencedAttachmentCandidatesOrThrow(
        _ candidates: ClipboardAttachmentCleanup
    ) throws -> OrphanedAttachmentCleanupResult {
        guard !candidates.isEmpty else {
            return OrphanedAttachmentCleanupResult(removedFiles: 0, removedBytes: 0)
        }

        let referenced = try repository.referencedAttachments(in: candidates)
        let unreferenced = attachmentReservations.subtractingActiveReservations(
            from: candidates.subtracting(referenced)
        )
        guard let deletionClaim = attachmentReservations.claimDeletion(for: unreferenced) else {
            return OrphanedAttachmentCleanupResult(removedFiles: 0, removedBytes: 0)
        }
        defer { deletionClaim.complete() }
        var removedFiles = 0
        var removedBytes: UInt64 = 0

        for fileName in deletionClaim.candidates.imageFileNames {
            let imageResult = try removeAttachmentFile(
                at: ClipEaseStoragePaths.imageFileURL(fileName: fileName, fileManager: fileManager)
            )
            removedFiles += imageResult.files
            removedBytes += imageResult.bytes

            let thumbnailResult = try removeAttachmentFile(
                at: ClipEaseStoragePaths.thumbnailFileURL(fileName: fileName, fileManager: fileManager)
            )
            removedFiles += thumbnailResult.files
            removedBytes += thumbnailResult.bytes
        }

        for fileName in deletionClaim.candidates.richTextFileNames {
            let result = try removeAttachmentFile(
                at: ClipEaseStoragePaths.richTextFileURL(fileName: fileName, fileManager: fileManager)
            )
            removedFiles += result.files
            removedBytes += result.bytes
            let rawHTMLResult = try removeAttachmentFile(
                at: Self.rawHTMLCompanionURL(
                    forRichTextFileName: fileName,
                    fileManager: fileManager
                )
            )
            removedFiles += rawHTMLResult.files
            removedBytes += rawHTMLResult.bytes
        }

        return OrphanedAttachmentCleanupResult(
            removedFiles: removedFiles,
            removedBytes: removedBytes
        )
    }

    func discardStagedAttachment(_ reservation: ClipboardAttachmentReservation?) {
        guard let reservation else {
            return
        }
        let candidates = reservation.candidates
        reservation.release()
        _ = deleteUnreferencedAttachments(candidates)
    }

    func rollbackOwnedStagedImageBeforeCommit(_ storedImage: StoredClipboardImage) async {
        let fileManager = self.fileManager
        await Task.detached(priority: .utility) {
            Self.rollbackOwnedStagedImage(
                fileName: storedImage.fileName,
                fileManager: fileManager,
                reservation: storedImage.reservation
            )
        }.value
    }

    func rollbackOwnedStagedRichTextBeforeCommit(_ storedRichText: StoredRichText) async {
        let fileManager = self.fileManager
        await Task.detached(priority: .utility) {
            defer { storedRichText.reservation?.release() }
            guard let fileURL = try? ClipEaseStoragePaths.richTextFileURL(
                fileName: storedRichText.fileName,
                fileManager: fileManager
            ) else { return }
            try? fileManager.removeItem(at: fileURL)
            if let rawHTMLURL = try? Self.rawHTMLCompanionURL(
                forRichTextFileName: storedRichText.fileName,
                fileManager: fileManager
            ) {
                try? fileManager.removeItem(at: rawHTMLURL)
            }
        }.value
    }

    func rollbackOwnedFileBeforeCommit(_ storedFile: StoredOwnedClipboardFile) async {
        let fileManager = self.fileManager
        await Task.detached(priority: .utility) {
            defer { storedFile.reservation?.release() }
            try? fileManager.removeItem(at: storedFile.fileURL)
        }.value
    }

    private func removeAttachmentFile(at url: URL) throws -> (files: Int, bytes: UInt64) {
        guard fileManager.fileExists(atPath: url.path) else {
            return (0, 0)
        }

        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        let fileSize = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
        try fileManager.removeItem(at: url)
        return (1, fileSize)
    }

    private static func rawHTMLCompanionURL(
        forRichTextFileName fileName: String,
        fileManager: FileManager
    ) throws -> URL {
        let validName = try ClipEaseStoragePaths.validAttachmentBaseName(fileName)
        return try ClipEaseStoragePaths.richTextsDirectory(fileManager: fileManager)
            .appendingPathComponent(".\(validName).raw.html", isDirectory: false)
    }

    private static func isDiskFull(_ error: Error) -> Bool {
        ClipboardFileSystemErrorClassifier.isDiskFull(error)
    }

    private func saveThumbnail(for image: NSImage, fileName: String) {
        guard let thumbnail = image.clipeaseThumbnail(maxPixelSize: Self.thumbnailMaxPixelSize),
              let thumbnailData = thumbnail.pngData() else {
            return
        }

        do {
            let directoryURL = try ClipEaseStoragePaths.thumbnailsDirectory(fileManager: fileManager)
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
            let thumbnailURL = directoryURL.appendingPathComponent(fileName)
            try thumbnailData.write(to: thumbnailURL, options: [.atomic])
        } catch {
            NSLog("ClipEase failed to save clipboard thumbnail: \(error.localizedDescription)")
        }
    }

    private func saveThumbnail(for image: CGImage, fileName: String) {
        guard let thumbnail = Self.thumbnail(
            for: image,
            maxPixelSize: Self.thumbnailMaxPixelSize
        ),
        let thumbnailData = Self.pngData(for: thumbnail) else {
            return
        }

        do {
            let directoryURL = try ClipEaseStoragePaths.thumbnailsDirectory(fileManager: fileManager)
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
            try thumbnailData.write(
                to: directoryURL.appendingPathComponent(fileName),
                options: .atomic
            )
        } catch {
            NSLog("ClipEase failed to save link preview thumbnail: \(error.localizedDescription)")
        }
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

    private static func thumbnail(
        for image: CGImage,
        maxPixelSize: CGSize
    ) -> CGImage? {
        let sourceWidth = CGFloat(image.width)
        let sourceHeight = CGFloat(image.height)
        guard sourceWidth > 0, sourceHeight > 0 else {
            return nil
        }

        let scale = min(
            maxPixelSize.width / sourceWidth,
            maxPixelSize.height / sourceHeight,
            1
        )
        let width = max(1, Int(floor(sourceWidth * scale)))
        let height = max(1, Int(floor(sourceHeight * scale)))
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        context.interpolationQuality = .high
        context.draw(
            image,
            in: CGRect(x: 0, y: 0, width: width, height: height)
        )
        return context.makeImage()
    }
}

private extension NSImage {
    func pngData() -> Data? {
        guard let tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffRepresentation) else {
            return nil
        }

        return bitmap.representation(using: .png, properties: [:])
    }

    func clipeaseThumbnail(maxPixelSize: CGSize) -> NSImage? {
        guard let source = cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let sourceWidth = CGFloat(source.width)
        let sourceHeight = CGFloat(source.height)
        guard sourceWidth > 0, sourceHeight > 0 else {
            return nil
        }

        let scale = min(maxPixelSize.width / sourceWidth, maxPixelSize.height / sourceHeight, 1)
        let targetSize = NSSize(
            width: max(1, floor(sourceWidth * scale)),
            height: max(1, floor(sourceHeight * scale))
        )
        let image = NSImage(size: targetSize)
        image.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        NSImage(cgImage: source, size: NSSize(width: sourceWidth, height: sourceHeight))
            .draw(
                in: NSRect(origin: .zero, size: targetSize),
                from: NSRect(origin: .zero, size: NSSize(width: sourceWidth, height: sourceHeight)),
                operation: .copy,
                fraction: 1
            )
        image.unlockFocus()
        return image
    }
}
