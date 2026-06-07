import Foundation

enum SQLiteSearchIndexDAO {
    static func searchItemIDs(_ query: ClipboardSearchQuery, in database: SQLiteDatabase) throws -> [ClipboardItem.ID] {
        let matchQuery = SQLiteRowMapper.escapedFTS5Query(query.text)
        let rows = try database.query(
            """
            SELECT clipboard_items.id
            FROM clipboard_items_fts
            INNER JOIN clipboard_items ON clipboard_items.id = clipboard_items_fts.item_id
            WHERE clipboard_items.is_deleted = 0
              AND clipboard_items_fts MATCH ?
            ORDER BY rank,
                     clipboard_items.is_pinned DESC,
                     clipboard_items.created_at DESC,
                     COALESCE(clipboard_items.pinned_at, clipboard_items.created_at) DESC
            LIMIT ? OFFSET ?
            """,
            values: [.text(matchQuery), .int(query.limit), .int(query.offset)]
        )
        return rows.compactMap { UUID(uuidString: $0.requiredText("id")) }
    }

    static func ensureReady(in database: SQLiteDatabase) throws {
        try database.execute(
            """
            DELETE FROM clipboard_items_fts
            WHERE item_id NOT IN (
                SELECT id FROM clipboard_items WHERE is_deleted = 0
            )
            """
        )

        let itemCount = try database.queryInt("SELECT COUNT(*) FROM clipboard_items WHERE is_deleted = 0")
        let indexedCount = try database.queryInt("SELECT COUNT(*) FROM clipboard_items_fts")
        guard indexedCount < itemCount else {
            return
        }

        let batchLimit = 1_000
        while true {
            let rows = try database.query(
                """
                SELECT
                    id, type, plain_text, url, link_title, link_subtitle,
                    source_app_name, created_at
                FROM clipboard_items
                WHERE is_deleted = 0
                  AND id NOT IN (SELECT item_id FROM clipboard_items_fts)
                ORDER BY created_at DESC
                LIMIT ?
                """,
                values: [.int(batchLimit)]
            )
            guard !rows.isEmpty else {
                break
            }

            try database.execute("BEGIN IMMEDIATE TRANSACTION")
            do {
                for row in rows {
                    guard let id = UUID(uuidString: row.requiredText("id")) else {
                        continue
                    }

                    try insertText(SQLiteRowMapper.searchText(from: row), for: id, in: database)
                }
                try database.execute("COMMIT")
            } catch {
                try? database.execute("ROLLBACK")
                throw error
            }
        }

        try database.execute(
            """
            INSERT OR REPLACE INTO clipboard_search_index_state (key, value, updated_at)
            VALUES ('last_rebuild_count', ?, ?)
            """,
            values: [.text("\(itemCount)"), .double(Date().timeIntervalSince1970)]
        )
    }

    static func insert(_ item: ClipboardItem, in database: SQLiteDatabase) throws {
        try insertText(SQLiteRowMapper.searchText(for: item), for: item.id, in: database)
    }

    static func insertText(_ text: String, for id: ClipboardItem.ID, in database: SQLiteDatabase) throws {
        try delete(with: [id], in: database)
        try database.execute(
            "INSERT INTO clipboard_items_fts (item_id, search_text) VALUES (?, ?)",
            values: [
                .text(id.uuidString),
                .text(text)
            ]
        )
    }

    static func delete(with ids: Set<ClipboardItem.ID>, in database: SQLiteDatabase) throws {
        guard !ids.isEmpty else {
            return
        }

        let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ",")
        try database.execute(
            "DELETE FROM clipboard_items_fts WHERE item_id IN (\(placeholders))",
            values: ids.map { .text($0.uuidString) }
        )
    }
}
