import Foundation

struct SQLiteClipboardStore: ClipboardHistoryRepository {
    static let currentSchemaVersion = 4
    private static let defaultItemOrderSQL = """
        clipboard_items.is_pinned DESC,
        clipboard_items.created_at DESC,
        COALESCE(clipboard_items.pinned_at, clipboard_items.created_at) DESC
        """

    let databaseURL: URL
    private let fileManager: FileManager

    init(databaseURL: URL, fileManager: FileManager = .default) {
        self.databaseURL = databaseURL
        self.fileManager = fileManager
    }

    init(fileManager: FileManager = .default) throws {
        self.init(
            databaseURL: try ClipEaseStoragePaths.sqliteStoreURL(fileManager: fileManager),
            fileManager: fileManager
        )
    }

    func initialize() throws {
        try createParentDirectory()
        try resetLegacyDatabaseIfNeeded()
        let database = try SQLiteDatabase(url: databaseURL)
        defer { database.close() }

        try database.execute("PRAGMA journal_mode = WAL")
        try database.execute("PRAGMA foreign_keys = ON")
        try database.execute("PRAGMA user_version = \(Self.currentSchemaVersion)")
        try createSchema(in: database)
        try recordSchemaVersion(in: database)
    }

    func replaceAllItems(with items: [ClipboardItem]) throws {
        try replaceAllItems(with: items, groups: [])
    }

