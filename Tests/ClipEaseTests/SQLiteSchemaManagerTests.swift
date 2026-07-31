import Foundation
import Testing
@testable import ClipEase

@Test func sqliteSchemaManagerCreatesCurrentSchemaAndRecordsVersion() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("clipease-sqlite-schema-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let database = try SQLiteConnection(url: directory.appendingPathComponent("ClipEase.sqlite"))
    defer { database.close() }

    let manager = SQLiteSchemaManager(currentSchemaVersion: SQLiteClipboardStore.currentSchemaVersion)
    try manager.createSchema(in: database)
    try manager.recordSchemaVersion(in: database)

    #expect(try database.queryInt("PRAGMA user_version") == SQLiteClipboardStore.currentSchemaVersion)
    #expect(try database.queryInt("SELECT COUNT(*) FROM schema_versions WHERE version = ?", values: [.int(SQLiteClipboardStore.currentSchemaVersion)]) == 1)
    #expect(try database.queryInt("SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = 'clipboard_items'") == 1)
    #expect(try database.queryInt("SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = 'clipboard_items_fts'") == 1)
    #expect(
        try database.queryInt(
            "SELECT COUNT(*) FROM sqlite_master WHERE type = 'index' AND name = 'idx_clipboard_items_live_order'"
        ) == 1
    )
    #expect(try database.query("PRAGMA table_info('item_ocr_results')").contains { $0.requiredText("name") == "text_regions" })
}

@Test func sqliteSchemaManagerRepairsMissingLegacyClipboardColumns() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("clipease-sqlite-schema-legacy-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let database = try SQLiteConnection(url: directory.appendingPathComponent("ClipEase.sqlite"))
    defer { database.close() }

    try database.execute(
        """
        CREATE TABLE clipboard_items (
            id TEXT PRIMARY KEY,
            type TEXT NOT NULL,
            plain_text TEXT NOT NULL DEFAULT '',
            source_app_name TEXT NOT NULL DEFAULT '',
            source_icon_name TEXT NOT NULL DEFAULT '',
            header_color TEXT NOT NULL DEFAULT '',
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL,
            is_pinned INTEGER NOT NULL DEFAULT 0,
            is_deleted INTEGER NOT NULL DEFAULT 0
        )
        """
    )

    try SQLiteSchemaManager(currentSchemaVersion: SQLiteClipboardStore.currentSchemaVersion)
        .createSchema(in: database)

    let columns = Set(try database.query("PRAGMA table_info('clipboard_items')").map { $0.requiredText("name") })
    for expected in [
        "url", "link_title", "link_subtitle", "source_bundle_id", "source_icon_file_name",
        "last_used_at", "pinned_at", "last_edited_at", "group_sort_order", "content_hash",
        "content_digest", "digest_version"
    ] {
        #expect(columns.contains(expected), "legacy schema is missing repaired column \(expected)")
    }

    #expect(
        try database.queryInt(
            "SELECT COUNT(*) FROM sqlite_master WHERE type = 'index' AND name = 'idx_clipboard_items_source_bundle'"
        ) == 1
    )
    #expect(
        try database.queryInt(
            "SELECT COUNT(*) FROM sqlite_master WHERE type = 'index' AND name = 'idx_clipboard_items_content_digest'"
        ) == 1
    )
}
