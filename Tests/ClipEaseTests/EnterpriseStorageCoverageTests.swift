import Foundation
import Testing
@testable import ClipEase

@Test func enterpriseStorageCancellationTokenHonorsRegistrationLifecycle() throws {
    let token = ClipboardSearchCancellationToken()
    let invoked = EnterpriseStorageCounter()
    let removed = EnterpriseStorageCounter()

    let activeID = token.registerCancellationHandler {
        invoked.increment()
    }
    let removedID = token.registerCancellationHandler {
        removed.increment()
    }
    token.unregisterCancellationHandler(removedID)
    token.unregisterCancellationHandler(nil)

    #expect(activeID != nil)
    #expect(!token.isCancelled)
    token.cancel()
    token.cancel()
    #expect(token.isCancelled)
    #expect(invoked.value == 1)
    #expect(removed.value == 0)

    let lateID = token.registerCancellationHandler {
        invoked.increment()
    }
    #expect(lateID == nil)
    #expect(invoked.value == 2)
    #expect(throws: CancellationError.self) {
        try token.throwIfCancelled()
    }
}

@Test func enterpriseStorageRepositoryDefaultsProvideCompatibilityPagingAndSearch() throws {
    let group = ClipboardGroup.makeDefault(name: "Research", sortOrder: 0)
    let browser = enterpriseStorageSource(
        name: "Browser",
        bundleID: "com.example.browser"
    )
    var pinned = enterpriseStorageText(
        "Résumé needle",
        timestamp: 400,
        sourceApp: browser,
        isPinned: true,
        pinnedAt: 500
    )
    pinned.ocrText = "invoice@example.com"
    let grouped = enterpriseStorageText(
        "Needle grouped",
        timestamp: 300,
        sourceApp: browser,
        groupID: group.id
    )
    let other = enterpriseStorageText(
        "unrelated",
        timestamp: 200,
        sourceApp: .clipease
    )
    let repository = EnterpriseStorageDefaultRepository(
        snapshot: ClipboardHistorySnapshot(
            items: [other, grouped, pinned],
            groups: [group]
        )
    )

    #expect(try repository.backfillContentDigests(limit: 20) == 0)
    #expect(
        try repository.compactIfNeeded(
            policy: ClipboardDatabaseCompactionPolicy(
                minimumFreeRatio: 0,
                minimumFreeBytes: 1
            )
        ) == .skipped
    )
    try repository.prepareSearchIndex()
    #expect(try repository.loadItems().map(\.id) == [other.id, grouped.id, pinned.id])
    #expect(try repository.loadItems(limit: 0, offset: 0).isEmpty)
    #expect(try repository.loadItems(limit: -1, offset: -4).isEmpty)
    #expect(try repository.loadItems(limit: 2, offset: -4).map(\.id) == [other.id, grouped.id])
    #expect(try repository.loadItems(limit: 4, offset: 1).map(\.id) == [grouped.id, pinned.id])

    let snapshotPage = try repository.loadSnapshot(itemLimit: 1, offset: 1)
    #expect(snapshotPage.items.map(\.id) == [grouped.id])
    #expect(snapshotPage.groups == [group])
    #expect(try repository.loadItemPage(limit: 0, after: nil).items.isEmpty)

    let groupedContentHash = try #require(grouped.contentHash)
    #expect(
        try repository.loadItems(
            contentHash: groupedContentHash,
            sourceBundleID: nil
        ).map(\.id) == [grouped.id]
    )
    #expect(
        try repository.loadItems(
            contentHash: groupedContentHash,
            sourceBundleID: browser.bundleID
        ).map(\.id) == [grouped.id]
    )
    #expect(
        try repository.loadItems(
            contentHash: groupedContentHash,
            sourceBundleID: SourceAppInfo.clipease.bundleID
        ).isEmpty
    )

    #expect(
        try repository.searchItems(
            ClipboardSearchQuery(text: " \n ", limit: 10)
        ).isEmpty
    )
    #expect(
        try repository.searchItems(
            ClipboardSearchQuery(text: "needle", limit: 0)
        ).isEmpty
    )
    let offsetSearch = try repository.searchItems(
        ClipboardSearchQuery(text: "needle", limit: 1, offset: 1)
    )
    #expect(offsetSearch.map(\.id) == [pinned.id])

    let fullyFiltered = try repository.searchItems(
        ClipboardSearchQuery(
            text: "needle",
            limit: 10,
            filters: ClipboardSearchQueryFilters(
                types: [.text],
                sourceAppNames: [browser.name],
                requiredGroupIDs: [group.id]
            )
        )
    )
    #expect(fullyFiltered.map(\.id) == [grouped.id])

    let filterOnlyPage = try repository.searchPage(
        ClipboardSearchQuery(
            text: " ",
            limit: 10,
            filters: ClipboardSearchQueryFilters(
                groupCriteria: ClipboardSearchQueryGroupCriteria(
                    includesPinned: true,
                    groupIDs: [group.id]
                )
            )
        ),
        after: nil,
        cancellation: ClipboardSearchCancellationToken()
    )
    #expect(filterOnlyPage.items.map(\.id) == [pinned.id, grouped.id])
    #expect(filterOnlyPage.nextCursor?.rank == nil)

    let secondPage = try repository.searchPage(
        ClipboardSearchQuery(text: "needle", limit: 10),
        after: ClipboardSearchCursor(
            rank: 0,
            isPinned: pinned.isPinned,
            createdAt: pinned.createdAt,
            pinnedOrCreatedAt: pinned.pinnedAt ?? pinned.createdAt,
            id: pinned.id
        ),
        cancellation: ClipboardSearchCancellationToken()
    )
    #expect(secondPage.items.map(\.id) == [grouped.id])

    let cancelled = ClipboardSearchCancellationToken()
    cancelled.cancel()
    #expect(throws: CancellationError.self) {
        _ = try repository.searchPage(
            ClipboardSearchQuery(text: "needle", limit: 10),
            after: nil,
            cancellation: cancelled
        )
    }
}

