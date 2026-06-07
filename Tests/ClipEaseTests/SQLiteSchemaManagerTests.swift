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
    #expect(try database.query("PRAGMA table_info('item_ocr_results')").contains { $0.requiredText("name") == "text_regions" })
}
