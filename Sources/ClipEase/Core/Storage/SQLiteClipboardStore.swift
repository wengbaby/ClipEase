import Foundation
import SQLite3

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

struct SQLiteClipboardStore: ClipboardHistoryRepository {
    static let currentSchemaVersion = 4

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
            try database.execute("DELETE FROM clipboard_items")

            for item in items {
                try insert(item, in: database)
            }

            for group in groups {
                try insert(group, in: database)
            }

            for item in items where item.groupID != nil {
                try insertGroupItem(for: item, in: database)
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

        let groups = try loadGroups(in: database)
        let groupedItems = try loadGroupedItems(in: database)
        let assetsByItemID = try loadAssetsByItemID(in: database)
        let fileReferencesByItemID = try loadFileReferencesByItemID(in: database)
        let ocrResultsByItemID = try loadOCRResultsByItemID(in: database)
        let rows = try database.query(
            """
            SELECT
                id, type, plain_text, url, link_title, link_subtitle,
                source_app_name, source_bundle_id, source_icon_name, source_icon_file_name,
                header_color, created_at, pinned_at, is_pinned, content_hash
            FROM clipboard_items
            WHERE is_deleted = 0
            ORDER BY is_pinned DESC, created_at DESC, COALESCE(pinned_at, created_at) DESC
            """
        )

        var items: [ClipboardItem] = []
        items.reserveCapacity(rows.count)

        for row in rows {
            guard let id = UUID(uuidString: row.requiredText("id")) else {
                continue
            }

            let assets = assetsByItemID[id] ?? []
            let fileReferences = fileReferencesByItemID[id] ?? []
            let imageAsset = assets.first { $0.type == "image" }
            let richTextAsset = assets.first { $0.type == "rich_text" }

            let groupInfo = groupedItems[id]
            let ocrResult = ocrResultsByItemID[id]
            items.append(
                ClipboardItem(
                    id: id,
                    type: ClipboardItemType(rawValue: row.requiredText("type")) ?? .text,
                    text: row.requiredText("plain_text"),
                    url: row.optionalText("url").flatMap(URL.init(string:)),
                    linkTitle: row.optionalText("link_title"),
                    linkSubtitle: row.optionalText("link_subtitle"),
                    imageFileName: imageAsset?.fileName,
                    imageWidth: imageAsset?.width,
                    imageHeight: imageAsset?.height,
                    imageHash: row.optionalText("content_hash"),
                    richTextFileName: richTextAsset?.fileName,
                    fileReferences: fileReferences,
                    createdAt: Date(timeIntervalSince1970: row.requiredDouble("created_at")),
                    sourceAppName: row.requiredText("source_app_name"),
                    sourceBundleID: row.optionalText("source_bundle_id"),
                    iconName: row.requiredText("source_icon_name"),
                    iconFileName: row.optionalText("source_icon_file_name"),
                    headerColorHex: row.requiredText("header_color"),
                    isPinned: row.requiredBool("is_pinned"),
                    pinnedAt: row.optionalDouble("pinned_at").map(Date.init(timeIntervalSince1970:)),
                    groupID: groupInfo?.groupID,
                    groupedAt: groupInfo?.createdAt,
                    ocrStatus: ocrResult?.status ?? .none,
                    ocrText: ocrResult?.text ?? "",
                    ocrEmails: ocrResult?.emails ?? [],
                    ocrPhoneNumbers: ocrResult?.phoneNumbers ?? [],
                    ocrURLs: ocrResult?.urls ?? [],
                    ocrTextRegions: ocrResult?.textRegions ?? [],
                    ocrUpdatedAt: ocrResult?.updatedAt
                )
            )
        }

        return ClipboardHistorySnapshot(items: items, groups: groups)
    }

    func saveSnapshot(_ snapshot: ClipboardHistorySnapshot) throws {
        try replaceAllItems(with: snapshot.items, groups: snapshot.groups)
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
        [
            databaseURL,
            URL(fileURLWithPath: databaseURL.path + "-wal"),
            URL(fileURLWithPath: databaseURL.path + "-shm")
        ]
    }

