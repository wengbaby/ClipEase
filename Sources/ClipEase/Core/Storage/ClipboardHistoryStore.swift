import Foundation
import AppKit
import UniformTypeIdentifiers

struct ClipboardItemFocusRequest: Equatable {
    enum Reason: Equatable {
        case inserted
        case refreshed
    }

    let id = UUID()
    let itemID: ClipboardItem.ID
    let reason: Reason

    init(itemID: ClipboardItem.ID, reason: Reason = .inserted) {
        self.itemID = itemID
        self.reason = reason
    }
}

struct ClipboardGroupDeletionResult: Equatable, Sendable {
    let deletedGroupIDs: Set<ClipboardGroup.ID>
    let removedItemCount: Int

    var didDeleteAnyGroup: Bool {
        !deletedGroupIDs.isEmpty
    }
}

private final class ClipboardSearchPagingCoordinator: @unchecked Sendable {
    struct CursorRequest: Sendable {
        let generation: UInt64
        let signature: Signature
        let cursor: ClipboardSearchCursor?
        let cancellation: ClipboardSearchCancellationToken
    }

    enum Request: Sendable {
        case cursor(CursorRequest)
        case compatibility
    }

    struct Signature: Equatable, Sendable {
        let text: String
        let limit: Int
        let filters: ClipboardSearchQueryFilters

        init(query: ClipboardSearchQuery) {
            text = query.text
            limit = query.limit
            filters = query.filters
        }
    }

    private let lock = NSLock()
    private var generation: UInt64 = 0
    private var activeSignature: Signature?
    private var loadedItemCount = 0
    private var nextCursor: ClipboardSearchCursor?
    private var activeCancellation: ClipboardSearchCancellationToken?

    func prepare(_ query: ClipboardSearchQuery) -> Request {
        var cancellationToSignal: ClipboardSearchCancellationToken?
        let request: Request = lock.withLock {
            let signature = Signature(query: query)
            if query.offset == 0 {
                cancellationToSignal = activeCancellation
                generation &+= 1
                let cancellation = ClipboardSearchCancellationToken()
                activeSignature = signature
                loadedItemCount = 0
                nextCursor = nil
                activeCancellation = cancellation
                return .cursor(CursorRequest(
                    generation: generation,
                    signature: signature,
                    cursor: nil,
                    cancellation: cancellation
                ))
            }

            guard activeSignature == signature,
                  query.offset == loadedItemCount,
                  let nextCursor,
                  let activeCancellation,
                  !activeCancellation.isCancelled else {
                cancellationToSignal = self.activeCancellation
                clearActiveRequest()
                return .compatibility
            }
            return .cursor(CursorRequest(
                generation: generation,
                signature: signature,
                cursor: nextCursor,
                cancellation: activeCancellation
            ))
        }
        cancellationToSignal?.cancel()
        return request
    }

    func complete(
        _ request: CursorRequest,
        page: ClipboardSearchPage
    ) -> Bool {
        lock.withLock {
            guard generation == request.generation,
                  activeSignature == request.signature,
                  activeCancellation === request.cancellation else {
                return false
            }
            loadedItemCount += page.items.count
            nextCursor = page.nextCursor
            return true
        }
    }

    func fail(_ request: CursorRequest) {
        let cancellation: ClipboardSearchCancellationToken? = lock.withLock {
            guard generation == request.generation,
                  activeSignature == request.signature,
                  activeCancellation === request.cancellation else {
                return nil
            }
            let cancellation = activeCancellation
            clearActiveRequest()
            return cancellation
        }
        cancellation?.cancel()
    }

    func cancelAll() {
        let cancellation: ClipboardSearchCancellationToken? = lock.withLock {
            generation &+= 1
            let cancellation = activeCancellation
            clearActiveRequest()
            return cancellation
        }
        cancellation?.cancel()
    }

    private func clearActiveRequest() {
        activeSignature = nil
        loadedItemCount = 0
        nextCursor = nil
        activeCancellation = nil
    }
}

@MainActor
final class ClipboardHistoryStore: ObservableObject {
    typealias ImageSelfWriteConsumer = @Sendable (Int, String?) async -> Bool

    private struct UpsertResult {
        let item: ClipboardItem
        let reusedLinkMetadata: Bool
    }

    private struct PreparedUpsert {
        let item: ClipboardItem
        let duplicateItems: [ClipboardItem]
        let duplicateIDs: Set<ClipboardItem.ID>
        let attachmentCleanup: ClipboardAttachmentCleanup
        let reusedLinkMetadata: Bool
        let startedAt: CFAbsoluteTime
    }

    @Published private(set) var items: [ClipboardItem] = [] {
        didSet {
            itemsMutationGeneration &+= 1
        }
    }
    private(set) var itemsMutationGeneration: UInt64 = 0
    @Published private(set) var groups: [ClipboardGroup] = []
    @Published private(set) var latestItemFocusRequest: ClipboardItemFocusRequest?
    @Published var retentionPolicy: HistoryRetentionPolicy {
        didSet {
            userDefaults.set(retentionPolicy.rawValue, forKey: Self.retentionPolicyKey)
            pruneExpiredItems(force: true)
        }
    }

    nonisolated private static let retentionPolicyKey = "history.retentionPolicy"
    nonisolated private static let debugTextPrefix = "轻贴性能测试文本 "
    nonisolated private static let debugBatchSize = 500
    nonisolated static let startupItemPageSize = HistoryPagingService.startupItemPageSize
    nonisolated static let incrementalItemPageSize = HistoryPagingService.incrementalItemPageSize
    private let persistence: ClipboardHistoryPersistence
    private let saveWriter: ClipboardHistorySaveWriter
    private let userDefaults: UserDefaults
    private var domainStore = ClipboardHistoryDomainStore()
    private let selfWriteGuard: ClipboardSelfWriteGuard
    private let imageSelfWriteConsumer: ImageSelfWriteConsumer
    private let ocrCoordinator: HistoryOCRCoordinator
    private let linkMetadataCoordinator: HistoryLinkMetadataCoordinator
    private let imageCommitWillBegin: @MainActor () -> Void
    private let imageOCRDidEnqueue: @MainActor (ClipboardItem) -> Void
    private let externalCopyFeedback: @MainActor (ClipboardItem) -> Void
    private var deferredSaveTask: Task<Void, Never>?
    private var requiresFullSnapshotSave = false
    private var debugGenerationTask: Task<Void, Never>?
    private var groupIndexByID: [ClipboardGroup.ID: Int] = [:]
    private var saveRevision = 0
    private var persistenceMutationGeneration: UInt64 = 0
    private var fullSnapshotPreparationError: ClipboardHistoryAuthoritativeSnapshotError?
    private var isLoadingNextPage = false
    private var didLoadAllPersistedItems = false
    private var nextPersistedItemOffset = 0
    private var nextPersistedItemCursor: HistoryPagingService.ItemCursor?
    private var pendingDeletedItemIDs = Set<ClipboardItem.ID>()
    private var pendingDeletedGroupIDs = Set<ClipboardGroup.ID>()
    private var pagedLoadTask: Task<Void, Never>?
    private var pagedLoadGeneration: UInt64 = 0
    private var searchIndexWarmupTask: Task<Void, Never>?
    private var pendingAttachmentCleanup = ClipboardAttachmentCleanup.empty
    private var activeRetentionCutoff: Date?
    private var retentionRunSchedule = HistoryRetentionRunSchedule()
    private var retentionRequestGeneration: UInt64 = 0
    private var pendingRetentionRequestGeneration: UInt64?
    private var pendingPageLoadReason: String?
    private var ocrOutcomeByItemID: [ClipboardItem.ID: ClipboardOCRExecutionOutcome] = [:]
    private var isTerminationDrainSealed = false
    private let searchPagingCoordinator = ClipboardSearchPagingCoordinator()

    var debugTextItemCount: Int {
        items.lazy.filter(Self.isDebugTextItem).count
    }

    var hasLoadedAllPersistedItems: Bool {
        didLoadAllPersistedItems
    }

    func authoritativeSnapshot() async throws -> ClipboardHistoryAuthoritativeSnapshot {
        while true {
            try Task.checkCancellation()
            let generation = persistenceMutationGeneration
            let pendingDeferredSave = deferredSaveTask
            await pendingDeferredSave?.value
            try Task.checkCancellation()

            guard isCurrentMutationGeneration(generation) else {
                continue
            }
            if let fullSnapshotPreparationError {
                throw fullSnapshotPreparationError
            }

            let history: ClipboardHistorySnapshot
            do {
                history = try await saveWriter.loadAuthoritativeSnapshotAfterPendingWrites()
            } catch {
                try Task.checkCancellation()
                guard isCurrentMutationGeneration(generation) else {
                    continue
                }
                if let fullSnapshotPreparationError {
                    throw fullSnapshotPreparationError
                }
                throw error
            }

            try Task.checkCancellation()
            guard isCurrentMutationGeneration(generation) else {
                continue
            }
            if let fullSnapshotPreparationError {
                throw fullSnapshotPreparationError
            }
            return ClipboardHistoryAuthoritativeSnapshot(
                history: history,
                mutationGeneration: generation
            )
        }
    }

    func isCurrentMutationGeneration(_ generation: UInt64) -> Bool {
        persistenceMutationGeneration == generation
    }

    var currentMutationGeneration: UInt64 {
        persistenceMutationGeneration
    }

    func makeClipboardPayloadImporter(
        limits: ClipboardPayloadImportLimits = ClipboardPayloadImportLimits(),
        payloadStager: ClipboardPayloadStager? = nil
    ) -> ClipboardPayloadImporter {
        ClipboardPayloadImporter(
            persistence: persistence,
            limits: limits,
            payloadStager: payloadStager
        )
    }

    func rollbackImportedClipboardImage(_ storedImage: StoredClipboardImage) async {
        await persistence.rollbackOwnedStagedImageBeforeCommit(storedImage)
    }

    func rollbackImportedOwnedFile(_ storedFile: StoredOwnedClipboardFile) async {
        await persistence.rollbackOwnedFileBeforeCommit(storedFile)
    }

    func deleteUnreferencedAttachmentCandidates(
        _ candidates: ClipboardAttachmentCleanup,
        discoveredAtMutationGeneration: UInt64
    ) async throws -> OrphanedAttachmentCleanupResult {
        guard !candidates.isEmpty else {
            return OrphanedAttachmentCleanupResult(removedFiles: 0, removedBytes: 0)
        }

        var observedGeneration = discoveredAtMutationGeneration
        while true {
            try Task.checkCancellation()
            if let fullSnapshotPreparationError {
                throw fullSnapshotPreparationError
            }
            let pendingDeferredSave = deferredSaveTask
            await pendingDeferredSave?.value
            try Task.checkCancellation()
            if let fullSnapshotPreparationError {
                throw fullSnapshotPreparationError
            }

            let currentGeneration = persistenceMutationGeneration
            guard currentGeneration == observedGeneration else {
                do {
                    let refreshedSnapshot = try await authoritativeSnapshot()
                    observedGeneration = refreshedSnapshot.mutationGeneration
                } catch let error as ClipboardHistoryAuthoritativeSnapshotError {
                    switch error {
                    case .preparationFailed:
                        throw error
                    case .persistenceFailed, .readFailed:
                        throw ClipboardHistoryAuthoritativeSnapshotError.preparationFailed(
                            description: error.localizedDescription
                        )
                    }
                } catch {
                    throw ClipboardHistoryAuthoritativeSnapshotError.preparationFailed(
                        description: error.localizedDescription
                    )
                }
                continue
            }

            return try await saveWriter.deleteUnreferencedAttachmentCandidates(candidates)
        }
    }

