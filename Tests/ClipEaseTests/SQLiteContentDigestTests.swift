import Foundation
import Testing
@testable import ClipEase

@Test func sqliteSchemaAddsVersionedBinaryContentDigestAndIndex() throws {
    let fixture = try SQLiteContentDigestFixture.make()
    defer { fixture.remove() }

    try fixture.store.initialize()
    let database = try SQLiteDatabase(url: fixture.databaseURL)
    defer { database.close() }

    let columns = try database.query("PRAGMA table_info('clipboard_items')")
        .map { $0.requiredText("name") }
    #expect(columns.contains("content_digest"))
    #expect(columns.contains("digest_version"))
    #expect(try database.queryInt(
        "SELECT COUNT(*) FROM sqlite_master WHERE type = 'index' AND name = 'idx_clipboard_items_content_digest'"
    ) == 1)
    #expect(try database.queryInt(
        "SELECT COUNT(*) FROM sqlite_master WHERE type = 'index' AND name = 'idx_clipboard_items_content_hash_active'"
    ) == 1)
    #expect(try database.queryInt(
        "SELECT COUNT(*) FROM sqlite_master WHERE type = 'index' AND name = 'idx_clipboard_items_deleted'"
    ) == 0)

    let digestPlan = try database.query(
        """
        EXPLAIN QUERY PLAN
        SELECT id
        FROM clipboard_items
        WHERE clipboard_items.is_deleted = 0
          AND clipboard_items.digest_version = ?
          AND clipboard_items.content_digest = ?
          AND clipboard_items.source_bundle_id = ?
        """,
        values: [
            .int(SQLiteContentDigest.currentVersion),
            .blob(SQLiteContentDigest.digest(for: "plan")),
            .text("app.clipease")
        ]
    )
    #expect(digestPlan.contains {
        $0.requiredText("detail").contains("idx_clipboard_items_content_digest")
    })

    let legacyPlan = try database.query(
        """
        EXPLAIN QUERY PLAN
        SELECT id
        FROM clipboard_items
        WHERE clipboard_items.is_deleted = 0
          AND clipboard_items.content_hash = ?
          AND clipboard_items.source_bundle_id = ?
        """,
        values: [
            .text("plan"),
            .text("app.clipease")
        ]
    )
    #expect(legacyPlan.contains {
        $0.requiredText("detail").contains("idx_clipboard_items_content_hash_active")
    })
}

@Test func sqliteItemDAODualWritesDigestAndLegacyHash() throws {
    let fixture = try SQLiteContentDigestFixture.make()
    defer { fixture.remove() }
    try fixture.store.initialize()
    let database = try SQLiteDatabase(url: fixture.databaseURL)
    defer { database.close() }
    let item = ClipboardItem.text("digest me", sourceApp: .clipease)

    try SQLiteItemDAO.insert(item, in: database)

    #expect(try database.queryInt(
        "SELECT length(content_digest) FROM clipboard_items WHERE id = ?",
        values: [.text(item.id.uuidString)]
    ) == 32)
    #expect(try database.queryInt(
        "SELECT digest_version FROM clipboard_items WHERE id = ?",
        values: [.text(item.id.uuidString)]
    ) == SQLiteContentDigest.currentVersion)
    #expect(try database.queryInt(
        "SELECT COUNT(*) FROM clipboard_items WHERE id = ? AND content_hash = ?",
        values: [.text(item.id.uuidString), .text("digest me")]
    ) == 1)
}

@Test func sqliteVersionFourMigrationAddsDigestColumnsWithoutRewritingLegacyHash() throws {
    let fixture = try SQLiteContentDigestFixture.make()
    defer { fixture.remove() }
    let legacyID = UUID()
    do {
        let database = try SQLiteDatabase(url: fixture.databaseURL)
        defer { database.close() }
        try database.execute(
            """
            CREATE TABLE clipboard_items (
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
            """
        )
        try database.execute(
            """
            INSERT INTO clipboard_items (
                id, type, plain_text, source_app_name, source_icon_name,
                header_color, created_at, updated_at, content_hash
            ) VALUES (?, 'text', 'legacy-value', 'Legacy', 'app.fill', '#000000', 1, 1, 'legacy-value')
            """,
            values: [.text(legacyID.uuidString)]
        )
        try database.execute(
            "CREATE INDEX idx_clipboard_items_deleted ON clipboard_items(is_deleted)"
        )
        try database.execute("PRAGMA user_version = 4")
    }

    try fixture.store.initialize()

    let database = try SQLiteDatabase(url: fixture.databaseURL)
    defer { database.close() }
    #expect(try database.queryInt("PRAGMA user_version") == 5)
    #expect(try database.queryInt(
        "SELECT COUNT(*) FROM clipboard_items WHERE id = ? AND content_hash = 'legacy-value'",
        values: [.text(legacyID.uuidString)]
    ) == 1)
    #expect(try database.queryInt(
        "SELECT COUNT(*) FROM sqlite_master WHERE type = 'index' AND name = 'idx_clipboard_items_deleted'"
    ) == 0)
    #expect(try fixture.store.loadItems(
        contentHash: "legacy-value",
        sourceBundleID: nil
    ).map(\.id) == [legacyID])
}