@Test func enterpriseStorageRepositoryDefaultsUseStableCursorOrdering() throws {
    let repository = EnterpriseStorageDefaultRepository()
    let sameCreatedAt = Date(timeIntervalSince1970: 1_000)

    let pinned = enterpriseStorageText(
        "needle pinned",
        timestamp: 100,
        isPinned: true,
        pinnedAt: 200
    )
    let unpinned = enterpriseStorageText("needle unpinned", timestamp: 900)
    #expect(
        try enterpriseStoragePageIDs(repository, items: [unpinned, pinned])
            == [pinned.id, unpinned.id]
    )

    let older = enterpriseStorageText("needle older", timestamp: 100)
    let newer = enterpriseStorageText("needle newer", timestamp: 200)
    #expect(
        try enterpriseStoragePageIDs(repository, items: [older, newer])
            == [newer.id, older.id]
    )

    let earlierPin = enterpriseStorageText(
        "needle earlier pin",
        timestamp: sameCreatedAt.timeIntervalSince1970,
        isPinned: true,
        pinnedAt: 1_100
    )
    let laterPin = enterpriseStorageText(
        "needle later pin",
        timestamp: sameCreatedAt.timeIntervalSince1970,
        isPinned: true,
        pinnedAt: 1_200
    )
    #expect(
        try enterpriseStoragePageIDs(repository, items: [earlierPin, laterPin])
            == [laterPin.id, earlierPin.id]
    )

    let tieA = enterpriseStorageText("needle tie", timestamp: 500)
    let tieB = enterpriseStorageText("needle tie", timestamp: 500)
    let descendingTieIDs = [tieA.id, tieB.id].sorted {
        $0.uuidString > $1.uuidString
    }
    #expect(
        try enterpriseStoragePageIDs(repository, items: [tieA, tieB])
            == descendingTieIDs
    )

    repository.replace(items: [unpinned])
    #expect(
        try repository.loadItemPage(
            limit: 10,
            after: HistoryPagingService.ItemCursor(item: pinned)
        ).items.map(\.id) == [unpinned.id]
    )
    repository.replace(items: [older])
    #expect(
        try repository.loadItemPage(
            limit: 10,
            after: HistoryPagingService.ItemCursor(item: newer)
        ).items.map(\.id) == [older.id]
    )
    repository.replace(items: [earlierPin])
    #expect(
        try repository.loadItemPage(
            limit: 10,
            after: HistoryPagingService.ItemCursor(item: laterPin)
        ).items.map(\.id) == [earlierPin.id]
    )
    let tieCursor = tieA.id.uuidString > tieB.id.uuidString ? tieA : tieB
    let tieAfter = tieCursor.id == tieA.id ? tieB : tieA
    repository.replace(items: [tieAfter])
    #expect(
        try repository.loadItemPage(
            limit: 10,
            after: HistoryPagingService.ItemCursor(item: tieCursor)
        ).items.map(\.id) == [tieAfter.id]
    )

    try enterpriseStorageExerciseSearchCursorBranches(
        repository: repository,
        pinned: pinned,
        unpinned: unpinned,
        older: older,
        newer: newer,
        earlierPin: earlierPin,
        laterPin: laterPin,
        tieAfter: tieAfter,
        tieCursor: tieCursor
    )
}