    private var pagingState: HistoryPagingService.State {
        HistoryPagingService.State(
            didLoadAll: didLoadAllPersistedItems,
            isLoadingNextPage: isLoadingNextPage
        )
    }

    init(
        persistence: ClipboardHistoryPersistence = ClipboardHistoryPersistence(),
        userDefaults: UserDefaults = .standard,
        saveWriter: ClipboardHistorySaveWriter? = nil,
        linkMetadataCoordinator: HistoryLinkMetadataCoordinator = HistoryLinkMetadataCoordinator(),
        selfWriteGuard: ClipboardSelfWriteGuard = ClipboardSelfWriteGuard(),
        imageSelfWriteConsumer: ImageSelfWriteConsumer? = nil,
        ocrCoordinator: HistoryOCRCoordinator = HistoryOCRCoordinator(),
        imageCommitWillBegin: @escaping @MainActor () -> Void = {},
        imageOCRDidEnqueue: @escaping @MainActor (ClipboardItem) -> Void = { _ in },
        externalCopyFeedback: @escaping @MainActor (ClipboardItem) -> Void = { _ in
            ClipEaseSoundPlayer.shared.playCopyFeedback()
        }
    ) {
        self.persistence = persistence
        self.saveWriter = saveWriter ?? ClipboardHistorySaveWriter(persistence: persistence)
        self.userDefaults = userDefaults
        self.linkMetadataCoordinator = linkMetadataCoordinator
        self.selfWriteGuard = selfWriteGuard
        self.imageSelfWriteConsumer = imageSelfWriteConsumer ?? { changeCount, fingerprint in
            await selfWriteGuard.consumeImage(
                changeCount: changeCount,
                fingerprint: fingerprint
            )
        }
        self.ocrCoordinator = ocrCoordinator
        self.imageCommitWillBegin = imageCommitWillBegin
        self.imageOCRDidEnqueue = imageOCRDidEnqueue
        self.externalCopyFeedback = externalCopyFeedback
        if userDefaults.object(forKey: Self.retentionPolicyKey) == nil {
            self.retentionPolicy = .sevenDays
        } else {
            self.retentionPolicy = HistoryRetentionPolicy(
                rawValue: userDefaults.integer(forKey: Self.retentionPolicyKey)
            ) ?? .sevenDays
        }
        self.saveWriter.setRecoveryRequestHandler { [weak self] in
            Task { @MainActor [weak self] in
                self?.submitFullResync()
            }
        }
        let loadStartedAt = CFAbsoluteTimeGetCurrent()
        let snapshot = persistence.loadSnapshot(itemLimit: Self.startupItemPageSize)
        PerformanceDiagnosticsService.shared.record(
            "history.store.loadStartupPage",
            category: "storage",
            durationMS: (CFAbsoluteTimeGetCurrent() - loadStartedAt) * 1_000,
            itemCount: snapshot.items.count,
            resultCount: snapshot.groups.count,
            metadata: ["limit": "\(Self.startupItemPageSize)"]
        )
        self.items = snapshot.items
        self.groups = snapshot.groups
        self.nextPersistedItemOffset = snapshot.items.count
        self.nextPersistedItemCursor = snapshot.items.last.map(
            HistoryPagingService.ItemCursor.init(item:)
        )
        self.didLoadAllPersistedItems = HistoryPagingService.didLoadAllAfterStartup(itemCount: snapshot.items.count)
        let sortStartedAt = CFAbsoluteTimeGetCurrent()
        rebuildItemIndexes()
        sortGroups()
        PerformanceDiagnosticsService.shared.record(
            "history.store.sort",
            category: "storage",
            durationMS: (CFAbsoluteTimeGetCurrent() - sortStartedAt) * 1_000,
            itemCount: items.count,
            resultCount: groups.count,
            metadata: ["mode": "snapshotOrder.indexOnly"]
        )
        pruneExpiredItems(force: true)
        let hashStartedAt = CFAbsoluteTimeGetCurrent()
        rebuildRecentHashes()
        PerformanceDiagnosticsService.shared.record(
            "history.store.rebuildHashes",
            category: "storage",
            durationMS: (CFAbsoluteTimeGetCurrent() - hashStartedAt) * 1_000,
            itemCount: items.count,
            resultCount: domainStore.recentHashCount
        )
        PerformanceDiagnosticsService.shared.record(
            "history.store.initialize",
            category: "storage",
            durationMS: (CFAbsoluteTimeGetCurrent() - loadStartedAt) * 1_000,
            itemCount: items.count,
            resultCount: groups.count,
            metadata: ["mode": "startupPage"]
        )
        itemsMutationGeneration = 1
        scheduleInitialBackgroundPageLoadIfNeeded()
        scheduleSearchIndexWarmup()
    }

    func addText(_ text: String, sourceApp: SourceAppInfo) {
        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedText.isEmpty else {
            return
        }

        let item: ClipboardItem
        if let hex = ColorParser.hexColor(from: normalizedText) {
            item = .color(hex, sourceApp: sourceApp)
        } else if let url = URLParser.url(from: normalizedText) {
            item = .link(url, originalText: normalizedText, sourceApp: sourceApp)
        } else {
            item = .text(normalizedText, sourceApp: sourceApp)
        }

        let upsertResult = upsertClipboardItem(item)
        let upsertedItem = upsertResult.item

        if upsertedItem.type == .link,
           let url = upsertedItem.url,
           !upsertResult.reusedLinkMetadata {
            fetchLinkTitle(for: upsertedItem.id, url: url)
        }

        playExternalCopyFeedbackIfNeeded(for: upsertedItem)
    }

    func consumeLatestItemFocusRequest() -> ClipboardItemFocusRequest? {
        let request = latestItemFocusRequest
        latestItemFocusRequest = nil
        return request
    }

    func addRichText(
        _ data: Data,
        plainText: String,
        sourceApp: SourceAppInfo,
        groupID: ClipboardGroup.ID? = nil,
        importAuthority: ClipboardImportAuthority = ClipboardImportAuthority(),
        rawAsset: ClipboardRichTextRawAsset? = nil
    ) async throws -> ClipboardItem? {
        let normalizedText = plainText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedText.isEmpty else {
            return nil
        }
        let storedRichText = try await persistence.saveRichTextOrThrow(
            data,
            rawAsset: rawAsset
        )
        do {
            try Task.checkCancellation()
        } catch {
            await persistence.rollbackOwnedStagedRichTextBeforeCommit(storedRichText)
            throw error
        }

        var item = ClipboardItem.richText(
            plainText: normalizedText,
            fileName: storedRichText.fileName,
            sourceApp: sourceApp
        )
        let now = Date()
        if let groupID, groupIndexByID[groupID] != nil {
            item.groupID = groupID
            item.groupedAt = now
        }

        let preparedUpsert = prepareClipboardItemUpsert(
            item,
            replacingRichTextFileName: storedRichText.fileName
        )
        let revision = nextSaveRevision()
        let mutationGeneration = persistenceMutationGeneration
        let receipt: ClipboardImportCommitReceipt
        do {
            receipt = try await saveWriter.commitImportedItemAwaitingDecision(
                preparedUpsert.item,
                deleting: preparedUpsert.duplicateIDs,
                displacedItems: preparedUpsert.duplicateItems,
                groups: groups,
                acceptedCleanup: preparedUpsert.attachmentCleanup,
                stagedAttachmentReservations: [storedRichText.reservation].compactMap { $0 },
                revision: revision
            )
        } catch is CancellationError {
            await persistence.rollbackOwnedStagedRichTextBeforeCommit(storedRichText)
            throw CancellationError()
        } catch let failure as ClipboardHistoryCommitFailure {
            await discardStagedAttachments([storedRichText.reservation])
            throw failure.underlyingError
        } catch {
            await discardStagedAttachments([storedRichText.reservation])
            throw error
        }

        guard isCurrentMutationGeneration(mutationGeneration),
              importAuthority.tryAccept() else {
            do {
                try await saveWriter.compensateImportedItem(receipt)
            } catch let failure as ClipboardHistoryCommitFailure {
                throw failure.underlyingError
            }
            return nil
        }
        guard saveWriter.acceptImportedItem(receipt) else { return nil }

        let insertedItem = applyPreparedClipboardItemUpsert(
            preparedUpsert,
            persist: false
        ).item
        playExternalCopyFeedbackIfNeeded(for: insertedItem)
        return insertedItem
    }

    func addImage(_ image: NSImage, sourceApp: SourceAppInfo) {
        guard let storedImage = persistence.saveImage(image) else {
            return
        }

        var item = ClipboardItem.image(
            fileName: storedImage.fileName,
            width: storedImage.width,
            height: storedImage.height,
            hash: storedImage.hash,
            sourceApp: sourceApp
        )
        item.ocrStatus = .pending

        let insertedItem = upsertClipboardItem(
            item,
            stagedAttachmentReservations: [storedImage.reservation].compactMap { $0 }
        ).item
        enqueueOCRIfNeeded(for: insertedItem)
        playExternalCopyFeedbackIfNeeded(for: insertedItem)
    }

    func addImage(
        _ storedImage: StoredClipboardImage,
        sourceApp: SourceAppInfo,
        importAuthority: ClipboardImportAuthority = ClipboardImportAuthority(),
        automaticOCRAllowed: Bool = true
    ) async throws -> ClipboardItem? {
        do {
            try Task.checkCancellation()
        } catch {
            await persistence.rollbackOwnedStagedImageBeforeCommit(storedImage)
            throw error
        }

        var item = ClipboardItem.image(
            fileName: storedImage.fileName,
            width: storedImage.width,
            height: storedImage.height,
            hash: storedImage.hash,
            sourceApp: sourceApp
        )
        if !automaticOCRAllowed {
            item.ocrStatus = .none
        }
        let preparedUpsert = prepareClipboardItemUpsert(item)
        imageCommitWillBegin()
        let revision = nextSaveRevision()
        let mutationGeneration = persistenceMutationGeneration
        let receipt: ClipboardImportCommitReceipt
        do {
            receipt = try await saveWriter.commitImportedItemAwaitingDecision(
                preparedUpsert.item,
                deleting: preparedUpsert.duplicateIDs,
                displacedItems: preparedUpsert.duplicateItems,
                groups: groups,
                acceptedCleanup: preparedUpsert.attachmentCleanup,
                stagedAttachmentReservations: [storedImage.reservation].compactMap { $0 },
                revision: revision
            )
        } catch is CancellationError {
            await persistence.rollbackOwnedStagedImageBeforeCommit(storedImage)
            throw CancellationError()
        } catch let failure as ClipboardHistoryCommitFailure {
            await discardStagedAttachments([storedImage.reservation])
            throw failure.underlyingError
        } catch {
            await discardStagedAttachments([storedImage.reservation])
            throw error
        }

        guard isCurrentMutationGeneration(mutationGeneration),
              importAuthority.tryAccept() else {
            do {
                try await saveWriter.compensateImportedItem(receipt)
            } catch let failure as ClipboardHistoryCommitFailure {
                throw failure.underlyingError
            }
            return nil
        }
        guard saveWriter.acceptImportedItem(receipt) else { return nil }
        let insertedItem = applyPreparedClipboardItemUpsert(
            preparedUpsert,
            persist: false
        ).item
        enqueueOCRIfNeeded(for: insertedItem)
        imageOCRDidEnqueue(insertedItem)
        playExternalCopyFeedbackIfNeeded(for: insertedItem)
        return insertedItem
    }

