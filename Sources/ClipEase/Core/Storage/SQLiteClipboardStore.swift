import Foundation
import SQLite3

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

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

        try database.execute("PRAGMA wal_checkpoint(TRUNCATE)")
        let pageSize = try database.queryInt("PRAGMA page_size")
        let pageCount = try database.queryInt("PRAGMA page_count")
        let freelistCount = try database.queryInt("PRAGMA freelist_count")

        guard policy.shouldCompact(
            pageSize: pageSize,
            pageCount: pageCount,
            freelistCount: freelistCount
        ) else {
            return .skipped
        }

        let beforeBytes = pageSize * pageCount
        try database.execute("VACUUM")
        try database.execute("PRAGMA wal_checkpoint(TRUNCATE)")
        let afterPageSize = try database.queryInt("PRAGMA page_size")
        let afterPageCount = try database.queryInt("PRAGMA page_count")
        let afterBytes = afterPageSize * afterPageCount
        return .compacted(beforeBytes: beforeBytes, afterBytes: afterBytes)
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
        try database.execute("""
            CREATE TABLE IF NOT EXISTS schema_versions (
                version INTEGER PRIMARY KEY,
                applied_at REAL NOT NULL
            )
            """)

        try database.execute("""
            CREATE TABLE IF NOT EXISTS clipboard_items (
                id TEXT PRIMARY KEY,
                type TEXT NOT NULL,
                plain_text TEXT NOT NULL DEFAULT '',
                url TEXT,
                link_title TEXT,
                link_subtitle TEXT,
                source_app_name TEXT NOT NULL DEFAULT '',
                source_bundle_id TEXT,
                source_icon_name TEXT NOT NULL DEFAULT '',
                source_icon_file_name TEXT,
                header_color TEXT NOT NULL DEFAULT '',
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL,
                last_used_at REAL,
                pinned_at REAL,
                is_pinned INTEGER NOT NULL DEFAULT 0,
                is_deleted INTEGER NOT NULL DEFAULT 0,
                last_edited_at REAL,
                group_sort_order INTEGER,
                content_hash TEXT
            )
            """)

        try database.execute("""
            CREATE TABLE IF NOT EXISTS item_assets (
                id TEXT PRIMARY KEY,
                item_id TEXT NOT NULL,
                asset_type TEXT NOT NULL,
                file_name TEXT NOT NULL,
                original_file_name TEXT,
                width INTEGER,
                height INTEGER,
                byte_size INTEGER,
                created_at REAL NOT NULL,
                FOREIGN KEY(item_id) REFERENCES clipboard_items(id) ON DELETE CASCADE
            )
            """)

        try database.execute("""
            CREATE TABLE IF NOT EXISTS clipboard_item_files (
                id TEXT PRIMARY KEY,
                item_id TEXT NOT NULL,
                display_order INTEGER NOT NULL DEFAULT 0,
                file_path TEXT NOT NULL,
                file_name TEXT NOT NULL,
                file_extension TEXT,
                uti_or_content_type TEXT,
                byte_size INTEGER,
                modified_at REAL,
                is_directory INTEGER NOT NULL DEFAULT 0,
                is_alias INTEGER NOT NULL DEFAULT 0,
                path_status TEXT NOT NULL DEFAULT 'unknown',
                last_checked_at REAL,
                created_at REAL NOT NULL,
                FOREIGN KEY(item_id) REFERENCES clipboard_items(id) ON DELETE CASCADE
            )
            """)

        try database.execute("""
            CREATE TABLE IF NOT EXISTS groups (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                color_hex TEXT NOT NULL,
                icon_name TEXT NOT NULL,
                sort_order INTEGER NOT NULL DEFAULT 0,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL
            )
            """)

        try database.execute("""
            CREATE TABLE IF NOT EXISTS group_items (
                id TEXT PRIMARY KEY,
                group_id TEXT NOT NULL,
                item_id TEXT NOT NULL,
                created_at REAL NOT NULL,
                sort_order INTEGER NOT NULL DEFAULT 0,
                UNIQUE(item_id),
                FOREIGN KEY(group_id) REFERENCES groups(id) ON DELETE CASCADE,
                FOREIGN KEY(item_id) REFERENCES clipboard_items(id) ON DELETE CASCADE
            )
            """)

        try database.execute("""
            CREATE TABLE IF NOT EXISTS item_ocr_results (
                item_id TEXT PRIMARY KEY,
                status TEXT NOT NULL,
                recognized_text TEXT NOT NULL DEFAULT '',
                emails TEXT NOT NULL DEFAULT '',
                phone_numbers TEXT NOT NULL DEFAULT '',
                urls TEXT NOT NULL DEFAULT '',
                text_regions TEXT NOT NULL DEFAULT '',
                updated_at REAL,
                FOREIGN KEY(item_id) REFERENCES clipboard_items(id) ON DELETE CASCADE
            )
            """)
        try addColumnIfNeeded("item_ocr_results", column: "text_regions", definition: "TEXT NOT NULL DEFAULT ''", in: database)

        try database.execute("""
            CREATE VIRTUAL TABLE IF NOT EXISTS clipboard_items_fts USING fts5(
                item_id UNINDEXED,
                search_text,
                tokenize='unicode61'
            )
            """)

        try database.execute("""
            CREATE TABLE IF NOT EXISTS clipboard_search_index_state (
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL,
                updated_at REAL NOT NULL
            )
            """)

        try database.execute(
            "CREATE INDEX IF NOT EXISTS idx_clipboard_items_created_at ON clipboard_items(created_at DESC)"
        )
        try database.execute(
            "CREATE INDEX IF NOT EXISTS idx_clipboard_items_type_created_at ON clipboard_items(type, created_at DESC)"
        )
        try database.execute(
            "CREATE INDEX IF NOT EXISTS idx_clipboard_items_source_app ON clipboard_items(source_app_name)"
        )
        try database.execute(
            "CREATE INDEX IF NOT EXISTS idx_clipboard_items_source_bundle ON clipboard_items(source_bundle_id)"
        )
        try database.execute(
            "CREATE INDEX IF NOT EXISTS idx_clipboard_items_pinned ON clipboard_items(is_pinned, pinned_at DESC)"
        )
        try database.execute(
            "CREATE INDEX IF NOT EXISTS idx_clipboard_items_deleted ON clipboard_items(is_deleted)"
        )
        try database.execute(
            "CREATE INDEX IF NOT EXISTS idx_clipboard_items_content_hash ON clipboard_items(content_hash)"
        )
        try database.execute(
            "CREATE INDEX IF NOT EXISTS idx_item_assets_item_id ON item_assets(item_id)"
        )
        try database.execute(
            "CREATE INDEX IF NOT EXISTS idx_item_assets_type ON item_assets(asset_type)"
        )
        try database.execute(
            "CREATE INDEX IF NOT EXISTS idx_clipboard_item_files_item_id ON clipboard_item_files(item_id, display_order)"
        )
        try database.execute(
            "CREATE INDEX IF NOT EXISTS idx_group_items_group_id ON group_items(group_id, sort_order)"
        )
        try database.execute(
            "CREATE INDEX IF NOT EXISTS idx_item_ocr_results_status ON item_ocr_results(status)"
        )
    }

    private func recordSchemaVersion(in database: SQLiteDatabase) throws {
        try database.execute("PRAGMA user_version = \(Self.currentSchemaVersion)")
        try database.execute(
            "INSERT OR IGNORE INTO schema_versions (version, applied_at) VALUES (?, ?)",
            values: [.int(Self.currentSchemaVersion), .double(Date().timeIntervalSince1970)]
        )
    }

    private func addColumnIfNeeded(
        _ table: String,
        column: String,
        definition: String,
        in database: SQLiteDatabase
    ) throws {
        let escapedTable = table.replacingOccurrences(of: "'", with: "''")
        let rows = try database.query("PRAGMA table_info('\(escapedTable)')")
        guard !rows.contains(where: { $0.requiredText("name") == column }) else {
            return
        }

        try database.execute("ALTER TABLE \(table) ADD COLUMN \(column) \(definition)")
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

enum SQLiteStoreError: Error, LocalizedError {
    case openFailed(String)
    case prepareFailed(String)
    case executeFailed(String)
    case bindFailed(String)
    case queryReturnedNoRows

    var errorDescription: String? {
        switch self {
        case .openFailed(let message):
            "SQLite open failed: \(message)"
        case .prepareFailed(let message):
            "SQLite prepare failed: \(message)"
        case .executeFailed(let message):
            "SQLite execute failed: \(message)"
        case .bindFailed(let message):
            "SQLite bind failed: \(message)"
        case .queryReturnedNoRows:
            "SQLite query returned no rows"
        }
    }
}

final class SQLiteDatabase {
    private var handle: OpaquePointer?

    init(url: URL) throws {
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        if sqlite3_open_v2(url.path, &handle, flags, nil) != SQLITE_OK {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            sqlite3_close(handle)
            throw SQLiteStoreError.openFailed(message)
        }
    }

    func close() {
        sqlite3_close(handle)
        handle = nil
    }

    func execute(_ sql: String, values: [SQLiteValue] = []) throws {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }

        try bind(values, to: statement)

        let result = sqlite3_step(statement)
        guard result == SQLITE_DONE || result == SQLITE_ROW else {
            throw SQLiteStoreError.executeFailed(lastErrorMessage)
        }
    }

    func queryInt(_ sql: String, values: [SQLiteValue] = []) throws -> Int {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }

        try bind(values, to: statement)

        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw SQLiteStoreError.queryReturnedNoRows
        }

        return Int(sqlite3_column_int64(statement, 0))
    }

    func query(_ sql: String, values: [SQLiteValue] = []) throws -> [SQLiteRow] {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }

        try bind(values, to: statement)

        var rows: [SQLiteRow] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE {
                break
            }

            guard result == SQLITE_ROW else {
                throw SQLiteStoreError.executeFailed(lastErrorMessage)
            }

            var values: [String: SQLiteCell] = [:]
            for index in 0..<sqlite3_column_count(statement) {
                guard let namePointer = sqlite3_column_name(statement, index) else {
                    continue
                }

                let name = String(cString: namePointer)
                switch sqlite3_column_type(statement, index) {
                case SQLITE_NULL:
                    values[name] = .null
                case SQLITE_INTEGER:
                    values[name] = .int(Int(sqlite3_column_int64(statement, index)))
                case SQLITE_FLOAT:
                    values[name] = .double(sqlite3_column_double(statement, index))
                default:
                    let text = sqlite3_column_text(statement, index)
                        .map { String(cString: $0) } ?? ""
                    values[name] = .text(text)
                }
            }

            rows.append(SQLiteRow(values: values))
        }

        return rows
    }

    private func prepare(_ sql: String) throws -> OpaquePointer? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteStoreError.prepareFailed(lastErrorMessage)
        }
        return statement
    }

    private func bind(_ values: [SQLiteValue], to statement: OpaquePointer?) throws {
        for (index, value) in values.enumerated() {
            let sqliteIndex = Int32(index + 1)
            let result: Int32

            switch value {
            case .null:
                result = sqlite3_bind_null(statement, sqliteIndex)
            case .text(let text):
                result = sqlite3_bind_text(statement, sqliteIndex, text, -1, sqliteTransient)
            case .int(let int):
                result = sqlite3_bind_int64(statement, sqliteIndex, sqlite3_int64(int))
            case .double(let double):
                result = sqlite3_bind_double(statement, sqliteIndex, double)
            case .bool(let bool):
                result = sqlite3_bind_int(statement, sqliteIndex, bool ? 1 : 0)
            }

            guard result == SQLITE_OK else {
                throw SQLiteStoreError.bindFailed(lastErrorMessage)
            }
        }
    }

    private var lastErrorMessage: String {
        handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
    }
}

