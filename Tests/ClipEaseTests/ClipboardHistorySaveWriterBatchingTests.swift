import Foundation
import Testing
@testable import ClipEase

@Test func saveWriterEnterpriseBatchPolicyIsTwentyMillisecondsOrFiftyMutations() {
    #expect(ClipboardHistoryWriteBatchPolicy.enterpriseDefault.maximumDelayMilliseconds == 20)
    #expect(ClipboardHistoryWriteBatchPolicy.enterpriseDefault.maximumMutationCount == 50)
}

@Test func saveWriterAutomaticallyDrainsWhenTheBatchWindowExpires() {
    let repository = SaveWriterBatchRecordingRepository()
    let writer = ClipboardHistorySaveWriter(
        persistence: ClipboardHistoryPersistence(repository: repository),
        batchPolicy: ClipboardHistoryWriteBatchPolicy(
            maximumDelayMilliseconds: 5,
            maximumMutationCount: 50
        )
    )
    writer.upsertAsync(
        ClipboardItem.text("timer", sourceApp: .clipease),
        deleting: [],
        groups: [],
        revision: 1
    )

    #expect(repository.waitUntilAnyBatch(timeout: 1))
    #expect(repository.batches.count == 1)
}

@Test func saveWriterCoalescesOverwriteableItemMutationsWithinOneBatch() {
    let repository = SaveWriterBatchRecordingRepository()
    let writer = ClipboardHistorySaveWriter(
        persistence: ClipboardHistoryPersistence(repository: repository),
        batchPolicy: ClipboardHistoryWriteBatchPolicy(
            maximumDelayMilliseconds: 60_000,
            maximumMutationCount: 50
        )
    )
    var first = ClipboardItem.text("first", sourceApp: .clipease)
    var second = ClipboardItem.text("second", sourceApp: .clipease)
    second = ClipboardItem(
        id: first.id,
        type: second.type,
        text: second.text,
        url: second.url,
        linkTitle: second.linkTitle,
        linkSubtitle: second.linkSubtitle,
        imageFileName: second.imageFileName,
        imageWidth: second.imageWidth,
        imageHeight: second.imageHeight,
        imageHash: second.imageHash,
        richTextFileName: second.richTextFileName,
        fileReferences: second.fileReferences,
        createdAt: second.createdAt,
        sourceAppName: second.sourceAppName,
        sourceBundleID: second.sourceBundleID,
        iconName: second.iconName,
        iconFileName: second.iconFileName,
        headerColorHex: second.headerColorHex,
        isPinned: second.isPinned,
        pinnedAt: second.pinnedAt,
        groupID: second.groupID,
        groupedAt: second.groupedAt
    )
    first.isPinned = true
    first.pinnedAt = Date(timeIntervalSince1970: 10)
    second.isPinned = false
    second.pinnedAt = nil

    writer.updateItemAsync(
        ClipboardHistoryItemMutation(item: first, fields: [.pin]),
        revision: 1
    )
    writer.updateItemAsync(
        ClipboardHistoryItemMutation(item: second, fields: [.pin]),
        revision: 2
    )

    let result = writer.drain()

    #expect(result.attemptedMutationCount == 1)
    #expect(result.committedMutationCount == 1)
    #expect(!result.requiresFullResync)
    #expect(repository.batches.count == 1)
    #expect(repository.batches[0].count == 1)
    guard case .update(let mutation) = repository.batches[0][0] else {
        Issue.record("Expected a narrow update mutation")
        return
    }
    #expect(mutation.item.text == "second")
    #expect(mutation.fields == [.pin])
}

@Test func saveWriterFlushesAtFiftyMutationsAndPreservesRevisionOrder() {
    let repository = SaveWriterBatchRecordingRepository()
    let writer = ClipboardHistorySaveWriter(
        persistence: ClipboardHistoryPersistence(repository: repository),
        batchPolicy: ClipboardHistoryWriteBatchPolicy(
            maximumDelayMilliseconds: 60_000,
            maximumMutationCount: 50
        )
    )

    for revision in 1 ... 50 {
        writer.upsertAsync(
            ClipboardItem.text("item-\(revision)", sourceApp: .clipease),
            deleting: [],
            groups: [],
            revision: revision
        )
    }
    writer.flush()

    #expect(repository.batches.count == 1)
    #expect(repository.batches[0].count == 50)
    #expect(repository.batches[0].compactMap(\.itemID).count == 50)
}