    func addFiles(_ urls: [URL], sourceApp: SourceAppInfo) {
        let references = fileReferences(from: urls)
        guard !references.isEmpty else {
            return
        }
        let item = ClipboardItem.file(
            references: references,
            sourceApp: sourceApp
        )

        let insertedItem = upsertClipboardItem(item).item
        enqueueOCRIfNeeded(for: insertedItem)
        playExternalCopyFeedbackIfNeeded(for: insertedItem)
    }

    func addOwnedFile(
        _ storedFile: StoredOwnedClipboardFile,
        sourceApp: SourceAppInfo,
        importAuthority: ClipboardImportAuthority = ClipboardImportAuthority(),
        automaticOCRAllowed: Bool = true
    ) async throws -> ClipboardItem? {
        do {
            try Task.checkCancellation()
        } catch {
            await persistence.rollbackOwnedFileBeforeCommit(storedFile)
            throw error
        }
        let references = fileReferences(from: [storedFile.fileURL])
        guard !references.isEmpty else {
            await persistence.rollbackOwnedFileBeforeCommit(storedFile)
            return nil
        }
        var item = ClipboardItem.file(
            references: references,
            sourceApp: sourceApp,
            ownedAttachmentFileName: storedFile.fileName
        )
        if !automaticOCRAllowed {
            item.ocrStatus = .none
        }
        let preparedUpsert = prepareClipboardItemUpsert(item)
        let revision = nextSaveRevision()
        let mutationGeneration = persistenceMutationGeneration
        let receipt: ClipboardImportCommitReceipt
        do {
            receipt = try await saveWriter.commitImportedItemAwaitingDecision(
                preparedUpsert.item,
                deleting: preparedUpsert.duplicateIDs,
                displacedItems: preparedUpsert.duplicateItems,
                groups: groups,
                acceptedCleanup: preparedUpsert.attachmentCleanup,
                stagedAttachmentReservations: [storedFile.reservation].compactMap { $0 },
                revision: revision
            )
        } catch is CancellationError {
            await persistence.rollbackOwnedFileBeforeCommit(storedFile)
            throw CancellationError()
        } catch let failure as ClipboardHistoryCommitFailure {
            await discardStagedAttachments([storedFile.reservation])
            throw failure.underlyingError
        } catch {
            await discardStagedAttachments([storedFile.reservation])
            throw error
        }

        guard isCurrentMutationGeneration(mutationGeneration),
              importAuthority.tryAccept() else {
            do {
                try await saveWriter.compensateImportedItem(receipt)
            } catch let failure as ClipboardHistoryCommitFailure {
                throw failure.underlyingError
            }
            return nil
        }
        guard saveWriter.acceptImportedItem(receipt) else {
            return nil
        }
        let insertedItem = applyPreparedClipboardItemUpsert(
            preparedUpsert,
            persist: false
        ).item
        enqueueOCRIfNeeded(for: insertedItem)
        playExternalCopyFeedbackIfNeeded(for: insertedItem)
        return insertedItem
    }

    func item(with id: ClipboardItem.ID?) -> ClipboardItem? {
        guard let id else {
            return nil
        }

        guard let index = itemIndex(for: id) else {
            return nil
        }

        return items[index]
    }

    func itemIndex(with id: ClipboardItem.ID?) -> Int? {
        guard let id else {
            return nil
        }

        return itemIndex(for: id)
    }

    func cachedItemIndex(with id: ClipboardItem.ID?) -> Int? {
        guard let id,
              let index = domainStore.cachedItemIndex(for: id, in: items) else {
            return nil
        }

        return index
    }

    @discardableResult
    func loadMoreItemsIfNeeded(
        visibleUpperBound: Int,
        preloadMargin: Int = 160
    ) -> Task<Void, Never>? {
        guard HistoryPagingService.shouldLoadMoreItems(
            state: pagingState,
            visibleUpperBound: visibleUpperBound,
            itemCount: items.count,
            preloadMargin: preloadMargin
        ) else {
            return nil
        }

        return loadNextItemPage(reason: "visibleWindow")
    }

    nonisolated func searchItems(_ query: ClipboardSearchQuery) -> [ClipboardItem] {
        let startedAt = CFAbsoluteTimeGetCurrent()
        let request = searchPagingCoordinator.prepare(query)
        let items: [ClipboardItem]
        switch request {
        case .compatibility:
            items = persistence.searchItems(query)
        case .cursor(let cursorRequest):
            do {
                let page = try persistence.searchPage(
                    query,
                    after: cursorRequest.cursor,
                    cancellation: cursorRequest.cancellation
                )
                guard searchPagingCoordinator.complete(cursorRequest, page: page) else {
                    return []
                }
                items = page.items
            } catch is CancellationError {
                searchPagingCoordinator.fail(cursorRequest)
                return []
            } catch {
                searchPagingCoordinator.fail(cursorRequest)
                NSLog("ClipEase failed to search clipboard history cursor page: \(error.localizedDescription)")
                return []
            }
        }
        let durationMS = (CFAbsoluteTimeGetCurrent() - startedAt) * 1_000
        Task { @MainActor in
            PerformanceDiagnosticsService.shared.record(
                "history.store.searchAll",
                category: "search",
                durationMS: durationMS,
                resultCount: items.count,
                metadata: [
                    "queryLength": "\(query.text.count)",
                    "limit": "\(query.limit)"
                ]
            )
        }
        return items
    }