enum SQLiteValue {
    case null
    case text(String)
    case int(Int)
    case double(Double)
    case bool(Bool)

    static func optionalText(_ text: String?) -> SQLiteValue {
        text.map(SQLiteValue.text) ?? .null
    }

    static func optionalInt(_ int: Int?) -> SQLiteValue {
        int.map(SQLiteValue.int) ?? .null
    }

    static func optionalDouble(_ double: Double?) -> SQLiteValue {
        double.map(SQLiteValue.double) ?? .null
    }
}

struct SQLiteRow {
    let values: [String: SQLiteCell]

    func requiredText(_ key: String) -> String {
        optionalText(key) ?? ""
    }

    func optionalText(_ key: String) -> String? {
        switch values[key] {
        case .text(let text):
            text
        case .int(let int):
            String(int)
        case .double(let double):
            String(double)
        case .null, .none:
            nil
        }
    }

    func requiredDouble(_ key: String) -> Double {
        optionalDouble(key) ?? 0
    }

    func optionalDouble(_ key: String) -> Double? {
        switch values[key] {
        case .double(let double):
            double
        case .int(let int):
            Double(int)
        case .text(let text):
            Double(text)
        case .null, .none:
            nil
        }
    }

    func optionalInt(_ key: String) -> Int? {
        switch values[key] {
        case .int(let int):
            int
        case .double(let double):
            Int(double)
        case .text(let text):
            Int(text)
        case .null, .none:
            nil
        }
    }

    func requiredInt(_ key: String) -> Int {
        optionalInt(key) ?? 0
    }

    func requiredBool(_ key: String) -> Bool {
        (optionalInt(key) ?? 0) != 0
    }
}

enum SQLiteCell {
    case null
    case text(String)
    case int(Int)
    case double(Double)
}
