import Foundation

struct PerformanceDiagnosticsRetentionPolicy: Equatable, Sendable {
    static let defaultPolicy = PerformanceDiagnosticsRetentionPolicy(
        retentionDays: 3,
        maxBytes: 5 * 1_024 * 1_024
    )

    let retentionDays: Int
    let maxBytes: Int

    init(retentionDays: Int, maxBytes: Int) {
        self.retentionDays = max(1, retentionDays)
        self.maxBytes = max(1, maxBytes)
    }
}

struct PerformanceDiagnosticsStore {
    let databaseURL: URL
    private let fileManager: FileManager
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(databaseURL: URL, fileManager: FileManager = .default) throws {
        self.databaseURL = databaseURL
        self.fileManager = fileManager
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        try initialize()
    }

    init(fileManager: FileManager = .default) throws {
        try self.init(
            databaseURL: ClipEaseStoragePaths.diagnosticsStoreURL(fileManager: fileManager),
            fileManager: fileManager
        )
    }

    func append(_ event: PerformanceDiagnosticEvent) throws {
        let database = try SQLiteDatabase(url: databaseURL)
        defer { database.close() }
        let payload = try encoder.encode(event)
        let payloadText = String(data: payload, encoding: .utf8) ?? "{}"
        try database.execute(
            """
            INSERT INTO performance_events (
                id, timestamp, name, category, duration_ms, item_count, result_count,
                payload, payload_bytes
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            values: [
                .text(event.id.uuidString),
                .double(event.timestamp.timeIntervalSince1970),
                .text(event.name),
                .text(event.category),
                .double(event.durationMS),
                .optionalInt(event.itemCount),
                .optionalInt(event.resultCount),
                .text(payloadText),
                .int(payload.count)
            ]
        )
    }

    func recentEvents(limit: Int) throws -> [PerformanceDiagnosticEvent] {
        let database = try SQLiteDatabase(url: databaseURL)
        defer { database.close() }
        let rows = try database.query(
            """
            SELECT payload
            FROM performance_events
            ORDER BY timestamp DESC, rowid DESC
            LIMIT ?
            """,
            values: [.int(max(0, limit))]
        )

        return rows.compactMap { row in
            guard let data = row.requiredText("payload").data(using: .utf8) else {
                return nil
            }
            return try? decoder.decode(PerformanceDiagnosticEvent.self, from: data)
        }
    }

    func cleanup(policy: PerformanceDiagnosticsRetentionPolicy, now: Date = Date()) throws {
        let database = try SQLiteDatabase(url: databaseURL)
        defer { database.close() }

        let cutoff = now.addingTimeInterval(TimeInterval(-policy.retentionDays * 24 * 60 * 60))
        try database.execute(
            "DELETE FROM performance_events WHERE timestamp < ?",
            values: [.double(cutoff.timeIntervalSince1970)]
        )

        while try totalPayloadBytes(in: database) > policy.maxBytes {
            let deleted = try database.queryInt(
                """
                SELECT COUNT(*)
                FROM performance_events
                WHERE rowid = (
                    SELECT rowid
                    FROM performance_events
                    ORDER BY timestamp ASC, rowid ASC
                    LIMIT 1
                )
                """
            )
            guard deleted > 0 else {
                break
            }

            try database.execute(
                """
                DELETE FROM performance_events
                WHERE rowid = (
                    SELECT rowid
                    FROM performance_events
                    ORDER BY timestamp ASC, rowid ASC
                    LIMIT 1
                )
                """
            )
        }
        try database.execute("PRAGMA wal_checkpoint(TRUNCATE)")
        try database.execute("VACUUM")
    }

    var fileSize: UInt64 {
        guard let values = try? databaseURL.resourceValues(forKeys: [.fileSizeKey]),
              let size = values.fileSize else {
            return 0
        }
        return UInt64(size)
    }

    private func initialize() throws {
        try fileManager.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let database = try SQLiteDatabase(url: databaseURL)
        defer { database.close() }
        try database.execute("PRAGMA journal_mode = WAL")
        try database.execute(
            """
            CREATE TABLE IF NOT EXISTS performance_events (
                id TEXT PRIMARY KEY,
                timestamp REAL NOT NULL,
                name TEXT NOT NULL,
                category TEXT NOT NULL,
                duration_ms REAL NOT NULL,
                item_count INTEGER,
                result_count INTEGER,
                payload TEXT NOT NULL,
                payload_bytes INTEGER NOT NULL
            )
            """
        )
        try database.execute(
            """
            CREATE INDEX IF NOT EXISTS idx_performance_events_timestamp
            ON performance_events(timestamp)
            """
        )
    }

    private func totalPayloadBytes(in database: SQLiteDatabase) throws -> Int {
        try database.queryInt("SELECT COALESCE(SUM(payload_bytes), 0) FROM performance_events")
    }
}
