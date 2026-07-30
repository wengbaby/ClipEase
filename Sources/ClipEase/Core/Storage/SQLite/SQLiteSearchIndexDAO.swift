import Foundation

struct SQLiteSearchCursor: Equatable, Sendable {
    let rank: Double?
    let isPinned: Bool
    let createdAt: Date
    let pinnedOrCreatedAt: Date
    let id: ClipboardItem.ID
}

struct SQLiteSearchIDPage: Equatable, Sendable {
    let itemIDs: [ClipboardItem.ID]
    let nextCursor: SQLiteSearchCursor?
}

enum SQLiteSearchIndexDAO {
    static func searchItemIDs(_ query: ClipboardSearchQuery, in database: SQLiteDatabase) throws -> [ClipboardItem.ID] {
        guard let statement = searchStatement(
            query,
            after: nil,
            offset: query.offset
        ) else {
            return []
        }
        let rows = try database.query(statement.sql, values: statement.values)
        return rows.compactMap { UUID(uuidString: $0.requiredText("id")) }
    }

    static func searchPage(
        _ query: ClipboardSearchQuery,
        after cursor: SQLiteSearchCursor?,
        in database: SQLiteDatabase
    ) throws -> SQLiteSearchIDPage {
        guard let statement = searchStatement(query, after: cursor, offset: 0) else {
            return SQLiteSearchIDPage(itemIDs: [], nextCursor: nil)
        }
        return page(from: try database.query(statement.sql, values: statement.values))
    }

    static func searchPageCancellable(
        _ query: ClipboardSearchQuery,
        after cursor: SQLiteSearchCursor?,
        in database: SQLiteDatabase
    ) async throws -> SQLiteSearchIDPage {
        guard let statement = searchStatement(query, after: cursor, offset: 0) else {
            return SQLiteSearchIDPage(itemIDs: [], nextCursor: nil)
        }
        let rows = try await database.queryCancellable(
            statement.sql,
            values: statement.values
        )
        return page(from: rows)
    }

