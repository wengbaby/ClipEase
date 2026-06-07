import Foundation
import Testing
@testable import ClipEase

@Test func sqliteDatabaseCompactorSkipsWhenPolicyDoesNotRequireCompaction() throws {
    let fixture = try SQLiteDatabaseCompactorFixture.make()
    defer { fixture.remove() }

    let database = try SQLiteDatabase(url: fixture.databaseURL)
    defer { database.close() }
    try fixture.store.initialize()

    let result = try SQLiteDatabaseCompactor.compactIfNeeded(
        database: database,
        policy: ClipboardDatabaseCompactionPolicy(
            minimumFreeRatio: 1,
            minimumFreeBytes: Int.max
        )
    )

    #expect(result == .skipped)
}

@Test func sqliteDatabaseCompactorShrinksDatabaseWhenFreePagesExceedPolicy() throws {
    let fixture = try SQLiteDatabaseCompactorFixture.make()
    defer { fixture.remove() }

    let database = try SQLiteDatabase(url: fixture.databaseURL)
    defer { database.close() }
    try fixture.store.initialize()

    try database.execute("CREATE TABLE compaction_junk (payload TEXT NOT NULL)")
    for _ in 0..<300 {
        try database.execute(
            "INSERT INTO compaction_junk (payload) VALUES (?)",
            values: [.text(String(repeating: "x", count: 8_192))]
        )
    }
    try database.execute("DELETE FROM compaction_junk")
    try database.execute("PRAGMA wal_checkpoint(TRUNCATE)")

    let pageCount = try database.queryInt("PRAGMA page_count")
    let freelistCount = try database.queryInt("PRAGMA freelist_count")
    #expect(pageCount > 0)
    #expect(freelistCount > 0)

    let result = try SQLiteDatabaseCompactor.compactIfNeeded(
        database: database,
        policy: ClipboardDatabaseCompactionPolicy(
            minimumFreeRatio: 0,
            minimumFreeBytes: 1
        )
    )

    #expect(result.reclaimedBytes > 0)
}

private struct SQLiteDatabaseCompactorFixture {
    let directory: URL
    let databaseURL: URL
    let store: SQLiteClipboardStore

    static func make() throws -> SQLiteDatabaseCompactorFixture {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("clipease-sqlite-compactor-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let databaseURL = directory.appendingPathComponent("ClipEase.sqlite")
        return SQLiteDatabaseCompactorFixture(
            directory: directory,
            databaseURL: databaseURL,
            store: SQLiteClipboardStore(databaseURL: databaseURL)
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}