@Test func enterpriseStorageRepositoryDefaultsApplyMutationsAndReturnAttachmentCleanup() throws {
    let group = ClipboardGroup.makeDefault(name: "Protected", sortOrder: 0)
    var image = ClipboardItem.image(
        fileName: "inserted.png",
        width: 16,
        height: 16,
        hash: "inserted-hash",
        sourceApp: .clipease
    )
    image.createdAt = Date(timeIntervalSince1970: 100)
    var rich = ClipboardItem.richText(
        plainText: "rich",
        fileName: "rich.rtf",
        sourceApp: .clipease
    )
    rich.createdAt = Date(timeIntervalSince1970: 90)
    rich.groupID = group.id
    let retained = enterpriseStorageText("retained", timestamp: 200)
    let repository = EnterpriseStorageDefaultRepository(
        snapshot: ClipboardHistorySnapshot(
            items: [image, rich, retained],
            groups: [group]
        )
    )

    try repository.insertItems([])
    let inserted = enterpriseStorageText("new insert", timestamp: 300)
    try repository.insertItems([inserted])
    #expect(repository.snapshot.items.first?.id == inserted.id)

    let replacement = enterpriseStorageText("replacement", timestamp: 400)
    try repository.upsertItem(
        replacement,
        deleting: [inserted.id],
        groups: [group]
    )
    #expect(repository.snapshot.items.first?.id == replacement.id)
    #expect(!repository.snapshot.items.contains { $0.id == inserted.id })

    var updated = retained
    updated.isPinned = true
    updated.pinnedAt = Date(timeIntervalSince1970: 500)
    let batchInsert = enterpriseStorageText("batch insert", timestamp: 450)
    try repository.applyMutations([
        .upsert(
            ClipboardHistoryUpsertMutation(
                item: batchInsert,
                deletedIDs: [replacement.id],
                groups: [group]
            )
        ),
        .update(
            ClipboardHistoryItemMutation(item: updated, fields: [.pin])
        ),
    ])
    #expect(repository.snapshot.items.first?.id == batchInsert.id)
    #expect(repository.snapshot.items.first { $0.id == retained.id }?.isPinned == true)

    #expect(throws: ClipboardHistoryWriteMutationError.self) {
        try repository.applyMutations([
            .update(
                ClipboardHistoryItemMutation(
                    item: enterpriseStorageText("missing", timestamp: 1),
                    fields: [.metadata]
                )
            ),
        ])
    }

    #expect(
        try repository.deleteItems(with: [], deletingGroups: []).isEmpty
    )
    let groupCleanup = try repository.deleteItems(
        with: [image.id],
        deletingGroups: [group.id]
    )
    #expect(groupCleanup.imageFileNames == ["inserted.png"])
    #expect(groupCleanup.richTextFileNames == ["rich.rtf"])
    #expect(!repository.snapshot.groups.contains { $0.id == group.id })

    let deleteAllCleanup = try repository.deleteAllItems(preserving: [group])
    #expect(deleteAllCleanup.isEmpty)
    #expect(repository.snapshot.items.isEmpty)
    #expect(repository.snapshot.groups == [group])

    let restored = enterpriseStorageText("restored", timestamp: 250)
    repository.replace(
        items: [image, retained],
        groups: [group]
    )
    let compensation = try repository.compensateImportedItem(
        insertedItemID: image.id,
        restoring: [retained, restored]
    )
    #expect(compensation.imageFileNames == ["inserted.png"])
    #expect(repository.snapshot.items.map(\.id).contains(restored.id))
    #expect(repository.snapshot.items.filter { $0.id == retained.id }.count == 1)

    #expect(
        try repository.referencedAttachments(in: .empty).isEmpty
    )
    repository.replace(items: [image, rich], groups: [group])
    let referenced = try repository.referencedAttachments(
        in: ClipboardAttachmentCleanup(
            imageFileNames: ["inserted.png", "orphan.png"],
            richTextFileNames: ["rich.rtf", "orphan.rtf"]
        )
    )
    #expect(referenced.imageFileNames == ["inserted.png"])
    #expect(referenced.richTextFileNames == ["rich.rtf"])

    let oldUngrouped = enterpriseStorageText("old", timestamp: 10)
    let newUngrouped = enterpriseStorageText("new", timestamp: 1_000)
    var oldPinned = enterpriseStorageText(
        "old pinned",
        timestamp: 20,
        isPinned: true,
        pinnedAt: 30
    )
    oldPinned.ocrText = "protected"
    let oldGrouped = enterpriseStorageText(
        "old grouped",
        timestamp: 30,
        groupID: group.id
    )
    repository.replace(
        items: [oldUngrouped, newUngrouped, oldPinned, oldGrouped],
        groups: [group]
    )
    #expect(
        try repository.deleteExpiredItems(
            before: Date(timeIntervalSince1970: 0)
        ).isEmpty
    )
    let retention = try repository.deleteExpiredItemsWithResult(
        before: Date(timeIntervalSince1970: 100)
    )
    #expect(retention.removedItemIDs == [oldUngrouped.id])
    #expect(retention.protectedGroupIDs == [group.id])
    #expect(!repository.snapshot.items.contains { $0.id == oldUngrouped.id })
    #expect(repository.snapshot.items.contains { $0.id == oldPinned.id })
    #expect(repository.snapshot.items.contains { $0.id == oldGrouped.id })
}

