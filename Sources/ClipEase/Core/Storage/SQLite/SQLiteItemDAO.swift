import Foundation

enum SQLiteItemMutationError: LocalizedError {
    case itemNotFound(ClipboardItem.ID)

    var errorDescription: String? {
        switch self {
        case .itemNotFound(let itemID):
            "SQLite clipboard item \(itemID.uuidString) does not exist."
        }
    }
}

enum SQLiteItemDAO {
    private static let queryBatchSize = 400

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

    static func loadItemIDs(
        in database: SQLiteDatabase,
        whereSQL: String,
        values: [SQLiteValue],
        orderSQL: String
    ) throws -> [UUID] {
        try database.query(
            """
            SELECT id
            FROM clipboard_items
            WHERE \(whereSQL)
            ORDER BY \(orderSQL)
            """,
            values: values
        ).compactMap { UUID(uuidString: $0.requiredText("id")) }
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

        var itemIDs: Set<ClipboardItem.ID> = []
        for batch in uuidStringBatches(ids) {
            let placeholders = placeholders(count: batch.count)
            let itemRows = try database.query(
                "SELECT item_id FROM group_items WHERE group_id IN (\(placeholders))",
                values: batch.map(SQLiteValue.text)
            )
            itemIDs.formUnion(itemRows.compactMap { UUID(uuidString: $0.requiredText("item_id")) })
        }
        return itemIDs
    }

    static func referencedAttachments(
        in candidates: ClipboardAttachmentCleanup,
        database: SQLiteDatabase
    ) throws -> ClipboardAttachmentCleanup {
        ClipboardAttachmentCleanup(
            imageFileNames: try referencedFileNames(
                assetType: "image",
                candidates: candidates.imageFileNames,
                database: database
            ),
            richTextFileNames: try referencedFileNames(
                assetType: "rich_text",
                candidates: candidates.richTextFileNames,
                database: database
            )
        )
    }

    static func attachmentCleanup(
        forItemIDs ids: Set<ClipboardItem.ID>,
        database: SQLiteDatabase
    ) throws -> ClipboardAttachmentCleanup {
        guard !ids.isEmpty else {
            return .empty
        }

        var cleanup = ClipboardAttachmentCleanup.empty
        for batch in uuidStringBatches(ids) {
            let placeholders = placeholders(count: batch.count)
            let rows = try database.query(
                """
                SELECT DISTINCT asset_type, file_name
                FROM item_assets
                WHERE item_id IN (\(placeholders))
                  AND asset_type IN ('image', 'rich_text')
                """,
                values: batch.map(SQLiteValue.text)
            )
            cleanup = cleanup.union(attachmentCleanup(from: rows))
        }
        return cleanup
    }

    static func attachmentCleanup(
        forItemsInGroups ids: Set<ClipboardGroup.ID>,
        database: SQLiteDatabase
    ) throws -> ClipboardAttachmentCleanup {
        guard !ids.isEmpty else {
            return .empty
        }

        var cleanup = ClipboardAttachmentCleanup.empty
        for batch in uuidStringBatches(ids) {
            let placeholders = placeholders(count: batch.count)
            let rows = try database.query(
                """
                SELECT DISTINCT item_assets.asset_type, item_assets.file_name
                FROM item_assets
                INNER JOIN group_items ON group_items.item_id = item_assets.item_id
                WHERE group_items.group_id IN (\(placeholders))
                  AND item_assets.asset_type IN ('image', 'rich_text')
                """,
                values: batch.map(SQLiteValue.text)
            )
            cleanup = cleanup.union(attachmentCleanup(from: rows))
        }
        return cleanup
    }

    static func allAttachmentCleanup(database: SQLiteDatabase) throws -> ClipboardAttachmentCleanup {
        let rows = try database.query(
            """
            SELECT DISTINCT asset_type, file_name
            FROM item_assets
            WHERE asset_type IN ('image', 'rich_text')
            """
        )
        return attachmentCleanup(from: rows)
    }

