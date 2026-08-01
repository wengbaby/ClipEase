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

@Test func currentSQLiteStoreRepairsMissingMeasuredOrderIndex() throws {
    let directory = try makeSQLiteMigrationTestDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let databaseURL = directory.appendingPathComponent("ClipEase.sqlite")
    let database = try SQLiteConnection(url: databaseURL)
    let schemaManager = SQLiteSchemaManager(currentSchemaVersion: SQLiteClipboardStore.currentSchemaVersion)
    try schemaManager.createSchema(in: database)
    try schemaManager.recordSchemaVersion(in: database)
    try database.execute("DROP INDEX idx_clipboard_items_live_order")
    database.close()

    try SQLiteClipboardStore(databaseURL: databaseURL).initialize()

    let repaired = try SQLiteConnection(url: databaseURL)
    defer { repaired.close() }
    #expect(
        try repaired.queryInt(
            "SELECT COUNT(*) FROM sqlite_master WHERE type = 'index' AND name = 'idx_clipboard_items_live_order'"
        ) == 1
    )
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

@Test func legacySQLiteMigrationPreservesUnknownLegacyTables() throws {
    let fixture = try SQLiteLegacyStoreFixture.make(userVersion: 1)
    defer { fixture.remove() }

    let store = SQLiteClipboardStore(databaseURL: fixture.databaseURL)

    try store.initialize()

    #expect(try fixture.legacyMarkerValue() == "keep")
    #expect(try fixture.userVersion() == SQLiteClipboardStore.currentSchemaVersion)
}

@Test func additiveSQLiteMigrationCanRetryAfterPartialFailure() throws {
    let directory = try makeSQLiteMigrationTestDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let databaseURL = directory.appendingPathComponent("ClipEase.sqlite")
    try createLegacyDatabase(at: databaseURL, userVersion: 4)
    let migrator = SQLiteSchemaMigrator(
        currentSchemaVersion: SQLiteClipboardStore.currentSchemaVersion
    )

    #expect(throws: SQLiteMigrationTestError.injectedFailure) {
        _ = try migrator.migrateIfNeeded(
            databaseURL: databaseURL,
            fileManager: .default,
            createSchema: { database in
                try database.execute(
                    "CREATE TABLE IF NOT EXISTS partial_additive_marker (value TEXT)"
                )
                throw SQLiteMigrationTestError.injectedFailure
            },
            recordSchemaVersion: { _ in
                Issue.record("A failed schema pass must not record the new version")
            }
        )
    }

    do {
        let database = try SQLiteDatabase(url: databaseURL)
        defer { database.close() }
        #expect(try database.queryInt("PRAGMA user_version") == 4)
        #expect(try database.queryInt(
            "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = 'partial_additive_marker'"
        ) == 1)
    }

    let schemaManager = SQLiteSchemaManager(
        currentSchemaVersion: SQLiteClipboardStore.currentSchemaVersion
    )
    #expect(try migrator.migrateIfNeeded(
        databaseURL: databaseURL,
        fileManager: .default,
        createSchema: { try schemaManager.createSchema(in: $0) },
        recordSchemaVersion: { try schemaManager.recordSchemaVersion(in: $0) }
    ))

    let database = try SQLiteDatabase(url: databaseURL)
    defer { database.close() }
    #expect(try database.queryInt("PRAGMA user_version") == SQLiteClipboardStore.currentSchemaVersion)
    #expect(try database.queryInt(
        "SELECT COUNT(*) FROM legacy_marker WHERE value = 'keep'"
    ) == 1)
}