@Test func sqliteDigestLookupVerifiesCollisionAndFallsBackToLegacyHash() throws {
    let fixture = try SQLiteContentDigestFixture.make()
    defer { fixture.remove() }
    try fixture.store.initialize()
    let database = try SQLiteDatabase(url: fixture.databaseURL)
    defer { database.close() }
    let collision = ClipboardItem.text("different", sourceApp: .clipease)
    let legacy = ClipboardItem.text("legacy", sourceApp: .clipease)
    let oldVersion = ClipboardItem.text("old-version", sourceApp: .clipease)
    try SQLiteItemDAO.insert(collision, in: database)
    try SQLiteItemDAO.insert(legacy, in: database)
    try SQLiteItemDAO.insert(oldVersion, in: database)
    try database.execute(
        """
        UPDATE clipboard_items
        SET content_digest = ?, digest_version = ?
        WHERE id = ?
        """,
        values: [
            .blob(SQLiteContentDigest.digest(for: "target")),
            .int(SQLiteContentDigest.currentVersion),
            .text(collision.id.uuidString)
        ]
    )
    try database.execute(
        "UPDATE clipboard_items SET content_digest = NULL, digest_version = NULL WHERE id = ?",
        values: [.text(legacy.id.uuidString)]
    )
    try database.execute(
        """
        UPDATE clipboard_items
        SET content_digest = ?, digest_version = ?
        WHERE id = ?
        """,
        values: [
            .blob(SQLiteContentDigest.digest(for: "wrong-nonempty-digest")),
            .int(SQLiteContentDigest.currentVersion - 1),
            .text(oldVersion.id.uuidString)
        ]
    )

    #expect(try fixture.store.loadItems(contentHash: "target", sourceBundleID: nil).isEmpty)
    #expect(try fixture.store.loadItems(contentHash: "legacy", sourceBundleID: nil).map(\.id) == [legacy.id])
    #expect(try fixture.store.loadItems(
        contentHash: "old-version",
        sourceBundleID: nil
    ).map(\.id) == [oldVersion.id])
}

@Test func sqliteContentDigestBackfillIsCappedAndResumable() throws {
    let fixture = try SQLiteContentDigestFixture.make()
    defer { fixture.remove() }
    try fixture.store.initialize()
    let database = try SQLiteDatabase(url: fixture.databaseURL)
    defer { database.close() }

    for index in 0..<501 {
        try SQLiteItemDAO.insert(
            ClipboardItem.text("legacy-\(index)", sourceApp: .clipease),
            in: database
        )
    }
    try database.execute("UPDATE clipboard_items SET content_digest = NULL, digest_version = NULL")

    #expect(try SQLiteItemDAO.backfillContentDigests(in: database) == 500)
    #expect(try database.queryInt(
        "SELECT COUNT(*) FROM clipboard_items WHERE content_digest IS NULL"
    ) == 1)
    #expect(try SQLiteItemDAO.backfillContentDigests(in: database) == 1)
    #expect(try SQLiteItemDAO.backfillContentDigests(in: database) == 0)
}

private struct SQLiteContentDigestFixture {
    let directory: URL
    let databaseURL: URL
    let store: SQLiteClipboardStore

    static func make() throws -> SQLiteContentDigestFixture {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("clipease-digest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let databaseURL = directory.appendingPathComponent("ClipEase.sqlite")
        return SQLiteContentDigestFixture(
            directory: directory,
            databaseURL: databaseURL,
            store: SQLiteClipboardStore(databaseURL: databaseURL)
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}