    private func scheduleSearchIndexWarmup() {
        searchIndexWarmupTask?.cancel()
        let persistence = persistence
        searchIndexWarmupTask = Task.detached(priority: .utility) {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else {
                return
            }

            let startedAt = CFAbsoluteTimeGetCurrent()
            while !Task.isCancelled {
                let backfilledCount = persistence.backfillContentDigests()
                guard backfilledCount == SQLiteContentDigest.batchSize else {
                    break
                }
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
            guard !Task.isCancelled else {
                return
            }
            persistence.prepareSearchIndex()
            let durationMS = (CFAbsoluteTimeGetCurrent() - startedAt) * 1_000
            await MainActor.run {
                PerformanceDiagnosticsService.shared.record(
                    "history.store.searchIndexWarmup",
                    category: "search",
                    durationMS: durationMS
                )
            }
        }
    }

    func deleteItem(with id: ClipboardItem.ID?) {
        guard let id else {
            return
        }

        guard let deletedIndex = itemIndex(for: id) else {
            return
        }

        let deletedItems = [items[deletedIndex]]
        let attachmentCleanup = ClipboardAttachmentCleanup(items: deletedItems)
        items.remove(at: deletedIndex)
        rebuildItemIndexes()
        cancelOCRTasks(for: deletedItems)
        cancelLinkMetadataTasks(for: deletedItems)
        removeRecentHashes(for: deletedItems)
        persistIncrementalDelete(itemIDs: [id], attachmentCleanup: attachmentCleanup)
    }

    func clearAllItems() {
        let removedItems = items
        let attachmentCleanup = ClipboardAttachmentCleanup(items: removedItems)
        items.removeAll()
        rebuildItemIndexes()
        didLoadAllPersistedItems = true
        cancelAllOCRTasks()
        cancelAllLinkMetadataTasks()
        domainStore.removeAllRecentHashes()
        selfWriteGuard.removeAll()
        persistDeleteAll(attachmentCleanup: attachmentCleanup)
    }

    func importItems(_ importedItems: [ClipboardItem]) -> Int {
        let sanitizedItems = sanitizedImportedItems(importedItems)
        let newItems = nonDuplicateItems(from: sanitizedItems)

        guard !newItems.isEmpty else {
            return 0
        }

        items.append(contentsOf: newItems)
        sortItems()
        pruneExpiredItems()
        rebuildRecentHashesAndGroupCounts()
        persistIncrementalInsert(newItems)
        return newItems.count
    }

    func importBackupItems(_ importedItems: [ClipboardItem], groups importedGroups: [ClipboardGroup] = []) -> Int {
        let groupCountBeforeImport = groups.count
        let groupIDMapping = importBackupGroups(importedGroups)
        if groups.count != groupCountBeforeImport {
            persistGroupsIncrementally()
        }
        let validGroupIDs = Set(groups.map(\.id))
        let sanitizedItems = importedItems.map { item in
            sanitizedBackupItem(item, groupIDMapping: groupIDMapping, validGroupIDs: validGroupIDs)
        }

        let newItems = nonDuplicateItems(from: sanitizedItems)

        guard !newItems.isEmpty else {
            return 0
        }

        items.append(contentsOf: newItems)
        sortItems()
        pruneExpiredItems()
        rebuildRecentHashesAndGroupCounts()
        persistIncrementalInsert(newItems)
        return newItems.count
    }

    func duplicateCount(for importedItems: [ClipboardItem]) -> Int {
        importedItems.count - nonDuplicateItems(from: importedItems).count
    }

    func togglePinned(for id: ClipboardItem.ID?) {
        guard let id,
              let index = itemIndex(for: id) else {
            return
        }

        items[index].isPinned.toggle()
        items[index].pinnedAt = items[index].isPinned ? Date() : nil
        sortItems()
        if let updatedItem = item(with: id) {
            persistItemMutation(updatedItem, fields: [.pin])
        }
    }

    enum GroupRenameResult: Equatable {
        case renamed
        case unchanged
        case empty
        case duplicate
        case notFound

        init(_ result: GroupService.RenameResult) {
            switch result {
            case .renamed:
                self = .renamed
            case .unchanged:
                self = .unchanged
            case .empty:
                self = .empty
            case .duplicate:
                self = .duplicate
            case .notFound:
                self = .notFound
            }
        }
    }

    @discardableResult
    func createGroup() -> ClipboardGroup {
        let group = ClipboardGroup.makeDefault(
            name: GroupService.uniqueGroupName(baseName: ClipboardGroup.defaultName, groups: groups),
            sortOrder: groups.count
        )
        groups.append(group)
        sortGroups()
        persistGroupsIncrementally()
        return group
    }

    @discardableResult
    func renameGroup(_ id: ClipboardGroup.ID, name: String) -> GroupRenameResult {
        let result = GroupService.renameGroup(
            id,
            name: name,
            groups: &groups,
            indexByID: &groupIndexByID
        )
        if result == .renamed {
            persistGroupsIncrementally()
        }
        return GroupRenameResult(result)
    }

    func updateGroupAppearance(_ id: ClipboardGroup.ID, colorHex: String? = nil, iconName: String? = nil) {
        let didUpdate = GroupService.updateGroupAppearance(
            id,
            colorHex: colorHex,
            iconName: iconName,
            groups: &groups,
            indexByID: &groupIndexByID
        )
        guard didUpdate else {
            return
        }

        persistGroupsIncrementally()
    }

    func deleteGroup(_ id: ClipboardGroup.ID) -> Int {
        deleteGroupWithResult(id).removedItemCount
    }

    func deleteGroupWithResult(_ id: ClipboardGroup.ID) -> ClipboardGroupDeletionResult {
        deleteGroupsWithResult([id])
    }

    func deleteGroups(_ ids: Set<ClipboardGroup.ID>) -> Int {
        deleteGroupsWithResult(ids).removedItemCount
    }

    func deleteGroupsWithResult(_ ids: Set<ClipboardGroup.ID>) -> ClipboardGroupDeletionResult {
        guard !ids.isEmpty else {
            return ClipboardGroupDeletionResult(deletedGroupIDs: [], removedItemCount: 0)
        }

        let existingGroupIDs = Set(groups.lazy.map(\.id).filter(ids.contains))
        guard !existingGroupIDs.isEmpty else {
            return ClipboardGroupDeletionResult(deletedGroupIDs: [], removedItemCount: 0)
        }
        let removedItems = items.filter { item in
            item.groupID.map(existingGroupIDs.contains) ?? false
        }
        let attachmentCleanup = ClipboardAttachmentCleanup(items: removedItems)
        groups.removeAll { existingGroupIDs.contains($0.id) }
        items.removeAll { item in
            item.groupID.map(existingGroupIDs.contains) ?? false
        }
        rebuildItemIndexes()
        sortGroups()
        cancelOCRTasks(for: removedItems)
        cancelLinkMetadataTasks(for: removedItems)
        removeRecentHashes(for: removedItems)
        persistIncrementalDelete(
            itemIDs: Set(removedItems.map(\.id)),
            groupIDs: existingGroupIDs,
            attachmentCleanup: attachmentCleanup
        )
        persistGroupsIncrementally()
        return ClipboardGroupDeletionResult(
            deletedGroupIDs: existingGroupIDs,
            removedItemCount: removedItems.count
        )
    }

    func moveGroup(fromOffsets source: IndexSet, toOffset destination: Int) {
        groups.move(fromOffsets: source, toOffset: destination)
        for index in groups.indices {
            groups[index].sortOrder = index
        }
        rebuildGroupIndex()
        persistGroupsIncrementally()
    }

    func addItem(_ id: ClipboardItem.ID?, toGroup groupID: ClipboardGroup.ID) {
        guard let id,
              groupIndexByID[groupID] != nil,
              let index = itemIndex(for: id) else {
            return
        }

        let now = Date()
        let oldGroupID = items[index].groupID
        guard oldGroupID != groupID || items[index].groupedAt == nil else {
            return
        }
        items[index].groupID = groupID
        items[index].groupedAt = now
        let updatedItem = items[index]
        updateGroupCountOnMove(from: oldGroupID, to: groupID)
        sortItems()
        persistItemMutation(updatedItem, fields: [.group])
    }

    @discardableResult
    func addItems(_ ids: Set<ClipboardItem.ID>, toGroup groupID: ClipboardGroup.ID) -> Int {
        guard !ids.isEmpty,
              groupIndexByID[groupID] != nil else {
            return 0
        }

        let now = Date()
        var changedCount = 0
        var changedItems: [ClipboardItem] = []
        for index in items.indices where ids.contains(items[index].id) {
            var didChangeItem = false
            let oldGroupID = items[index].groupID
            if items[index].groupID != groupID {
                items[index].groupID = groupID
                items[index].groupedAt = now
                didChangeItem = true
            } else if items[index].groupedAt == nil {
                items[index].groupedAt = now
                didChangeItem = true
            }

            if didChangeItem {
                changedCount += 1
                changedItems.append(items[index])
                updateGroupCountOnMove(from: oldGroupID, to: groupID)
            }
        }

        guard changedCount > 0 else {
            return 0
        }

        sortItems()
        for item in changedItems {
            persistItemMutation(item, fields: [.group])
        }
        return changedCount
    }

    func removeItemFromGroup(_ id: ClipboardItem.ID?) {
        guard let id,
              let index = itemIndex(for: id),
              items[index].groupID != nil else {
            return
        }

        let oldGroupID = items[index].groupID
        items[index].groupID = nil
        items[index].groupedAt = nil
        updateGroupCountOnMove(from: oldGroupID, to: nil)
        persistItemMutation(items[index], fields: [.group])
    }

    func group(with id: ClipboardGroup.ID?) -> ClipboardGroup? {
        guard let id else {
            return nil
        }

        guard let index = groupIndex(for: id) else {
            return nil
        }

        return groups[index]
    }

    func itemCount(inGroup id: ClipboardGroup.ID) -> Int {
        domainStore.itemCount(inGroup: id)
    }

    func markUsed(_ id: ClipboardItem.ID?) {
        guard let id,
              let index = itemIndex(for: id),
              !items[index].isPinned else {
            return
        }

        items[index].createdAt = Date()
        sortItems()
        if let updatedItem = item(with: id) {
            persistItemMutation(updatedItem, fields: [.metadata])
        }
    }

    @discardableResult
    func updateEditableContent(for id: ClipboardItem.ID?, text: String) -> ClipboardItem? {
        guard let id,
              let index = itemIndex(for: id) else {
            return nil
        }

        let item = items[index]
        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var shouldFetchUpdatedLinkMetadata = false

        switch item.type {
        case .text:
            guard !normalizedText.isEmpty else {
                return nil
            }

            items[index] = item.updatingEditableContent(
                text: normalizedText,
                richTextFileUpdate: .remove
            )
        case .link:
            guard let url = URLParser.url(from: normalizedText) else {
                return nil
            }

            let fallbackTitle = Self.fallbackLinkTitle(for: url)
            let didChangeURL = item.url != url
            let canReuseMetadata = !didChangeURL
                && Self.hasEnrichedLinkMetadata(item, fallbackTitle: fallbackTitle)

            items[index] = item.updatingEditableContent(
                text: normalizedText,
                url: url,
                linkTitle: canReuseMetadata ? item.linkTitle : fallbackTitle,
                linkSubtitle: url.absoluteString,
                preserveLinkImage: !didChangeURL
            )
            shouldFetchUpdatedLinkMetadata = !canReuseMetadata
        case .color:
            guard let hex = ColorParser.hexColor(from: normalizedText) else {
                return nil
            }

            items[index] = item.updatingEditableContent(text: hex)
        case .image, .file:
            return nil
        }

        items[index].createdAt = Date()
        sortItems()
        rebuildRecentHashes()
        guard let updatedItem = self.item(with: id) else {
            return nil
        }
        var attachmentCleanup = ClipboardAttachmentCleanup.empty
        if let richTextFileName = item.richTextFileName,
           updatedItem.richTextFileName == nil {
            attachmentCleanup = attachmentCleanup.union(
                ClipboardAttachmentCleanup(richTextFileNames: [richTextFileName])
            )
        }
        if let imageFileName = item.imageFileName,
           updatedItem.imageFileName == nil {
            attachmentCleanup = attachmentCleanup.union(
                ClipboardAttachmentCleanup(imageFileNames: [imageFileName])
            )
        }
        persistItemMutation(
            updatedItem,
            fields: [.content, .metadata],
            attachmentCleanup: attachmentCleanup
        )
        latestItemFocusRequest = ClipboardItemFocusRequest(itemID: updatedItem.id, reason: .refreshed)

        if updatedItem.type == .link,
           let url = updatedItem.url,
           shouldFetchUpdatedLinkMetadata {
            fetchLinkTitle(for: updatedItem.id, url: url)
        }

        return updatedItem
    }

    private func fetchLinkTitle(for id: ClipboardItem.ID, url: URL) {
        fetchLinkMetadata(for: id, url: url)
    }

    private func fetchLinkMetadata(for id: ClipboardItem.ID, url: URL) {
        linkMetadataCoordinator.fetch(
            id: id,
            url: url,
            persistence: persistence,
            applying: { [weak self] title, storedImage, id, url in
                self?.applyLinkMetadata(title: title, storedImage: storedImage, for: id, url: url) ?? false
            }
        )
    }

    private func cancelLinkMetadataTasks(for removedItems: [ClipboardItem]) {
        linkMetadataCoordinator.cancelTasks(for: removedItems)
    }

    private func cancelLinkMetadataTasks(for ids: Set<ClipboardItem.ID>) {
        linkMetadataCoordinator.cancelTasks(for: ids)
    }

    private func cancelAllLinkMetadataTasks() {
        linkMetadataCoordinator.cancelAllTasks()
    }

    private func updateLinkTitle(_ title: String, for id: ClipboardItem.ID, url: URL) {
        applyLinkMetadata(title: title, storedImage: nil, for: id, url: url)
    }

    @discardableResult
    func applyLinkMetadata(
        title: String?,
        storedImage: StoredClipboardImage?,
        for id: ClipboardItem.ID,
        url: URL
    ) -> Bool {
        guard let index = itemIndex(for: id),
              LinkMetadataService.canApplyMetadata(to: items[index], expectedURL: url) else {
            scheduleStagedAttachmentDiscard([storedImage?.reservation])
            return false
        }

        let existingItem = items[index]
        guard LinkMetadataService.shouldApplyMetadata(
            title: title,
            storedImage: storedImage,
            to: existingItem
        ) else {
            scheduleStagedAttachmentDiscard([storedImage?.reservation])
            return true
        }

        let attachmentCleanup: ClipboardAttachmentCleanup
        if let oldImageFileName = existingItem.imageFileName,
           let newImageFileName = storedImage?.fileName,
           oldImageFileName != newImageFileName {
            attachmentCleanup = ClipboardAttachmentCleanup(imageFileNames: [oldImageFileName])
        } else {
            attachmentCleanup = .empty
        }

        items[index] = existingItem.updatingLinkMetadata(
            title: title,
            imageFileName: storedImage?.fileName,
            imageWidth: storedImage?.width,
            imageHeight: storedImage?.height,
            imageHash: storedImage?.hash
        )
        persistItemMutation(
            items[index],
            fields: [.metadata],
            attachmentCleanup: attachmentCleanup,
            stagedAttachmentReservations: [storedImage?.reservation].compactMap { $0 }
        )
        return true
    }

    func addDebugTextItems(count: Int) {
        guard count > 0 else {
            return
        }

        debugGenerationTask?.cancel()
        let sourceApp = SourceAppInfo.clipease
        debugGenerationTask = Task(priority: .utility) { [weak self] in
            let newItems = await ClipboardHistoryStore.makeDebugTextItems(
                count: count,
                sourceApp: sourceApp
            )

            guard !Task.isCancelled else {
                return
            }

            await MainActor.run {
                guard let self else {
                    return
                }

                self.mergeDebugTextItems(newItems)
                self.debugGenerationTask = nil
            }
        }
    }

    func clearDebugTextItems() -> Int {
        debugGenerationTask?.cancel()
        debugGenerationTask = nil
        let removedItems = items.filter(Self.isDebugTextItem)
        guard !removedItems.isEmpty else {
            return 0
        }

        items.removeAll(where: Self.isDebugTextItem)
        rebuildItemIndexes()
        rebuildRecentHashes()
        persistIncrementalDelete(itemIDs: Set(removedItems.map(\.id)))
        return removedItems.count
    }

    func flushPendingSave() {
        debugGenerationTask?.cancel()
        debugGenerationTask = nil
        if isTerminationDrainSealed {
            saveWriter.flush()
            return
        }
        if deferredSaveTask != nil || requiresFullSnapshotSave {
            // Deferred snapshot mutations still require the existing repair/full-save
            // path. The normal capture path is incremental and only needs a bounded
            // writer barrier at termination.
            saveImmediately()
            return
        }

        saveWriter.flush()
    }

    func makeTerminationDrainHandle() -> ClipboardHistoryTerminationDrainHandle {
        if !isTerminationDrainSealed {
            isTerminationDrainSealed = true
            deferredSaveTask?.cancel()
            deferredSaveTask = nil
            debugGenerationTask?.cancel()
            debugGenerationTask = nil
            cancelPagedLoad()
            searchIndexWarmupTask?.cancel()
            searchIndexWarmupTask = nil
            cancelAllLinkMetadataTasks()
            cancelAllOCRTasks()
            searchPagingCoordinator.cancelAll()
        }

        let writer = saveWriter
        return ClipboardHistoryTerminationDrainHandle {
            await writer.flushAsync()
        }
    }

    private func mergeDebugTextItems(_ newItems: [ClipboardItem]) {
        guard !newItems.isEmpty else {
            return
        }

        items.insert(contentsOf: newItems, at: 0)
        sortItems()
        pruneExpiredItems()
        rebuildRecentHashes()
        persistDebugItemsIncrementally(newItems)
    }

    private func persistDebugItemsIncrementally(_ items: [ClipboardItem]) {
        let revision = nextSaveRevision()
        let saveWriter = saveWriter
        saveWriter.insertItemsAsync(items, revision: revision)
        PerformanceDiagnosticsService.shared.record(
            "history.store.addDebugTextItems",
            category: "storage",
            durationMS: 0,
            itemCount: items.count,
            metadata: ["revision": "\(revision)"]
        )
    }

    func registerSelfWrite(changeCount: Int, payload: ClipboardSelfWritePayload) {
        selfWriteGuard.register(changeCount: changeCount, payload: payload)
    }

    func registerPendingImageSelfWrite(
        changeCount: Int,
        payload: ClipboardEncodedImagePayload
    ) {
        selfWriteGuard.registerPendingImage(
            changeCount: changeCount,
            payload: payload
        )
    }

    @discardableResult
    func consumeSelfWrite(
        changeCount: Int,
        payload: ClipboardSelfWritePayload?
    ) -> Bool {
        selfWriteGuard.consume(changeCount: changeCount, payload: payload)
    }

    @discardableResult
    func consumeImageSelfWrite(
        changeCount: Int,
        fingerprint: String?
    ) async -> Bool {
        await imageSelfWriteConsumer(changeCount, fingerprint)
    }

    func imageData(for item: ClipboardItem) -> Data? {
        guard let fileName = item.imageFileName else {
            return nil
        }

        return persistence.imageData(fileName: fileName)
    }

    func thumbnailImage(for item: ClipboardItem) -> NSImage? {
        guard let fileName = item.imageFileName else {
            return nil
        }

        return persistence.thumbnailImage(fileName: fileName)
    }

    func richTextData(for item: ClipboardItem) -> Data? {
        guard let fileName = item.richTextFileName else {
            return nil
        }

        return persistence.richTextData(fileName: fileName)
    }

    @discardableResult
    func updateRichTextContent(
        for id: ClipboardItem.ID?,
        data: Data,
        plainText: String
    ) async throws -> ClipboardItem? {
        guard let id,
              let index = itemIndex(for: id) else {
            return nil
        }

        let item = items[index]
        let normalizedText = plainText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard item.type == .text,
              !normalizedText.isEmpty else {
            return nil
        }

        let storedRichText = try await persistence.saveRichTextOrThrow(data)
        do {
            try Task.checkCancellation()
        } catch {
            await discardStagedAttachments([storedRichText.reservation])
            throw error
        }
        guard let currentIndex = itemIndex(for: id),
              items[currentIndex] == item else {
            await discardStagedAttachments([storedRichText.reservation])
            return nil
        }

        var updatedItem = item.updatingEditableContent(
            text: normalizedText,
            richTextFileUpdate: .replace(storedRichText.fileName)
        )
        updatedItem.createdAt = Date()
        let attachmentCleanup = ClipboardAttachmentCleanup(
            richTextFileNames: item.richTextFileName == storedRichText.fileName
                ? []
                : Set([item.richTextFileName].compactMap { $0 })
        )

        do {
            try await saveWriter.upsertAwaitingCommit(
                updatedItem,
                deleting: [],
                groups: groups,
                attachmentCleanup: .empty,
                stagedAttachmentReservations: [storedRichText.reservation].compactMap { $0 },
                revision: nextSaveRevision()
            )
        } catch is CancellationError {
            await discardStagedAttachments([storedRichText.reservation])
            throw CancellationError()
        } catch let failure as ClipboardHistoryCommitFailure {
            await discardStagedAttachments([storedRichText.reservation])
            throw failure.underlyingError
        } catch {
            await discardStagedAttachments([storedRichText.reservation])
            throw error
        }

        let cleanupGeneration = currentMutationGeneration
        guard let appliedIndex = itemIndex(for: id) else {
            await cleanupAttachmentsAfterCommittedMutation(
                attachmentCleanup.union(
                    ClipboardAttachmentCleanup(
                        richTextFileNames: [storedRichText.fileName]
                    )
                ),
                discoveredAtMutationGeneration: cleanupGeneration
            )
            return nil
        }
        guard items[appliedIndex] == item else {
            let currentItem = items[appliedIndex]
            if let mergedItem = mergeRichTextEdit(
                updatedItem,
                withMetadataFrom: currentItem,
                replacing: item
            ) {
                let reconciliationTask = Task<ClipboardItem?, Error> { @MainActor [weak self] in
                    guard let self else {
                        return nil
                    }
                    return try await self.reconcileCommittedRichTextEdit(
                        mergedItem,
                        replacing: currentItem,
                        attachmentCleanup: attachmentCleanup
                    )
                }
                return try await reconciliationTask.value
            }
            await cleanupAttachmentsAfterCommittedMutation(
                attachmentCleanup.union(
                    ClipboardAttachmentCleanup(
                        richTextFileNames: [storedRichText.fileName]
                    )
                ),
                discoveredAtMutationGeneration: cleanupGeneration
            )
            return currentItem
        }
        items[appliedIndex] = updatedItem
        sortItems()
        rebuildRecentHashes()
        latestItemFocusRequest = ClipboardItemFocusRequest(itemID: updatedItem.id, reason: .refreshed)
        await cleanupAttachmentsAfterCommittedMutation(
            attachmentCleanup,
            discoveredAtMutationGeneration: currentMutationGeneration
        )
        return updatedItem
    }

    private func reconcileCommittedRichTextEdit(
        _ mergedItem: ClipboardItem,
        replacing currentItem: ClipboardItem,
        attachmentCleanup: ClipboardAttachmentCleanup
    ) async throws -> ClipboardItem? {
        do {
            try await saveWriter.upsertAwaitingCommit(
                mergedItem,
                deleting: [],
                groups: groups,
                attachmentCleanup: .empty,
                revision: nextSaveRevision()
            )
        } catch let failure as ClipboardHistoryCommitFailure {
            throw failure.underlyingError
        }

        guard let mergedIndex = itemIndex(for: mergedItem.id),
              items[mergedIndex] == currentItem else {
            return item(with: mergedItem.id)
        }
        items[mergedIndex] = mergedItem
        sortItems()
        rebuildRecentHashes()
        latestItemFocusRequest = ClipboardItemFocusRequest(
            itemID: mergedItem.id,
            reason: .refreshed
        )
        await cleanupAttachmentsAfterCommittedMutation(
            attachmentCleanup,
            discoveredAtMutationGeneration: currentMutationGeneration
        )
        return mergedItem
    }

    private func cleanupAttachmentsAfterCommittedMutation(
        _ candidates: ClipboardAttachmentCleanup,
        discoveredAtMutationGeneration generation: UInt64
    ) async {
        let cleanupTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            _ = try? await self.deleteUnreferencedAttachmentCandidates(
                candidates,
                discoveredAtMutationGeneration: generation
            )
        }
        await cleanupTask.value
    }

