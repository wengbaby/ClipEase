import Foundation

typealias SQLiteClipboardSearchPage = ClipboardSearchPage

struct SQLiteClipboardStore: ClipboardHistoryRepository {
    static let currentSchemaVersion = 5
    private static let mutationBatchSize = 400
    private static let retentionEligibilitySQL = """
        clipboard_items.is_deleted = 0
        AND clipboard_items.is_pinned = 0
        AND clipboard_items.created_at < ?
        AND NOT EXISTS (
            SELECT 1
            FROM group_items
            INNER JOIN groups ON groups.id = group_items.group_id
            WHERE group_items.item_id = clipboard_items.id
        )
        """
    private static let defaultItemOrderSQL = SQLiteHistoryPageQuery.orderSQL

    let databaseURL: URL
    private let fileManager: FileManager
    private let connectionCoordinator: SQLiteConnectionCoordinator
    private let migrationCreateSchema: ((SQLiteDatabase) throws -> Void)?
    private let migrationRecordSchemaVersion: ((SQLiteDatabase) throws -> Void)?

    var coordinatedWriterConnectionCount: Int {
        connectionCoordinator.createdWriterCount
    }

    init(
        databaseURL: URL,
        fileManager: FileManager = .default,
        migrationCreateSchema: ((SQLiteDatabase) throws -> Void)? = nil,
        migrationRecordSchemaVersion: ((SQLiteDatabase) throws -> Void)? = nil
    ) {
        self.databaseURL = databaseURL
        self.fileManager = fileManager
        self.migrationCreateSchema = migrationCreateSchema
        self.migrationRecordSchemaVersion = migrationRecordSchemaVersion
        connectionCoordinator = SQLiteConnectionCoordinator(
            databaseURL: databaseURL,
            maximumReaderCount: 2
        )
    }

    init(fileManager: FileManager = .default) throws {
        self.init(
            databaseURL: try ClipEaseStoragePaths.sqliteStoreURL(fileManager: fileManager),
            fileManager: fileManager
        )
    }

    func initialize() throws {
        let database = try openReadyDatabase()
        database.close()
    }

    func replaceAllItems(with items: [ClipboardItem]) throws {
        try replaceAllItems(with: items, groups: [])
    }

    func replaceAllItems(with items: [ClipboardItem], groups: [ClipboardGroup]) throws {
        let database = try openReadyDatabase()
        defer { database.close() }

        try database.execute("BEGIN IMMEDIATE TRANSACTION")

        do {
            try database.execute("DELETE FROM group_items")
            try database.execute("DELETE FROM groups")
            try database.execute("DELETE FROM item_ocr_results")
            try database.execute("DELETE FROM item_assets")
            try database.execute("DELETE FROM clipboard_item_files")
            try database.execute("DELETE FROM clipboard_items_fts")
            try database.execute("DELETE FROM clipboard_search_index_state")
            try database.execute("DELETE FROM clipboard_items")

            for item in items {
                try insertItem(item, in: database)
            }

            for group in groups {
                try SQLiteGroupDAO.insert(group, in: database)
            }

            for item in items where item.groupID != nil {
                try SQLiteGroupDAO.insertGroupItem(for: item, in: database)
            }

            try database.execute("COMMIT")
        } catch {
            try? database.execute("ROLLBACK")
            throw error
        }
    }

    func saveItems(_ items: [ClipboardItem]) throws {
        try replaceAllItems(with: items)
    }

    func loadSnapshot() throws -> ClipboardHistorySnapshot {
        let database = try openReadyDatabase()
        defer { database.close() }

        let groups = try SQLiteGroupDAO.loadGroups(in: database)
        let items = try SQLiteItemDAO.loadItems(
            in: database,
            whereSQL: "clipboard_items.is_deleted = 0",
            values: [],
            orderSQL: Self.defaultItemOrderSQL
        )

        return ClipboardHistorySnapshot(items: items, groups: groups)
    }

