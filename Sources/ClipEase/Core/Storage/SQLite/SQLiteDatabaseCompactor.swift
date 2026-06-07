enum SQLiteDatabaseCompactor {
    static func compactIfNeeded(
        database: SQLiteDatabase,
        policy: ClipboardDatabaseCompactionPolicy
    ) throws -> ClipboardDatabaseCompactionResult {
        try database.execute("PRAGMA wal_checkpoint(TRUNCATE)")
        let pageSize = try database.queryInt("PRAGMA page_size")
        let pageCount = try database.queryInt("PRAGMA page_count")
        let freelistCount = try database.queryInt("PRAGMA freelist_count")

        guard policy.shouldCompact(
            pageSize: pageSize,
            pageCount: pageCount,
            freelistCount: freelistCount
        ) else {
            return .skipped
        }

        let beforeBytes = pageSize * pageCount
        try database.execute("VACUUM")
        try database.execute("PRAGMA wal_checkpoint(TRUNCATE)")
        let afterPageSize = try database.queryInt("PRAGMA page_size")
        let afterPageCount = try database.queryInt("PRAGMA page_count")
        let afterBytes = afterPageSize * afterPageCount
        return .compacted(beforeBytes: beforeBytes, afterBytes: afterBytes)
    }
}
