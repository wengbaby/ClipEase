import Foundation

enum ClipboardHistoryWriteRecovery: Equatable, Sendable {
    case incrementalAllowed
    case fullResyncRequired(failedRevision: Int)
}

enum ClipboardHistoryWriteOperation: String, Equatable, Sendable {
    case save
    case upsert
    case insertItems
    case upsertGroups
    case delete
    case deleteAll
    case retention
}

enum ClipboardHistoryAuthoritativeSnapshotError: Error, LocalizedError, Equatable, Sendable {
    case preparationFailed(description: String)
    case persistenceFailed(
        operation: ClipboardHistoryWriteOperation,
        revision: Int,
        description: String
    )
    case readFailed(description: String)

    var errorDescription: String? {
        switch self {
        case .preparationFailed(let description):
            "Failed to prepare the complete clipboard history snapshot: \(description)"
        case let .persistenceFailed(operation, revision, description):
            "Clipboard history \(operation.rawValue) failed at revision \(revision): \(description)"
        case .readFailed(let description):
            "Failed to read the complete clipboard history snapshot: \(description)"
        }
    }
}

struct ClipboardHistoryAuthoritativeSnapshot: Sendable {
    let history: ClipboardHistorySnapshot
    let mutationGeneration: UInt64
}

struct ClipboardHistoryCommitFailure: Error, @unchecked Sendable {
    let underlyingError: Error
}

final class ClipboardHistorySaveWriter: @unchecked Sendable {
    private struct RetentionRestorationAuthority {
        let revision: Int
        let cutoff: Date
        let protectedGroupIDs: Set<ClipboardGroup.ID>
    }

    private struct PendingMutation {
        let repositoryMutation: ClipboardHistoryRepositoryMutation
        let attachmentCleanup: ClipboardAttachmentCleanup
        let stagedAttachmentReservations: [ClipboardAttachmentReservation]
        let revision: Int
    }

    private let queue = DispatchQueue(label: "app.clipease.history-save", qos: .utility)
    private let persistence: ClipboardHistoryPersistence
    private let attachmentCleanup: @Sendable (ClipboardAttachmentCleanup) throws -> Void
    private let usesPersistentAttachmentCleanupRetry: Bool
    private var recoveryRequest: @Sendable () -> Void
    private let compactionScheduler = ClipboardDatabaseCompactionScheduler()
    private let batchPolicy: ClipboardHistoryWriteBatchPolicy
    private var latestRevision = 0
    private var recovery: ClipboardHistoryWriteRecovery = .incrementalAllowed
    private var isRecoveryRequestPending = false
    private var pendingAttachmentCleanup = ClipboardAttachmentCleanup.empty
    private var retainedPersistenceFailure: ClipboardHistoryAuthoritativeSnapshotError?
    private var unresolvedImportReceiptCount = 0
    private var deletedItemRevision: [ClipboardItem.ID: Int] = [:]
    private var deleteAllRevision = 0
    private var fullSnapshotRevision = 0
    private var fullSnapshotItemIDs = Set<ClipboardItem.ID>()
    private var retentionRestorationAuthorities: [RetentionRestorationAuthority] = []
    private var pendingMutations: [PendingMutation] = []
    private var accumulatedBarrierDrainResult = ClipboardHistoryWriteDrainResult.empty
    private var scheduledBatchToken: UInt64 = 0
    private var scheduledAttachmentCleanupRetryToken: UInt64 = 0
    private var retainedAttachmentCleanupFailure: String?

    var unresolvedImportReceiptCountForTesting: Int {
        queue.sync { unresolvedImportReceiptCount }
    }

    var attachmentCleanupFailureForTesting: String? {
        queue.sync { retainedAttachmentCleanupFailure }
    }

    init(
        persistence: ClipboardHistoryPersistence,
        attachmentCleanup: (@Sendable (ClipboardAttachmentCleanup) throws -> Void)? = nil,
        recoveryRequest: @escaping @Sendable () -> Void = {},
        batchPolicy: ClipboardHistoryWriteBatchPolicy = .enterpriseDefault
    ) {
        self.persistence = persistence
        if let attachmentCleanup {
            self.attachmentCleanup = attachmentCleanup
            self.usesPersistentAttachmentCleanupRetry = false
        } else {
            self.attachmentCleanup = { cleanup in
                _ = try persistence.scheduleAttachmentCleanupOrThrow(cleanup)
            }
            self.usesPersistentAttachmentCleanupRetry =
                persistence.hasPersistentAttachmentCleanupRetryLedger
        }
        self.recoveryRequest = recoveryRequest
        self.batchPolicy = batchPolicy
        if usesPersistentAttachmentCleanupRetry {
            queue.async { [weak self] in
                self?.replayPersistedAttachmentCleanup()
            }
        }
    }

    func setRecoveryRequestHandler(_ handler: @escaping @Sendable () -> Void) {
        queue.sync {
            recoveryRequest = handler
        }
    }

    func recoveryRequestDidNotSubmit() {
        queue.async { [self] in
            isRecoveryRequestPending = false
        }
    }