    func loadItems(limit: Int, offset: Int) throws -> [ClipboardItem] {
        guard limit > 0 else {
            return []
        }

        let database = try openReadyDatabase()
        defer { database.close() }

        return try SQLiteItemDAO.loadItems(
            in: database,
            whereSQL: "clipboard_items.is_deleted = 0",
            values: [],
            orderSQL: Self.defaultItemOrderSQL,
            limit: limit,
            offset: max(0, offset)
        )
    }

    func loadItemPage(
        limit: Int,
        after cursor: HistoryPagingService.ItemCursor?
    ) throws -> HistoryPagingService.ItemPage {
        try prepareConnectionCoordinatorIfNeeded()
        return try connectionCoordinator.withReader { database in
            try SQLiteHistoryPageQuery.loadPage(
                after: cursor,
                limit: limit,
                in: database
            )
        }
    }

    func loadSnapshot(itemLimit: Int, offset: Int) throws -> ClipboardHistorySnapshot {
        guard itemLimit > 0 else {
            let database = try openReadyDatabase()
            defer { database.close() }
            return ClipboardHistorySnapshot(items: [], groups: try SQLiteGroupDAO.loadGroups(in: database))
        }

        let database = try openReadyDatabase()
        defer { database.close() }

        let groups = try SQLiteGroupDAO.loadGroups(in: database)
        let items = try SQLiteItemDAO.loadItems(
            in: database,
            whereSQL: "clipboard_items.is_deleted = 0",
            values: [],
            orderSQL: Self.defaultItemOrderSQL,
            limit: itemLimit,
            offset: max(0, offset)
        )
        return ClipboardHistorySnapshot(items: items, groups: groups)
    }

    func loadItems(contentHash: String, sourceBundleID: String?) throws -> [ClipboardItem] {
        let database = try openReadyDatabase()
        defer { database.close() }

        let digest = SQLiteContentDigest.digest(for: contentHash)
        var digestWhereSQL = """
            clipboard_items.is_deleted = 0
            AND clipboard_items.digest_version = ?
            AND clipboard_items.content_digest = ?
            """
        var digestValues: [SQLiteValue] = [
            .int(SQLiteContentDigest.currentVersion),
            .blob(digest)
        ]
        var legacyWhereSQL = """
            clipboard_items.is_deleted = 0
            AND clipboard_items.content_hash = ?
            """
        var legacyValues: [SQLiteValue] = [.text(contentHash)]
        if let sourceBundleID {
            digestWhereSQL += " AND clipboard_items.source_bundle_id = ?"
            digestValues.append(.text(sourceBundleID))
            legacyWhereSQL += " AND clipboard_items.source_bundle_id = ?"
            legacyValues.append(.text(sourceBundleID))
        }

        let digestCandidates = try SQLiteItemDAO.loadItems(
            in: database,
            whereSQL: digestWhereSQL,
            values: digestValues,
            orderSQL: Self.defaultItemOrderSQL
        )
        let legacyCandidates = try SQLiteItemDAO.loadItems(
            in: database,
            whereSQL: legacyWhereSQL,
            values: legacyValues,
            orderSQL: Self.defaultItemOrderSQL
        )
        // A digest narrows the lookup, but the stable legacy value remains the
        // collision-verification authority during the dual-read release.
        var seenIDs = Set<ClipboardItem.ID>()
        return (digestCandidates + legacyCandidates)
            .filter { $0.contentHash == contentHash && seenIDs.insert($0.id).inserted }
            .sorted(by: Self.shouldSortItemBefore)
    }

    func backfillContentDigests(limit: Int) throws -> Int {
        let database = try openReadyDatabase()
        defer { database.close() }
        return try SQLiteItemDAO.backfillContentDigests(in: database, limit: limit)
    }