@Test func sqliteMigrationPersistsPhaseAcrossFailureAndCompletesOnRetry() throws {
    let directory = try makeSQLiteMigrationTestDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let databaseURL = directory.appendingPathComponent("ClipEase.sqlite")
    try createLegacyDatabase(at: databaseURL, userVersion: 4)
    let migrator = SQLiteSchemaMigrator(
        currentSchemaVersion: SQLiteClipboardStore.currentSchemaVersion
    )

    #expect(throws: SQLiteMigrationTestError.injectedFailure) {
        _ = try migrator.migrateIfNeeded(
            databaseURL: databaseURL,
            fileManager: .default,
            createSchema: { database in
                try database.execute("CREATE TABLE IF NOT EXISTS partial_phase_marker (value TEXT)")
                throw SQLiteMigrationTestError.injectedFailure
            },
            recordSchemaVersion: { _ in
                Issue.record("A failed migration must not record the completed phase")
            }
        )
    }

    do {
        let database = try SQLiteDatabase(url: databaseURL)
        defer { database.close() }
        #expect(
            try database.queryInt(
                "SELECT COUNT(*) FROM schema_migration_state WHERE id = 1 AND phase = 'started'"
            ) == 1
        )
        #expect(try database.queryInt("PRAGMA user_version") == 4)
    }

    let schemaManager = SQLiteSchemaManager(
        currentSchemaVersion: SQLiteClipboardStore.currentSchemaVersion
    )
    #expect(try migrator.migrateIfNeeded(
        databaseURL: databaseURL,
        fileManager: .default,
        createSchema: { try schemaManager.createSchema(in: $0) },
        recordSchemaVersion: { try schemaManager.recordSchemaVersion(in: $0) }
    ))

    let database = try SQLiteDatabase(url: databaseURL)
    defer { database.close() }
    #expect(
        try database.queryInt(
            "SELECT COUNT(*) FROM schema_migration_state WHERE id = 1 AND phase = 'backfill_pending'"
        ) == 1
    )
    #expect(try database.queryInt("PRAGMA user_version") == SQLiteClipboardStore.currentSchemaVersion)
}

@Test func sqlitePooledFirstUseMigratesLegacyDatabaseWithoutSelfDeadlock() throws {
    let fixture = try SQLiteMigrationStoreFixture.make(userVersion: 4)
    defer { fixture.remove() }

    let page = try SQLiteClipboardStore(databaseURL: fixture.databaseURL)
        .loadItemPage(limit: 1, after: nil)
    #expect(page.items.isEmpty)
}

@Test func sqliteReadPathFallsBackToLegacyDatabaseWhenMigrationFails() throws {
    let fixture = try SQLiteMigrationStoreFixture.make(userVersion: 5)
    defer { fixture.remove() }
    let item = ClipboardItem.text("legacy fallback", sourceApp: .clipease)

    do {
        let database = try SQLiteDatabase(url: fixture.databaseURL)
        let schemaManager = SQLiteSchemaManager(
            currentSchemaVersion: SQLiteClipboardStore.currentSchemaVersion
        )
        try schemaManager.createSchema(in: database)
        try schemaManager.recordSchemaVersion(in: database)
        try SQLiteItemDAO.insert(item, in: database)
        try database.execute("PRAGMA user_version = 4")
        database.close()
    }

    let failingStore = SQLiteClipboardStore(
        databaseURL: fixture.databaseURL,
        migrationCreateSchema: { _ in
            throw SQLiteMigrationTestError.injectedFailure
        }
    )

    let snapshot = try failingStore.loadSnapshot()
    #expect(snapshot.items.map(\.id) == [item.id])
}

@Test func sqliteWriterRetryMigratesAfterPooledLegacyReadFallback() throws {
    let fixture = try SQLiteMigrationStoreFixture.make(userVersion: 5)
    defer { fixture.remove() }
    let schemaManager = SQLiteSchemaManager(
        currentSchemaVersion: SQLiteClipboardStore.currentSchemaVersion
    )
    do {
        let database = try SQLiteDatabase(url: fixture.databaseURL)
        try schemaManager.createSchema(in: database)
        try schemaManager.recordSchemaVersion(in: database)
        try database.execute("PRAGMA user_version = 4")
        database.close()
    }

    var shouldFailMigration = true
    let store = SQLiteClipboardStore(
        databaseURL: fixture.databaseURL,
        migrationCreateSchema: { database in
            if shouldFailMigration {
                throw SQLiteMigrationTestError.injectedFailure
            }
            try schemaManager.createSchema(in: database)
        }
    )

    let page = try store.loadItemPage(limit: 1, after: nil)
    #expect(page.items.isEmpty)
    shouldFailMigration = false

    try store.upsertGroups([
        ClipboardGroup.makeDefault(name: "Recovered", sortOrder: 0)
    ])

    let database = try SQLiteDatabase(url: fixture.databaseURL)
    defer { database.close() }
    #expect(try database.queryInt("PRAGMA user_version") == SQLiteClipboardStore.currentSchemaVersion)
    #expect(try database.queryInt("SELECT COUNT(*) FROM groups WHERE name = 'Recovered'") == 1)
}