    private func discardStagedAttachments(
        _ optionalReservations: [ClipboardAttachmentReservation?]
    ) async {
        let reservations = optionalReservations.compactMap { $0 }
        guard !reservations.isEmpty else {
            return
        }
        let candidates = reservations.reduce(into: ClipboardAttachmentCleanup.empty) { cleanup, reservation in
            cleanup = cleanup.union(reservation.candidates)
        }
        reservations.forEach { $0.release() }
        let persistence = persistence
        await Task.detached(priority: .utility) {
            _ = persistence.deleteUnreferencedAttachments(candidates)
        }.value
    }

    private func scheduleStagedAttachmentDiscard(
        _ reservations: [ClipboardAttachmentReservation?]
    ) {
        Task { @MainActor [weak self] in
            await self?.discardStagedAttachments(reservations)
        }
    }

    private func mergeRichTextEdit(
        _ updatedItem: ClipboardItem,
        withMetadataFrom currentItem: ClipboardItem,
        replacing originalItem: ClipboardItem
    ) -> ClipboardItem? {
        guard currentItem.id == originalItem.id,
              currentItem.type == originalItem.type,
              currentItem.text == originalItem.text,
              currentItem.url == originalItem.url,
              currentItem.imageFileName == originalItem.imageFileName,
              currentItem.richTextFileName == originalItem.richTextFileName,
              currentItem.fileReferences == originalItem.fileReferences else {
            return nil
        }

        var mergedItem = updatedItem
        mergedItem.linkTitle = currentItem.linkTitle
        mergedItem.isPinned = currentItem.isPinned
        mergedItem.pinnedAt = currentItem.pinnedAt
        mergedItem.groupID = currentItem.groupID
        mergedItem.groupedAt = currentItem.groupedAt
        mergedItem.ocrStatus = currentItem.ocrStatus
        mergedItem.ocrText = currentItem.ocrText
        mergedItem.ocrEmails = currentItem.ocrEmails
        mergedItem.ocrPhoneNumbers = currentItem.ocrPhoneNumbers
        mergedItem.ocrURLs = currentItem.ocrURLs
        mergedItem.ocrTextRegions = currentItem.ocrTextRegions
        mergedItem.ocrUpdatedAt = currentItem.ocrUpdatedAt
        return mergedItem
    }

    func imageFileURL(for item: ClipboardItem) -> URL? {
        guard let fileName = item.imageFileName else {
            return nil
        }

        return try? ClipEaseStoragePaths.imageFileURL(fileName: fileName)
    }

    func ocrResult(for item: ClipboardItem) -> ClipboardOCRMatch? {
        guard !item.ocrText.isEmpty || !item.ocrEmails.isEmpty || !item.ocrPhoneNumbers.isEmpty || !item.ocrURLs.isEmpty else {
            return nil
        }

        return ClipboardOCRMatch(
            text: item.ocrText,
            emails: item.ocrEmails,
            phoneNumbers: item.ocrPhoneNumbers,
            urls: item.ocrURLs,
            textRegions: item.ocrTextRegions
        )
    }

    func ocrBadgeItems(for item: ClipboardItem) -> [String] {
        var results: [String] = []
        results.append(contentsOf: item.ocrEmails)
        results.append(contentsOf: item.ocrPhoneNumbers)
        results.append(contentsOf: item.ocrURLs)
        return results
    }

    func setOCRInteractiveThrottleActive(_ isActive: Bool) {
        ocrCoordinator.setInteractiveThrottleActive(isActive)
    }

    func ocrExecutionOutcome(
        for id: ClipboardItem.ID
    ) -> ClipboardOCRExecutionOutcome? {
        ocrOutcomeByItemID[id]
    }

    private func enqueueOCRIfNeeded(for item: ClipboardItem) {
        guard item.ocrStatus == .pending else {
            return
        }

        let sourceURL: URL?
        switch item.type {
        case .image:
            sourceURL = imageFileURL(for: item)
        case .file:
            sourceURL = item.fileReferences.first(where: { $0.isOCRCandidate }).map { URL(fileURLWithPath: $0.path) }
        default:
            sourceURL = nil
        }

        ocrCoordinator.enqueue(
            item: item,
            sourceURL: sourceURL,
            setProcessing: { [weak self] id in
                self?.setOCRStatus(.processing, for: id)
            },
            applyResult: { [weak self] result, status, id in
                self?.applyOCRResult(result, status: status, to: id)
            },
            applyOutcome: { [weak self] outcome, id in
                self?.ocrOutcomeByItemID[id] = outcome
            }
        )
    }