    static func deleteItems(with ids: Set<ClipboardItem.ID>, in database: SQLiteDatabase) throws {
        guard !ids.isEmpty else {
            return
        }

        for batch in uuidStringBatches(ids) {
            let placeholders = placeholders(count: batch.count)
            try database.execute(
                "DELETE FROM clipboard_items WHERE id IN (\(placeholders))",
                values: batch.map(SQLiteValue.text)
            )
        }
    }

    static func deleteItems(inGroups ids: Set<ClipboardGroup.ID>, in database: SQLiteDatabase) throws {
        guard !ids.isEmpty else {
            return
        }

        for batch in uuidStringBatches(ids) {
            let placeholders = placeholders(count: batch.count)
            try database.execute(
                """
                DELETE FROM clipboard_items
                WHERE id IN (
                    SELECT item_id FROM group_items WHERE group_id IN (\(placeholders))
                )
                """,
                values: batch.map(SQLiteValue.text)
            )
        }
    }

    static func updateItem(
        _ mutation: ClipboardHistoryItemMutation,
        in database: SQLiteDatabase
    ) throws {
        guard !mutation.fields.isEmpty else {
            return
        }
        guard try database.queryInt(
            "SELECT COUNT(*) FROM clipboard_items WHERE id = ? AND is_deleted = 0",
            values: [.text(mutation.item.id.uuidString)]
        ) == 1 else {
            throw SQLiteItemMutationError.itemNotFound(mutation.item.id)
        }

        var shouldRefreshSearchIndex = false
        if mutation.fields.contains(.pin) {
            try updatePin(for: mutation.item, in: database)
        }
        if mutation.fields.contains(.group) {
            try updateGroup(for: mutation.item, in: database)
        }
        if mutation.fields.contains(.content) {
            shouldRefreshSearchIndex = try updateContent(
                for: mutation.item,
                in: database
            ) || shouldRefreshSearchIndex
        }
        if mutation.fields.contains(.metadata) {
            shouldRefreshSearchIndex = try updateMetadata(
                for: mutation.item,
                in: database
            ) || shouldRefreshSearchIndex
        }
        if mutation.fields.contains(.ocr) {
            shouldRefreshSearchIndex = try updateOCR(
                for: mutation.item,
                in: database
            ) || shouldRefreshSearchIndex
        }

        if shouldRefreshSearchIndex {
            try SQLiteSearchIndexDAO.insert(mutation.item, in: database)
        }
    }