    func replaceAllItems(with items: [ClipboardItem], groups: [ClipboardGroup]) throws {
        try createParentDirectory()
        try resetLegacyDatabaseIfNeeded()
        let database = try SQLiteDatabase(url: databaseURL)
        defer { database.close() }

        try database.execute("PRAGMA foreign_keys = ON")
        try database.execute("BEGIN IMMEDIATE TRANSACTION")

        do {
            try createSchema(in: database)
            try recordSchemaVersion(in: database)
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
        try createParentDirectory()
        try resetLegacyDatabaseIfNeeded()
        let database = try SQLiteDatabase(url: databaseURL)
        defer { database.close() }

        try database.execute("PRAGMA foreign_keys = ON")
        try createSchema(in: database)
        try recordSchemaVersion(in: database)

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

        try createParentDirectory()
        try resetLegacyDatabaseIfNeeded()
        let database = try SQLiteDatabase(url: databaseURL)
        defer { database.close() }

        try database.execute("PRAGMA foreign_keys = ON")
        try createSchema(in: database)
        try recordSchemaVersion(in: database)

        return try SQLiteItemDAO.loadItems(
            in: database,
            whereSQL: "clipboard_items.is_deleted = 0",
            values: [],
            orderSQL: Self.defaultItemOrderSQL,
            limit: limit,
            offset: max(0, offset)
        )
    }

    func loadSnapshot(itemLimit: Int, offset: Int) throws -> ClipboardHistorySnapshot {
        guard itemLimit > 0 else {
            try createParentDirectory()
            try resetLegacyDatabaseIfNeeded()
            let database = try SQLiteDatabase(url: databaseURL)
            defer { database.close() }
            try database.execute("PRAGMA foreign_keys = ON")
            try createSchema(in: database)
            try recordSchemaVersion(in: database)
            return ClipboardHistorySnapshot(items: [], groups: try SQLiteGroupDAO.loadGroups(in: database))
        }

        try createParentDirectory()
        try resetLegacyDatabaseIfNeeded()
        let database = try SQLiteDatabase(url: databaseURL)
        defer { database.close() }

        try database.execute("PRAGMA foreign_keys = ON")
        try createSchema(in: database)
        try recordSchemaVersion(in: database)

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
        try createParentDirectory()
        try resetLegacyDatabaseIfNeeded()
        let database = try SQLiteDatabase(url: databaseURL)
        defer { database.close() }

        try database.execute("PRAGMA foreign_keys = ON")
        try createSchema(in: database)
        try recordSchemaVersion(in: database)

        let sourcePredicate: String
        var values: [SQLiteValue] = [.text(contentHash)]
        if let sourceBundleID {
            sourcePredicate = "clipboard_items.source_bundle_id = ?"
            values.append(.text(sourceBundleID))
        } else {
            sourcePredicate = "clipboard_items.source_bundle_id IS NULL"
        }

        return try SQLiteItemDAO.loadItems(
            in: database,
            whereSQL: "clipboard_items.is_deleted = 0 AND clipboard_items.content_hash = ? AND \(sourcePredicate)",
            values: values,
            orderSQL: Self.defaultItemOrderSQL
        )
    }

    func searchItems(_ query: ClipboardSearchQuery) throws -> [ClipboardItem] {
        let rawQuery = query.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawQuery.isEmpty,
              query.limit > 0 else {
            return []
        }

        try createParentDirectory()
        try resetLegacyDatabaseIfNeeded()
        let database = try SQLiteDatabase(url: databaseURL)
        defer { database.close() }

        try database.execute("PRAGMA foreign_keys = ON")
        try createSchema(in: database)
        try recordSchemaVersion(in: database)

        let ids = try SQLiteSearchIndexDAO.searchItemIDs(query, in: database)
        return try SQLiteItemDAO.loadItems(withOrderedIDs: ids, orderSQL: Self.defaultItemOrderSQL, in: database)
    }

    func prepareSearchIndex() throws {
        try createParentDirectory()
        try resetLegacyDatabaseIfNeeded()
        let database = try SQLiteDatabase(url: databaseURL)
        defer { database.close() }

        try database.execute("PRAGMA foreign_keys = ON")
        try createSchema(in: database)
        try recordSchemaVersion(in: database)
        try SQLiteSearchIndexDAO.ensureReady(in: database)
    }

    func saveSnapshot(_ snapshot: ClipboardHistorySnapshot) throws {
        try replaceAllItems(with: snapshot.items, groups: snapshot.groups)
    }

    func insertItems(_ items: [ClipboardItem]) throws {
        guard !items.isEmpty else {
            return
        }

        try createParentDirectory()
        try resetLegacyDatabaseIfNeeded()
        let database = try SQLiteDatabase(url: databaseURL)
        defer { database.close() }

        try database.execute("PRAGMA foreign_keys = ON")
        try createSchema(in: database)
        try recordSchemaVersion(in: database)
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

    func upsertItem(_ item: ClipboardItem, deleting deletedIDs: Set<ClipboardItem.ID>, groups: [ClipboardGroup]) throws {
        try createParentDirectory()
        try resetLegacyDatabaseIfNeeded()
        let database = try SQLiteDatabase(url: databaseURL)
        defer { database.close() }

        try database.execute("PRAGMA foreign_keys = ON")
        try createSchema(in: database)
        try recordSchemaVersion(in: database)
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

    func deleteItems(with ids: Set<ClipboardItem.ID>, deletingGroups groupIDs: Set<ClipboardGroup.ID>) throws {
        guard !ids.isEmpty || !groupIDs.isEmpty else {
            return
        }

        try createParentDirectory()
        try resetLegacyDatabaseIfNeeded()
        let database = try SQLiteDatabase(url: databaseURL)
        defer { database.close() }

        try database.execute("PRAGMA foreign_keys = ON")
        try createSchema(in: database)
        try recordSchemaVersion(in: database)
        try database.execute("BEGIN IMMEDIATE TRANSACTION")

        do {
            try deleteItems(with: ids, in: database)
            try deleteItems(inGroups: groupIDs, in: database)
            try SQLiteGroupDAO.deleteGroups(with: groupIDs, in: database)
            try database.execute("COMMIT")
        } catch {
            try? database.execute("ROLLBACK")
            throw error
        }
    }

    func deleteAllItemsAndGroups() throws {
        try createParentDirectory()
        try removeExistingDatabaseFiles()
        try deleteHistoryStorageDirectories()
        try initialize()
    }

    func compactIfNeeded(policy: ClipboardDatabaseCompactionPolicy) throws -> ClipboardDatabaseCompactionResult {
        let database = try SQLiteDatabase(url: databaseURL)
        defer { database.close() }

        return try SQLiteDatabaseCompactor.compactIfNeeded(database: database, policy: policy)
    }

    func countItems() throws -> Int {
        try resetLegacyDatabaseIfNeeded()
        let database = try SQLiteDatabase(url: databaseURL)
        defer { database.close() }
        return try database.queryInt("SELECT COUNT(*) FROM clipboard_items")
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

    private func removeExistingDatabaseFiles() throws {
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

    private func resetLegacyDatabaseIfNeeded() throws {
        guard fileManager.fileExists(atPath: databaseURL.path) else {
            return
        }

        let database = try SQLiteDatabase(url: databaseURL)
        let userVersion = try database.queryInt("PRAGMA user_version")
        database.close()
        guard userVersion < Self.currentSchemaVersion else {
            return
        }

        let backupManager = SQLiteBackupManager(fileManager: fileManager)
        let backup = try backupManager.backupDatabaseFiles(for: databaseURL, reason: "schema-\(userVersion)-to-\(Self.currentSchemaVersion)")
        do {
            let migrator = SQLiteSchemaMigrator(currentSchemaVersion: Self.currentSchemaVersion)
            _ = try migrator.migrateIfNeeded(
                databaseURL: databaseURL,
                fileManager: fileManager,
                createSchema: createSchema(in:),
                recordSchemaVersion: recordSchemaVersion(in:)
            )
            Task { @MainActor in
                PerformanceDiagnosticsService.shared.record(
                    "history.sqlite.migration",
                    category: "storage",
                    durationMS: 0,
                    metadata: [
                        "fromVersion": "\(userVersion)",
                        "toVersion": "\(Self.currentSchemaVersion)",
                        "backup": backup?.directoryURL.path ?? ""
                    ]
                )
            }
        } catch {
            Task { @MainActor in
                PerformanceDiagnosticsService.shared.recordError(
                    "history.sqlite.migration.failed",
                    category: "storage",
                    error: error,
                    metadata: [
                        "fromVersion": "\(userVersion)",
                        "toVersion": "\(Self.currentSchemaVersion)",
                        "backup": backup?.directoryURL.path ?? ""
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

        try SQLiteSearchIndexDAO.delete(with: ids, in: database)
        try SQLiteItemDAO.deleteItems(with: ids, in: database)
    }

    private func deleteItems(inGroups ids: Set<ClipboardGroup.ID>, in database: SQLiteDatabase) throws {
        guard !ids.isEmpty else {
            return
        }

        let itemIDs = try SQLiteItemDAO.loadItemIDs(inGroups: ids, in: database)
        try SQLiteSearchIndexDAO.delete(with: itemIDs, in: database)
        try SQLiteItemDAO.deleteItems(inGroups: ids, in: database)
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