    func loadAuthoritativeSnapshotAfterPendingWrites() async throws -> ClipboardHistorySnapshot {
        try Task.checkCancellation()
        let driver = ClipboardHistoryAsyncRequestDriver<ClipboardHistorySnapshot>()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard driver.install(continuation) else {
                    return
                }
                queue.async { [self] in
                    guard !driver.isCompleted else {
                        return
                    }
                    _ = drainPendingMutations()

                    if case .fullResyncRequired(let failedRevision) = recovery {
                        let failure = retainedPersistenceFailure ?? .persistenceFailed(
                            operation: .save,
                            revision: failedRevision,
                            description: "A full persistence resync is required."
                        )
                        driver.finish(.failure(failure))
                        return
                    }

                    do {
                        driver.finish(.success(try persistence.loadSnapshotOrThrow()))
                    } catch {
                        driver.finish(
                            .failure(
                                ClipboardHistoryAuthoritativeSnapshotError.readFailed(
                                    description: error.localizedDescription
                                )
                            )
                        )
                    }
                }
            }
        } onCancel: {
            driver.cancel()
        }
    }

    func deleteUnreferencedAttachmentCandidates(
        _ candidates: ClipboardAttachmentCleanup
    ) async throws -> OrphanedAttachmentCleanupResult {
        try Task.checkCancellation()
        let driver = ClipboardHistoryAsyncRequestDriver<OrphanedAttachmentCleanupResult>()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard driver.install(continuation) else {
                    return
                }
                queue.async { [self] in
                    guard !driver.isCompleted else {
                        return
                    }
                    _ = drainPendingMutations()

                    if case .fullResyncRequired(let failedRevision) = recovery {
                        let failure = retainedPersistenceFailure ?? .persistenceFailed(
                            operation: .save,
                            revision: failedRevision,
                            description: "A full persistence resync is required."
                        )
                        driver.finish(.failure(failure))
                        return
                    }

                    do {
                        driver.finish(
                            .success(
                                try persistence.deleteUnreferencedAttachmentCandidatesOrThrow(candidates)
                            )
                        )
                    } catch {
                        driver.finish(.failure(error))
                    }
                }
            }
        } onCancel: {
            driver.cancel()
        }
    }

    func saveAsync(
        _ snapshot: ClipboardHistorySnapshot,
        attachmentCleanup: ClipboardAttachmentCleanup = .empty,
        stagedAttachmentReservations: [ClipboardAttachmentReservation] = [],
        revision: Int
    ) {
        queue.async { [self] in
            _ = drainPendingMutations()
            do {
                if let persistedCleanup = try saveIfCurrent(snapshot, revision: revision) {
                    completeFullSave(
                        attachmentCleanup: attachmentCleanup.union(persistedCleanup)
                    )
                    releaseStagedAttachments(stagedAttachmentReservations)
                } else {
                    discardStagedAttachments(stagedAttachmentReservations)
                }
            } catch {
                discardStagedAttachments(stagedAttachmentReservations)
                retainPersistenceFailure(operation: .save, revision: revision, error: error)
                requireFullResync(afterFailureAt: revision, attachmentCleanup: attachmentCleanup)
                NSLog("ClipEase failed to save clipboard history: \(error.localizedDescription)")
                recordPersistenceError("history.persistence.save.failed", error: error, revision: revision)
            }
        }
    }

    func upsertAsync(
        _ item: ClipboardItem,
        deleting deletedIDs: Set<ClipboardItem.ID>,
        groups: [ClipboardGroup],
        attachmentCleanup: ClipboardAttachmentCleanup = .empty,
        stagedAttachmentReservations: [ClipboardAttachmentReservation] = [],
        revision: Int
    ) {
        queue.async { [self] in
            enqueueMutation(
                PendingMutation(
                    repositoryMutation: .upsert(
                        ClipboardHistoryUpsertMutation(
                            item: item,
                            deletedIDs: deletedIDs,
                            groups: groups
                        )
                    ),
                    attachmentCleanup: attachmentCleanup,
                    stagedAttachmentReservations: stagedAttachmentReservations,
                    revision: revision
                )
            )
        }
    }

    func updateItemAsync(
        _ mutation: ClipboardHistoryItemMutation,
        attachmentCleanup: ClipboardAttachmentCleanup = .empty,
        stagedAttachmentReservations: [ClipboardAttachmentReservation] = [],
        revision: Int
    ) {
        guard !mutation.fields.isEmpty else {
            return
        }
        queue.async { [self] in
            enqueueMutation(
                PendingMutation(
                    repositoryMutation: .update(mutation),
                    attachmentCleanup: attachmentCleanup,
                    stagedAttachmentReservations: stagedAttachmentReservations,
                    revision: revision
                )
            )
        }
    }

    func upsertAwaitingCommit(
        _ item: ClipboardItem,
        deleting deletedIDs: Set<ClipboardItem.ID>,
        groups: [ClipboardGroup],
        attachmentCleanup: ClipboardAttachmentCleanup = .empty,
        stagedAttachmentReservations: [ClipboardAttachmentReservation] = [],
        revision: Int
    ) async throws {
        try Task.checkCancellation()
        let driver = ClipboardHistoryAsyncRequestDriver<Void>()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard driver.install(continuation) else {
                    return
                }
                queue.async { [self] in
                    guard !driver.isCompleted else {
                        return
                    }
                    _ = drainPendingMutations()
                    guard shouldAttemptIncrementalWrite(
                        revision: revision,
                        attachmentCleanup: attachmentCleanup
                    ) else {
                        discardStagedAttachments(stagedAttachmentReservations)
                        let error = retainedPersistenceFailure ?? .preparationFailed(
                            description: "The clipboard history update could not be committed."
                        )
                        driver.finish(.failure(error))
                        return
                    }
                    guard driver.beginCommit() else {
                        return
                    }

                    do {
                        guard try upsertIfCurrent(
                            item,
                            deleting: deletedIDs,
                            groups: groups,
                            revision: revision
                        ) else {
                            discardStagedAttachments(stagedAttachmentReservations)
                            driver.finish(
                                .failure(
                                    ClipboardHistoryCommitFailure(
                                        underlyingError: ClipboardHistoryAuthoritativeSnapshotError.preparationFailed(
                                            description: "The clipboard history update was superseded."
                                        )
                                    )
                                )
                            )
                            return
                        }
                        performAttachmentCleanup(attachmentCleanup)
                        releaseStagedAttachments(stagedAttachmentReservations)
                        driver.finish(.success(()))
                    } catch {
                        discardStagedAttachments(stagedAttachmentReservations)
                        retainPersistenceFailure(operation: .upsert, revision: revision, error: error)
                        requireFullResync(
                            afterFailureAt: revision,
                            attachmentCleanup: attachmentCleanup
                        )
                        recordPersistenceError(
                            "history.persistence.upsert.failed",
                            error: error,
                            revision: revision
                        )
                        driver.finish(
                            .failure(ClipboardHistoryCommitFailure(underlyingError: error))
                        )
                    }
                }
            }
        } onCancel: {
            driver.cancelBeforeCommit()
        }
    }

    func commitImportedItemAwaitingDecision(
        _ item: ClipboardItem,
        deleting deletedIDs: Set<ClipboardItem.ID>,
        displacedItems: [ClipboardItem],
        groups: [ClipboardGroup],
        acceptedCleanup: ClipboardAttachmentCleanup,
        stagedAttachmentReservations: [ClipboardAttachmentReservation],
        revision: Int
    ) async throws -> ClipboardImportCommitReceipt {
        try Task.checkCancellation()
        let driver = ClipboardHistoryAsyncRequestDriver<ClipboardImportCommitReceipt>()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard driver.install(continuation) else { return }
                queue.async { [self] in
                    guard !driver.isCompleted else { return }
                    _ = drainPendingMutations()
                    guard shouldAttemptIncrementalWrite(
                        revision: revision,
                        attachmentCleanup: acceptedCleanup
                    ) else {
                        discardStagedAttachments(stagedAttachmentReservations)
                        let error = retainedPersistenceFailure ?? .preparationFailed(
                            description: "The clipboard history update could not be committed."
                        )
                        driver.finish(.failure(error))
                        return
                    }
                    guard driver.beginCommit() else { return }

                    do {
                        guard try upsertIfCurrent(
                            item,
                            deleting: deletedIDs,
                            groups: groups,
                            revision: revision
                        ) else {
                            discardStagedAttachments(stagedAttachmentReservations)
                            driver.finish(.failure(ClipboardHistoryCommitFailure(
                                underlyingError: ClipboardHistoryAuthoritativeSnapshotError.preparationFailed(
                                    description: "The clipboard history update was superseded."
                                )
                            )))
                            return
                        }
                        let receipt = ClipboardImportCommitReceipt(
                            revision: revision,
                            insertedItem: item,
                            displacedItems: displacedItems,
                            acceptedCleanup: acceptedCleanup,
                            stagedReservations: stagedAttachmentReservations
                        )
                        unresolvedImportReceiptCount += 1
                        driver.finish(.success(receipt))
                    } catch {
                        discardStagedAttachments(stagedAttachmentReservations)
                        retainPersistenceFailure(operation: .upsert, revision: revision, error: error)
                        requireFullResync(
                            afterFailureAt: revision,
                            attachmentCleanup: acceptedCleanup
                        )
                        recordPersistenceError(
                            "history.persistence.upsert.failed",
                            error: error,
                            revision: revision
                        )
                        driver.finish(.failure(ClipboardHistoryCommitFailure(underlyingError: error)))
                    }
                }
            }
        } onCancel: {
            driver.cancelBeforeCommit()
        }
    }

    @discardableResult
    func acceptImportedItem(_ receipt: ClipboardImportCommitReceipt) -> Bool {
        guard receipt.resolveAccepted() else { return false }
        queue.async { [self] in
            _ = drainPendingMutations()
            performAttachmentCleanup(receipt.acceptedCleanup)
            releaseStagedAttachments(receipt.stagedReservations)
            importReceiptDidResolve()
        }
        return true
    }

    func compensateImportedItem(_ receipt: ClipboardImportCommitReceipt) async throws {
        guard receipt.resolveCompensated() else { return }
        let driver = ClipboardHistoryAsyncRequestDriver<Void>()
        try await withCheckedThrowingContinuation { continuation in
            guard driver.install(continuation) else { return }
            queue.async { [self] in
                _ = drainPendingMutations()
                defer { importReceiptDidResolve() }
                let restorations = receipt.displacedItems.filter {
                    shouldRestoreDisplacedItem($0, from: receipt)
                }

                do {
                    let cleanup = try persistence.compensateImportedItemOrThrow(
                        insertedItemID: receipt.insertedItem.id,
                        restoring: restorations
                    )
                    releaseStagedAttachments(receipt.stagedReservations)
                    performAttachmentCleanup(
                        cleanup.union(Self.candidates(for: receipt.stagedReservations))
                    )
                    driver.finish(.success(()))
                } catch {
                    releaseStagedAttachments(receipt.stagedReservations)
                    retainPersistenceFailure(operation: .upsert, revision: receipt.revision, error: error)
                    requireFullResync(
                        afterFailureAt: receipt.revision,
                        attachmentCleanup: .empty
                    )
                    driver.finish(.failure(ClipboardHistoryCommitFailure(underlyingError: error)))
                }
            }
        }
    }

    func insertItemsAsync(_ items: [ClipboardItem], revision: Int) {
        queue.async { [self] in
            _ = drainPendingMutations()
            guard shouldAttemptIncrementalWrite(
                revision: revision,
                attachmentCleanup: .empty
            ) else {
                return
            }

            do {
                try insertItemsIfCurrent(items, revision: revision)
            } catch {
                retainPersistenceFailure(operation: .insertItems, revision: revision, error: error)
                requireFullResync(afterFailureAt: revision, attachmentCleanup: .empty)
                NSLog("ClipEase failed to insert clipboard history items: \(error.localizedDescription)")
                recordPersistenceError("history.persistence.insert.failed", error: error, revision: revision)
            }
        }
    }

    func upsertGroupsAsync(_ groups: [ClipboardGroup], revision: Int) {
        guard !groups.isEmpty else {
            return
        }

        queue.async { [self] in
            accumulateBarrierDrainResult(drainPendingMutations())
            guard shouldAttemptIncrementalWrite(
                revision: revision,
                attachmentCleanup: .empty
            ) else {
                return
            }

            do {
                try upsertGroupsIfCurrent(groups, revision: revision)
            } catch {
                retainPersistenceFailure(operation: .upsertGroups, revision: revision, error: error)
                requireFullResync(afterFailureAt: revision, attachmentCleanup: .empty)
                NSLog("ClipEase failed to upsert clipboard history groups: \(error.localizedDescription)")
                recordPersistenceError(
                    "history.persistence.upsertGroups.failed",
                    error: error,
                    revision: revision
                )
            }
        }
    }

    func deleteAsync(
        itemIDs: Set<ClipboardItem.ID>,
        groupIDs: Set<ClipboardGroup.ID>,
        attachmentCleanup: ClipboardAttachmentCleanup = .empty,
        revision: Int
    ) {
        queue.async { [self] in
            _ = drainPendingMutations()
            guard shouldAttemptIncrementalWrite(
                revision: revision,
                attachmentCleanup: attachmentCleanup
            ) else {
                return
            }

            do {
                if let repositoryCleanup = try deleteIfCurrent(
                    itemIDs: itemIDs,
                    groupIDs: groupIDs,
                    revision: revision
                ) {
                    performAttachmentCleanup(attachmentCleanup.union(repositoryCleanup))
                }
            } catch {
                retainPersistenceFailure(operation: .delete, revision: revision, error: error)
                requireFullResync(afterFailureAt: revision, attachmentCleanup: attachmentCleanup)
                NSLog("ClipEase failed to delete clipboard history items: \(error.localizedDescription)")
                recordPersistenceError("history.persistence.delete.failed", error: error, revision: revision)
            }
        }
    }

    func deleteAllAsync(
        preserving groups: [ClipboardGroup],
        attachmentCleanup: ClipboardAttachmentCleanup = .empty,
        revision: Int
    ) {
        queue.async { [self] in
            _ = drainPendingMutations()
            guard shouldAttemptIncrementalWrite(
                revision: revision,
                attachmentCleanup: attachmentCleanup
            ) else {
                return
            }

            do {
                if let repositoryCleanup = try deleteAllIfCurrent(
                    preserving: groups,
                    revision: revision
                ) {
                    performAttachmentCleanup(attachmentCleanup.union(repositoryCleanup))
                }
            } catch {
                retainPersistenceFailure(operation: .deleteAll, revision: revision, error: error)
                requireFullResync(afterFailureAt: revision, attachmentCleanup: attachmentCleanup)
                NSLog("ClipEase failed to clear clipboard history: \(error.localizedDescription)")
                recordPersistenceError("history.persistence.deleteAll.failed", error: error, revision: revision)
            }
        }
    }

    func deleteExpiredAsync(
        before cutoff: Date,
        revision: Int,
        completion: @escaping @Sendable () -> Void = {}
    ) {
        queue.async { [self] in
            _ = drainPendingMutations()
            defer { completion() }
            guard shouldAttemptIncrementalWrite(
                revision: revision,
                attachmentCleanup: .empty
            ) else {
                return
            }

            do {
                if let repositoryCleanup = try deleteExpiredIfCurrent(
                    before: cutoff,
                    revision: revision
                ) {
                    performAttachmentCleanup(repositoryCleanup)
                }
            } catch {
                retainPersistenceFailure(operation: .retention, revision: revision, error: error)
                requireFullResync(afterFailureAt: revision, attachmentCleanup: .empty)
                NSLog("ClipEase failed to prune expired clipboard history: \(error.localizedDescription)")
                recordPersistenceError("history.persistence.retention.failed", error: error, revision: revision)
            }
        }
    }

    func saveSync(
        _ snapshot: ClipboardHistorySnapshot,
        attachmentCleanup: ClipboardAttachmentCleanup = .empty,
        stagedAttachmentReservations: [ClipboardAttachmentReservation] = [],
        revision: Int
    ) throws {
        try queue.sync { [self] in
            _ = drainPendingMutations()
            do {
                if let persistedCleanup = try saveIfCurrent(snapshot, revision: revision) {
                    completeFullSave(
                        attachmentCleanup: attachmentCleanup.union(persistedCleanup)
                    )
                    releaseStagedAttachments(stagedAttachmentReservations)
                } else {
                    discardStagedAttachments(stagedAttachmentReservations)
                }
            } catch {
                discardStagedAttachments(stagedAttachmentReservations)
                retainPersistenceFailure(operation: .save, revision: revision, error: error)
                requireFullResync(afterFailureAt: revision, attachmentCleanup: attachmentCleanup)
                throw error
            }
        }
    }

    func flush() {
        _ = drain()
    }

    @discardableResult
    func drain() -> ClipboardHistoryWriteDrainResult {
        queue.sync { [self] in
            drainIncludingBarrierResults()
        }
    }

    func flushAsync() async -> ClipboardHistoryWriteDrainResult {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                continuation.resume(returning: drainIncludingBarrierResults())
            }
        }
    }

    private func accumulateBarrierDrainResult(_ result: ClipboardHistoryWriteDrainResult) {
        accumulatedBarrierDrainResult = Self.mergingDrainResults(
            accumulatedBarrierDrainResult,
            result
        )
    }

    private func drainIncludingBarrierResults() -> ClipboardHistoryWriteDrainResult {
        let result = Self.mergingDrainResults(
            accumulatedBarrierDrainResult,
            drainPendingMutations()
        )
        accumulatedBarrierDrainResult = .empty
        return result
    }

    private static func mergingDrainResults(
        _ lhs: ClipboardHistoryWriteDrainResult,
        _ rhs: ClipboardHistoryWriteDrainResult
    ) -> ClipboardHistoryWriteDrainResult {
        ClipboardHistoryWriteDrainResult(
            attemptedMutationCount: lhs.attemptedMutationCount + rhs.attemptedMutationCount,
            committedMutationCount: lhs.committedMutationCount + rhs.committedMutationCount,
            requiresFullResync: lhs.requiresFullResync || rhs.requiresFullResync
        )
    }

    private func enqueueMutation(_ mutation: PendingMutation) {
        let newestQueuedRevision = pendingMutations.last?.revision ?? latestRevision
        guard mutation.revision > newestQueuedRevision,
              shouldAttemptIncrementalWrite(
                  revision: mutation.revision,
                  attachmentCleanup: mutation.attachmentCleanup
              ) else {
            discardStagedAttachments(mutation.stagedAttachmentReservations)
            return
        }

        let wasEmpty = pendingMutations.isEmpty
        if !coalescePendingMutation(mutation) {
            pendingMutations.append(mutation)
        }

        if pendingMutations.count >= batchPolicy.maximumMutationCount {
            _ = drainPendingMutations()
        } else if wasEmpty {
            schedulePendingMutationDrain()
        }
    }

    private func coalescePendingMutation(_ newer: PendingMutation) -> Bool {
        for index in pendingMutations.indices.reversed() {
            let existing = pendingMutations[index]
            if case .upsert(let interveningUpsert) = existing.repositoryMutation,
               interveningUpsert.deletedIDs.contains(newer.repositoryMutation.itemID) {
                return false
            }
            guard existing.repositoryMutation.itemID == newer.repositoryMutation.itemID else {
                continue
            }

            let mergedRepositoryMutation: ClipboardHistoryRepositoryMutation
            switch (existing.repositoryMutation, newer.repositoryMutation) {
            case let (.update(older), .update(latest)):
                guard existing.attachmentCleanup.isEmpty,
                      newer.attachmentCleanup.isEmpty,
                      existing.stagedAttachmentReservations.isEmpty,
                      newer.stagedAttachmentReservations.isEmpty,
                      let merged = older.merging(latest) else {
                    return false
                }
                mergedRepositoryMutation = .update(merged)
            case let (.upsert(older), .upsert(latest)):
                guard existing.attachmentCleanup.isEmpty,
                      newer.attachmentCleanup.isEmpty,
                      existing.stagedAttachmentReservations.isEmpty,
                      newer.stagedAttachmentReservations.isEmpty,
                      older.deletedIDs.isEmpty,
                      latest.deletedIDs.isEmpty,
                      older.groups == latest.groups else {
                    return false
                }
                mergedRepositoryMutation = .upsert(latest)
            default:
                return false
            }

            pendingMutations.remove(at: index)
            pendingMutations.append(
                PendingMutation(
                    repositoryMutation: mergedRepositoryMutation,
                    attachmentCleanup: newer.attachmentCleanup,
                    stagedAttachmentReservations: newer.stagedAttachmentReservations,
                    revision: newer.revision
                )
            )
            return true
        }
        return false
    }

    private func schedulePendingMutationDrain() {
        scheduledBatchToken &+= 1
        let token = scheduledBatchToken
        queue.asyncAfter(
            deadline: .now() + .milliseconds(batchPolicy.maximumDelayMilliseconds)
        ) { [self] in
            guard token == scheduledBatchToken else {
                return
            }
            _ = drainPendingMutations()
        }
    }

    private func drainPendingMutations() -> ClipboardHistoryWriteDrainResult {
        guard !pendingMutations.isEmpty else {
            return ClipboardHistoryWriteDrainResult(
                attemptedMutationCount: 0,
                committedMutationCount: 0,
                requiresFullResync: isFullResyncRequired
            )
        }

        let batch = pendingMutations
        pendingMutations.removeAll(keepingCapacity: true)
        scheduledBatchToken &+= 1
        let finalRevision = batch.last?.revision ?? latestRevision
        latestRevision = finalRevision
        let startedAt = CFAbsoluteTimeGetCurrent()
        let persistenceInterval = PerformanceDiagnosticsSignposter.beginInterval(
            name: "history.persistence.batch",
            category: "storage"
        )
        defer {
            PerformanceDiagnosticsSignposter.endInterval(persistenceInterval)
        }

        do {
            try persistence.applyMutationsOrThrow(batch.map(\.repositoryMutation))
            var cleanup = ClipboardAttachmentCleanup.empty
            var deletedItemCount = 0
            for mutation in batch {
                cleanup = cleanup.union(mutation.attachmentCleanup)
                releaseStagedAttachments(mutation.stagedAttachmentReservations)
                if case .upsert(let upsert) = mutation.repositoryMutation {
                    deletedItemCount += upsert.deletedIDs.count
                    for id in upsert.deletedIDs {
                        deletedItemRevision[id] = max(
                            deletedItemRevision[id] ?? 0,
                            mutation.revision
                        )
                    }
                }
            }
            if !cleanup.isEmpty {
                performAttachmentCleanup(cleanup)
            }
            compactDatabaseIfNeeded()
            let durationMS = (CFAbsoluteTimeGetCurrent() - startedAt) * 1_000
            let committedMutationCount = batch.count
            Task { @MainActor in
                PerformanceDiagnosticsService.shared.record(
                    "history.persistence.upsertBatch",
                    category: "storage",
                    durationMS: durationMS,
                    itemCount: committedMutationCount,
                    resultCount: committedMutationCount,
                    metadata: [
                        "revision": "\(finalRevision)",
                        "deletedCount": "\(deletedItemCount)"
                    ]
                )
            }
            return ClipboardHistoryWriteDrainResult(
                attemptedMutationCount: committedMutationCount,
                committedMutationCount: committedMutationCount,
                requiresFullResync: false
            )
        } catch {
            let cleanup = batch.reduce(into: ClipboardAttachmentCleanup.empty) { result, mutation in
                result = result.union(mutation.attachmentCleanup)
                discardStagedAttachments(mutation.stagedAttachmentReservations)
            }
            retainPersistenceFailure(operation: .upsert, revision: finalRevision, error: error)
            requireFullResync(afterFailureAt: finalRevision, attachmentCleanup: cleanup)
            NSLog(
                "ClipEase failed to apply clipboard history batch; count=%d errorType=%@",
                batch.count,
                String(describing: type(of: error))
            )
            recordPersistenceError(
                "history.persistence.upsertBatch.failed",
                error: error,
                revision: finalRevision
            )
            return ClipboardHistoryWriteDrainResult(
                attemptedMutationCount: batch.count,
                committedMutationCount: 0,
                requiresFullResync: true
            )
        }
    }

    private var isFullResyncRequired: Bool {
        if case .fullResyncRequired = recovery {
            return true
        }
        return false
    }

    private func saveIfCurrent(
        _ snapshot: ClipboardHistorySnapshot,
        revision: Int
    ) throws -> ClipboardAttachmentCleanup? {
        guard revision > latestRevision else {
            return nil
        }

        latestRevision = revision
        let persistedCleanup: ClipboardAttachmentCleanup
        if case .fullResyncRequired = recovery {
            persistedCleanup = ClipboardAttachmentCleanup(
                items: try persistence.loadSnapshotOrThrow().items
            )
        } else {
            persistedCleanup = .empty
        }
        try persistence.saveSnapshotOrThrow(snapshot)
        if unresolvedImportReceiptCount > 0 {
            fullSnapshotRevision = revision
            fullSnapshotItemIDs = Set(snapshot.items.map(\.id))
        }
        compactDatabaseIfNeeded()
        return persistedCleanup
    }

    private func shouldAttemptIncrementalWrite(
        revision: Int,
        attachmentCleanup: ClipboardAttachmentCleanup
    ) -> Bool {
        guard revision > latestRevision else {
            return false
        }

        guard case .incrementalAllowed = recovery else {
            latestRevision = revision
            pendingAttachmentCleanup = pendingAttachmentCleanup.union(attachmentCleanup)
            if !isRecoveryRequestPending {
                isRecoveryRequestPending = true
                recoveryRequest()
            }
            return false
        }

        return true
    }

    private func requireFullResync(
        afterFailureAt revision: Int,
        attachmentCleanup: ClipboardAttachmentCleanup
    ) {
        pendingAttachmentCleanup = pendingAttachmentCleanup.union(attachmentCleanup)
        isRecoveryRequestPending = false
        if case .incrementalAllowed = recovery {
            recovery = .fullResyncRequired(failedRevision: revision)
        }
    }

    private func completeFullSave(attachmentCleanup: ClipboardAttachmentCleanup) {
        let cleanup = pendingAttachmentCleanup.union(attachmentCleanup)
        pendingAttachmentCleanup = .empty
        recovery = .incrementalAllowed
        isRecoveryRequestPending = false
        retainedPersistenceFailure = nil
        performAttachmentCleanup(cleanup)
    }

    private func performAttachmentCleanup(_ cleanup: ClipboardAttachmentCleanup) {
        guard !cleanup.isEmpty else {
            return
        }
        do {
            try attachmentCleanup(cleanup)
            refreshAttachmentCleanupRetryState()
        } catch {
            retainAttachmentCleanupFailure(error)
        }
    }

    private func replayPersistedAttachmentCleanup() {
        guard usesPersistentAttachmentCleanupRetry else {
            return
        }
        do {
            _ = try persistence.replayPendingAttachmentCleanupOrThrow()
            refreshAttachmentCleanupRetryState()
        } catch {
            retainAttachmentCleanupFailure(error)
        }
    }

    private func refreshAttachmentCleanupRetryState() {
        guard usesPersistentAttachmentCleanupRetry else {
            retainedAttachmentCleanupFailure = nil
            return
        }
        do {
            let status = try persistence.attachmentCleanupRetryStatusOrThrow()
            if status.terminalEntryCount > 0 || status.rejectedCandidateCount > 0 {
                retainedAttachmentCleanupFailure =
                    "terminal=\(status.totalTerminalFailureCount),"
                    + "rejected=\(status.rejectedCandidateCount)"
            } else {
                retainedAttachmentCleanupFailure = nil
            }

            scheduledAttachmentCleanupRetryToken &+= 1
            let token = scheduledAttachmentCleanupRetryToken
            guard let delay = status.retryDelay else {
                return
            }
            queue.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self,
                      token == scheduledAttachmentCleanupRetryToken else {
                    return
                }
                replayPersistedAttachmentCleanup()
            }
        } catch {
            retainAttachmentCleanupFailure(error)
        }
    }

    private func retainAttachmentCleanupFailure(_ error: Error) {
        let nsError = error as NSError
        retainedAttachmentCleanupFailure =
            "\(String(describing: type(of: error))):\(nsError.code)"
        NSLog(
            "ClipEase attachment cleanup retry failed; errorType=%@ code=%d",
            String(describing: type(of: error)),
            nsError.code
        )
    }

    private func releaseStagedAttachments(_ reservations: [ClipboardAttachmentReservation]) {
        reservations.forEach { $0.release() }
    }

    private func discardStagedAttachments(_ reservations: [ClipboardAttachmentReservation]) {
        guard !reservations.isEmpty else {
            return
        }
        let candidates = reservations.reduce(into: ClipboardAttachmentCleanup.empty) { cleanup, reservation in
            cleanup = cleanup.union(reservation.candidates)
        }
        releaseStagedAttachments(reservations)
        performAttachmentCleanup(candidates)
    }

    private static func candidates(
        for reservations: [ClipboardAttachmentReservation]
    ) -> ClipboardAttachmentCleanup {
        reservations.reduce(into: ClipboardAttachmentCleanup.empty) { cleanup, reservation in
            cleanup = cleanup.union(reservation.candidates)
        }
    }

    private func retainPersistenceFailure(
        operation: ClipboardHistoryWriteOperation,
        revision: Int,
        error: Error
    ) {
        retainedPersistenceFailure = .persistenceFailed(
            operation: operation,
            revision: revision,
            description: error.localizedDescription
        )
    }

    private func upsertIfCurrent(
        _ item: ClipboardItem,
        deleting deletedIDs: Set<ClipboardItem.ID>,
        groups: [ClipboardGroup],
        revision: Int
    ) throws -> Bool {
        guard revision > latestRevision else {
            return false
        }

        latestRevision = revision
        let startedAt = CFAbsoluteTimeGetCurrent()
        try persistence.upsertItemOrThrow(item, deleting: deletedIDs, groups: groups)
        for id in deletedIDs {
            deletedItemRevision[id] = max(deletedItemRevision[id] ?? 0, revision)
        }
        compactDatabaseIfNeeded()
        let durationMS = (CFAbsoluteTimeGetCurrent() - startedAt) * 1_000
        Task { @MainActor in
            PerformanceDiagnosticsService.shared.record(
                "history.persistence.upsert",
                category: "storage",
                durationMS: durationMS,
                itemCount: deletedIDs.count,
                resultCount: 1,
                metadata: ["revision": "\(revision)", "type": item.type.rawValue]
            )
        }
        return true
    }

    private func insertItemsIfCurrent(_ items: [ClipboardItem], revision: Int) throws {
        guard revision > latestRevision,
              !items.isEmpty else {
            return
        }

        latestRevision = revision
        let startedAt = CFAbsoluteTimeGetCurrent()
        try persistence.insertItemsOrThrow(items)
        compactDatabaseIfNeeded()
        let durationMS = (CFAbsoluteTimeGetCurrent() - startedAt) * 1_000
        Task { @MainActor in
            PerformanceDiagnosticsService.shared.record(
                "history.persistence.insertDebugItems",
                category: "storage",
                durationMS: durationMS,
                itemCount: items.count,
                metadata: ["revision": "\(revision)"]
            )
        }
    }

    private func upsertGroupsIfCurrent(_ groups: [ClipboardGroup], revision: Int) throws {
        guard revision > latestRevision,
              !groups.isEmpty else {
            return
        }

        latestRevision = revision
        let startedAt = CFAbsoluteTimeGetCurrent()
        try persistence.upsertGroupsOrThrow(groups)
        compactDatabaseIfNeeded()
        let durationMS = (CFAbsoluteTimeGetCurrent() - startedAt) * 1_000
        Task { @MainActor in
            PerformanceDiagnosticsService.shared.record(
                "history.persistence.upsertGroups",
                category: "storage",
                durationMS: durationMS,
                itemCount: groups.count,
                metadata: ["revision": "\(revision)"]
            )
        }
    }

    private func deleteIfCurrent(
        itemIDs: Set<ClipboardItem.ID>,
        groupIDs: Set<ClipboardGroup.ID>,
        revision: Int
    ) throws -> ClipboardAttachmentCleanup? {
        guard revision > latestRevision else {
            return nil
        }

        latestRevision = revision
        let startedAt = CFAbsoluteTimeGetCurrent()
        let repositoryCleanup = try persistence.deleteItemsOrThrow(with: itemIDs, deletingGroups: groupIDs)
        for id in itemIDs {
            deletedItemRevision[id] = max(deletedItemRevision[id] ?? 0, revision)
        }
        compactDatabaseIfNeeded()
        let durationMS = (CFAbsoluteTimeGetCurrent() - startedAt) * 1_000
        Task { @MainActor in
            PerformanceDiagnosticsService.shared.record(
                "history.persistence.delete",
                category: "storage",
                durationMS: durationMS,
                itemCount: itemIDs.count,
                resultCount: groupIDs.count,
                metadata: ["revision": "\(revision)"]
            )
        }
        return repositoryCleanup
    }

    private func deleteAllIfCurrent(
        preserving groups: [ClipboardGroup],
        revision: Int
    ) throws -> ClipboardAttachmentCleanup? {
        guard revision > latestRevision else {
            return nil
        }

        latestRevision = revision
        let startedAt = CFAbsoluteTimeGetCurrent()
        let repositoryCleanup = try persistence.deleteAllItemsOrThrow(preserving: groups)
        deleteAllRevision = max(deleteAllRevision, revision)
        compactDatabaseIfNeeded(force: true)
        let durationMS = (CFAbsoluteTimeGetCurrent() - startedAt) * 1_000
        Task { @MainActor in
            PerformanceDiagnosticsService.shared.record(
                "history.persistence.deleteAll",
                category: "storage",
                durationMS: durationMS,
                metadata: ["revision": "\(revision)"]
            )
        }
        return repositoryCleanup
    }

    private func deleteExpiredIfCurrent(
        before cutoff: Date,
        revision: Int
    ) throws -> ClipboardAttachmentCleanup? {
        guard revision > latestRevision else {
            return nil
        }

        latestRevision = revision
        let startedAt = CFAbsoluteTimeGetCurrent()
        let cleanup: ClipboardAttachmentCleanup
        if unresolvedImportReceiptCount > 0 {
            let result = try persistence.deleteExpiredItemsWithResultOrThrow(before: cutoff)
            cleanup = result.cleanup
            for id in result.removedItemIDs {
                deletedItemRevision[id] = max(deletedItemRevision[id] ?? 0, revision)
            }
            retentionRestorationAuthorities.append(RetentionRestorationAuthority(
                revision: revision,
                cutoff: cutoff,
                protectedGroupIDs: result.protectedGroupIDs
            ))
        } else {
            cleanup = try persistence.deleteExpiredItemsOrThrow(before: cutoff)
        }
        compactDatabaseIfNeeded()
        let durationMS = (CFAbsoluteTimeGetCurrent() - startedAt) * 1_000
        Task { @MainActor in
            PerformanceDiagnosticsService.shared.record(
                "history.persistence.retention",
                category: "storage",
                durationMS: durationMS,
                metadata: ["revision": "\(revision)"]
            )
        }
        return cleanup
    }

    private func shouldRestoreDisplacedItem(
        _ item: ClipboardItem,
        from receipt: ClipboardImportCommitReceipt
    ) -> Bool {
        guard deleteAllRevision <= receipt.revision,
              (deletedItemRevision[item.id] ?? 0) <= receipt.revision else {
            return false
        }
        if fullSnapshotRevision > receipt.revision,
           !fullSnapshotItemIDs.contains(item.id) {
            return false
        }
        for authority in retentionRestorationAuthorities where authority.revision > receipt.revision {
            let isProtectedByGroup = item.groupID.map(authority.protectedGroupIDs.contains) == true
            if !item.isPinned,
               item.createdAt < authority.cutoff,
               !isProtectedByGroup {
                return false
            }
        }
        return true
    }

    private func importReceiptDidResolve() {
        unresolvedImportReceiptCount -= 1
        guard unresolvedImportReceiptCount == 0 else { return }
        fullSnapshotRevision = 0
        fullSnapshotItemIDs = []
        retentionRestorationAuthorities.removeAll(keepingCapacity: true)
    }

    private func compactDatabaseIfNeeded(force: Bool = false) {
        let now = Date()
        guard compactionScheduler.shouldRun(now: now, force: force) else {
            return
        }

        compactionScheduler.markRun(at: now)
        let startedAt = CFAbsoluteTimeGetCurrent()
        let result: ClipboardDatabaseCompactionResult
        do {
            result = try persistence.compactDatabaseIfNeededOrThrow()
        } catch {
            NSLog("ClipEase failed to compact clipboard history database: \(error.localizedDescription)")
            recordPersistenceError("history.persistence.compact.failed", error: error, revision: latestRevision)
            return
        }

        guard case .compacted = result else {
            return
        }

        let durationMS = (CFAbsoluteTimeGetCurrent() - startedAt) * 1_000
        Task { @MainActor in
            PerformanceDiagnosticsService.shared.record(
                "history.persistence.compact",
                category: "storage",
                durationMS: durationMS,
                resultCount: result.reclaimedBytes,
                metadata: ["reclaimedBytes": "\(result.reclaimedBytes)"]
            )
        }
    }

    private func recordPersistenceError(_ name: String, error: Error, revision: Int) {
        Task { @MainActor in
            PerformanceDiagnosticsService.shared.recordError(
                name,
                category: "storage",
                error: error,
                metadata: ["revision": "\(revision)"]
            )
        }
    }
}