@Test func sqliteDigestBackfillCompletesPersistedMigrationPhase() throws {
    let fixture = try SQLiteMigrationStoreFixture.make(userVersion: 4)
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
                source_bundle_id TEXT,
                pinned_at REAL,
                source_app_name TEXT NOT NULL DEFAULT '',
                source_icon_name TEXT NOT NULL DEFAULT '',
                header_color TEXT NOT NULL DEFAULT '',
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL,
                is_pinned INTEGER NOT NULL DEFAULT 0,
                is_deleted INTEGER NOT NULL DEFAULT 0,
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
    }

    let store = SQLiteClipboardStore(databaseURL: fixture.databaseURL)
    try store.initialize()
    do {
        let database = try SQLiteDatabase(url: fixture.databaseURL)
        defer { database.close() }
        #expect(
            try database.queryInt(
                "SELECT COUNT(*) FROM schema_migration_state WHERE id = 1 AND phase = 'backfill_pending'"
            ) == 1
        )
    }

    #expect(try store.backfillContentDigests(limit: 500) == 1)
    let database = try SQLiteDatabase(url: fixture.databaseURL)
    defer { database.close() }
    #expect(
        try database.queryInt(
            "SELECT COUNT(*) FROM schema_migration_state WHERE id = 1 AND phase = 'completed'"
        ) == 1
    )
}

