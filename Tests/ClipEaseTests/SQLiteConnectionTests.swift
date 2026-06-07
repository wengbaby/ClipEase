import Foundation
import Testing
@testable import ClipEase

@Test func sqliteConnectionExecutesParameterizedQueriesAndCloses() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("clipease-sqlite-connection-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let databaseURL = directory.appendingPathComponent("ClipEase.sqlite")
    let connection = try SQLiteConnection(url: databaseURL)
    defer { connection.close() }

    try connection.execute("CREATE TABLE sample (id INTEGER PRIMARY KEY, value TEXT NOT NULL)")
    try connection.execute("INSERT INTO sample (value) VALUES (?)", values: [.text("hello")])

    #expect(try connection.queryInt("SELECT COUNT(*) FROM sample") == 1)
    #expect(try connection.query("SELECT value FROM sample").first?.requiredText("value") == "hello")
}