private final class ClipboardHistoryAsyncRequestDriver<Value: Sendable>: @unchecked Sendable {
    typealias Continuation = CheckedContinuation<Value, Error>

    private let lock = NSLock()
    private var continuation: Continuation?
    private var terminalResult: Result<Value, Error>?
    private var commitHasBegun = false

    var isCompleted: Bool {
        lock.withLock { terminalResult != nil }
    }

    func install(_ continuation: Continuation) -> Bool {
        let result = lock.withLock { () -> Result<Value, Error>? in
            if let terminalResult {
                return terminalResult
            }
            self.continuation = continuation
            return nil
        }

        if let result {
            continuation.resume(with: result)
            return false
        }
        return true
    }

    func finish(_ result: Result<Value, Error>) {
        complete(with: result)
    }

    func beginCommit() -> Bool {
        lock.withLock {
            guard terminalResult == nil else {
                return false
            }
            commitHasBegun = true
            return true
        }
    }

    func cancel() {
        complete(with: .failure(CancellationError()))
    }

    func cancelBeforeCommit() {
        let result: Result<Value, Error> = .failure(CancellationError())
        let continuation = lock.withLock { () -> Continuation? in
            guard terminalResult == nil,
                  !commitHasBegun else {
                return nil
            }
            terminalResult = result
            let continuation = self.continuation
            self.continuation = nil
            return continuation
        }
        continuation?.resume(with: result)
    }

    private func complete(with result: Result<Value, Error>) {
        let continuation = lock.withLock { () -> Continuation? in
            guard terminalResult == nil else {
                return nil
            }
            terminalResult = result
            let continuation = self.continuation
            self.continuation = nil
            return continuation
        }
        continuation?.resume(with: result)
    }
}
