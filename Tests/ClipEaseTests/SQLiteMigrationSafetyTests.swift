import Foundation
import Testing
@testable import ClipEase

@Test func legacySQLiteInitializationDoesNotDeleteExistingDatabase() throws {
    let directory = try makeSQLiteMigrationTestDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let databaseURL = directory.appendingPathComponent("ClipEase.sqlite")
    try createLegacyDatabase(at: databaseURL, userVersion: 1)

    let originalBytes = try Data(contentsOf: databaseURL)
    let store = SQLiteClipboardStore(databaseURL: databaseURL)

    try store.initialize()

    #expect(FileManager.default.fileExists(atPath: databaseURL.path))
    #expect((try Data(contentsOf: databaseURL)).count >= originalBytes.count)
}

@Test func legacySQLiteInitializationCreatesBackupWithSidecars() throws {
    let directory = try makeSQLiteMigrationTestDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let databaseURL = directory.appendingPathComponent("ClipEase.sqlite")
    try createLegacyDatabase(at: databaseURL, userVersion: 1)
    try Data("wal".utf8).write(to: URL(fileURLWithPath: databaseURL.path + "-wal"))
    try Data("shm".utf8).write(to: URL(fileURLWithPath: databaseURL.path + "-shm"))

    let store = SQLiteClipboardStore(databaseURL: databaseURL)

    try store.initialize()

    let backupDirectories = try FileManager.default.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: nil
    )
    .filter { $0.lastPathComponent.hasPrefix("ClipEase.sqlite.backup-") }

    #expect(backupDirectories.count == 1)
    let backupDirectory = try #require(backupDirectories.first)
    #expect(FileManager.default.fileExists(atPath: backupDirectory.appendingPathComponent("ClipEase.sqlite").path))
    #expect(FileManager.default.fileExists(atPath: backupDirectory.appendingPathComponent("ClipEase.sqlite-wal").path))
    #expect(FileManager.default.fileExists(atPath: backupDirectory.appendingPathComponent("ClipEase.sqlite-shm").path))
}

private func makeSQLiteMigrationTestDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("clipease-migration-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

private func createLegacyDatabase(at url: URL, userVersion: Int) throws {
    let database = try SQLiteDatabase(url: url)
    defer { database.close() }
    try database.execute("PRAGMA user_version = \(userVersion)")
    try database.execute("CREATE TABLE legacy_marker (value TEXT NOT NULL)")
    try database.execute("INSERT INTO legacy_marker (value) VALUES ('keep')")
}