@Test func enterpriseStoragePersistenceDeletesOnlyUnreferencedFallbackAttachments() throws {
    let rootURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(
            "clipease-enterprise-storage-cleanup-\(UUID().uuidString)", isDirectory: true
        )
    try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: rootURL) }

    let fileManager = EnterpriseStorageFileManager(rootURL: rootURL)
    let referencedImage = ClipboardItem.image(
        fileName: "keep.png",
        width: 1,
        height: 1,
        hash: "keep",
        sourceApp: .clipease
    )
    let repository = EnterpriseStorageDefaultRepository(
        snapshot: ClipboardHistorySnapshot(
            items: [referencedImage],
            groups: []
        )
    )
    let persistence = ClipboardHistoryPersistence(
        fileManager: fileManager,
        repository: repository
    )
    try persistence.applyMutationsOrThrow([])
    #expect(!persistence.hasPersistentAttachmentCleanupRetryLedger)
    #expect(try persistence.attachmentCleanupRetryStatusOrThrow() == .empty)
    #expect(try persistence.replayPendingAttachmentCleanupOrThrow() == .empty)
    let emptyResult = persistence.deleteUnreferencedAttachments(.empty)
    #expect(emptyResult.removedFiles == 0)
    #expect(emptyResult.removedBytes == 0)

    let keepURL = try ClipEaseStoragePaths.imageFileURL(
        fileName: "keep.png",
        fileManager: fileManager
    )
    let orphanImageURL = try ClipEaseStoragePaths.imageFileURL(
        fileName: "orphan.png",
        fileManager: fileManager
    )
    let orphanThumbnailURL = try ClipEaseStoragePaths.thumbnailFileURL(
        fileName: "orphan.png",
        fileManager: fileManager
    )
    let orphanRichTextURL = try ClipEaseStoragePaths.richTextFileURL(
        fileName: "orphan.rtf",
        fileManager: fileManager
    )
    let orphanHTMLURL = orphanRichTextURL.deletingLastPathComponent()
        .appendingPathComponent(".orphan.rtf.raw.html")
    for url in [keepURL, orphanImageURL, orphanThumbnailURL, orphanRichTextURL, orphanHTMLURL] {
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([0x01, 0x02, 0x03]).write(to: url, options: .atomic)
    }

    let status = try persistence.scheduleAttachmentCleanupOrThrow(
        ClipboardAttachmentCleanup(
            imageFileNames: ["keep.png", "orphan.png"],
            richTextFileNames: ["orphan.rtf"]
        )
    )
    #expect(status == .empty)
    #expect(fileManager.fileExists(atPath: keepURL.path))
    #expect(!fileManager.fileExists(atPath: orphanImageURL.path))
    #expect(!fileManager.fileExists(atPath: orphanThumbnailURL.path))
    #expect(!fileManager.fileExists(atPath: orphanRichTextURL.path))
    #expect(!fileManager.fileExists(atPath: orphanHTMLURL.path))
}