    private func resetLegacyDatabaseIfNeeded() throws {
        guard fileManager.fileExists(atPath: databaseURL.path) else {
            return
        }

        let database = try SQLiteDatabase(url: databaseURL)
        let userVersion = try database.queryInt("PRAGMA user_version")
        let needsReset = userVersion < Self.currentSchemaVersion
        database.close()
        guard needsReset else {
            return
        }

        try removeExistingDatabaseFiles()
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

    private func loadOCRResultsByItemID(in database: SQLiteDatabase) throws -> [UUID: SQLiteOCRResultRow] {
        let rows = try database.query(
            """
            SELECT
                item_ocr_results.item_id, status, recognized_text, emails, phone_numbers,
                urls, text_regions, item_ocr_results.updated_at
            FROM item_ocr_results
            INNER JOIN clipboard_items ON clipboard_items.id = item_ocr_results.item_id
            WHERE clipboard_items.is_deleted = 0
            """
        )

        var results: [UUID: SQLiteOCRResultRow] = [:]
        results.reserveCapacity(rows.count)
        for row in rows {
            guard let itemID = UUID(uuidString: row.requiredText("item_id")) else {
                continue
            }

            results[itemID] = SQLiteOCRResultRow(
                status: ClipboardOCRStatus(rawValue: row.requiredText("status")) ?? .none,
                text: row.requiredText("recognized_text"),
                emails: Self.decodeList(row.requiredText("emails")),
                phoneNumbers: Self.decodeList(row.requiredText("phone_numbers")),
                urls: Self.decodeList(row.requiredText("urls")),
                textRegions: Self.decodeRegions(row.optionalText("text_regions") ?? ""),
                updatedAt: row.optionalDouble("updated_at").map(Date.init(timeIntervalSince1970:))
            )
        }

        return results
    }

    private func loadAssetsByItemID(in database: SQLiteDatabase) throws -> [UUID: [SQLiteAssetRow]] {
        let rows = try database.query(
            """
            SELECT item_id, asset_type, file_name, width, height
            FROM item_assets
            INNER JOIN clipboard_items ON clipboard_items.id = item_assets.item_id
            WHERE clipboard_items.is_deleted = 0
            ORDER BY item_assets.created_at ASC
            """
        )

        var assetsByItemID: [UUID: [SQLiteAssetRow]] = [:]
        for row in rows {
            guard let itemID = UUID(uuidString: row.requiredText("item_id")) else {
                continue
            }

            assetsByItemID[itemID, default: []].append(
                SQLiteAssetRow(
                    type: row.requiredText("asset_type"),
                    fileName: row.requiredText("file_name"),
                    width: row.optionalInt("width"),
                    height: row.optionalInt("height")
                )
            )
        }

        return assetsByItemID
    }

    private func loadFileReferencesByItemID(in database: SQLiteDatabase) throws -> [UUID: [ClipboardFileReference]] {
        let rows = try database.query(
            """
            SELECT
                clipboard_item_files.id, clipboard_item_files.item_id, display_order,
                file_path, file_name, file_extension, uti_or_content_type, byte_size,
                modified_at, is_directory, is_alias, path_status, last_checked_at,
                clipboard_item_files.created_at
            FROM clipboard_item_files
            INNER JOIN clipboard_items ON clipboard_items.id = clipboard_item_files.item_id
            WHERE clipboard_items.is_deleted = 0
            ORDER BY clipboard_item_files.item_id ASC, display_order ASC, clipboard_item_files.created_at ASC
            """
        )

        var referencesByItemID: [UUID: [ClipboardFileReference]] = [:]
        for row in rows {
            guard let id = UUID(uuidString: row.requiredText("id")),
                  let itemID = UUID(uuidString: row.requiredText("item_id")) else {
                continue
            }

            referencesByItemID[itemID, default: []].append(
                ClipboardFileReference(
                    id: id,
                    itemID: itemID,
                    orderIndex: row.requiredInt("display_order"),
                    path: row.requiredText("file_path"),
                    displayName: row.requiredText("file_name"),
                    fileExtension: row.optionalText("file_extension"),
                    contentType: row.optionalText("uti_or_content_type"),
                    fileSize: row.optionalInt("byte_size"),
                    modifiedAt: row.optionalDouble("modified_at").map(Date.init(timeIntervalSince1970:)),
                    isDirectory: row.requiredBool("is_directory"),
                    isAlias: row.requiredBool("is_alias"),
                    pathStatus: ClipboardFilePathStatus(rawValue: row.requiredText("path_status")) ?? .unknown,
                    lastCheckedAt: row.optionalDouble("last_checked_at").map(Date.init(timeIntervalSince1970:)),
                    createdAt: Date(timeIntervalSince1970: row.requiredDouble("created_at"))
                )
            )
        }

        return referencesByItemID
    }

    private func loadGroups(in database: SQLiteDatabase) throws -> [ClipboardGroup] {
        let rows = try database.query(
            """
            SELECT id, name, color_hex, icon_name, sort_order, created_at, updated_at
            FROM groups
            ORDER BY sort_order ASC, created_at ASC
            """
        )

        return rows.compactMap { row in
            guard let id = UUID(uuidString: row.requiredText("id")) else {
                return nil
            }

            return ClipboardGroup(
                id: id,
                name: row.requiredText("name"),
                colorHex: row.requiredText("color_hex"),
                iconName: row.requiredText("icon_name"),
                sortOrder: row.requiredInt("sort_order"),
                createdAt: Date(timeIntervalSince1970: row.requiredDouble("created_at")),
                updatedAt: Date(timeIntervalSince1970: row.requiredDouble("updated_at"))
            )
        }
    }

    private func loadGroupedItems(in database: SQLiteDatabase) throws -> [UUID: SQLiteGroupItemRow] {
        let rows = try database.query(
            """
            SELECT group_id, item_id, created_at, sort_order
            FROM group_items
            ORDER BY created_at DESC
            """
        )

        var groupedItems: [UUID: SQLiteGroupItemRow] = [:]
        for row in rows {
            guard let itemID = UUID(uuidString: row.requiredText("item_id")),
                  let groupID = UUID(uuidString: row.requiredText("group_id")) else {
                continue
            }

            groupedItems[itemID] = SQLiteGroupItemRow(
                groupID: groupID,
                createdAt: Date(timeIntervalSince1970: row.requiredDouble("created_at")),
                sortOrder: row.requiredInt("sort_order")
            )
        }

        return groupedItems
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

    private func insert(_ item: ClipboardItem, in database: SQLiteDatabase) throws {
        try database.execute(
            """
            INSERT INTO clipboard_items (
                id, type, plain_text, url, link_title, link_subtitle,
                source_app_name, source_bundle_id, source_icon_name, source_icon_file_name,
                header_color, created_at, updated_at, last_used_at, pinned_at, is_pinned,
                is_deleted, last_edited_at, group_sort_order, content_hash
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, NULL, NULL, ?)
            """,
            values: [
                .text(item.id.uuidString),
                .text(item.type.rawValue),
                .text(item.text),
                .optionalText(item.url?.absoluteString),
                .optionalText(item.linkTitle),
                .optionalText(item.linkSubtitle),
                .text(item.sourceAppName),
                .optionalText(item.sourceBundleID),
                .text(item.iconName),
                .optionalText(item.iconFileName),
                .text(item.headerColorHex),
                .double(item.createdAt.timeIntervalSince1970),
                .double(item.createdAt.timeIntervalSince1970),
                .null,
                .optionalDouble(item.pinnedAt?.timeIntervalSince1970),
                .bool(item.isPinned),
                .optionalText(item.contentHash)
            ]
        )

        if let imageFileName = item.imageFileName {
            try insertAsset(
                itemID: item.id,
                type: "image",
                fileName: imageFileName,
                width: item.imageWidth,
                height: item.imageHeight,
                createdAt: item.createdAt,
                in: database
            )
        }

        if let richTextFileName = item.richTextFileName {
            try insertAsset(
                itemID: item.id,
                type: "rich_text",
                fileName: richTextFileName,
                width: nil,
                height: nil,
                createdAt: item.createdAt,
                in: database
            )
        }

        for fileReference in item.fileReferences {
            try insertFileReference(fileReference, itemID: item.id, in: database)
        }

        if item.ocrStatus != .none || !item.ocrText.isEmpty {
            try insertOCRResult(item, in: database)
        }
    }

    private func insertOCRResult(_ item: ClipboardItem, in database: SQLiteDatabase) throws {
        try database.execute(
            """
            INSERT INTO item_ocr_results (
                item_id, status, recognized_text, emails, phone_numbers, urls, text_regions, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """,
            values: [
                .text(item.id.uuidString),
                .text(item.ocrStatus.rawValue),
                .text(item.ocrText),
                .text(Self.encodeList(item.ocrEmails)),
                .text(Self.encodeList(item.ocrPhoneNumbers)),
                .text(Self.encodeList(item.ocrURLs)),
                .text(Self.encodeRegions(item.ocrTextRegions)),
                .optionalDouble(item.ocrUpdatedAt?.timeIntervalSince1970)
            ]
        )
    }

    private func insertFileReference(
        _ fileReference: ClipboardFileReference,
        itemID: UUID,
        in database: SQLiteDatabase
    ) throws {
        try database.execute(
            """
            INSERT INTO clipboard_item_files (
                id, item_id, display_order, file_path, file_name, file_extension,
                uti_or_content_type, byte_size, modified_at, is_directory, is_alias,
                path_status, last_checked_at, created_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            values: [
                .text(fileReference.id.uuidString),
                .text(itemID.uuidString),
                .int(fileReference.orderIndex),
                .text(fileReference.path),
                .text(fileReference.displayName),
                .optionalText(fileReference.fileExtension),
                .optionalText(fileReference.contentType),
                .optionalInt(fileReference.fileSize),
                .optionalDouble(fileReference.modifiedAt?.timeIntervalSince1970),
                .bool(fileReference.isDirectory),
                .bool(fileReference.isAlias),
                .text(fileReference.pathStatus.rawValue),
                .optionalDouble(fileReference.lastCheckedAt?.timeIntervalSince1970),
                .double(fileReference.createdAt.timeIntervalSince1970)
            ]
        )
    }

    private func insertAsset(
        itemID: UUID,
        type: String,
        fileName: String,
        width: Int?,
        height: Int?,
        createdAt: Date,
        in database: SQLiteDatabase
    ) throws {
        try database.execute(
            """
            INSERT INTO item_assets (
                id, item_id, asset_type, file_name, original_file_name,
                width, height, byte_size, created_at
            ) VALUES (?, ?, ?, ?, NULL, ?, ?, NULL, ?)
            """,
            values: [
                .text(UUID().uuidString),
                .text(itemID.uuidString),
                .text(type),
                .text(fileName),
                .optionalInt(width),
                .optionalInt(height),
                .double(createdAt.timeIntervalSince1970)
            ]
        )
    }

    private func insert(_ group: ClipboardGroup, in database: SQLiteDatabase) throws {
        try database.execute(
            """
            INSERT INTO groups (
                id, name, color_hex, icon_name, sort_order, created_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            values: [
                .text(group.id.uuidString),
                .text(group.name),
                .text(group.colorHex),
                .text(group.iconName),
                .int(group.sortOrder),
                .double(group.createdAt.timeIntervalSince1970),
                .double(group.updatedAt.timeIntervalSince1970)
            ]
        )
    }

    private func insertGroupItem(for item: ClipboardItem, in database: SQLiteDatabase) throws {
        guard let groupID = item.groupID else {
            return
        }

        try database.execute(
            """
            INSERT INTO group_items (
                id, group_id, item_id, created_at, sort_order
            ) VALUES (?, ?, ?, ?, ?)
            """,
            values: [
                .text(UUID().uuidString),
                .text(groupID.uuidString),
                .text(item.id.uuidString),
                .double((item.groupedAt ?? item.createdAt).timeIntervalSince1970),
                .int(0)
            ]
        )
    }
}

private struct SQLiteAssetRow {
    let type: String
    let fileName: String
    let width: Int?
    let height: Int?
}

private struct SQLiteOCRResultRow {
    let status: ClipboardOCRStatus
    let text: String
    let emails: [String]
    let phoneNumbers: [String]
    let urls: [String]
    let textRegions: [ClipboardOCRTextRegion]
    let updatedAt: Date?
}

private extension SQLiteClipboardStore {
    static func encodeList(_ values: [String]) -> String {
        (try? String(data: JSONEncoder().encode(values), encoding: .utf8)) ?? "[]"
    }

    static func decodeList(_ text: String) -> [String] {
        guard let data = text.data(using: .utf8),
              let values = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }

        return values
    }

    static func encodeRegions(_ regions: [ClipboardOCRTextRegion]) -> String {
        (try? String(data: JSONEncoder().encode(regions), encoding: .utf8)) ?? "[]"
    }

    static func decodeRegions(_ text: String) -> [ClipboardOCRTextRegion] {
        guard let data = text.data(using: .utf8),
              let regions = try? JSONDecoder().decode([ClipboardOCRTextRegion].self, from: data) else {
            return []
        }

        return regions
    }
}

private struct SQLiteGroupItemRow {
    let groupID: UUID
    let createdAt: Date
    let sortOrder: Int
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