@Test func saveWriterDoesNotBatchAcrossDeleteOrFullRevisionBarriers() {
    let repository = SaveWriterBatchRecordingRepository()
    let persistence = ClipboardHistoryPersistence(repository: repository)
    let writer = ClipboardHistorySaveWriter(
        persistence: persistence,
        batchPolicy: ClipboardHistoryWriteBatchPolicy(
            maximumDelayMilliseconds: 60_000,
            maximumMutationCount: 50
        )
    )
    let first = ClipboardItem.text("before-delete", sourceApp: .clipease)
    let second = ClipboardItem.text("after-delete", sourceApp: .clipease)
    let third = ClipboardItem.text("after-save", sourceApp: .clipease)

    writer.upsertAsync(first, deleting: [], groups: [], revision: 1)
    writer.deleteAsync(itemIDs: [first.id], groupIDs: [], revision: 2)
    writer.upsertAsync(second, deleting: [], groups: [], revision: 3)
    writer.saveAsync(
        ClipboardHistorySnapshot(items: [second], groups: []),
        revision: 4
    )
    writer.upsertAsync(third, deleting: [], groups: [], revision: 5)
    writer.flush()

    #expect(repository.events == [
        .batch(["before-delete"]),
        .delete,
        .batch(["after-delete"]),
        .save,
        .batch(["after-save"])
    ])
}

@Test func saveWriterDoesNotBatchAcrossImportReceiptBarrier() async throws {
    let repository = SaveWriterBatchRecordingRepository()
    let writer = ClipboardHistorySaveWriter(
        persistence: ClipboardHistoryPersistence(repository: repository),
        batchPolicy: ClipboardHistoryWriteBatchPolicy(
            maximumDelayMilliseconds: 60_000,
            maximumMutationCount: 50
        )
    )
    let before = ClipboardItem.text("before-import", sourceApp: .clipease)
    let imported = ClipboardItem.text("imported", sourceApp: .clipease)
    let after = ClipboardItem.text("after-import", sourceApp: .clipease)

    writer.upsertAsync(before, deleting: [], groups: [], revision: 1)
    let receipt = try await writer.commitImportedItemAwaitingDecision(
        imported,
        deleting: [],
        displacedItems: [],
        groups: [],
        acceptedCleanup: .empty,
        stagedAttachmentReservations: [],
        revision: 2
    )
    #expect(writer.acceptImportedItem(receipt))
    writer.upsertAsync(after, deleting: [], groups: [], revision: 3)
    writer.flush()

    #expect(repository.events == [
        .batch(["before-import"]),
        .upsert("imported"),
        .batch(["after-import"])
    ])
}

@Test func saveWriterFlushAsyncDrainsIncrementalWritesWithoutFullSnapshot() async {
    let repository = SaveWriterBatchRecordingRepository()
    let writer = ClipboardHistorySaveWriter(
        persistence: ClipboardHistoryPersistence(repository: repository),
        batchPolicy: ClipboardHistoryWriteBatchPolicy(
            maximumDelayMilliseconds: 60_000,
            maximumMutationCount: 50
        )
    )
    writer.upsertAsync(
        ClipboardItem.text("queued", sourceApp: .clipease),
        deleting: [],
        groups: [],
        revision: 1
    )

    let result = await writer.flushAsync()

    #expect(result.attemptedMutationCount == 1)
    #expect(result.committedMutationCount == 1)
    #expect(repository.saveSnapshotCount == 0)
}

@Test func saveWriterFlushAsyncCanBeRacedByAnExternalTimeout() async {
    let repository = SaveWriterBatchRecordingRepository()
    repository.blockNextBatch()
    let writer = ClipboardHistorySaveWriter(
        persistence: ClipboardHistoryPersistence(repository: repository),
        batchPolicy: ClipboardHistoryWriteBatchPolicy(
            maximumDelayMilliseconds: 60_000,
            maximumMutationCount: 50
        )
    )
    writer.upsertAsync(
        ClipboardItem.text("blocked", sourceApp: .clipease),
        deleting: [],
        groups: [],
        revision: 1
    )

    let flushTask = Task { await writer.flushAsync() }
    #expect(repository.waitUntilBatchStarted(timeout: 1))
    let timeoutTask = Task {
        try? await Task.sleep(for: .milliseconds(20))
        return true
    }
    #expect(await timeoutTask.value)

    repository.releaseBlockedBatch()
    let result = await flushTask.value
    #expect(result.committedMutationCount == 1)
    #expect(repository.saveSnapshotCount == 0)
}