@Test func enterpriseStorageSQLiteExercisesCompatibilitySearchAndMutationBatches() async throws {
    let fixture = try EnterpriseStorageSQLiteFixture.make()
    defer { fixture.remove() }

    let group = ClipboardGroup.makeDefault(name: "SQLite Group", sortOrder: 0)
    var pinned = enterpriseStorageText(
        "shared needle",
        timestamp: 100,
        isPinned: true,
        pinnedAt: 400
    )
    pinned.groupID = group.id
    var earlierPinned = enterpriseStorageText(
        "shared needle", timestamp: 100, isPinned: true, pinnedAt: 350
    )
    earlierPinned.groupID = group.id
    let newer = enterpriseStorageText("shared needle", timestamp: 300)
    let older = enterpriseStorageText("shared needle", timestamp: 200)
    let tie = enterpriseStorageText("shared needle", timestamp: 200)
    try fixture.store.saveSnapshot(
        ClipboardHistorySnapshot(
            items: [older, pinned, tie, newer, earlierPinned],
            groups: [group]
        )
    )

    let database = try SQLiteDatabase(url: fixture.databaseURL)
    try database.execute(
        "UPDATE clipboard_items SET content_digest = NULL, digest_version = NULL WHERE id = ?",
        values: [.text(older.id.uuidString)]
    )
    database.close()

    let pinnedContentHash = try #require(pinned.contentHash)
    let compatibilityItems = try fixture.store.loadItems(
        contentHash: pinnedContentHash,
        sourceBundleID: SourceAppInfo.clipease.bundleID
    )
    #expect(compatibilityItems.count == 5)
    #expect(compatibilityItems.first?.id == pinned.id)
    #expect(try fixture.store.backfillContentDigests(limit: 1) == 1)
    #expect(try fixture.store.backfillContentDigests(limit: 1) == 0)

    #expect(
        try fixture.store.searchItems(
            ClipboardSearchQuery(text: "needle", limit: 0)
        ).isEmpty
    )
    let query = ClipboardSearchQuery(text: "needle", limit: 2)
    let searchItems = try fixture.store.searchItems(query)
    #expect(searchItems.count == 2)
    let sqlitePage = try fixture.store.searchPage(
        query,
        after: Optional<SQLiteSearchCursor>.none
    )
    #expect(sqlitePage.items.count == 2)
    #expect(sqlitePage.nextCursor != nil)

    let repositoryPage = try fixture.store.searchPage(
        query,
        after: nil,
        cancellation: ClipboardSearchCancellationToken()
    )
    #expect(repositoryPage.items.count == 2)
    #expect(repositoryPage.nextCursor != nil)

    let asyncPage = try await fixture.store.searchPageCancellable(
        query,
        after: nil
    )
    #expect(asyncPage.items.count == 2)

    let cancelled = ClipboardSearchCancellationToken()
    cancelled.cancel()
    #expect(throws: CancellationError.self) {
        _ = try fixture.store.searchPage(
            query,
            after: nil,
            cancellation: cancelled
        )
    }

    try fixture.store.applyMutations([])
    var updatedOlder = older
    updatedOlder.isPinned = true
    updatedOlder.pinnedAt = Date(timeIntervalSince1970: 500)
    var groupedInsert = enterpriseStorageText("batch grouped", timestamp: 600)
    groupedInsert.groupID = group.id
    try fixture.store.applyMutations([
        .upsert(
            ClipboardHistoryUpsertMutation(
                item: groupedInsert,
                deletedIDs: [newer.id],
                groups: [group]
            )
        ),
        .update(
            ClipboardHistoryItemMutation(
                item: updatedOlder,
                fields: [.pin]
            )
        ),
    ])

    let snapshot = try fixture.store.loadSnapshot()
    #expect(snapshot.items.contains { $0.id == groupedInsert.id && $0.groupID == group.id })
    #expect(snapshot.items.contains { $0.id == updatedOlder.id && $0.isPinned })
    #expect(!snapshot.items.contains { $0.id == newer.id })
}