    private func setOCRStatus(_ status: ClipboardOCRStatus, for id: ClipboardItem.ID) {
        guard let index = itemIndex(for: id) else {
            return
        }

        items[index].ocrStatus = status
        persistItemMutation(items[index], fields: [.ocr])
    }

    private func applyOCRResult(_ result: ClipboardOCRMatch, status: ClipboardOCRStatus, to id: ClipboardItem.ID) {
        guard let index = itemIndex(for: id) else {
            return
        }

        items[index] = items[index].updatingOCR(
            status: status,
            text: result.text,
            emails: result.emails,
            phoneNumbers: result.phoneNumbers,
            urls: result.urls,
            textRegions: result.textRegions
        )
        sortItems()
        if let updatedItem = item(with: id) {
            persistItemMutation(updatedItem, fields: [.ocr])
        }
    }

    private func cancelOCRTasks(for removedItems: [ClipboardItem]) {
        ocrCoordinator.cancelTasks(for: removedItems)
        for id in removedItems.map(\.id) {
            ocrOutcomeByItemID[id] = nil
        }
    }

    private func cancelOCRTasks(for ids: Set<ClipboardItem.ID>) {
        ocrCoordinator.cancelTasks(for: ids)
        for id in ids {
            ocrOutcomeByItemID[id] = nil
        }
    }

    private func cancelAllOCRTasks() {
        ocrCoordinator.cancelAllTasks()
        ocrOutcomeByItemID.removeAll()
    }

    private func sortItems() {
        items.sort(by: Self.shouldSortBefore)
        rebuildItemIndexes()
    }

    private func insertItemMaintainingSort(_ item: ClipboardItem) {
        let insertionIndex = sortedInsertionIndex(for: item)
        items.insert(item, at: insertionIndex)
        updateItemIndexes(startingAt: insertionIndex)
        domainStore.incrementGroupCount(for: item.groupID)
    }

    private func sortedInsertionIndex(for item: ClipboardItem) -> Int {
        var low = items.startIndex
        var high = items.endIndex

        while low < high {
            let mid = low + (high - low) / 2
            if Self.shouldSortBefore(item, items[mid]) {
                high = mid
            } else {
                low = mid + 1
            }
        }

        return low
    }

    private func updateItemIndexes(startingAt startIndex: Int) {
        domainStore.updateIndexes(startingAt: startIndex, in: items)
    }

    private static func shouldSortBefore(_ lhs: ClipboardItem, _ rhs: ClipboardItem) -> Bool {
        if lhs.isPinned != rhs.isPinned {
            return lhs.isPinned && !rhs.isPinned
        }

        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt > rhs.createdAt
        }

        let lhsPinnedOrCreatedAt = lhs.pinnedAt ?? lhs.createdAt
        let rhsPinnedOrCreatedAt = rhs.pinnedAt ?? rhs.createdAt
        if lhsPinnedOrCreatedAt != rhsPinnedOrCreatedAt {
            return lhsPinnedOrCreatedAt > rhsPinnedOrCreatedAt
        }

