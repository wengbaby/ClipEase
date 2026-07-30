import Foundation

enum SQLiteHistoryPageQuery {
    static let orderSQL = """
        clipboard_items.is_pinned DESC,
        clipboard_items.created_at DESC,
        COALESCE(clipboard_items.pinned_at, clipboard_items.created_at) DESC,
        clipboard_items.id DESC
        """

    static func loadPage(
        after cursor: HistoryPagingService.ItemCursor?,
        limit: Int,
        in database: SQLiteDatabase
    ) throws -> HistoryPagingService.ItemPage {
        let boundedLimit = max(0, limit)
        guard boundedLimit > 0 else {
            return HistoryPagingService.ItemPage(items: [])
        }

        let predicate = predicate(after: cursor)
        let items = try SQLiteItemDAO.loadItems(
            in: database,
            whereSQL: predicate.sql,
            values: predicate.values,
            orderSQL: orderSQL,
            limit: boundedLimit
        )
        return HistoryPagingService.ItemPage(items: items)
    }

    static func explainQueryPlan(
        after cursor: HistoryPagingService.ItemCursor?,
        limit: Int,
        in database: SQLiteDatabase
    ) throws -> [String] {
        let predicate = predicate(after: cursor)
        let rows = try database.query(
            """
            EXPLAIN QUERY PLAN
            SELECT clipboard_items.id
            FROM clipboard_items
            WHERE \(predicate.sql)
            ORDER BY \(orderSQL)
            LIMIT ?
            """,
            values: predicate.values + [.int(max(0, limit))]
        )
        return rows.map { $0.requiredText("detail") }
    }

    private static func predicate(
        after cursor: HistoryPagingService.ItemCursor?
    ) -> (sql: String, values: [SQLiteValue]) {
        guard let cursor else {
            return (
                sql: "clipboard_items.is_deleted = 0",
                values: []
            )
        }

        let pinned = cursor.isPinned ? 1 : 0
        let createdAt = cursor.createdAt.timeIntervalSince1970
        let pinnedOrCreatedAt = cursor.pinnedOrCreatedAt.timeIntervalSince1970
        let id = cursor.id.uuidString
        return (
            sql: """
                clipboard_items.is_deleted = 0
                AND (
                    clipboard_items.is_pinned < ?
                    OR (
                        clipboard_items.is_pinned = ?
                        AND clipboard_items.created_at < ?
                    )
                    OR (
                        clipboard_items.is_pinned = ?
                        AND clipboard_items.created_at = ?
                        AND COALESCE(clipboard_items.pinned_at, clipboard_items.created_at) < ?
                    )
                    OR (
                        clipboard_items.is_pinned = ?
                        AND clipboard_items.created_at = ?
                        AND COALESCE(clipboard_items.pinned_at, clipboard_items.created_at) = ?
                        AND clipboard_items.id < ?
                    )
                )
                """,
            values: [
                .int(pinned),
                .int(pinned),
                .double(createdAt),
                .int(pinned),
                .double(createdAt),
                .double(pinnedOrCreatedAt),
                .int(pinned),
                .double(createdAt),
                .double(pinnedOrCreatedAt),
                .text(id)
            ]
        )
    }
}