private func enterpriseStorageExerciseSearchCursorBranches(
    repository: EnterpriseStorageDefaultRepository,
    pinned: ClipboardItem,
    unpinned: ClipboardItem,
    older: ClipboardItem,
    newer: ClipboardItem,
    earlierPin: ClipboardItem,
    laterPin: ClipboardItem,
    tieAfter: ClipboardItem,
    tieCursor: ClipboardItem
) throws {
    let query = ClipboardSearchQuery(text: "needle", limit: 10)

    repository.replace(items: [unpinned])
    let rankAfter = try repository.searchPage(
        query,
        after: enterpriseStorageSearchCursor(item: pinned, rank: -1),
        cancellation: ClipboardSearchCancellationToken()
    )
    #expect(rankAfter.items.map(\.id) == [unpinned.id])

    let incompatibleRank = try repository.searchPage(
        query,
        after: enterpriseStorageSearchCursor(item: pinned, rank: nil),
        cancellation: ClipboardSearchCancellationToken()
    )
    #expect(incompatibleRank.items.isEmpty)

    repository.replace(items: [unpinned])
    #expect(
        try repository.searchPage(
            query,
            after: enterpriseStorageSearchCursor(item: pinned, rank: 0),
            cancellation: ClipboardSearchCancellationToken()
        ).items.map(\.id) == [unpinned.id]
    )
    repository.replace(items: [older])
    #expect(
        try repository.searchPage(
            query,
            after: enterpriseStorageSearchCursor(item: newer, rank: 0),
            cancellation: ClipboardSearchCancellationToken()
        ).items.map(\.id) == [older.id]
    )
    repository.replace(items: [earlierPin])
    #expect(
        try repository.searchPage(
            query,
            after: enterpriseStorageSearchCursor(item: laterPin, rank: 0),
            cancellation: ClipboardSearchCancellationToken()
        ).items.map(\.id) == [earlierPin.id]
    )
    repository.replace(items: [tieAfter])
    #expect(
        try repository.searchPage(
            query,
            after: enterpriseStorageSearchCursor(item: tieCursor, rank: 0),
            cancellation: ClipboardSearchCancellationToken()
        ).items.map(\.id) == [tieAfter.id]
    )
}