@Test func saveWriterGroupUpsertIsAnOrderedBarrierBeforeGroupedItemInsertion() {
    let repository = SaveWriterBatchRecordingRepository()
    let writer = ClipboardHistorySaveWriter(
        persistence: ClipboardHistoryPersistence(repository: repository),
        batchPolicy: ClipboardHistoryWriteBatchPolicy(
            maximumDelayMilliseconds: 60_000,
            maximumMutationCount: 50
        )
    )
    let beforeBarrier = ClipboardItem.text("before-group", sourceApp: .clipease)
    let group = ClipboardGroup.makeDefault(name: "Imported", sortOrder: 0)
    var groupedItem = ClipboardItem.text("after-group", sourceApp: .clipease)
    groupedItem.groupID = group.id
    groupedItem.groupedAt = groupedItem.createdAt

    writer.updateItemAsync(
        ClipboardHistoryItemMutation(item: beforeBarrier, fields: [.metadata]),
        revision: 1
    )
    writer.upsertGroupsAsync([group], revision: 2)
    writer.insertItemsAsync([groupedItem], revision: 3)
    writer.flush()

    #expect(repository.events == [
        .batch(["before-group"]),
        .groups(["Imported"]),
        .insert(["after-group"]),
    ])
    #expect(repository.saveSnapshotCount == 0)
}

private final class SaveWriterBatchRecordingRepository: ClipboardHistoryRepository, @unchecked Sendable {
    enum Event: Equatable {
        case batch([String])
        case upsert(String)
        case groups([String])
        case insert([String])
        case delete
        case save
    }

    private let lock = NSLock()
    private let batchObserved = DispatchSemaphore(value: 0)
    private let batchStarted = DispatchSemaphore(value: 0)
    private let batchRelease = DispatchSemaphore(value: 0)
    private var shouldBlockBatch = false
    private var storedBatches: [[ClipboardHistoryRepositoryMutation]] = []
    private var storedEvents: [Event] = []
    private var storedSaveSnapshotCount = 0

    var batches: [[ClipboardHistoryRepositoryMutation]] {
        lock.withLock { storedBatches }
    }

    var events: [Event] {
        lock.withLock { storedEvents }
    }

    var saveSnapshotCount: Int {
        lock.withLock { storedSaveSnapshotCount }
    }

    func blockNextBatch() {
        lock.withLock {
            shouldBlockBatch = true
        }
    }

    func waitUntilBatchStarted(timeout: TimeInterval) -> Bool {
        batchStarted.wait(timeout: .now() + timeout) == .success
    }

    func waitUntilAnyBatch(timeout: TimeInterval) -> Bool {
        batchObserved.wait(timeout: .now() + timeout) == .success
    }

    func releaseBlockedBatch() {
        batchRelease.signal()
    }

    func loadSnapshot() throws -> ClipboardHistorySnapshot {
        ClipboardHistorySnapshot(items: [], groups: [])
    }

    func saveSnapshot(_ snapshot: ClipboardHistorySnapshot) throws {
        lock.withLock {
            storedSaveSnapshotCount += 1
            storedEvents.append(.save)
        }
    }

    func upsertItem(
        _ item: ClipboardItem,
        deleting deletedIDs: Set<ClipboardItem.ID>,
        groups: [ClipboardGroup]
    ) throws {
        lock.withLock {
            storedEvents.append(.upsert(item.text))
        }
    }

    func upsertGroups(_ groups: [ClipboardGroup]) throws {
        lock.withLock {
            storedEvents.append(.groups(groups.map(\.name)))
        }
    }

    func insertItems(_ items: [ClipboardItem]) throws {
        lock.withLock {
            storedEvents.append(.insert(items.map(\.text)))
        }
    }

    func applyMutations(_ mutations: [ClipboardHistoryRepositoryMutation]) throws {
        let block = lock.withLock { () -> Bool in
            storedBatches.append(mutations)
            storedEvents.append(.batch(mutations.map(\.item.text)))
            let result = shouldBlockBatch
            shouldBlockBatch = false
            return result
        }
        batchObserved.signal()
        if block {
            batchStarted.signal()
            batchRelease.wait()
        }
    }

    func deleteItems(
        with ids: Set<ClipboardItem.ID>,
        deletingGroups groupIDs: Set<ClipboardGroup.ID>
    ) throws -> ClipboardAttachmentCleanup {
        lock.withLock {
            storedEvents.append(.delete)
        }
        return .empty
    }
}