@Test func sqliteMigrationRepairsPartialClipboardSchemaForReadAndWrite() throws {
    let fixture = try SQLiteMigrationStoreFixture.make(userVersion: 4)
    defer { fixture.remove() }

    do {
        let database = try SQLiteDatabase(url: fixture.databaseURL)
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
                is_deleted INTEGER NOT NULL DEFAULT 0,
                content_hash TEXT
            )
            """
        )
    }

    let store = SQLiteClipboardStore(databaseURL: fixture.databaseURL)
    try store.initialize()

    let item = ClipboardItem.text("migrated", sourceApp: .clipease)
    try store.insertItems([item])

    let snapshot = try store.loadSnapshot()
    #expect(snapshot.items.map(\.id) == [item.id])
    let migratedDatabase = try SQLiteDatabase(url: fixture.databaseURL)
    defer { migratedDatabase.close() }
    #expect(try migratedDatabase.queryInt("PRAGMA user_version") == SQLiteClipboardStore.currentSchemaVersion)
}

@Test func sqliteDigestBootstrapMarksAlreadyCompleteCurrentDatabase() throws {
    let fixture = try SQLiteMigrationStoreFixture.make(userVersion: 5)
    defer { fixture.remove() }

    do {
        let database = try SQLiteDatabase(url: fixture.databaseURL)
        let schemaManager = SQLiteSchemaManager(
            currentSchemaVersion: SQLiteClipboardStore.currentSchemaVersion
        )
        try schemaManager.createSchema(in: database)
        try schemaManager.recordSchemaVersion(in: database)
        try SQLiteItemDAO.insert(
            ClipboardItem.text("already complete", sourceApp: .clipease),
            in: database
        )
        database.close()
    }

    let store = SQLiteClipboardStore(databaseURL: fixture.databaseURL)
    #expect(try store.backfillContentDigests(limit: 500) == 0)

    let database = try SQLiteDatabase(url: fixture.databaseURL)
    defer { database.close() }
    #expect(
        try database.queryInt(
            "SELECT COUNT(*) FROM schema_migration_state WHERE id = 1 AND phase = 'completed'"
        ) == 1
    )
}

@Test func clipboardPersistenceExposesDigestBackfillFailuresToWarmupCallers() throws {
    let fixture = try SQLiteMigrationStoreFixture.make(userVersion: 4)
    defer { fixture.remove() }
    let persistence = ClipboardHistoryPersistence(
        repository: SQLiteClipboardStore(
            databaseURL: fixture.databaseURL,
            migrationCreateSchema: { _ in
                throw SQLiteMigrationTestError.injectedFailure
            }
        )
    )

    #expect(throws: SQLiteMigrationTestError.injectedFailure) {
        _ = try persistence.backfillContentDigestsOrThrow(limit: 500)
    }
}

@Test func searchIndexWarmupRetriesBackfillBeforePreparingIndex() async {
    let repository = SearchIndexWarmupRepository(failuresBeforeSuccess: 2)
    let didPrepare = await ClipboardHistoryStore.performSearchIndexWarmup(
        persistence: ClipboardHistoryPersistence(repository: repository),
        initialDelayNanoseconds: 0,
        batchDelayNanoseconds: 0,
        retryDelaysNanoseconds: [0, 0]
    )

    #expect(didPrepare)
    #expect(repository.backfillCallCount == 3)
    #expect(repository.prepareCallCount == 1)
}

@Test func searchIndexWarmupStopsAfterBoundedBackfillFailures() async {
    let repository = SearchIndexWarmupRepository(failuresBeforeSuccess: 3)
    let didPrepare = await ClipboardHistoryStore.performSearchIndexWarmup(
        persistence: ClipboardHistoryPersistence(repository: repository),
        initialDelayNanoseconds: 0,
        batchDelayNanoseconds: 0,
        retryDelaysNanoseconds: [0, 0]
    )

    #expect(!didPrepare)
    #expect(repository.backfillCallCount == 3)
    #expect(repository.prepareCallCount == 0)
}

@Test func sqliteStoreMigrationFailureRestoresBackupAndRetriesFromLegacyVersion() throws {
    let directory = try makeSQLiteMigrationTestDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let databaseURL = directory.appendingPathComponent("ClipEase.sqlite")
    try createLegacyDatabase(at: databaseURL, userVersion: 4)

    let failingStore = SQLiteClipboardStore(
        databaseURL: databaseURL,
        migrationCreateSchema: { database in
            try database.execute("CREATE TABLE migration_should_restore (value TEXT)")
            throw SQLiteMigrationTestError.injectedFailure
        }
    )

    #expect(throws: SQLiteMigrationTestError.injectedFailure) {
        try failingStore.initialize()
    }

    do {
        let database = try SQLiteDatabase(url: databaseURL)
        defer { database.close() }
        #expect(try database.queryInt("PRAGMA user_version") == 4)
        #expect(try database.queryInt(
            "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = 'migration_should_restore'"
        ) == 0)
        #expect(try database.queryInt("SELECT COUNT(*) FROM legacy_marker WHERE value = 'keep'") == 1)
    }

    let retryStore = SQLiteClipboardStore(databaseURL: databaseURL)
    try retryStore.initialize()

    let database = try SQLiteDatabase(url: databaseURL)
    defer { database.close() }
    #expect(try database.queryInt("PRAGMA user_version") == SQLiteClipboardStore.currentSchemaVersion)
    #expect(try database.queryInt("SELECT COUNT(*) FROM legacy_marker WHERE value = 'keep'") == 1)
}

@Test func sqliteBackupRestoreRequiresMainBackupAndLeavesLiveFilesUntouched() throws {
    let directory = try makeSQLiteMigrationTestDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let databaseURL = directory.appendingPathComponent("ClipEase.sqlite")
    let backupDirectory = directory.appendingPathComponent("missing-main-backup", isDirectory: true)
    try FileManager.default.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
    try Data("live-main".utf8).write(to: databaseURL)
    try Data("live-wal".utf8).write(to: URL(fileURLWithPath: databaseURL.path + "-wal"))

    #expect(throws: SQLiteBackupRestoreError.missingMainDatabaseBackup) {
        try SQLiteBackupManager().restoreDatabaseFiles(
            from: SQLiteBackupResult(
                directoryURL: backupDirectory,
                copiedFiles: ["ClipEase.sqlite"]
            ),
            to: databaseURL
        )
    }

    #expect(try Data(contentsOf: databaseURL) == Data("live-main".utf8))
    #expect(try Data(contentsOf: URL(fileURLWithPath: databaseURL.path + "-wal")) == Data("live-wal".utf8))
}

@Test func sqliteBackupRestoreFailsBeforeReplacingLiveFilesWhenCopiedSidecarIsMissing() throws {
    let directory = try makeSQLiteMigrationTestDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let databaseURL = directory.appendingPathComponent("ClipEase.sqlite")
    let backupDirectory = directory.appendingPathComponent("missing-sidecar-backup", isDirectory: true)
    try FileManager.default.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
    try Data("live-main".utf8).write(to: databaseURL)
    try Data("live-wal".utf8).write(to: URL(fileURLWithPath: databaseURL.path + "-wal"))
    try Data("backup-main".utf8).write(to: backupDirectory.appendingPathComponent("ClipEase.sqlite"))

    #expect(throws: SQLiteBackupRestoreError.missingCopiedBackupFile("ClipEase.sqlite-wal")) {
        try SQLiteBackupManager().restoreDatabaseFiles(
            from: SQLiteBackupResult(
                directoryURL: backupDirectory,
                copiedFiles: ["ClipEase.sqlite", "ClipEase.sqlite-wal"]
            ),
            to: databaseURL
        )
    }

    #expect(try Data(contentsOf: databaseURL) == Data("live-main".utf8))
    #expect(try Data(contentsOf: URL(fileURLWithPath: databaseURL.path + "-wal")) == Data("live-wal".utf8))
}

@Test func sqliteBackupRestoreRollsBackWhenReplacementFailsAfterFirstFile() throws {
    let directory = try makeSQLiteMigrationTestDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let databaseURL = directory.appendingPathComponent("ClipEase.sqlite")
    let backupDirectory = directory.appendingPathComponent("restore-failure-backup", isDirectory: true)
    try FileManager.default.createDirectory(at: backupDirectory, withIntermediateDirectories: true)

    let liveMainURL = databaseURL
    let liveWALURL = URL(fileURLWithPath: databaseURL.path + "-wal")
    try Data("live-main".utf8).write(to: liveMainURL)
    try Data("live-wal".utf8).write(to: liveWALURL)
    try Data("backup-main".utf8).write(to: backupDirectory.appendingPathComponent("ClipEase.sqlite"))
    try Data("backup-wal".utf8).write(to: backupDirectory.appendingPathComponent("ClipEase.sqlite-wal"))

    var replacementCount = 0
    let backupManager = SQLiteBackupManager(
        replaceLiveFile: { destinationURL, stagedURL in
            replacementCount += 1
            guard replacementCount != 2 else {
                throw SQLiteMigrationTestError.injectedFailure
            }
            _ = try FileManager.default.replaceItemAt(
                destinationURL,
                withItemAt: stagedURL,
                backupItemName: nil,
                options: []
            )
        }
    )

    #expect(throws: SQLiteMigrationTestError.injectedFailure) {
        try backupManager.restoreDatabaseFiles(
            from: SQLiteBackupResult(
                directoryURL: backupDirectory,
                copiedFiles: ["ClipEase.sqlite", "ClipEase.sqlite-wal"]
            ),
            to: databaseURL
        )
    }

    #expect(try Data(contentsOf: liveMainURL) == Data("live-main".utf8))
    #expect(try Data(contentsOf: liveWALURL) == Data("live-wal".utf8))
    #expect(try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        .filter { $0.lastPathComponent.hasPrefix(".ClipEase.sqlite.rollback-") }
        .isEmpty)
}

@Test func sqliteBackupRestoreReportsRollbackFailureInsteadOfClaimingRecovery() throws {
    let directory = try makeSQLiteMigrationTestDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let databaseURL = directory.appendingPathComponent("ClipEase.sqlite")
    let backupDirectory = directory.appendingPathComponent("rollback-failure-backup", isDirectory: true)
    try FileManager.default.createDirectory(at: backupDirectory, withIntermediateDirectories: true)

    try Data("live-main".utf8).write(to: databaseURL)
    try Data("live-wal".utf8).write(to: URL(fileURLWithPath: databaseURL.path + "-wal"))
    try Data("backup-main".utf8).write(to: backupDirectory.appendingPathComponent("ClipEase.sqlite"))
    try Data("backup-wal".utf8).write(to: backupDirectory.appendingPathComponent("ClipEase.sqlite-wal"))
    var replacementCount = 0
    let backupManager = SQLiteBackupManager(
        replaceLiveFile: { destinationURL, stagedURL in
            replacementCount += 1
            guard replacementCount != 2, replacementCount != 3 else {
                throw SQLiteMigrationTestError.injectedFailure
            }
            _ = try FileManager.default.replaceItemAt(
                destinationURL,
                withItemAt: stagedURL,
                backupItemName: nil,
                options: []
            )
        }
    )

    #expect(throws: SQLiteBackupRestoreError.rollbackFailed(["ClipEase.sqlite"])) {
        try backupManager.restoreDatabaseFiles(
            from: SQLiteBackupResult(
                directoryURL: backupDirectory,
                copiedFiles: ["ClipEase.sqlite", "ClipEase.sqlite-wal"]
            ),
            to: databaseURL
        )
    }
}

@Test func sqliteResetToEmptyStoreWaitsForReadersFromOtherCoordinators() throws {
    let directory = try makeSQLiteMigrationTestDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let databaseURL = directory.appendingPathComponent("ClipEase.sqlite")
    try SQLiteClipboardStore(databaseURL: databaseURL).initialize()

    let readerCoordinator = SQLiteConnectionCoordinator(databaseURL: databaseURL)
    let readerEntered = DispatchSemaphore(value: 0)
    let releaseReader = DispatchSemaphore(value: 0)
    let readerFinished = DispatchSemaphore(value: 0)
    DispatchQueue.global().async {
        try? readerCoordinator.withReader { _ in
            readerEntered.signal()
            _ = releaseReader.wait(timeout: .distantFuture)
        }
        readerFinished.signal()
    }
    #expect(readerEntered.wait(timeout: .now() + 1) == .success)

    let resetFinished = DispatchSemaphore(value: 0)
    DispatchQueue.global().async {
        try? SQLiteClipboardStore(databaseURL: databaseURL).resetToEmptyStore()
        resetFinished.signal()
    }

    #expect(resetFinished.wait(timeout: .now() + 0.1) == .timedOut)
    releaseReader.signal()
    #expect(readerFinished.wait(timeout: .now() + 1) == .success)
    #expect(resetFinished.wait(timeout: .now() + 1) == .success)

    let snapshot = try SQLiteClipboardStore(databaseURL: databaseURL).loadSnapshot()
    #expect(snapshot.items.isEmpty)
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

private struct SQLiteMigrationStoreFixture {
    let directory: URL
    let databaseURL: URL

    static func make(userVersion: Int) throws -> SQLiteMigrationStoreFixture {
        let directory = try makeSQLiteMigrationTestDirectory()
        let databaseURL = directory.appendingPathComponent("ClipEase.sqlite")
        let database = try SQLiteDatabase(url: databaseURL)
        try database.execute("PRAGMA user_version = \(userVersion)")
        database.close()
        return SQLiteMigrationStoreFixture(directory: directory, databaseURL: databaseURL)
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}

private enum SQLiteMigrationTestError: Error, Equatable {
    case injectedFailure
}

private final class SearchIndexWarmupRepository: ClipboardHistoryRepository {
    private var failuresRemaining: Int
    private(set) var backfillCallCount = 0
    private(set) var prepareCallCount = 0

    init(failuresBeforeSuccess: Int) {
        failuresRemaining = failuresBeforeSuccess
    }

    func loadSnapshot() throws -> ClipboardHistorySnapshot {
        ClipboardHistorySnapshot(items: [], groups: [])
    }

    func saveSnapshot(_ snapshot: ClipboardHistorySnapshot) throws {
        _ = snapshot
    }

    func backfillContentDigests(limit: Int) throws -> Int {
        _ = limit
        backfillCallCount += 1
        if failuresRemaining > 0 {
            failuresRemaining -= 1
            throw SQLiteMigrationTestError.injectedFailure
        }
        return 0
    }

    func prepareSearchIndex() throws {
        prepareCallCount += 1
    }
}
