import Foundation
import Testing
@testable import ClipEase

@Test func sqliteBackupManagerReturnsNilWhenMainDatabaseDoesNotExist() throws {
    let fixture = try SQLiteBackupManagerFixture.make()
    defer { fixture.remove() }

    let result = try SQLiteBackupManager()
        .backupDatabaseFiles(for: fixture.databaseURL, reason: "missing")

    #expect(result == nil)
}

@Test func sqliteBackupManagerCopiesMainDatabaseAndExistingSidecars() throws {
    let fixture = try SQLiteBackupManagerFixture.make()
    defer { fixture.remove() }

    try Data("main".utf8).write(to: fixture.databaseURL)
    try Data("wal".utf8).write(to: URL(fileURLWithPath: fixture.databaseURL.path + "-wal"))
    try Data("shm".utf8).write(to: URL(fileURLWithPath: fixture.databaseURL.path + "-shm"))
    try Data("journal".utf8).write(to: URL(fileURLWithPath: fixture.databaseURL.path + "-journal"))

    let optionalResult = try SQLiteBackupManager().backupDatabaseFiles(
        for: fixture.databaseURL,
        reason: "schema/1:4"
    )
    let result = try #require(optionalResult)

    #expect(result.copiedFiles == [
        "ClipEase.sqlite",
        "ClipEase.sqlite-wal",
        "ClipEase.sqlite-shm",
        "ClipEase.sqlite-journal"
    ])
    #expect(result.directoryURL.lastPathComponent.hasPrefix("ClipEase.sqlite.backup-schema-1-4-"))
    #expect(try Data(contentsOf: result.directoryURL.appendingPathComponent("ClipEase.sqlite")) == Data("main".utf8))
    #expect(try Data(contentsOf: result.directoryURL.appendingPathComponent("ClipEase.sqlite-wal")) == Data("wal".utf8))
    #expect(try Data(contentsOf: result.directoryURL.appendingPathComponent("ClipEase.sqlite-shm")) == Data("shm".utf8))
    #expect(try Data(contentsOf: result.directoryURL.appendingPathComponent("ClipEase.sqlite-journal")) == Data("journal".utf8))
}

@Test func sqliteBackupManagerDatabaseFileURLsPreserveExpectedSidecarOrder() {
    let databaseURL = URL(fileURLWithPath: "/tmp/ClipEase.sqlite")

    #expect(SQLiteBackupManager.databaseFileURLs(for: databaseURL).map(\.path) == [
        "/tmp/ClipEase.sqlite",
        "/tmp/ClipEase.sqlite-wal",
        "/tmp/ClipEase.sqlite-shm",
        "/tmp/ClipEase.sqlite-journal"
    ])
}

private struct SQLiteBackupManagerFixture {
    let directoryURL: URL
    let databaseURL: URL

    static func make() throws -> SQLiteBackupManagerFixture {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("clipease-backup-manager-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return SQLiteBackupManagerFixture(
            directoryURL: directoryURL,
            databaseURL: directoryURL.appendingPathComponent("ClipEase.sqlite")
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: directoryURL)
    }
}
