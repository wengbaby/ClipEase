import Foundation

enum SQLiteItemDAO {
    static func loadItems(
        in database: SQLiteDatabase,
        whereSQL: String,
        values: [SQLiteValue],
        orderSQL: String,
        limit: Int? = nil,
        offset: Int = 0
    ) throws -> [ClipboardItem] {
        var queryValues = values
        var limitSQL = ""
        if let limit {
            limitSQL = "LIMIT ? OFFSET ?"
            queryValues.append(.int(max(0, limit)))
            queryValues.append(.int(max(0, offset)))
        }

        let rows = try database.query(
            """
            SELECT
                id, type, plain_text, url, link_title, link_subtitle,
                source_app_name, source_bundle_id, source_icon_name, source_icon_file_name,
                header_color, created_at, pinned_at, is_pinned, content_hash
            FROM clipboard_items
            WHERE \(whereSQL)
            ORDER BY \(orderSQL)
            \(limitSQL)
            """,
            values: queryValues
        )
        return try makeItems(from: rows, in: database)
    }

    static func loadItems(
        withOrderedIDs ids: [UUID],
        orderSQL: String,
        in database: SQLiteDatabase
    ) throws -> [ClipboardItem] {
        guard !ids.isEmpty else {
            return []
        }

        let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ",")
        let items = try loadItems(
            in: database,
            whereSQL: "clipboard_items.id IN (\(placeholders))",
            values: ids.map { .text($0.uuidString) },
            orderSQL: orderSQL
        )
        let orderByID = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($0.element, $0.offset) })
        return items.sorted {
            (orderByID[$0.id] ?? Int.max) < (orderByID[$1.id] ?? Int.max)
        }
    }

    static func loadItemIDs(inGroups ids: Set<ClipboardGroup.ID>, in database: SQLiteDatabase) throws -> Set<ClipboardItem.ID> {
        guard !ids.isEmpty else {
            return []
        }

        let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ",")
        let itemRows = try database.query(
            "SELECT item_id FROM group_items WHERE group_id IN (\(placeholders))",
            values: ids.map { .text($0.uuidString) }
        )
        return Set(itemRows.compactMap { UUID(uuidString: $0.requiredText("item_id")) })
    }

    static func deleteItems(with ids: Set<ClipboardItem.ID>, in database: SQLiteDatabase) throws {
        guard !ids.isEmpty else {
            return
        }

        let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ",")
        try database.execute(
            "DELETE FROM clipboard_items WHERE id IN (\(placeholders))",
            values: ids.map { .text($0.uuidString) }
        )
    }

    static func deleteItems(inGroups ids: Set<ClipboardGroup.ID>, in database: SQLiteDatabase) throws {
        guard !ids.isEmpty else {
            return
        }

        let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ",")
        try database.execute(
            """
            DELETE FROM clipboard_items
            WHERE id IN (
                SELECT item_id FROM group_items WHERE group_id IN (\(placeholders))
            )
            """,
            values: ids.map { .text($0.uuidString) }
        )
    }

    static func insert(_ item: ClipboardItem, in database: SQLiteDatabase) throws {
        try database.execute(
            """
            INSERT OR REPLACE INTO clipboard_items (
                id, type, plain_text, url, link_title, link_subtitle,
                source_app_name, source_bundle_id, source_icon_name, source_icon_file_name,
                header_color, created_at, updated_at, last_used_at, pinned_at, is_pinned,
                is_deleted, last_edited_at, group_sort_order, content_hash
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, NULL, NULL, ?)
            """,
            values: [
                .text(item.id.uuidString),
                .text(item.type.rawValue),
                .text(item.text),
                .optionalText(item.url?.absoluteString),
                .optionalText(item.linkTitle),
                .optionalText(item.linkSubtitle),
                .text(item.sourceAppName),
                .optionalText(item.sourceBundleID),
                .text(item.iconName),
                .optionalText(item.iconFileName),
                .text(item.headerColorHex),
                .double(item.createdAt.timeIntervalSince1970),
                .double(item.createdAt.timeIntervalSince1970),
                .null,
                .optionalDouble(item.pinnedAt?.timeIntervalSince1970),
                .bool(item.isPinned),
                .optionalText(item.contentHash)
            ]
        )

        if let imageFileName = item.imageFileName {
            try insertAsset(
                itemID: item.id,
                type: "image",
                fileName: imageFileName,
                width: item.imageWidth,
                height: item.imageHeight,
                createdAt: item.createdAt,
                in: database
            )
        }

        if let richTextFileName = item.richTextFileName {
            try insertAsset(
                itemID: item.id,
                type: "rich_text",
                fileName: richTextFileName,
                width: nil,
                height: nil,
                createdAt: item.createdAt,
                in: database
            )
        }

        for fileReference in item.fileReferences {
            try insertFileReference(fileReference, itemID: item.id, in: database)
        }

        if item.ocrStatus != .none || !item.ocrText.isEmpty {
            try insertOCRResult(item, in: database)
        }
    }

    private static func makeItems(from rows: [SQLiteRow], in database: SQLiteDatabase) throws -> [ClipboardItem] {
        let ids = rows.compactMap { UUID(uuidString: $0.requiredText("id")) }
        let idSet = Set(ids)
        let assetsByItemID = try loadAssetsByItemID(for: idSet, in: database)
        let fileReferencesByItemID = try loadFileReferencesByItemID(for: idSet, in: database)
        let ocrResultsByItemID = try loadOCRResultsByItemID(for: idSet, in: database)
        let groupedItems = try loadGroupedItems(for: idSet, in: database)

        var items: [ClipboardItem] = []
        items.reserveCapacity(rows.count)
        for row in rows {
            guard let id = UUID(uuidString: row.requiredText("id")) else {
                continue
            }

            items.append(
                SQLiteRowMapper.makeItem(
                    from: row,
                    id: id,
                    assets: assetsByItemID[id] ?? [],
                    fileReferences: fileReferencesByItemID[id] ?? [],
                    groupInfo: groupedItems[id],
                    ocrResult: ocrResultsByItemID[id]
                )
            )
        }

        return items
    }

    private static func loadAssetsByItemID(for ids: Set<UUID>, in database: SQLiteDatabase) throws -> [UUID: [SQLiteAssetRow]] {
        guard !ids.isEmpty else {
            return [:]
        }

        let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ",")
        let rows = try database.query(
            """
            SELECT item_id, asset_type, file_name, width, height
            FROM item_assets
            WHERE item_id IN (\(placeholders))
            ORDER BY created_at ASC
            """,
            values: ids.map { .text($0.uuidString) }
        )

        var assetsByItemID: [UUID: [SQLiteAssetRow]] = [:]
        for row in rows {
            guard let itemID = UUID(uuidString: row.requiredText("item_id")) else {
                continue
            }

            assetsByItemID[itemID, default: []].append(
                SQLiteAssetRow(
                    type: row.requiredText("asset_type"),
                    fileName: row.requiredText("file_name"),
                    width: row.optionalInt("width"),
                    height: row.optionalInt("height")
                )
            )
        }

        return assetsByItemID
    }

    private static func loadFileReferencesByItemID(
        for ids: Set<UUID>,
        in database: SQLiteDatabase
    ) throws -> [UUID: [ClipboardFileReference]] {
        guard !ids.isEmpty else {
            return [:]
        }

        let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ",")
        let rows = try database.query(
            """
            SELECT
                id, item_id, display_order, file_path, file_name, file_extension,
                uti_or_content_type, byte_size, modified_at, is_directory, is_alias,
                path_status, last_checked_at, created_at
            FROM clipboard_item_files
            WHERE item_id IN (\(placeholders))
            ORDER BY item_id ASC, display_order ASC, created_at ASC
            """,
            values: ids.map { .text($0.uuidString) }
        )

        var referencesByItemID: [UUID: [ClipboardFileReference]] = [:]
        for row in rows {
            guard let id = UUID(uuidString: row.requiredText("id")),
                  let itemID = UUID(uuidString: row.requiredText("item_id")) else {
                continue
            }

            referencesByItemID[itemID, default: []].append(
                ClipboardFileReference(
                    id: id,
                    itemID: itemID,
                    orderIndex: row.requiredInt("display_order"),
                    path: row.requiredText("file_path"),
                    displayName: row.requiredText("file_name"),
                    fileExtension: row.optionalText("file_extension"),
                    contentType: row.optionalText("uti_or_content_type"),
                    fileSize: row.optionalInt("byte_size"),
                    modifiedAt: row.optionalDouble("modified_at").map(Date.init(timeIntervalSince1970:)),
                    isDirectory: row.requiredBool("is_directory"),
                    isAlias: row.requiredBool("is_alias"),
                    pathStatus: ClipboardFilePathStatus(rawValue: row.requiredText("path_status")) ?? .unknown,
                    lastCheckedAt: row.optionalDouble("last_checked_at").map(Date.init(timeIntervalSince1970:)),
                    createdAt: Date(timeIntervalSince1970: row.requiredDouble("created_at"))
                )
            )
        }

        return referencesByItemID
    }

    private static func loadGroupedItems(for ids: Set<UUID>, in database: SQLiteDatabase) throws -> [UUID: SQLiteGroupItemRow] {
        guard !ids.isEmpty else {
            return [:]
        }

        let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ",")
        let rows = try database.query(
            """
            SELECT group_id, item_id, created_at, sort_order
            FROM group_items
            WHERE item_id IN (\(placeholders))
            ORDER BY created_at DESC
            """,
            values: ids.map { .text($0.uuidString) }
        )

        var groupedItems: [UUID: SQLiteGroupItemRow] = [:]
        for row in rows {
            guard let itemID = UUID(uuidString: row.requiredText("item_id")),
                  let groupID = UUID(uuidString: row.requiredText("group_id")) else {
                continue
            }

            groupedItems[itemID] = SQLiteGroupItemRow(
                groupID: groupID,
                createdAt: Date(timeIntervalSince1970: row.requiredDouble("created_at")),
                sortOrder: row.requiredInt("sort_order")
            )
        }

        return groupedItems
    }

    private static func loadOCRResultsByItemID(for ids: Set<UUID>, in database: SQLiteDatabase) throws -> [UUID: SQLiteOCRResultRow] {
        guard !ids.isEmpty else {
            return [:]
        }

        let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ",")
        let rows = try database.query(
            """
            SELECT
                item_id, status, recognized_text, emails, phone_numbers,
                urls, text_regions, updated_at
            FROM item_ocr_results
            WHERE item_id IN (\(placeholders))
            """,
            values: ids.map { .text($0.uuidString) }
        )

        var results: [UUID: SQLiteOCRResultRow] = [:]
        results.reserveCapacity(rows.count)
        for row in rows {
            guard let itemID = UUID(uuidString: row.requiredText("item_id")) else {
                continue
            }

            results[itemID] = SQLiteOCRResultRow(
                status: ClipboardOCRStatus(rawValue: row.requiredText("status")) ?? .none,
                text: row.requiredText("recognized_text"),
                emails: SQLiteRowMapper.decodeList(row.requiredText("emails")),
                phoneNumbers: SQLiteRowMapper.decodeList(row.requiredText("phone_numbers")),
                urls: SQLiteRowMapper.decodeList(row.requiredText("urls")),
                textRegions: SQLiteRowMapper.decodeRegions(row.optionalText("text_regions") ?? ""),
                updatedAt: row.optionalDouble("updated_at").map(Date.init(timeIntervalSince1970:))
            )
        }

        return results
    }

    private static func insertOCRResult(_ item: ClipboardItem, in database: SQLiteDatabase) throws {
        try database.execute(
            """
            INSERT INTO item_ocr_results (
                item_id, status, recognized_text, emails, phone_numbers, urls, text_regions, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """,
            values: [
                .text(item.id.uuidString),
                .text(item.ocrStatus.rawValue),
                .text(item.ocrText),
                .text(SQLiteRowMapper.encodeList(item.ocrEmails)),
                .text(SQLiteRowMapper.encodeList(item.ocrPhoneNumbers)),
                .text(SQLiteRowMapper.encodeList(item.ocrURLs)),
                .text(SQLiteRowMapper.encodeRegions(item.ocrTextRegions)),
                .optionalDouble(item.ocrUpdatedAt?.timeIntervalSince1970)
            ]
        )
    }

    private static func insertFileReference(
        _ fileReference: ClipboardFileReference,
        itemID: UUID,
        in database: SQLiteDatabase
    ) throws {
        try database.execute(
            """
            INSERT INTO clipboard_item_files (
                id, item_id, display_order, file_path, file_name, file_extension,
                uti_or_content_type, byte_size, modified_at, is_directory, is_alias,
                path_status, last_checked_at, created_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            values: [
                .text(fileReference.id.uuidString),
                .text(itemID.uuidString),
                .int(fileReference.orderIndex),
                .text(fileReference.path),
                .text(fileReference.displayName),
                .optionalText(fileReference.fileExtension),
                .optionalText(fileReference.contentType),
                .optionalInt(fileReference.fileSize),
                .optionalDouble(fileReference.modifiedAt?.timeIntervalSince1970),
                .bool(fileReference.isDirectory),
                .bool(fileReference.isAlias),
                .text(fileReference.pathStatus.rawValue),
                .optionalDouble(fileReference.lastCheckedAt?.timeIntervalSince1970),
                .double(fileReference.createdAt.timeIntervalSince1970)
            ]
        )
    }

    private static func insertAsset(
        itemID: UUID,
        type: String,
        fileName: String,
        width: Int?,
        height: Int?,
        createdAt: Date,
        in database: SQLiteDatabase
    ) throws {
        try database.execute(
            """
            INSERT INTO item_assets (
                id, item_id, asset_type, file_name, original_file_name,
                width, height, byte_size, created_at
            ) VALUES (?, ?, ?, ?, NULL, ?, ?, NULL, ?)
            """,
            values: [
                .text(UUID().uuidString),
                .text(itemID.uuidString),
                .text(type),
                .text(fileName),
                .optionalInt(width),
                .optionalInt(height),
                .double(createdAt.timeIntervalSince1970)
            ]
        )
    }
}
