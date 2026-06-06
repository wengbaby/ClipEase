import Foundation
import Testing
@testable import ClipEase

@Test func databaseCompactionPolicyRequiresTwentyFivePercentFreePages() {
    let policy = ClipboardDatabaseCompactionPolicy(
        minimumFreeRatio: 0.25,
        minimumFreeBytes: 1
    )

    #expect(!policy.shouldCompact(pageSize: 4_096, pageCount: 100, freelistCount: 24))
    #expect(policy.shouldCompact(pageSize: 4_096, pageCount: 100, freelistCount: 25))
}

@Test func sqliteCompactionShrinksDatabaseWhenFreePagesExceedPolicy() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("clipease-compact-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let url = directory.appendingPathComponent("ClipEase.sqlite")
    let store = SQLiteClipboardStore(databaseURL: url)
    try store.initialize()
    let database = try SQLiteDatabase(url: url)
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
    database.close()

    #expect(pageCount > 0)
    #expect(freelistCount > 0)

    let result = try store.compactIfNeeded(policy: ClipboardDatabaseCompactionPolicy(
        minimumFreeRatio: 0,
        minimumFreeBytes: 1
    ))

    #expect(result.reclaimedBytes > 0)
}
