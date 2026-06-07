import Foundation
@testable import ClipEase

struct SQLiteLegacyStoreFixture {
    let directoryURL: URL
    let databaseURL: URL

    static func make(userVersion: Int) throws -> SQLiteLegacyStoreFixture {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("clipease-legacy-fixture-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let databaseURL = directoryURL.appendingPathComponent("ClipEase.sqlite")
        let fixture = SQLiteLegacyStoreFixture(directoryURL: directoryURL, databaseURL: databaseURL)
        try fixture.createDatabase(userVersion: userVersion)
        return fixture
    }

    func remove() {
        try? FileManager.default.removeItem(at: directoryURL)
    }

    func userVersion() throws -> Int {
        let database = try SQLiteDatabase(url: databaseURL)
        defer { database.close() }
        return try database.queryInt("PRAGMA user_version")
    }

    func legacyMarkerValue() throws -> String {
        let database = try SQLiteDatabase(url: databaseURL)
        defer { database.close() }
        return try database.query("SELECT value FROM legacy_marker LIMIT 1")
            .first?
            .requiredText("value") ?? ""
    }

    private func createDatabase(userVersion: Int) throws {
        let database = try SQLiteDatabase(url: databaseURL)
        defer { database.close() }
        try database.execute("PRAGMA user_version = \(userVersion)")
        try database.execute("CREATE TABLE legacy_marker (value TEXT NOT NULL)")
        try database.execute("INSERT INTO legacy_marker (value) VALUES ('keep')")
    }
}