        return lhs.id.uuidString > rhs.id.uuidString
    }

    private func persistedDuplicateItems(for item: ClipboardItem) -> [ClipboardItem] {
        guard !didLoadAllPersistedItems,
              let contentHash = item.contentHash else {
            return []
        }

        return persistence.loadItems(
            contentHash: contentHash,
            sourceBundleID: nil
        )
    }

    private func itemIndex(for id: ClipboardItem.ID) -> Int? {
        domainStore.itemIndex(for: id, in: items)
    }

    private func groupIndex(for id: ClipboardGroup.ID) -> Int? {
        GroupService.groupIndex(for: id, groups: groups, indexByID: &groupIndexByID)
    }

    private func rebuildItemIndexes() {
        domainStore.rebuildIndexes(for: items)
    }

    private func sortGroups() {
        groupIndexByID = GroupService.sortGroupsAndBuildIndex(&groups)
    }

    private func rebuildGroupIndex() {
        groupIndexByID = GroupService.rebuildGroupIndex(groups)
    }

    private func scheduleInitialBackgroundPageLoadIfNeeded() {
        guard !didLoadAllPersistedItems else {
            return
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 600_000_000)
            self.loadNextItemPage(reason: "startupBackground")
        }
    }

    @discardableResult
    private func loadNextItemPage(reason: String) -> Task<Void, Never>? {
        guard !isTerminationDrainSealed,
              !didLoadAllPersistedItems else {
            return nil
        }
        guard pendingRetentionRequestGeneration == nil else {
            pendingPageLoadReason = reason
            return nil
        }
        guard !isLoadingNextPage else {
            return nil
        }

        isLoadingNextPage = true
        pagedLoadGeneration &+= 1
        let generation = pagedLoadGeneration
        let request = HistoryPagingService.nextPageRequest(
            itemCount: nextPersistedItemOffset,
            cursor: nextPersistedItemCursor
        )
        let persistence = persistence
        let task = Task(priority: .utility) {
            let startedAt = CFAbsoluteTimeGetCurrent()
            let page = await Task.detached(priority: .utility) {
                persistence.loadItemPage(
                    limit: request.limit,
                    after: request.cursor
                )
            }.value
            let durationMS = (CFAbsoluteTimeGetCurrent() - startedAt) * 1_000
            mergeLoadedPage(
                page,
                offset: request.offset,
                requestedCursor: request.cursor,
                limit: request.limit,
                durationMS: durationMS,
                reason: reason,
                generation: generation
            )
        }
        pagedLoadTask = task
        return task
    }

    private func retentionRequestDidComplete(generation: UInt64) {
        guard pendingRetentionRequestGeneration == generation else {
            return
        }

        pendingRetentionRequestGeneration = nil
        guard let reason = pendingPageLoadReason else {
            return
        }
        pendingPageLoadReason = nil
        loadNextItemPage(reason: reason)
    }

    private func mergeLoadedPage(
        _ page: HistoryPagingService.ItemPage,
        offset: Int,
        requestedCursor: HistoryPagingService.ItemCursor?,
        limit: Int,
        durationMS: Double,
        reason: String,
        generation: UInt64
    ) {
        guard generation == pagedLoadGeneration else {
            return
        }

        defer {
            isLoadingNextPage = false
            pagedLoadTask = nil
        }

        switch HistoryPagingService.mergeResult(
            pageCount: page.items.count,
            requestedCursor: requestedCursor,
            currentCursor: nextPersistedItemCursor,
            limit: limit
        ) {
        case .stale:
            return
        case .append(let didLoadAll):
            nextPersistedItemOffset += page.items.count
            if let nextCursor = page.nextCursor {
                nextPersistedItemCursor = nextCursor
            }
            appendLoadedItems(page.items)
            didLoadAllPersistedItems = didLoadAll
        }

        PerformanceDiagnosticsService.shared.record(
            "history.store.loadNextPage",
            category: "storage",
            durationMS: durationMS,
            itemCount: page.items.count,
            resultCount: items.count,
            metadata: [
                "offset": "\(offset)",
                "limit": "\(limit)",
                "reason": reason,
                "didLoadAll": "\(didLoadAllPersistedItems)"
            ]
        )
    }

    private func appendLoadedItems(_ page: [ClipboardItem]) {
        let existingIDs = Set(items.map(\.id))
        let validGroupIDs = Set(groups.map(\.id))
        let newItems = page.filter { item in
            let isExpired = activeRetentionCutoff.map { cutoff in
                !item.isPinned
                    && item.createdAt < cutoff
                    && item.groupID.map(validGroupIDs.contains) != true
            } ?? false
            return !isExpired
                && !existingIDs.contains(item.id)
                && !pendingDeletedItemIDs.contains(item.id)
                && item.groupID.map(pendingDeletedGroupIDs.contains) != true
        }
        guard !newItems.isEmpty else {
            return
        }

        items.append(contentsOf: newItems)
        sortItems()
        for item in newItems {
            addRecentHash(for: item)
        }
    }

    private func cancelPagedLoad() {
        pagedLoadGeneration &+= 1
        pagedLoadTask?.cancel()
        pagedLoadTask = nil
        isLoadingNextPage = false
    }

    private func persistIncrementalUpsert(
        _ item: ClipboardItem,
        deleting deletedIDs: Set<ClipboardItem.ID>,
        attachmentCleanup: ClipboardAttachmentCleanup = .empty,
        stagedAttachmentReservations: [ClipboardAttachmentReservation] = []
    ) {
        guard !isTerminationDrainSealed else {
            scheduleStagedAttachmentDiscard(stagedAttachmentReservations.map(Optional.some))
            return
        }
        pendingDeletedItemIDs.formUnion(deletedIDs)
        let mustSaveFullSnapshot = requiresFullSnapshotSave
        deferredSaveTask?.cancel()
        deferredSaveTask = nil
        if mustSaveFullSnapshot {
            persistCurrentSnapshotAsync(
                adding: attachmentCleanup,
                stagedAttachmentReservations: stagedAttachmentReservations
            )
            return
        }
        let groups = groups
        let revision = nextSaveRevision()
        let saveWriter = saveWriter
        let attachmentCleanup = drainPendingAttachmentCleanup(adding: attachmentCleanup)
        saveWriter.upsertAsync(
            item,
            deleting: deletedIDs,
            groups: groups,
            attachmentCleanup: attachmentCleanup,
            stagedAttachmentReservations: stagedAttachmentReservations,
            revision: revision
        )
    }

    private func persistItemMutation(
        _ item: ClipboardItem,
        fields: ClipboardHistoryItemMutationFields,
        attachmentCleanup: ClipboardAttachmentCleanup = .empty,
        stagedAttachmentReservations: [ClipboardAttachmentReservation] = []
    ) {
        guard !fields.isEmpty else {
            return
        }
        guard !isTerminationDrainSealed else {
            scheduleStagedAttachmentDiscard(stagedAttachmentReservations.map(Optional.some))
            return
        }

        let mustSaveFullSnapshot = requiresFullSnapshotSave
        deferredSaveTask?.cancel()
        deferredSaveTask = nil
        if mustSaveFullSnapshot {
            persistCurrentSnapshotAsync(
                adding: attachmentCleanup,
                stagedAttachmentReservations: stagedAttachmentReservations
            )
            return
        }

        let cleanup = drainPendingAttachmentCleanup(adding: attachmentCleanup)
        saveWriter.updateItemAsync(
            ClipboardHistoryItemMutation(item: item, fields: fields),
            attachmentCleanup: cleanup,
            stagedAttachmentReservations: stagedAttachmentReservations,
            revision: nextSaveRevision()
        )
    }

    private func persistIncrementalInsert(_ insertedItems: [ClipboardItem]) {
        guard !insertedItems.isEmpty,
              !isTerminationDrainSealed else {
            return
        }

        let mustSaveFullSnapshot = requiresFullSnapshotSave
        deferredSaveTask?.cancel()
        deferredSaveTask = nil
        if mustSaveFullSnapshot {
            persistCurrentSnapshotAsync()
            return
        }

        saveWriter.insertItemsAsync(
            insertedItems,
            revision: nextSaveRevision()
        )
    }

    private func persistGroupsIncrementally() {
        guard !groups.isEmpty,
              !isTerminationDrainSealed else {
            return
        }

        let mustSaveFullSnapshot = requiresFullSnapshotSave
        deferredSaveTask?.cancel()
        deferredSaveTask = nil
        if mustSaveFullSnapshot {
            persistCurrentSnapshotAsync()
            return
        }

        saveWriter.upsertGroupsAsync(
            groups,
            revision: nextSaveRevision()
        )
    }

    private func persistIncrementalDelete(
        itemIDs: Set<ClipboardItem.ID>,
        groupIDs: Set<ClipboardGroup.ID> = [],
        attachmentCleanup: ClipboardAttachmentCleanup = .empty
    ) {
        guard !isTerminationDrainSealed else {
            return
        }
        pendingDeletedItemIDs.formUnion(itemIDs)
        pendingDeletedGroupIDs.formUnion(groupIDs)
        nextPersistedItemOffset = max(0, nextPersistedItemOffset - itemIDs.count)
        let mustSaveFullSnapshot = requiresFullSnapshotSave
        deferredSaveTask?.cancel()
        deferredSaveTask = nil
        cancelPagedLoad()
        if mustSaveFullSnapshot {
            persistCurrentSnapshotAsync(adding: attachmentCleanup)
            return
        }
        let revision = nextSaveRevision()
        let saveWriter = saveWriter
        let attachmentCleanup = drainPendingAttachmentCleanup(adding: attachmentCleanup)
        saveWriter.deleteAsync(
            itemIDs: itemIDs,
            groupIDs: groupIDs,
            attachmentCleanup: attachmentCleanup,
            revision: revision
        )
    }

    private func persistDeleteAll(attachmentCleanup: ClipboardAttachmentCleanup = .empty) {
        guard !isTerminationDrainSealed else {
            return
        }
        deferredSaveTask?.cancel()
        deferredSaveTask = nil
        cancelPagedLoad()
        requiresFullSnapshotSave = false
        nextPersistedItemOffset = 0
        nextPersistedItemCursor = nil
        let revision = nextSaveRevision()
        let saveWriter = saveWriter
        let attachmentCleanup = drainPendingAttachmentCleanup(adding: attachmentCleanup)
        saveWriter.deleteAllAsync(
            preserving: groups,
            attachmentCleanup: attachmentCleanup,
            revision: revision
        )
    }

    private func saveImmediately() {
        do {
            try saveImmediatelyOrThrow()
        } catch {
            NSLog("ClipEase failed to save clipboard history: \(error.localizedDescription)")
            PerformanceDiagnosticsService.shared.recordError(
                "history.persistence.saveImmediate.failed",
                category: "storage",
                error: error
            )
        }
    }

    private func saveImmediatelyOrThrow() throws {
        guard !isTerminationDrainSealed else {
            return
        }
        deferredSaveTask?.cancel()
        deferredSaveTask = nil
        requiresFullSnapshotSave = true
        do {
            try loadAllPersistedItemsBeforeFullSave()
        } catch {
            recordFullSnapshotPreparationFailure(error)
            throw error
        }
        let attachmentCleanup = drainPendingAttachmentCleanup()
        requiresFullSnapshotSave = false
        fullSnapshotPreparationError = nil
        try saveWriter.saveSync(
            ClipboardHistorySnapshot(items: items, groups: groups),
            attachmentCleanup: attachmentCleanup,
            revision: nextSaveRevision()
        )
    }

    private func submitFullResync() {
        deferredSaveTask?.cancel()
        deferredSaveTask = nil
        requiresFullSnapshotSave = true
        guard persistCurrentSnapshotAsync() else {
            saveWriter.recoveryRequestDidNotSubmit()
            return
        }
    }

    @discardableResult
    private func persistCurrentSnapshotAsync(
        adding attachmentCleanup: ClipboardAttachmentCleanup = .empty,
        stagedAttachmentReservations: [ClipboardAttachmentReservation] = []
    ) -> Bool {
        guard !isTerminationDrainSealed else {
            scheduleStagedAttachmentDiscard(stagedAttachmentReservations.map(Optional.some))
            return false
        }
        do {
            try loadAllPersistedItemsBeforeFullSave()
        } catch {
            scheduleStagedAttachmentDiscard(stagedAttachmentReservations.map(Optional.some))
            recordFullSnapshotPreparationFailure(error)
            return false
        }

        let cleanup = drainPendingAttachmentCleanup(adding: attachmentCleanup)
        requiresFullSnapshotSave = false
        fullSnapshotPreparationError = nil
        saveWriter.saveAsync(
            ClipboardHistorySnapshot(items: items, groups: groups),
            attachmentCleanup: cleanup,
            stagedAttachmentReservations: stagedAttachmentReservations,
            revision: nextSaveRevision()
        )
        return true
    }

    private func drainPendingAttachmentCleanup(
        adding attachmentCleanup: ClipboardAttachmentCleanup = .empty
    ) -> ClipboardAttachmentCleanup {
        let cleanup = pendingAttachmentCleanup.union(attachmentCleanup)
        pendingAttachmentCleanup = .empty
        return cleanup
    }

    private func loadAllPersistedItemsBeforeFullSave() throws {
        guard !didLoadAllPersistedItems else {
            return
        }

        cancelPagedLoad()
        let startedAt = CFAbsoluteTimeGetCurrent()
        let persistedSnapshot = try persistence.loadSnapshotOrThrow()
        let tombstonedItems = persistedSnapshot.items.filter { item in
            pendingDeletedItemIDs.contains(item.id)
                || item.groupID.map(pendingDeletedGroupIDs.contains) == true
        }
        pendingAttachmentCleanup = pendingAttachmentCleanup.union(
            ClipboardAttachmentCleanup(items: tombstonedItems)
        )
        let existingItemIDs = Set(items.map(\.id))
        let missingItems = persistedSnapshot.items.filter { item in
            !existingItemIDs.contains(item.id)
                && !pendingDeletedItemIDs.contains(item.id)
                && item.groupID.map(pendingDeletedGroupIDs.contains) != true
        }
        items.append(contentsOf: missingItems)

        let existingGroupIDs = Set(groups.map(\.id))
        let missingGroups = persistedSnapshot.groups.filter { group in
            !existingGroupIDs.contains(group.id)
                && !pendingDeletedGroupIDs.contains(group.id)
        }
        groups.append(contentsOf: missingGroups)
        nextPersistedItemOffset = persistedSnapshot.items.count
        nextPersistedItemCursor = persistedSnapshot.items.last.map(
            HistoryPagingService.ItemCursor.init(item:)
        )
        didLoadAllPersistedItems = true
        sortItems()
        sortGroups()
        _ = pruneExpiredItems()

        PerformanceDiagnosticsService.shared.record(
            "history.store.loadAllBeforeFullSave",
            category: "storage",
            durationMS: (CFAbsoluteTimeGetCurrent() - startedAt) * 1_000,
            itemCount: missingItems.count,
            resultCount: items.count
        )
    }

    private func recordFullSnapshotPreparationFailure(_ error: Error) {
        persistenceMutationGeneration &+= 1
        fullSnapshotPreparationError = .preparationFailed(
            description: error.localizedDescription
        )
        NSLog("ClipEase failed to prepare full history snapshot: \(error.localizedDescription)")
        PerformanceDiagnosticsService.shared.recordError(
            "history.persistence.prepareFullSnapshot.failed",
            category: "storage",
            error: error
        )
    }

    private func nextSaveRevision() -> Int {
        saveRevision += 1
        persistenceMutationGeneration &+= 1
        return saveRevision
    }

    private func rebuildRecentHashesAndGroupCounts() {
        rebuildItemIndexes()
        rebuildRecentHashes()
    }

    private func rebuildRecentHashes() {
        domainStore.rebuildRecentHashes(for: items)
    }

    private func addRecentHash(for item: ClipboardItem) {
        domainStore.addRecentHash(for: item)
    }

    private func removeRecentHashes(for removedItems: [ClipboardItem]) {
        domainStore.removeRecentHashes(for: removedItems)
    }

    private func updateGroupCountOnMove(from oldGroupID: ClipboardGroup.ID?, to newGroupID: ClipboardGroup.ID?) {
        domainStore.updateGroupCountOnMove(from: oldGroupID, to: newGroupID)
    }

    @discardableResult
    private func upsertClipboardItem(
        _ item: ClipboardItem,
        replacingRichTextFileName newRichTextFileName: String? = nil,
        stagedAttachmentReservations: [ClipboardAttachmentReservation] = []
    ) -> UpsertResult {
        applyPreparedClipboardItemUpsert(
            prepareClipboardItemUpsert(
                item,
                replacingRichTextFileName: newRichTextFileName
            ),
            persist: true,
            stagedAttachmentReservations: stagedAttachmentReservations
        )
    }

    private func prepareClipboardItemUpsert(
        _ item: ClipboardItem,
        replacingRichTextFileName newRichTextFileName: String? = nil
    ) -> PreparedUpsert {
        let startedAt = CFAbsoluteTimeGetCurrent()
        let hash = DuplicateResolver.contentKey(for: item)
        let cachedDuplicateIDs = domainStore.itemIDs(forContentKey: hash)
        let cachedDuplicateItems = cachedDuplicateIDs.compactMap { self.item(with: $0) }
        let persistedDuplicateItems = persistedDuplicateItems(for: item)
        let duplicateItems = DuplicateResolver.mergedDuplicateItems(
            cachedItems: cachedDuplicateItems,
            persistedItems: persistedDuplicateItems
        )
        let duplicateIDs = Set(duplicateItems.map(\.id))
        let firstDuplicate = duplicateItems.first
        var insertedItem = item
        var reusedLinkMetadata = false
        var duplicateCleanup = ClipboardAttachmentCleanup.empty

        if let firstDuplicate {
            insertedItem.isPinned = firstDuplicate.isPinned
            insertedItem.pinnedAt = firstDuplicate.pinnedAt
            insertedItem.groupID = firstDuplicate.groupID
            insertedItem.groupedAt = firstDuplicate.groupedAt

            if item.type == .link,
               let itemURL = item.url,
               let reusableMetadataItem = duplicateItems.first(where: { candidate in
                   guard candidate.type == .link,
                         candidate.url == itemURL else {
                       return false
                   }
                   return Self.hasEnrichedLinkMetadata(
                       candidate,
                       fallbackTitle: item.linkTitle
                   )
               }) {
                insertedItem = insertedItem.updatingLinkMetadata(
                    title: reusableMetadataItem.linkTitle,
                    imageFileName: reusableMetadataItem.imageFileName,
                    imageWidth: reusableMetadataItem.imageWidth,
                    imageHeight: reusableMetadataItem.imageHeight,
                    imageHash: reusableMetadataItem.imageHash
                )
                reusedLinkMetadata = true
            }

            let insertedRichTextFileName = newRichTextFileName ?? item.richTextFileName
            duplicateCleanup = ClipboardAttachmentCleanup(
                items: duplicateItems,
                preservingImageFileNames: Set([insertedItem.imageFileName].compactMap { $0 }),
                preservingRichTextFileNames: Set([insertedRichTextFileName].compactMap { $0 })
            )
        }

        return PreparedUpsert(
            item: insertedItem,
            duplicateItems: duplicateItems,
            duplicateIDs: duplicateIDs,
            attachmentCleanup: duplicateCleanup,
            reusedLinkMetadata: reusedLinkMetadata,
            startedAt: startedAt
        )
    }

    private func applyPreparedClipboardItemUpsert(
        _ preparedUpsert: PreparedUpsert,
        persist: Bool,
        stagedAttachmentReservations: [ClipboardAttachmentReservation] = []
    ) -> UpsertResult {
        let insertedItem = preparedUpsert.item
        if !preparedUpsert.duplicateIDs.isEmpty {
            items.removeAll { preparedUpsert.duplicateIDs.contains($0.id) }
            rebuildItemIndexes()
            cancelOCRTasks(for: preparedUpsert.duplicateIDs)
            cancelLinkMetadataTasks(for: preparedUpsert.duplicateIDs)
            removeRecentHashes(for: preparedUpsert.duplicateItems)
        }

        insertItemMaintainingSort(insertedItem)
        pruneExpiredItems()
        addRecentHash(for: insertedItem)
        if persist {
            persistIncrementalUpsert(
                insertedItem,
                deleting: preparedUpsert.duplicateIDs,
                attachmentCleanup: preparedUpsert.attachmentCleanup,
                stagedAttachmentReservations: stagedAttachmentReservations
            )
        }
        latestItemFocusRequest = ClipboardItemFocusRequest(itemID: insertedItem.id, reason: .inserted)
        PerformanceDiagnosticsService.shared.record(
            "history.store.upsert",
            category: "storage",
            durationMS: (CFAbsoluteTimeGetCurrent() - preparedUpsert.startedAt) * 1_000,
            itemCount: items.count,
            resultCount: preparedUpsert.duplicateItems.count,
            metadata: [
                "type": insertedItem.type.rawValue,
                "persistence": persist ? "incremental" : "awaited"
            ]
        )
        return UpsertResult(
            item: insertedItem,
            reusedLinkMetadata: preparedUpsert.reusedLinkMetadata
        )
    }

    private func playExternalCopyFeedbackIfNeeded(for item: ClipboardItem) {
        guard !item.isFromClipEase else {
            return
        }

        externalCopyFeedback(item)
    }

    private func clipboardFilePathSetKey(for urls: [URL]) -> String {
        urls
            .filter(\.isFileURL)
            .map { $0.standardizedFileURL.path }
            .sorted()
            .joined(separator: "\u{1F}")
    }

    private func nonDuplicateItems(from importedItems: [ClipboardItem]) -> [ClipboardItem] {
        DuplicateResolver.nonDuplicateItems(importedItems: importedItems, existingItems: items)
    }

    private func sanitizedImportedItems(_ importedItems: [ClipboardItem]) -> [ClipboardItem] {
        let validGroupIDs = Set(groups.map(\.id))
        return importedItems.map { item in
            sanitizedImportedItem(item, validGroupIDs: validGroupIDs)
        }
    }

    private func sanitizedImportedItem(
        _ item: ClipboardItem,
        validGroupIDs: Set<ClipboardGroup.ID>
    ) -> ClipboardItem {
        guard let groupID = item.groupID,
              validGroupIDs.contains(groupID) else {
            var sanitizedItem = item
            sanitizedItem.groupID = nil
            sanitizedItem.groupedAt = nil
            return sanitizedItem
        }

        var sanitizedItem = item
        sanitizedItem.groupedAt = item.groupedAt ?? item.createdAt
        return sanitizedItem
    }

    private func importBackupGroups(_ importedGroups: [ClipboardGroup]) -> [ClipboardGroup.ID: ClipboardGroup.ID] {
        guard !importedGroups.isEmpty else {
            return [:]
        }

        var mapping: [ClipboardGroup.ID: ClipboardGroup.ID] = [:]
        var knownIDs = Set(groups.map(\.id))
        var knownNames = Set(groups.map { GroupService.normalizedGroupName($0.name) })
        var groupsToAppend: [ClipboardGroup] = []

        for importedGroup in importedGroups {
            let normalizedName = GroupService.normalizedGroupName(importedGroup.name)
            if knownIDs.contains(importedGroup.id) {
                if let existingGroup = groups.first(where: { $0.id == importedGroup.id }),
                   GroupService.normalizedGroupName(existingGroup.name) == normalizedName {
                    mapping[importedGroup.id] = importedGroup.id
                }
                continue
            }

            guard !knownNames.contains(normalizedName) else {
                continue
            }

            var group = importedGroup
            group.sortOrder = groups.count + groupsToAppend.count
            groupsToAppend.append(group)
            knownIDs.insert(group.id)
            knownNames.insert(normalizedName)
            mapping[importedGroup.id] = group.id
        }

        guard !groupsToAppend.isEmpty else {
            return mapping
        }

        groups.append(contentsOf: groupsToAppend)
        sortGroups()
        return mapping
    }

    private func sanitizedBackupItem(
        _ item: ClipboardItem,
        groupIDMapping: [ClipboardGroup.ID: ClipboardGroup.ID],
        validGroupIDs: Set<ClipboardGroup.ID>
    ) -> ClipboardItem {
        guard let importedGroupID = item.groupID else {
            return item
        }

        var sanitizedItem = item
        let resolvedGroupID = groupIDMapping[importedGroupID]
            ?? (validGroupIDs.contains(importedGroupID) ? importedGroupID : nil)
        guard let resolvedGroupID else {
            sanitizedItem.groupID = nil
            sanitizedItem.groupedAt = nil
            return sanitizedItem
        }

        if validGroupIDs.contains(resolvedGroupID) {
            sanitizedItem.groupID = resolvedGroupID
            sanitizedItem.groupedAt = item.groupedAt ?? item.createdAt
        } else {
            sanitizedItem.groupID = nil
            sanitizedItem.groupedAt = nil
        }
        return sanitizedItem
    }

    private static func fallbackLinkTitle(for url: URL) -> String {
        let path = url.path(percentEncoded: false)
        if !path.isEmpty, path != "/" {
            return URL(fileURLWithPath: path).lastPathComponent
        }

        return url.host(percentEncoded: false) ?? url.absoluteString
    }

    private static func hasEnrichedLinkMetadata(
        _ item: ClipboardItem,
        fallbackTitle: String?
    ) -> Bool {
        if item.imageFileName != nil {
            return true
        }
        guard let title = item.linkTitle else {
            return false
        }

        var fallbackTitles = Set([fallbackTitle].compactMap { $0 })
        if let url = item.url {
            fallbackTitles.insert(Self.fallbackLinkTitle(for: url))
            let path = url.path(percentEncoded: false)
            fallbackTitles.insert(
                path.isEmpty || path == "/"
                    ? "/"
                    : URL(fileURLWithPath: path).lastPathComponent
            )
        }
        return !fallbackTitles.contains(title)
    }

    private func fileReferences(from urls: [URL]) -> [ClipboardFileReference] {
        let itemID = UUID()
        let createdAt = Date()
        var seenPaths = Set<String>()

        return urls.compactMap { url -> URL? in
            guard url.isFileURL else {
                return nil
            }

            let standardizedURL = url.standardizedFileURL
            guard seenPaths.insert(standardizedURL.path).inserted else {
                return nil
            }

            return standardizedURL
        }
        .enumerated()
        .map { index, url in
            fileReference(
                for: url,
                itemID: itemID,
                orderIndex: index,
                createdAt: createdAt
            )
        }
    }

    private func fileReference(
        for url: URL,
        itemID: UUID,
        orderIndex: Int,
        createdAt: Date
    ) -> ClipboardFileReference {
        let checkedAt = Date()
        let resourceKeys: Set<URLResourceKey> = [
            .contentTypeKey,
            .fileAllocatedSizeKey,
            .fileSizeKey,
            .isAliasFileKey,
            .isDirectoryKey,
            .isReadableKey,
            .ubiquitousItemDownloadingStatusKey,
            .contentModificationDateKey,
        ]
        let values = try? url.resourceValues(forKeys: resourceKeys)

        return ClipboardFileReference(
            itemID: itemID,
            orderIndex: orderIndex,
            path: url.path,
            displayName: url.lastPathComponent,
            fileExtension: url.pathExtension.isEmpty ? nil : url.pathExtension,
            contentType: contentTypeIdentifier(for: url, values: values),
            fileSize: values?.fileSize ?? values?.fileAllocatedSize,
            modifiedAt: values?.contentModificationDate,
            isDirectory: values?.isDirectory ?? false,
            isAlias: values?.isAliasFile ?? false,
            pathStatus: pathStatus(for: url, values: values),
            lastCheckedAt: checkedAt,
            createdAt: createdAt
        )
    }

    private func contentTypeIdentifier(for url: URL, values: URLResourceValues?) -> String? {
        if #available(macOS 11.0, *), let contentType = values?.contentType {
            return contentType.identifier
        }

        return UTType(filenameExtension: url.pathExtension)?.identifier
    }

    private func pathStatus(for url: URL, values: URLResourceValues?) -> ClipboardFilePathStatus {
        if values?.ubiquitousItemDownloadingStatus == .notDownloaded {
            return .placeholder
        }

        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return .missing
        }

        if values?.isReadable == false || !FileManager.default.isReadableFile(atPath: url.path) {
            return .permissionDenied
        }

        return .available
    }

    @discardableResult
    private func pruneExpiredItems(
        now: Date = Date(),
        force: Bool = false
    ) -> Bool {
        guard retentionRunSchedule.shouldRun(now: now, force: force) else {
            return false
        }

        let cutoff = HistoryRetentionService.cutoffDate(for: retentionPolicy, now: now)
        activeRetentionCutoff = cutoff
        guard let cutoff else {
            return false
        }

        cancelPagedLoad()
        let validGroupIDs = Set(groups.map(\.id))
        let removedItems = HistoryRetentionService.expiredItems(
            in: items,
            policy: retentionPolicy,
            validGroupIDs: validGroupIDs,
            now: now
        )

        if !removedItems.isEmpty {
            let removedIDs = Set(removedItems.map(\.id))
            pendingDeletedItemIDs.formUnion(removedIDs)
            nextPersistedItemOffset = max(0, nextPersistedItemOffset - removedItems.count)
            items.removeAll { removedIDs.contains($0.id) }
            rebuildItemIndexes()
            cancelOCRTasks(for: removedItems)
            cancelLinkMetadataTasks(for: removedItems)
            rebuildRecentHashes()
        }

        retentionRequestGeneration &+= 1
        let generation = retentionRequestGeneration
        pendingRetentionRequestGeneration = generation
        saveWriter.deleteExpiredAsync(
            before: cutoff,
            revision: nextSaveRevision(),
            completion: { [weak self] in
                Task { @MainActor [weak self] in
                    self?.retentionRequestDidComplete(generation: generation)
                }
            }
        )
        return !removedItems.isEmpty
    }

    private static func isDebugTextItem(_ item: ClipboardItem) -> Bool {
        item.type == .text
            && item.sourceBundleID == SourceAppInfo.clipease.bundleID
            && item.text.hasPrefix(debugTextPrefix)
    }

    nonisolated private static func makeDebugTextItems(
        count: Int,
        sourceApp: SourceAppInfo
    ) async -> [ClipboardItem] {
        let now = Date()
        var items: [ClipboardItem] = []
        items.reserveCapacity(count)

        for index in 0..<count {
            if Task.isCancelled {
                return []
            }

            items.append(
                ClipboardItem.debugText(
                    "\(debugTextPrefix)\(index + 1) keyword-\(index % 25) 搜索测试 \(UUID().uuidString)",
                    createdAt: now.addingTimeInterval(TimeInterval(-index)),
                    sourceApp: sourceApp
                )
            )

            if index > 0, index % debugBatchSize == 0 {
                await Task.yield()
            }
        }

        return items
    }
}
