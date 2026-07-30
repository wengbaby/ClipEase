import Foundation

struct SQLiteSchemaMigrator: Sendable {
    let currentSchemaVersion: Int

    init(currentSchemaVersion: Int) {
        self.currentSchemaVersion = currentSchemaVersion
    }

    func migrateIfNeeded(
        databaseURL: URL,
        fileManager: FileManager,
        createSchema: (SQLiteDatabase) throws -> Void,
        recordSchemaVersion: (SQLiteDatabase) throws -> Void
    ) throws -> Bool {
        guard fileManager.fileExists(atPath: databaseURL.path) else {
            return false
        }

        let database = try SQLiteDatabase(url: databaseURL)
        defer { database.close() }

        let userVersion = try database.queryInt("PRAGMA user_version")
        guard userVersion < currentSchemaVersion else {
            return false
        }

        try database.execute("PRAGMA foreign_keys = OFF")
        do {
            try createSchema(database)
            try recordSchemaVersion(database)
            try database.execute("PRAGMA foreign_keys = ON")
            return true
        } catch {
            try? database.execute("PRAGMA foreign_keys = ON")
            throw error
        }
    }
}
