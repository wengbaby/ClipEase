import Foundation

enum SQLiteSchemaMigrationPhase: String, Sendable {
    case started
    case backfillPending = "backfill_pending"
    case completed
}

enum SQLiteSchemaMigrationStateStore {
    static func ensureTable(in database: SQLiteDatabase) throws {
        try database.execute(
            """
            CREATE TABLE IF NOT EXISTS schema_migration_state (
                id INTEGER PRIMARY KEY CHECK (id = 1),
                source_version INTEGER NOT NULL,
                target_version INTEGER NOT NULL,
                phase TEXT NOT NULL,
                updated_at REAL NOT NULL
            )
            """
        )
    }

    static func begin(
        sourceVersion: Int,
        targetVersion: Int,
        in database: SQLiteDatabase
    ) throws {
        try ensureTable(in: database)
        try database.execute(
            """
            INSERT INTO schema_migration_state (
                id, source_version, target_version, phase, updated_at
            ) VALUES (1, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                source_version = excluded.source_version,
                target_version = excluded.target_version,
                phase = excluded.phase,
                updated_at = excluded.updated_at
            """,
            values: [
                .int(sourceVersion),
                .int(targetVersion),
                .text(SQLiteSchemaMigrationPhase.started.rawValue),
                .double(Date().timeIntervalSince1970)
            ]
        )
    }

    static func markBackfillPending(in database: SQLiteDatabase) throws {
        try database.execute(
            """
            UPDATE schema_migration_state
            SET phase = ?, updated_at = ?
            WHERE id = 1
            """,
            values: [
                .text(SQLiteSchemaMigrationPhase.backfillPending.rawValue),
                .double(Date().timeIntervalSince1970)
            ]
        )
    }

    static func markBackfillPendingIfStarted(in database: SQLiteDatabase) throws {
        try database.execute(
            """
            UPDATE schema_migration_state
            SET phase = ?, updated_at = ?
            WHERE id = 1 AND phase = ?
            """,
            values: [
                .text(SQLiteSchemaMigrationPhase.backfillPending.rawValue),
                .double(Date().timeIntervalSince1970),
                .text(SQLiteSchemaMigrationPhase.started.rawValue)
            ]
        )
    }

    /// Bootstraps a state row for databases that already reached the current
    /// schema before migration state was introduced. Only rows still needing
    /// a digest enter the pending phase; an already-complete database stays
    /// untouched.
    static func bootstrapIfNeeded(
        currentSchemaVersion: Int,
        in database: SQLiteDatabase
    ) throws {
        try ensureTable(in: database)
        guard try database.queryInt(
            "SELECT COUNT(*) FROM schema_migration_state WHERE id = 1"
        ) == 0 else {
            return
        }
        guard try database.queryInt(
            """
            SELECT COUNT(*)
            FROM clipboard_items
            WHERE content_hash IS NOT NULL
              AND (
                  content_digest IS NULL
                  OR digest_version != ?
                  OR length(content_digest) != 32
              )
            """,
            values: [.int(SQLiteContentDigest.currentVersion)]
        ) > 0 else {
            return
        }
        try begin(
            sourceVersion: currentSchemaVersion,
            targetVersion: currentSchemaVersion,
            in: database
        )
        try markBackfillPending(in: database)
    }

    /// Marks the migration complete only after every legacy content hash has a
    /// current-version, 32-byte digest. The legacy hash remains available for
    /// dual-read collision verification after this transition.
    static func markCompletedIfBackfillReady(
        in database: SQLiteDatabase,
        validationPassed: Bool
    ) throws {
        guard validationPassed else {
            return
        }
        try database.execute(
            """
            UPDATE schema_migration_state
            SET phase = ?, updated_at = ?
            WHERE id = 1
              AND phase = ?
              AND NOT EXISTS (
                  SELECT 1
                  FROM clipboard_items
                  WHERE content_hash IS NOT NULL
                    AND (
                        content_digest IS NULL
                        OR digest_version != ?
                        OR length(content_digest) != 32
                    )
              )
            """,
            values: [
                .text(SQLiteSchemaMigrationPhase.completed.rawValue),
                .double(Date().timeIntervalSince1970),
                .text(SQLiteSchemaMigrationPhase.backfillPending.rawValue),
                .int(SQLiteContentDigest.currentVersion)
            ]
        )
    }
}