    private static func shouldSortItemBefore(_ lhs: ClipboardItem, _ rhs: ClipboardItem) -> Bool {
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

    func searchItems(_ query: ClipboardSearchQuery) throws -> [ClipboardItem] {
        guard query.limit > 0 else {
            return []
        }

        try prepareConnectionCoordinatorIfNeeded()
        return try connectionCoordinator.withReader { database in
            let ids = try SQLiteSearchIndexDAO.searchItemIDs(query, in: database)
            return try SQLiteItemDAO.loadItems(
                withOrderedIDs: ids,
                orderSQL: Self.defaultItemOrderSQL,
                in: database
            )
        }
    }

    func searchPage(
        _ query: ClipboardSearchQuery,
        after cursor: SQLiteSearchCursor?
    ) throws -> SQLiteClipboardSearchPage {
        try prepareConnectionCoordinatorIfNeeded()
        return try connectionCoordinator.withReader { database in
            let idPage = try SQLiteSearchIndexDAO.searchPage(
                query,
                after: cursor,
                in: database
            )
            let items = try SQLiteItemDAO.loadItems(
                withOrderedIDs: idPage.itemIDs,
                orderSQL: Self.defaultItemOrderSQL,
                in: database
            )
            return SQLiteClipboardSearchPage(
                items: items,
                nextCursor: idPage.nextCursor
            )
        }
    }

    func searchPage(
        _ query: ClipboardSearchQuery,
        after cursor: ClipboardSearchCursor?,
        cancellation: ClipboardSearchCancellationToken
    ) throws -> ClipboardSearchPage {
        try prepareConnectionCoordinatorIfNeeded()
        return try connectionCoordinator.withCancellableReader(
            cancellation: cancellation
        ) { database in
            try cancellation.throwIfCancelled()
            let idPage = try SQLiteSearchIndexDAO.searchPage(
                query,
                after: cursor,
                in: database
            )
            try cancellation.throwIfCancelled()
            let items = try SQLiteItemDAO.loadItems(
                withOrderedIDs: idPage.itemIDs,
                orderSQL: Self.defaultItemOrderSQL,
                in: database
            )
            return ClipboardSearchPage(
                items: items,
                nextCursor: idPage.nextCursor
            )
        }
    }

    func searchPageCancellable(
        _ query: ClipboardSearchQuery,
        after cursor: SQLiteSearchCursor?
    ) async throws -> SQLiteClipboardSearchPage {
        try prepareConnectionCoordinatorIfNeeded()
        return try await connectionCoordinator.withReaderAsync { database in
            let idPage = try await SQLiteSearchIndexDAO.searchPageCancellable(
                query,
                after: cursor,
                in: database
            )
            try Task.checkCancellation()
            let items = try SQLiteItemDAO.loadItems(
                withOrderedIDs: idPage.itemIDs,
                orderSQL: Self.defaultItemOrderSQL,
                in: database
            )
            return SQLiteClipboardSearchPage(
                items: items,
                nextCursor: idPage.nextCursor
            )
        }
    }

    func prepareSearchIndex() throws {
        let database = try openReadyDatabase()
        defer { database.close() }

        try SQLiteSearchIndexDAO.ensureReady(in: database)
    }

    func saveSnapshot(_ snapshot: ClipboardHistorySnapshot) throws {
        try replaceAllItems(with: snapshot.items, groups: snapshot.groups)
    }

    func insertItems(_ items: [ClipboardItem]) throws {
        guard !items.isEmpty else {
            return
        }

        let database = try openReadyDatabase()
        defer { database.close() }

        try database.execute("BEGIN IMMEDIATE TRANSACTION")

        do {
            for item in items {
                try insertItem(item, in: database)
                if item.groupID != nil {
                    try SQLiteGroupDAO.insertGroupItem(for: item, in: database)
                }
            }

            try database.execute("COMMIT")
            try database.execute("PRAGMA wal_checkpoint(PASSIVE)")
        } catch {
            try? database.execute("ROLLBACK")
            throw error
        }
    }

    func upsertGroups(_ groups: [ClipboardGroup]) throws {
        guard !groups.isEmpty else {
            return
        }

        try prepareConnectionCoordinatorIfNeeded()
        try connectionCoordinator.withWriter { database in
            try database.execute("BEGIN IMMEDIATE TRANSACTION")
            do {
                try SQLiteGroupDAO.upsert(groups, in: database)
                try database.execute("COMMIT")
            } catch {
                try? database.execute("ROLLBACK")
                throw error
            }
        }
    }

    func upsertItem(_ item: ClipboardItem, deleting deletedIDs: Set<ClipboardItem.ID>, groups: [ClipboardGroup]) throws {
        let database = try openReadyDatabase()
        defer { database.close() }

        try database.execute("BEGIN IMMEDIATE TRANSACTION")

        do {
            try deleteItems(with: deletedIDs.union([item.id]), in: database)
            try SQLiteGroupDAO.upsert(groups, in: database)
            try insertItem(item, in: database)
            if item.groupID != nil {
                try SQLiteGroupDAO.insertGroupItem(for: item, in: database)
            }
            try database.execute("COMMIT")
        } catch {
            try? database.execute("ROLLBACK")
            throw error
        }
    }

    func applyMutations(
        _ mutations: [ClipboardHistoryRepositoryMutation]
    ) throws {
        guard !mutations.isEmpty else {
            return
        }

        try prepareConnectionCoordinatorIfNeeded()
        try connectionCoordinator.withWriter { database in
            try database.execute("BEGIN IMMEDIATE TRANSACTION")
            do {
                for mutation in mutations {
                    switch mutation {
                    case .upsert(let upsert):
                        try deleteItems(
                            with: upsert.deletedIDs.union([upsert.item.id]),
                            in: database
                        )
                        try SQLiteGroupDAO.upsert(upsert.groups, in: database)
                        try insertItem(upsert.item, in: database)
                        if upsert.item.groupID != nil {
                            try SQLiteGroupDAO.insertGroupItem(
                                for: upsert.item,
                                in: database
                            )
                        }
                    case .update(let update):
                        try SQLiteItemDAO.updateItem(update, in: database)
                    }
                }
                try database.execute("COMMIT")
            } catch {
                try? database.execute("ROLLBACK")
                throw error
            }
        }
    }

    @discardableResult
    func compensateImportedItem(
        insertedItemID: ClipboardItem.ID,
        restoring displacedItems: [ClipboardItem]
    ) throws -> ClipboardAttachmentCleanup {
        let database = try openReadyDatabase()
        defer { database.close() }

        try database.execute("BEGIN IMMEDIATE TRANSACTION")
        do {
            let cleanup = try SQLiteItemDAO.attachmentCleanup(
                forItemIDs: [insertedItemID],
                database: database
            )
            try deleteItems(with: [insertedItemID], in: database)
            for item in displacedItems {
                let currentRowExists = try !database.query(
                    "SELECT id FROM clipboard_items WHERE id = ? LIMIT 1",
                    values: [.text(item.id.uuidString)]
                ).isEmpty
                guard !currentRowExists else { continue }
                try insertItem(item, in: database)
                if item.groupID != nil {
                    try SQLiteGroupDAO.insertGroupItem(for: item, in: database)
                }
            }
            try database.execute("COMMIT")
            return cleanup
        } catch {
            try? database.execute("ROLLBACK")
            throw error
        }
    }

    @discardableResult
    func deleteItems(
        with ids: Set<ClipboardItem.ID>,
        deletingGroups groupIDs: Set<ClipboardGroup.ID>
    ) throws -> ClipboardAttachmentCleanup {
        guard !ids.isEmpty || !groupIDs.isEmpty else {
            return .empty
        }

        let database = try openReadyDatabase()
        defer { database.close() }

        try database.execute("BEGIN IMMEDIATE TRANSACTION")

        do {
            let cleanup = try SQLiteItemDAO
                .attachmentCleanup(forItemIDs: ids, database: database)
                .union(SQLiteItemDAO.attachmentCleanup(forItemsInGroups: groupIDs, database: database))
            try deleteItems(with: ids, in: database)
            try deleteItems(inGroups: groupIDs, in: database)
            try deleteGroups(with: groupIDs, in: database)
            try database.execute("COMMIT")
            return cleanup
        } catch {
            try? database.execute("ROLLBACK")
            throw error
        }
    }

    @discardableResult
    func deleteAllItems(
        preserving groups: [ClipboardGroup]
    ) throws -> ClipboardAttachmentCleanup {
        let database = try openReadyDatabase()
        defer { database.close() }

        try database.execute("BEGIN IMMEDIATE TRANSACTION")

        do {
            let cleanup = try SQLiteItemDAO.allAttachmentCleanup(database: database)
            try database.execute("DELETE FROM group_items")
            try database.execute("DELETE FROM item_ocr_results")
            try database.execute("DELETE FROM item_assets")
            try database.execute("DELETE FROM clipboard_item_files")
            try database.execute("DELETE FROM clipboard_items_fts")
            try database.execute("DELETE FROM clipboard_search_index_state")
            try database.execute("DELETE FROM clipboard_items")
            try database.execute("DELETE FROM groups")
            try SQLiteGroupDAO.upsert(groups, in: database)
            try database.execute("COMMIT")
            return cleanup
        } catch {
            try? database.execute("ROLLBACK")
            throw error
        }
    }

    @discardableResult
    func deleteExpiredItems(before cutoff: Date) throws -> ClipboardAttachmentCleanup {
        try deleteExpiredItemsWithResult(before: cutoff).cleanup
    }

    func deleteExpiredItemsWithResult(
        before cutoff: Date
    ) throws -> ClipboardHistoryRetentionDeletionResult {
        let database = try openReadyDatabase()
        defer { database.close() }

        try database.execute("BEGIN IMMEDIATE TRANSACTION")
        do {
            let values: [SQLiteValue] = [.double(cutoff.timeIntervalSince1970)]
            let itemRows = try database.query(
                """
                SELECT clipboard_items.id
                FROM clipboard_items
                WHERE \(Self.retentionEligibilitySQL)
                """,
                values: values
            )
            let itemIDs = Set(itemRows.compactMap { UUID(uuidString: $0.requiredText("id")) })
            let protectedGroupIDs = Set(try SQLiteGroupDAO.loadGroups(in: database).map(\.id))
            let cleanup = try SQLiteItemDAO.attachmentCleanup(forItemIDs: itemIDs, database: database)
            for batch in idBatches(itemIDs) {
                try SQLiteSearchIndexDAO.delete(with: batch, in: database)
            }
            try database.execute(
                "DELETE FROM clipboard_items WHERE \(Self.retentionEligibilitySQL)",
                values: values
            )
            try database.execute("COMMIT")
            return ClipboardHistoryRetentionDeletionResult(
                cleanup: cleanup,
                removedItemIDs: itemIDs,
                protectedGroupIDs: protectedGroupIDs
            )
        } catch {
            try? database.execute("ROLLBACK")
            throw error
        }
    }

    func compactIfNeeded(policy: ClipboardDatabaseCompactionPolicy) throws -> ClipboardDatabaseCompactionResult {
        let database = try openReadyDatabase()
        defer { database.close() }

        return try SQLiteDatabaseCompactor.compactIfNeeded(database: database, policy: policy)
    }

    func countItems() throws -> Int {
        let database = try openReadyDatabase()
        defer { database.close() }
        return try database.queryInt("SELECT COUNT(*) FROM clipboard_items")
    }

    func referencedAttachments(
        in candidates: ClipboardAttachmentCleanup
    ) throws -> ClipboardAttachmentCleanup {
        guard !candidates.isEmpty else {
            return .empty
        }

        let database = try openReadyDatabase()
        defer { database.close() }
        return try SQLiteItemDAO.referencedAttachments(in: candidates, database: database)
    }

    func resetToEmptyStore() throws {
        try removeExistingDatabaseFiles()
        try initialize()
    }

    func discardStoreFiles() throws {
        try removeExistingDatabaseFiles()
    }

    private func createParentDirectory() throws {
        try fileManager.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }

    private func prepareConnectionCoordinatorIfNeeded() throws {
        try connectionCoordinator.prepareIfNeeded {
            let database = try openReadyDatabase()
            database.close()
        }
    }

    private func openReadyDatabase() throws -> SQLiteDatabase {
        try createParentDirectory()
        let databaseExisted = fileManager.fileExists(atPath: databaseURL.path)
        let database = try SQLiteDatabase(url: databaseURL)

        let userVersion: Int
        do {
            userVersion = try database.queryInt("PRAGMA user_version")
        } catch {
            database.close()
            throw error
        }

        guard userVersion <= Self.currentSchemaVersion else {
            database.close()
            throw SQLiteStoreError.incompatibleSchemaVersion(
                found: userVersion,
                supported: Self.currentSchemaVersion
            )
        }

        if databaseExisted, userVersion < Self.currentSchemaVersion {
            database.close()
            try migrateLegacyDatabase(from: userVersion)
            return try openCurrentDatabase()
        }

        do {
            try configureReadyDatabase(
                database,
                createsSchema: userVersion < Self.currentSchemaVersion
            )
            return database
        } catch {
            database.close()
            throw error
        }
    }

    private func openCurrentDatabase() throws -> SQLiteDatabase {
        let database = try SQLiteDatabase(url: databaseURL)
        do {
            let userVersion = try database.queryInt("PRAGMA user_version")
            guard userVersion == Self.currentSchemaVersion else {
                throw SQLiteStoreError.incompatibleSchemaVersion(
                    found: userVersion,
                    supported: Self.currentSchemaVersion
                )
            }
            try configureReadyDatabase(database, createsSchema: false)
            return database
        } catch {
            database.close()
            throw error
        }
    }

    private func configureReadyDatabase(
        _ database: SQLiteDatabase,
        createsSchema: Bool
    ) throws {
        try database.execute("PRAGMA foreign_keys = ON")
        try ensureWALMode(in: database)
        if createsSchema {
            try createSchema(in: database)
            try recordSchemaVersion(in: database)
        }
        try ensureMeasuredQueryIndexes(in: database)
    }

    private func ensureMeasuredQueryIndexes(in database: SQLiteDatabase) throws {
        try database.execute(
            """
            CREATE INDEX IF NOT EXISTS idx_clipboard_items_live_order
            ON clipboard_items(
                is_pinned DESC,
                created_at DESC,
                COALESCE(pinned_at, created_at) DESC,
                id DESC
            )
            WHERE is_deleted = 0
            """
        )
    }

    private func ensureWALMode(in database: SQLiteDatabase) throws {
        let currentMode = try database.query("PRAGMA journal_mode")
            .first?
            .requiredText("journal_mode")
            .lowercased()
        guard currentMode != "wal" else {
            return
        }

        try database.execute("PRAGMA journal_mode = WAL")
    }

    private func removeExistingDatabaseFiles() throws {
        connectionCoordinator.invalidate()
        for url in databaseSidecarURLs() where fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    private func databaseSidecarURLs() -> [URL] {
        SQLiteBackupManager.databaseFileURLs(for: databaseURL)
    }

    private func deleteHistoryStorageDirectories() throws {
        let liveStoreURL = try ClipEaseStoragePaths.sqliteStoreURL(fileManager: fileManager)
        guard databaseURL.standardizedFileURL == liveStoreURL.standardizedFileURL else {
            return
        }

        let directoryURLs = try [
            ClipEaseStoragePaths.imagesDirectory(fileManager: fileManager),
            ClipEaseStoragePaths.thumbnailsDirectory(fileManager: fileManager),
            ClipEaseStoragePaths.richTextsDirectory(fileManager: fileManager),
            ClipEaseStoragePaths.appIconsDirectory(fileManager: fileManager)
        ]

        for directoryURL in directoryURLs where fileManager.fileExists(atPath: directoryURL.path) {
            try fileManager.removeItem(at: directoryURL)
        }
    }

    private func migrateLegacyDatabase(from userVersion: Int) throws {
        let backupManager = SQLiteBackupManager(fileManager: fileManager)
        let backup = try backupManager.backupDatabaseFiles(for: databaseURL, reason: "schema-\(userVersion)-to-\(Self.currentSchemaVersion)")
        do {
            let migrator = SQLiteSchemaMigrator(currentSchemaVersion: Self.currentSchemaVersion)
            _ = try migrator.migrateIfNeeded(
                databaseURL: databaseURL,
                fileManager: fileManager,
                createSchema: migrationCreateSchema ?? createSchema(in:),
                recordSchemaVersion: migrationRecordSchemaVersion ?? recordSchemaVersion(in:)
            )
            Task { @MainActor in
                PerformanceDiagnosticsService.shared.record(
                    "history.sqlite.migration",
                    category: "storage",
                    durationMS: 0,
                    metadata: [
                        "fromVersion": "\(userVersion)",
                        "toVersion": "\(Self.currentSchemaVersion)",
                        "backupRestored": "false"
                    ]
                )
            }
        } catch {
            connectionCoordinator.invalidate()
            if let backup {
                try backupManager.restoreDatabaseFiles(from: backup, to: databaseURL)
            }
            Task { @MainActor in
                PerformanceDiagnosticsService.shared.recordError(
                    "history.sqlite.migration.failed",
                    category: "storage",
                    error: error,
                    metadata: [
                        "fromVersion": "\(userVersion)",
                        "toVersion": "\(Self.currentSchemaVersion)",
                        "backupRestored": "\(backup != nil)"
                    ]
                )
            }
            throw error
        }
    }

    private func createSchema(in database: SQLiteDatabase) throws {
        try SQLiteSchemaManager(currentSchemaVersion: Self.currentSchemaVersion).createSchema(in: database)
    }

    private func recordSchemaVersion(in database: SQLiteDatabase) throws {
        try SQLiteSchemaManager(currentSchemaVersion: Self.currentSchemaVersion).recordSchemaVersion(in: database)
    }

    private func deleteItems(with ids: Set<ClipboardItem.ID>, in database: SQLiteDatabase) throws {
        guard !ids.isEmpty else {
            return
        }

        for batch in idBatches(ids) {
            try SQLiteSearchIndexDAO.delete(with: batch, in: database)
        }
        try SQLiteItemDAO.deleteItems(with: ids, in: database)
    }

    private func deleteItems(inGroups ids: Set<ClipboardGroup.ID>, in database: SQLiteDatabase) throws {
        guard !ids.isEmpty else {
            return
        }

        let itemIDs = try SQLiteItemDAO.loadItemIDs(inGroups: ids, in: database)
        for batch in idBatches(itemIDs) {
            try SQLiteSearchIndexDAO.delete(with: batch, in: database)
        }
        try SQLiteItemDAO.deleteItems(inGroups: ids, in: database)
    }

    private func deleteGroups(with ids: Set<ClipboardGroup.ID>, in database: SQLiteDatabase) throws {
        guard !ids.isEmpty else {
            return
        }

        for batch in idBatches(ids) {
            try SQLiteGroupDAO.deleteGroups(with: batch, in: database)
        }
    }

    private func idBatches<ID: Hashable>(_ ids: Set<ID>) -> [Set<ID>] where ID: CustomStringConvertible {
        let sortedIDs = ids.sorted { $0.description < $1.description }
        var batches: [Set<ID>] = []
        var startIndex = 0
        while startIndex < sortedIDs.count {
            let endIndex = min(startIndex + Self.mutationBatchSize, sortedIDs.count)
            batches.append(Set(sortedIDs[startIndex..<endIndex]))
            startIndex = endIndex
        }
        return batches
    }

    private func insertItem(_ item: ClipboardItem, in database: SQLiteDatabase) throws {
        try SQLiteItemDAO.insert(item, in: database)
        try SQLiteSearchIndexDAO.insert(item, in: database)
    }
}

extension ClipboardItem {
    var contentHash: String? {
        switch type {
        case .text, .link, .color, .file:
            text
        case .image:
            imageHash
        }
    }
}