    static func explainQueryPlan(
        _ query: ClipboardSearchQuery,
        after cursor: SQLiteSearchCursor?,
        in database: SQLiteDatabase
    ) throws -> [String] {
        guard let statement = searchStatement(query, after: cursor, offset: 0) else {
            return []
        }
        let rows = try database.query(
            "EXPLAIN QUERY PLAN \(statement.sql)",
            values: statement.values
        )
        return rows.map { $0.requiredText("detail") }
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

    private struct SearchStatement {
        let sql: String
        let values: [SQLiteValue]
    }

    private static func searchStatement(
        _ query: ClipboardSearchQuery,
        after cursor: SQLiteSearchCursor?,
        offset: Int
    ) -> SearchStatement? {
        let boundedLimit = max(0, query.limit)
        guard boundedLimit > 0 else {
            return nil
        }

        let rawQuery = query.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let usesFTS = !rawQuery.isEmpty
        guard usesFTS || hasDatabaseFilters(query.filters) else {
            return nil
        }

        let filter = searchFilterSQL(for: query.filters)
        var basePredicates = ["clipboard_items.is_deleted = 0"]
        var values: [SQLiteValue] = []
        let fromSQL: String
        let rankSQL: String
        if usesFTS {
            basePredicates.append("clipboard_items_fts MATCH ?")
            values.append(.text(SQLiteRowMapper.escapedFTS5Query(rawQuery)))
            fromSQL = """
                clipboard_items_fts
                INNER JOIN clipboard_items
                    ON clipboard_items.id = clipboard_items_fts.item_id
                """
            rankSQL = "clipboard_items_fts.rank"
        } else {
            fromSQL = "clipboard_items"
            rankSQL = "CAST(NULL AS REAL)"
        }
        basePredicates.append(contentsOf: filter.predicates)
        values.append(contentsOf: filter.values)

        let cursorPredicate = searchCursorPredicate(
            after: cursor,
            usesFTS: usesFTS
        )
        let orderSQL: String
        if usesFTS {
            orderSQL = """
                match_rank ASC,
                is_pinned DESC,
                created_at DESC,
                pinned_sort_at DESC,
                id DESC
                """
        } else {
            orderSQL = """
                is_pinned DESC,
                created_at DESC,
                pinned_sort_at DESC,
                id DESC
                """
        }
        values.append(contentsOf: cursorPredicate.values)
        values.append(.int(boundedLimit))
        values.append(.int(max(0, offset)))

        return SearchStatement(
            sql: """
                WITH search_candidates AS (
                    SELECT
                        clipboard_items.id AS id,
                        \(rankSQL) AS match_rank,
                        clipboard_items.is_pinned AS is_pinned,
                        clipboard_items.created_at AS created_at,
                        COALESCE(
                            clipboard_items.pinned_at,
                            clipboard_items.created_at
                        ) AS pinned_sort_at
                    FROM \(fromSQL)
                    WHERE \(basePredicates.joined(separator: "\n                      AND "))
                )
                SELECT
                    id,
                    match_rank,
                    is_pinned,
                    created_at,
                    pinned_sort_at
                FROM search_candidates
                \(cursorPredicate.sql)
                ORDER BY \(orderSQL)
                LIMIT ? OFFSET ?
                """,
            values: values
        )
    }

    private static func page(from rows: [SQLiteRow]) -> SQLiteSearchIDPage {
        let itemIDs = rows.compactMap { UUID(uuidString: $0.requiredText("id")) }
        let nextCursor = rows.last.flatMap { row -> SQLiteSearchCursor? in
            guard let id = UUID(uuidString: row.requiredText("id")) else {
                return nil
            }
            return SQLiteSearchCursor(
                rank: row.optionalDouble("match_rank"),
                isPinned: row.requiredBool("is_pinned"),
                createdAt: Date(timeIntervalSince1970: row.requiredDouble("created_at")),
                pinnedOrCreatedAt: Date(timeIntervalSince1970: row.requiredDouble("pinned_sort_at")),
                id: id
            )
        }
        return SQLiteSearchIDPage(itemIDs: itemIDs, nextCursor: nextCursor)
    }

    private static func searchCursorPredicate(
        after cursor: SQLiteSearchCursor?,
        usesFTS: Bool
    ) -> (sql: String, values: [SQLiteValue]) {
        guard let cursor else {
            return ("", [])
        }

        let pinned = cursor.isPinned ? 1 : 0
        let createdAt = cursor.createdAt.timeIntervalSince1970
        let pinnedOrCreatedAt = cursor.pinnedOrCreatedAt.timeIntervalSince1970
        let id = cursor.id.uuidString

        if usesFTS {
            guard let rank = cursor.rank else {
                return ("WHERE 0", [])
            }
            return (
                sql: """
                    WHERE (
                        match_rank > ?
                        OR (match_rank = ? AND is_pinned < ?)
                        OR (
                            match_rank = ?
                            AND is_pinned = ?
                            AND created_at < ?
                        )
                        OR (
                            match_rank = ?
                            AND is_pinned = ?
                            AND created_at = ?
                            AND pinned_sort_at < ?
                        )
                        OR (
                            match_rank = ?
                            AND is_pinned = ?
                            AND created_at = ?
                            AND pinned_sort_at = ?
                            AND id < ?
                        )
                    )
                    """,
                values: [
                    .double(rank),
                    .double(rank), .int(pinned),
                    .double(rank), .int(pinned), .double(createdAt),
                    .double(rank), .int(pinned), .double(createdAt), .double(pinnedOrCreatedAt),
                    .double(rank), .int(pinned), .double(createdAt), .double(pinnedOrCreatedAt), .text(id)
                ]
            )
        }

        guard cursor.rank == nil else {
            return ("WHERE 0", [])
        }
        return (
            sql: """
                WHERE (
                    is_pinned < ?
                    OR (
                        is_pinned = ?
                        AND created_at < ?
                    )
                    OR (
                        is_pinned = ?
                        AND created_at = ?
                        AND pinned_sort_at < ?
                    )
                    OR (
                        is_pinned = ?
                        AND created_at = ?
                        AND pinned_sort_at = ?
                        AND id < ?
                    )
                )
                """,
            values: [
                .int(pinned),
                .int(pinned), .double(createdAt),
                .int(pinned), .double(createdAt), .double(pinnedOrCreatedAt),
                .int(pinned), .double(createdAt), .double(pinnedOrCreatedAt), .text(id)
            ]
        )
    }

    private static func hasDatabaseFilters(
        _ filters: ClipboardSearchQueryFilters
    ) -> Bool {
        !filters.types.isEmpty
            || !filters.sourceAppNames.isEmpty
            || filters.requiresPinned
            || !filters.requiredGroupIDs.isEmpty
            || !filters.groupCriteria.isEmpty
    }

    private static func searchFilterSQL(
        for filters: ClipboardSearchQueryFilters
    ) -> (predicates: [String], values: [SQLiteValue]) {
        var predicates: [String] = []
        var values: [SQLiteValue] = []

        if !filters.types.isEmpty {
            let types = filters.types.map(\.rawValue).sorted()
            predicates.append("clipboard_items.type IN (\(placeholders(count: types.count)))")
            values.append(contentsOf: types.map(SQLiteValue.text))
        }

        if !filters.sourceAppNames.isEmpty {
            let sourceAppNames = filters.sourceAppNames.sorted()
            predicates.append("clipboard_items.source_app_name IN (\(placeholders(count: sourceAppNames.count)))")
            values.append(contentsOf: sourceAppNames.map(SQLiteValue.text))
        }

        if filters.requiresPinned {
            predicates.append("clipboard_items.is_pinned = 1")
        }

        if !filters.requiredGroupIDs.isEmpty {
            predicates.append(groupMembershipPredicate(alias: "required_group_items", count: filters.requiredGroupIDs.count))
            values.append(contentsOf: sortedUUIDValues(filters.requiredGroupIDs))
        }

        if !filters.groupCriteria.isEmpty {
            var groupPredicates: [String] = []
            if filters.groupCriteria.includesPinned {
                groupPredicates.append("clipboard_items.is_pinned = 1")
            }
            if !filters.groupCriteria.groupIDs.isEmpty {
                groupPredicates.append(groupMembershipPredicate(alias: "criteria_group_items", count: filters.groupCriteria.groupIDs.count))
                values.append(contentsOf: sortedUUIDValues(filters.groupCriteria.groupIDs))
            }
            predicates.append("(\(groupPredicates.joined(separator: " OR ")))")
        }

        return (predicates, values)
    }

    private static func groupMembershipPredicate(alias: String, count: Int) -> String {
        """
        EXISTS (
            SELECT 1 FROM group_items \(alias)
            WHERE \(alias).item_id = clipboard_items.id
              AND \(alias).group_id IN (\(placeholders(count: count)))
        )
        """
    }

    private static func placeholders(count: Int) -> String {
        Array(repeating: "?", count: count).joined(separator: ",")
    }

    private static func sortedUUIDValues(_ ids: Set<UUID>) -> [SQLiteValue] {
        ids.map(\.uuidString).sorted().map(SQLiteValue.text)
    }
}