    static func insert(_ item: ClipboardItem, in database: SQLiteDatabase) throws {
        let legacyContentHash = item.contentHash
        let contentDigest = legacyContentHash.map(SQLiteContentDigest.digest(for:))
        try database.execute(
            """
            INSERT OR REPLACE INTO clipboard_items (
                id, type, plain_text, url, link_title, link_subtitle,
                source_app_name, source_bundle_id, source_icon_name, source_icon_file_name,
                header_color, created_at, updated_at, last_used_at, pinned_at, is_pinned,
                is_deleted, last_edited_at, group_sort_order, content_hash,
                content_digest, digest_version
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, NULL, NULL, ?, ?, ?)
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
                .optionalText(legacyContentHash),
                .optionalBlob(contentDigest),
                contentDigest == nil ? .null : .int(SQLiteContentDigest.currentVersion)
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

    private static func updateContent(
        for item: ClipboardItem,
        in database: SQLiteDatabase
    ) throws -> Bool {
        guard let row = try database.query(
            """
            SELECT plain_text, url, link_subtitle, content_hash, digest_version,
                   content_digest
            FROM clipboard_items
            WHERE id = ? AND is_deleted = 0
            """,
            values: [.text(item.id.uuidString)]
        ).first else {
            throw SQLiteItemMutationError.itemNotFound(item.id)
        }

        let legacyContentHash = item.contentHash
        let contentDigest = legacyContentHash.map(SQLiteContentDigest.digest(for:))
        let searchableFieldsChanged = row.requiredText("plain_text") != item.text
            || row.optionalText("url") != item.url?.absoluteString
            || row.optionalText("link_subtitle") != item.linkSubtitle
        let digestChanged = row.optionalBlob("content_digest") != contentDigest
        let coreFieldsChanged = searchableFieldsChanged
            || row.optionalText("content_hash") != legacyContentHash
            || digestChanged
            || row.optionalInt("digest_version")
                != (contentDigest == nil ? nil : SQLiteContentDigest.currentVersion)

        if coreFieldsChanged {
            let now = Date().timeIntervalSince1970
            try database.execute(
                """
                UPDATE clipboard_items
                SET plain_text = ?,
                    url = ?,
                    link_subtitle = ?,
                    content_hash = ?,
                    content_digest = ?,
                    digest_version = ?,
                    updated_at = ?,
                    last_edited_at = ?
                WHERE id = ? AND is_deleted = 0
                """,
                values: [
                    .text(item.text),
                    .optionalText(item.url?.absoluteString),
                    .optionalText(item.linkSubtitle),
                    .optionalText(legacyContentHash),
                    .optionalBlob(contentDigest),
                    contentDigest == nil ? .null : .int(SQLiteContentDigest.currentVersion),
                    .double(now),
                    .double(now),
                    .text(item.id.uuidString)
                ]
            )
        }

        let existingRichTextFileName = try database.query(
            """
            SELECT file_name
            FROM item_assets
            WHERE item_id = ? AND asset_type = 'rich_text'
            LIMIT 1
            """,
            values: [.text(item.id.uuidString)]
        ).first?.optionalText("file_name")
        if existingRichTextFileName != item.richTextFileName {
            try database.execute(
                "DELETE FROM item_assets WHERE item_id = ? AND asset_type = 'rich_text'",
                values: [.text(item.id.uuidString)]
            )
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
        }

        return searchableFieldsChanged
    }

    private static func updatePin(
        for item: ClipboardItem,
        in database: SQLiteDatabase
    ) throws {
        guard let row = try database.query(
            "SELECT is_pinned, pinned_at FROM clipboard_items WHERE id = ?",
            values: [.text(item.id.uuidString)]
        ).first else {
            throw SQLiteItemMutationError.itemNotFound(item.id)
        }
        let pinnedAt = item.pinnedAt?.timeIntervalSince1970
        guard row.requiredBool("is_pinned") != item.isPinned
                || row.optionalDouble("pinned_at") != pinnedAt else {
            return
        }
        try database.execute(
            """
            UPDATE clipboard_items
            SET is_pinned = ?, pinned_at = ?, updated_at = ?
            WHERE id = ? AND is_deleted = 0
            """,
            values: [
                .bool(item.isPinned),
                .optionalDouble(pinnedAt),
                .double(Date().timeIntervalSince1970),
                .text(item.id.uuidString)
            ]
        )
    }

    private static func updateGroup(
        for item: ClipboardItem,
        in database: SQLiteDatabase
    ) throws {
        let currentGroupID = try database.query(
            "SELECT group_id FROM group_items WHERE item_id = ? LIMIT 1",
            values: [.text(item.id.uuidString)]
        ).first?.optionalText("group_id")
        let newGroupID = item.groupID?.uuidString
        guard currentGroupID != newGroupID else {
            return
        }

        try database.execute(
            "DELETE FROM group_items WHERE item_id = ?",
            values: [.text(item.id.uuidString)]
        )
        if item.groupID != nil {
            try SQLiteGroupDAO.insertGroupItem(for: item, in: database)
        }
    }

    private static func updateMetadata(
        for item: ClipboardItem,
        in database: SQLiteDatabase
    ) throws -> Bool {
        guard let row = try database.query(
            "SELECT created_at, link_title FROM clipboard_items WHERE id = ?",
            values: [.text(item.id.uuidString)]
        ).first else {
            throw SQLiteItemMutationError.itemNotFound(item.id)
        }
        let createdAt = item.createdAt.timeIntervalSince1970
        let titleChanged = row.optionalText("link_title") != item.linkTitle
        let createdAtChanged = row.requiredDouble("created_at") != createdAt
        if titleChanged || createdAtChanged {
            try database.execute(
                """
                UPDATE clipboard_items
                SET created_at = ?, link_title = ?, updated_at = ?
                WHERE id = ? AND is_deleted = 0
                """,
                values: [
                    .double(createdAt),
                    .optionalText(item.linkTitle),
                    .double(Date().timeIntervalSince1970),
                    .text(item.id.uuidString)
                ]
            )
        }

        let assetRow = try database.query(
            """
            SELECT file_name, width, height
            FROM item_assets
            WHERE item_id = ? AND asset_type = 'image'
            LIMIT 1
            """,
            values: [.text(item.id.uuidString)]
        ).first
        let assetChanged = assetRow?.optionalText("file_name") != item.imageFileName
            || assetRow?.optionalInt("width") != item.imageWidth
            || assetRow?.optionalInt("height") != item.imageHeight
        if assetChanged {
            try database.execute(
                "DELETE FROM item_assets WHERE item_id = ? AND asset_type = 'image'",
                values: [.text(item.id.uuidString)]
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
        }
        return titleChanged
    }

    private static func updateOCR(
        for item: ClipboardItem,
        in database: SQLiteDatabase
    ) throws -> Bool {
        let encodedEmails = SQLiteRowMapper.encodeList(item.ocrEmails)
        let encodedPhoneNumbers = SQLiteRowMapper.encodeList(item.ocrPhoneNumbers)
        let encodedURLs = SQLiteRowMapper.encodeList(item.ocrURLs)
        let encodedRegions = SQLiteRowMapper.encodeRegions(item.ocrTextRegions)
        let updatedAt = item.ocrUpdatedAt?.timeIntervalSince1970
        let existing = try database.query(
            """
            SELECT status, recognized_text, emails, phone_numbers, urls, text_regions, updated_at
            FROM item_ocr_results
            WHERE item_id = ?
            """,
            values: [.text(item.id.uuidString)]
        ).first
        let searchableFieldsChanged = existing?.requiredText("recognized_text") != item.ocrText
            || existing?.requiredText("emails") != encodedEmails
            || existing?.requiredText("phone_numbers") != encodedPhoneNumbers
            || existing?.requiredText("urls") != encodedURLs
        let anyFieldChanged = searchableFieldsChanged
            || existing?.requiredText("status") != item.ocrStatus.rawValue
            || existing?.requiredText("text_regions") != encodedRegions
            || existing?.optionalDouble("updated_at") != updatedAt
        guard anyFieldChanged else {
            return false
        }

        if item.ocrStatus == .none,
           item.ocrText.isEmpty,
           item.ocrEmails.isEmpty,
           item.ocrPhoneNumbers.isEmpty,
           item.ocrURLs.isEmpty,
           item.ocrTextRegions.isEmpty {
            try database.execute(
                "DELETE FROM item_ocr_results WHERE item_id = ?",
                values: [.text(item.id.uuidString)]
            )
        } else {
            try database.execute(
                """
                INSERT INTO item_ocr_results (
                    item_id, status, recognized_text, emails, phone_numbers, urls, text_regions, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(item_id) DO UPDATE SET
                    status = excluded.status,
                    recognized_text = excluded.recognized_text,
                    emails = excluded.emails,
                    phone_numbers = excluded.phone_numbers,
                    urls = excluded.urls,
                    text_regions = excluded.text_regions,
                    updated_at = excluded.updated_at
                """,
                values: [
                    .text(item.id.uuidString),
                    .text(item.ocrStatus.rawValue),
                    .text(item.ocrText),
                    .text(encodedEmails),
                    .text(encodedPhoneNumbers),
                    .text(encodedURLs),
                    .text(encodedRegions),
                    .optionalDouble(updatedAt)
                ]
            )
        }
        return searchableFieldsChanged
    }

    static func backfillContentDigests(
        in database: SQLiteDatabase,
        limit: Int = SQLiteContentDigest.batchSize
    ) throws -> Int {
        let boundedLimit = min(max(0, limit), SQLiteContentDigest.batchSize)
        guard boundedLimit > 0 else {
            return 0
        }

        try database.execute("BEGIN IMMEDIATE TRANSACTION")
        do {
            let rows = try database.query(
                """
                SELECT id, content_hash
                FROM clipboard_items
                WHERE content_hash IS NOT NULL
                  AND (
                      content_digest IS NULL
                      OR digest_version != ?
                      OR length(content_digest) != 32
                  )
                ORDER BY rowid ASC
                LIMIT ?
                """,
                values: [.int(SQLiteContentDigest.currentVersion), .int(boundedLimit)]
            )

            for row in rows {
                let legacyContentHash = row.requiredText("content_hash")
                try database.execute(
                    """
                    UPDATE clipboard_items
                    SET content_digest = ?, digest_version = ?
                    WHERE id = ?
                      AND content_hash IS NOT NULL
                      AND (
                          content_digest IS NULL
                          OR digest_version != ?
                          OR length(content_digest) != 32
                      )
                    """,
                    values: [
                        .blob(SQLiteContentDigest.digest(for: legacyContentHash)),
                        .int(SQLiteContentDigest.currentVersion),
                        .text(row.requiredText("id")),
                        .int(SQLiteContentDigest.currentVersion)
                    ]
                )
            }

            let structurallyBackfilled = rows.count
            let remainingCapacity = boundedLimit - structurallyBackfilled
            try database.execute("COMMIT")
            if remainingCapacity > 0 {
                let repaired = try repairInvalidContentDigests(
                    in: database,
                    limit: remainingCapacity
                )
                return structurallyBackfilled + repaired.repaired
            }
            return structurallyBackfilled
        } catch {
            try? database.execute("ROLLBACK")
            throw error
        }
    }

    static func repairInvalidContentDigests(
        in database: SQLiteDatabase,
        limit: Int
    ) throws -> (repaired: Int, remainingInvalid: Bool) {
        let boundedLimit = min(max(0, limit), SQLiteContentDigest.batchSize)
        guard boundedLimit > 0 else {
            return (0, false)
        }

        var invalid: [(id: String, contentHash: String, digest: Data)] = []
        var remainingInvalid = false
        var lastRowID = 0
        scan: while true {
            let rows = try database.query(
                """
                SELECT rowid, id, content_hash, content_digest, digest_version
                FROM clipboard_items
                WHERE content_hash IS NOT NULL AND rowid > ?
                ORDER BY rowid ASC
                LIMIT ?
                """,
                values: [.int(lastRowID), .int(SQLiteContentDigest.batchSize)]
            )
            guard !rows.isEmpty else {
                break
            }

            for row in rows {
                lastRowID = row.requiredInt("rowid")
                let contentHash = row.requiredText("content_hash")
                let expectedDigest = SQLiteContentDigest.digest(for: contentHash)
                let isValid = row.optionalInt("digest_version") == SQLiteContentDigest.currentVersion
                    && row.optionalBlob("content_digest") == expectedDigest
                guard !isValid else {
                    continue
                }
                if invalid.count == boundedLimit {
                    remainingInvalid = true
                    break scan
                }
                invalid.append(
                    (id: row.requiredText("id"), contentHash: contentHash, digest: expectedDigest)
                )
            }

            if rows.count < SQLiteContentDigest.batchSize {
                break
            }
        }

        guard !invalid.isEmpty else {
            return (0, remainingInvalid)
        }

        try database.execute("BEGIN IMMEDIATE TRANSACTION")
        do {
            var repairedCount = 0
            for entry in invalid {
                try database.execute(
                    """
                    UPDATE clipboard_items
                    SET content_digest = ?, digest_version = ?
                    WHERE id = ? AND content_hash = ?
                    """,
                    values: [
                        .blob(entry.digest),
                        .int(SQLiteContentDigest.currentVersion),
                        .text(entry.id),
                        .text(entry.contentHash)
                    ]
                )

                if try database.queryInt("SELECT changes()") == 1 {
                    repairedCount += 1
                    continue
                }

                guard let row = try database.query(
                    "SELECT content_hash, content_digest, digest_version FROM clipboard_items WHERE id = ?",
                    values: [.text(entry.id)]
                ).first,
                    let currentHash = row.optionalText("content_hash") else {
                    continue
                }
                let isValid = row.optionalInt("digest_version") == SQLiteContentDigest.currentVersion
                    && row.optionalBlob("content_digest")
                        == SQLiteContentDigest.digest(for: currentHash)
                if !isValid {
                    remainingInvalid = true
                }
            }
            try database.execute("COMMIT")
            return (repairedCount, remainingInvalid)
        } catch {
            try? database.execute("ROLLBACK")
            throw error
        }
    }

    static func validateContentDigests(in database: SQLiteDatabase) throws -> Bool {
        var lastRowID = 0
        while true {
            let rows = try database.query(
                """
                SELECT rowid, content_hash, content_digest, digest_version
                FROM clipboard_items
                WHERE content_hash IS NOT NULL AND rowid > ?
                ORDER BY rowid ASC
                LIMIT ?
                """,
                values: [.int(lastRowID), .int(SQLiteContentDigest.batchSize)]
            )
            guard !rows.isEmpty else {
                return true
            }
            for row in rows {
                lastRowID = row.requiredInt("rowid")
                guard row.optionalInt("digest_version") == SQLiteContentDigest.currentVersion,
                      row.optionalBlob("content_digest")
                        == SQLiteContentDigest.digest(for: row.requiredText("content_hash")) else {
                    return false
                }
            }
            if rows.count < SQLiteContentDigest.batchSize {
                return true
            }
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

    private static func referencedFileNames(
        assetType: String,
        candidates: Set<String>,
        database: SQLiteDatabase
    ) throws -> Set<String> {
        guard !candidates.isEmpty else {
            return []
        }

        let sortedCandidates = candidates.sorted()
        var referenced: Set<String> = []
        var startIndex = 0

        while startIndex < sortedCandidates.count {
            let endIndex = min(startIndex + queryBatchSize, sortedCandidates.count)
            let batch = Array(sortedCandidates[startIndex..<endIndex])
            let placeholders = placeholders(count: batch.count)
            let rows = try database.query(
                """
                SELECT DISTINCT file_name
                FROM item_assets
                WHERE asset_type = ?
                  AND file_name IN (\(placeholders))
                """,
                values: [.text(assetType)] + batch.map(SQLiteValue.text)
            )
            referenced.formUnion(rows.map { $0.requiredText("file_name") })
            startIndex = endIndex
        }

        return referenced
    }

    private static func attachmentCleanup(from rows: [SQLiteRow]) -> ClipboardAttachmentCleanup {
        var imageFileNames: Set<String> = []
        var richTextFileNames: Set<String> = []

        for row in rows {
            switch row.requiredText("asset_type") {
            case "image":
                imageFileNames.insert(row.requiredText("file_name"))
            case "rich_text":
                richTextFileNames.insert(row.requiredText("file_name"))
            default:
                continue
            }
        }

        return ClipboardAttachmentCleanup(
            imageFileNames: imageFileNames,
            richTextFileNames: richTextFileNames
        )
    }

    private static func uuidStringBatches(_ ids: Set<UUID>) -> [[String]] {
        let sortedIDs = ids.map(\.uuidString).sorted()
        var batches: [[String]] = []
        var startIndex = 0
        while startIndex < sortedIDs.count {
            let endIndex = min(startIndex + queryBatchSize, sortedIDs.count)
            batches.append(Array(sortedIDs[startIndex..<endIndex]))
            startIndex = endIndex
        }
        return batches
    }

    private static func placeholders(count: Int) -> String {
        Array(repeating: "?", count: count).joined(separator: ",")
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