private func enterpriseStoragePageIDs(
    _ repository: EnterpriseStorageDefaultRepository,
    items: [ClipboardItem]
) throws -> [ClipboardItem.ID] {
    repository.replace(items: items)
    return try repository.loadItemPage(limit: items.count, after: nil).items.map(\.id)
}

private func enterpriseStorageSearchCursor(
    item: ClipboardItem,
    rank: Double?
) -> ClipboardSearchCursor {
    ClipboardSearchCursor(
        rank: rank,
        isPinned: item.isPinned,
        createdAt: item.createdAt,
        pinnedOrCreatedAt: item.pinnedAt ?? item.createdAt,
        id: item.id
    )
}

private func enterpriseStorageText(
    _ text: String,
    timestamp: TimeInterval,
    sourceApp: SourceAppInfo = .clipease,
    isPinned: Bool = false,
    pinnedAt: TimeInterval? = nil,
    groupID: ClipboardGroup.ID? = nil
) -> ClipboardItem {
    var item = ClipboardItem.debugText(
        text,
        createdAt: Date(timeIntervalSince1970: timestamp),
        sourceApp: sourceApp
    )
    item.isPinned = isPinned
    item.pinnedAt = pinnedAt.map(Date.init(timeIntervalSince1970:))
    item.groupID = groupID
    item.groupedAt = groupID.map { _ in Date(timeIntervalSince1970: timestamp) }
    return item
}

private func enterpriseStorageSource(name: String, bundleID: String) -> SourceAppInfo {
    SourceAppInfo(
        name: name,
        bundleID: bundleID,
        iconName: "app.fill",
        iconFileName: nil,
        headerColorHex: "#2E8CFF"
    )
}

private final class EnterpriseStorageDefaultRepository: ClipboardHistoryRepository {
    private(set) var snapshot: ClipboardHistorySnapshot
    private(set) var saveCount = 0

    init(snapshot: ClipboardHistorySnapshot = ClipboardHistorySnapshot(items: [], groups: [])) {
        self.snapshot = snapshot
    }

    func loadSnapshot() throws -> ClipboardHistorySnapshot {
        snapshot
    }

    func saveSnapshot(_ snapshot: ClipboardHistorySnapshot) throws {
        self.snapshot = snapshot
        saveCount += 1
    }

    func replace(
        items: [ClipboardItem],
        groups: [ClipboardGroup] = []
    ) {
        snapshot = ClipboardHistorySnapshot(items: items, groups: groups)
    }
}

private final class EnterpriseStorageCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue = 0

    var value: Int {
        lock.withLock { storedValue }
    }

    func increment() {
        lock.withLock {
            storedValue += 1
        }
    }
}

private final class EnterpriseStorageFileManager: FileManager, @unchecked Sendable {
    private let rootURL: URL

    init(rootURL: URL) {
        self.rootURL = rootURL
        super.init()
    }

    override func url(
        for directory: FileManager.SearchPathDirectory,
        in domain: FileManager.SearchPathDomainMask,
        appropriateFor url: URL?,
        create shouldCreate: Bool
    ) throws -> URL {
        if shouldCreate {
            try createDirectory(at: rootURL, withIntermediateDirectories: true)
        }
        return rootURL
    }
}

private struct EnterpriseStorageSQLiteFixture {
    let directory: URL
    let databaseURL: URL
    let store: SQLiteClipboardStore

    static func make() throws -> EnterpriseStorageSQLiteFixture {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "clipease-enterprise-storage-sqlite-\(UUID().uuidString)", isDirectory: true
            )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let databaseURL = directory.appendingPathComponent("ClipEase.sqlite")
        return EnterpriseStorageSQLiteFixture(
            directory: directory,
            databaseURL: databaseURL,
            store: SQLiteClipboardStore(databaseURL: databaseURL)
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}
