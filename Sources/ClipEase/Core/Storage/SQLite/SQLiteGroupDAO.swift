import Foundation

enum SQLiteGroupDAO {
    static func loadGroups(in database: SQLiteDatabase) throws -> [ClipboardGroup] {
        let rows = try database.query(
            """
            SELECT id, name, color_hex, icon_name, sort_order, created_at, updated_at
            FROM groups
            ORDER BY sort_order ASC, created_at ASC
            """
        )

        return rows.compactMap { row in
            guard let id = UUID(uuidString: row.requiredText("id")) else {
                return nil
            }

            return ClipboardGroup(
                id: id,
                name: row.requiredText("name"),
                colorHex: row.requiredText("color_hex"),
                iconName: row.requiredText("icon_name"),
                sortOrder: row.requiredInt("sort_order"),
                createdAt: Date(timeIntervalSince1970: row.requiredDouble("created_at")),
                updatedAt: Date(timeIntervalSince1970: row.requiredDouble("updated_at"))
            )
        }
    }

    static func insert(_ group: ClipboardGroup, in database: SQLiteDatabase) throws {
        try database.execute(
            """
            INSERT INTO groups (
                id, name, color_hex, icon_name, sort_order, created_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            values: values(for: group)
        )
    }

    static func upsert(_ groups: [ClipboardGroup], in database: SQLiteDatabase) throws {
        for group in groups {
            try database.execute(
                """
                INSERT OR REPLACE INTO groups (
                    id, name, color_hex, icon_name, sort_order, created_at, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                values: values(for: group)
            )
        }
    }

    static func deleteGroups(with ids: Set<ClipboardGroup.ID>, in database: SQLiteDatabase) throws {
        guard !ids.isEmpty else {
            return
        }

        let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ",")
        try database.execute(
            "DELETE FROM groups WHERE id IN (\(placeholders))",
            values: ids.map { .text($0.uuidString) }
        )
    }

    static func insertGroupItem(for item: ClipboardItem, in database: SQLiteDatabase) throws {
        guard let groupID = item.groupID else {
            return
        }

        try database.execute(
            """
            INSERT INTO group_items (
                id, group_id, item_id, created_at, sort_order
            ) VALUES (?, ?, ?, ?, ?)
            """,
            values: [
                .text(UUID().uuidString),
                .text(groupID.uuidString),
                .text(item.id.uuidString),
                .double((item.groupedAt ?? item.createdAt).timeIntervalSince1970),
                .int(0)
            ]
        )
    }

    private static func values(for group: ClipboardGroup) -> [SQLiteValue] {
        [
            .text(group.id.uuidString),
            .text(group.name),
            .text(group.colorHex),
            .text(group.iconName),
            .int(group.sortOrder),
            .double(group.createdAt.timeIntervalSince1970),
            .double(group.updatedAt.timeIntervalSince1970)
        ]
    }
}
