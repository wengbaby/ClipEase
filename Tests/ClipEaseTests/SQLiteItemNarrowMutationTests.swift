import Foundation
import Testing
@testable import ClipEase

@Test func sqliteNarrowPinMutationPreservesAssetsOCRAndFTSRow() throws {
    let fixture = try SQLiteItemMutationFixture.make()
    defer { fixture.remove() }
    let database = try fixture.openReadyDatabase()
    defer { database.close() }

    var item = ClipboardItem.image(
        fileName: "pinned-image.png",
        width: 640,
        height: 480,
        hash: "image-hash",
        sourceApp: .clipease
    )
    item.ocrStatus = .completed
    item.ocrText = "searchable OCR"
    item.ocrUpdatedAt = Date(timeIntervalSince1970: 100)
    try SQLiteItemDAO.insert(item, in: database)
    try SQLiteSearchIndexDAO.insert(item, in: database)
    let assetID = try #require(
        database.query(
            "SELECT id FROM item_assets WHERE item_id = ?",
            values: [.text(item.id.uuidString)]
        ).first?.requiredText("id")
    )
    let ftsRowID = try database.queryInt(
        "SELECT rowid FROM clipboard_items_fts WHERE item_id = ?",
        values: [.text(item.id.uuidString)]
    )

    item.isPinned = true
    item.pinnedAt = Date(timeIntervalSince1970: 200)
    try SQLiteItemDAO.updateItem(
        ClipboardHistoryItemMutation(item: item, fields: [.pin]),
        in: database
    )

    let loaded = try #require(try SQLiteItemDAO.loadItems(
        withOrderedIDs: [item.id],
        orderSQL: "clipboard_items.created_at DESC",
        in: database
    ).first)
    #expect(loaded.isPinned)
    #expect(loaded.pinnedAt == item.pinnedAt)
    #expect(loaded.ocrText == "searchable OCR")
    #expect(try database.query(
        "SELECT id FROM item_assets WHERE item_id = ?",
        values: [.text(item.id.uuidString)]
    ).first?.requiredText("id") == assetID)
    #expect(try database.queryInt(
        "SELECT rowid FROM clipboard_items_fts WHERE item_id = ?",
        values: [.text(item.id.uuidString)]
    ) == ftsRowID)
}

@Test func sqliteNarrowOCRMutationRefreshesFTSOnlyWhenSearchableFieldsChange() throws {
    let fixture = try SQLiteItemMutationFixture.make()
    defer { fixture.remove() }
    let database = try fixture.openReadyDatabase()
    defer { database.close() }

    var item = ClipboardItem.image(
        fileName: "ocr-image.png",
        width: 320,
        height: 180,
        hash: "ocr-hash",
        sourceApp: .clipease
    )
    try SQLiteItemDAO.insert(item, in: database)
    try SQLiteSearchIndexDAO.insert(item, in: database)
    try SQLiteSearchIndexDAO.insertText("sentinel", for: UUID(), in: database)
    let initialFTSRowID = try database.queryInt(
        "SELECT rowid FROM clipboard_items_fts WHERE item_id = ?",
        values: [.text(item.id.uuidString)]
    )

    item = item.updatingOCR(
        status: .completed,
        text: "recognized invoice",
        emails: ["billing@example.com"],
        phoneNumbers: [],
        urls: [],
        textRegions: [],
        updatedAt: Date(timeIntervalSince1970: 100)
    )
    try SQLiteItemDAO.updateItem(
        ClipboardHistoryItemMutation(item: item, fields: [.ocr]),
        in: database
    )
    let changedFTSRowID = try database.queryInt(
        "SELECT rowid FROM clipboard_items_fts WHERE item_id = ?",
        values: [.text(item.id.uuidString)]
    )
    #expect(changedFTSRowID != initialFTSRowID)

    var statusOnly = item
    statusOnly.ocrStatus = .processing
    statusOnly.ocrUpdatedAt = Date(timeIntervalSince1970: 200)
    try SQLiteItemDAO.updateItem(
        ClipboardHistoryItemMutation(item: statusOnly, fields: [.ocr]),
        in: database
    )
    let statusOnlyFTSRowID = try database.queryInt(
        "SELECT rowid FROM clipboard_items_fts WHERE item_id = ?",
        values: [.text(item.id.uuidString)]
    )
    #expect(statusOnlyFTSRowID == changedFTSRowID)

    try SQLiteItemDAO.updateItem(
        ClipboardHistoryItemMutation(item: statusOnly, fields: [.ocr]),
        in: database
    )
    #expect(try database.queryInt(
        "SELECT rowid FROM clipboard_items_fts WHERE item_id = ?",
        values: [.text(item.id.uuidString)]
    ) == changedFTSRowID)
}

@Test func sqliteNarrowGroupMutationSkipsAnUnchangedMembership() throws {
    let fixture = try SQLiteItemMutationFixture.make()
    defer { fixture.remove() }
    let database = try fixture.openReadyDatabase()
    defer { database.close() }

    let group = ClipboardGroup.makeDefault(name: "Work", sortOrder: 0)
    try SQLiteGroupDAO.insert(group, in: database)
    var item = ClipboardItem.text("grouped", sourceApp: .clipease)
    item.groupID = group.id
    item.groupedAt = Date(timeIntervalSince1970: 100)
    try SQLiteItemDAO.insert(item, in: database)
    try SQLiteGroupDAO.insertGroupItem(for: item, in: database)
    let membershipID = try #require(
        database.query(
            "SELECT id FROM group_items WHERE item_id = ?",
            values: [.text(item.id.uuidString)]
        ).first?.requiredText("id")
    )

    item.groupedAt = Date(timeIntervalSince1970: 200)
    try SQLiteItemDAO.updateItem(
        ClipboardHistoryItemMutation(item: item, fields: [.group]),
        in: database
    )

    #expect(try database.query(
        "SELECT id FROM group_items WHERE item_id = ?",
        values: [.text(item.id.uuidString)]
    ).first?.requiredText("id") == membershipID)

    item.groupID = nil
    item.groupedAt = nil
    try SQLiteItemDAO.updateItem(
        ClipboardHistoryItemMutation(item: item, fields: [.group]),
        in: database
    )
    #expect(try database.queryInt(
        "SELECT COUNT(*) FROM group_items WHERE item_id = ?",
        values: [.text(item.id.uuidString)]
    ) == 0)
}

@Test func sqliteNarrowMetadataMutationPreservesUnchangedAssetAndFTSRows() throws {
    let fixture = try SQLiteItemMutationFixture.make()
    defer { fixture.remove() }
    let database = try fixture.openReadyDatabase()
    defer { database.close() }

    var item = ClipboardItem.link(
        URL(string: "https://example.com/article")!,
        originalText: "https://example.com/article",
        sourceApp: .clipease
    )
    item = item.updatingLinkMetadata(
        title: "Original title",
        imageFileName: "preview.png",
        imageWidth: 640,
        imageHeight: 360,
        imageHash: "preview-hash"
    )
    try SQLiteItemDAO.insert(item, in: database)
    try SQLiteSearchIndexDAO.insert(item, in: database)
    try SQLiteSearchIndexDAO.insertText("sentinel", for: UUID(), in: database)
    let assetID = try #require(
        database.query(
            "SELECT id FROM item_assets WHERE item_id = ? AND asset_type = 'image'",
            values: [.text(item.id.uuidString)]
        ).first?.requiredText("id")
    )
    let ftsRowID = try database.queryInt(
        "SELECT rowid FROM clipboard_items_fts WHERE item_id = ?",
        values: [.text(item.id.uuidString)]
    )

    try SQLiteItemDAO.updateItem(
        ClipboardHistoryItemMutation(item: item, fields: [.metadata]),
        in: database
    )
    #expect(try database.query(
        "SELECT id FROM item_assets WHERE item_id = ? AND asset_type = 'image'",
        values: [.text(item.id.uuidString)]
    ).first?.requiredText("id") == assetID)
    #expect(try database.queryInt(
        "SELECT rowid FROM clipboard_items_fts WHERE item_id = ?",
        values: [.text(item.id.uuidString)]
    ) == ftsRowID)

    item = item.updatingLinkMetadata(title: "Updated searchable title")
    try SQLiteItemDAO.updateItem(
        ClipboardHistoryItemMutation(item: item, fields: [.metadata]),
        in: database
    )
    #expect(try database.queryInt(
        "SELECT rowid FROM clipboard_items_fts WHERE item_id = ?",
        values: [.text(item.id.uuidString)]
    ) != ftsRowID)
    #expect(try database.query(
        "SELECT id FROM item_assets WHERE item_id = ? AND asset_type = 'image'",
        values: [.text(item.id.uuidString)]
    ).first?.requiredText("id") == assetID)
}

@Test func sqliteNarrowContentMutationRefreshesFTSOnlyForSearchableChanges() throws {
    let fixture = try SQLiteItemMutationFixture.make()
    defer { fixture.remove() }
    let database = try fixture.openReadyDatabase()
    defer { database.close() }

    let original = ClipboardItem.richText(
        plainText: "same searchable text",
        fileName: "original.rtf",
        sourceApp: .clipease
    )
    try SQLiteItemDAO.insert(original, in: database)
    try SQLiteSearchIndexDAO.insert(original, in: database)
    try SQLiteSearchIndexDAO.insertText("sentinel", for: UUID(), in: database)
    let originalFTSRowID = try database.queryInt(
        "SELECT rowid FROM clipboard_items_fts WHERE item_id = ?",
        values: [.text(original.id.uuidString)]
    )

    let attachmentOnlyChange = original.updatingEditableContent(
        text: original.text,
        richTextFileUpdate: .remove
    )
    try SQLiteItemDAO.updateItem(
        ClipboardHistoryItemMutation(
            item: attachmentOnlyChange,
            fields: [.content]
        ),
        in: database
    )

    #expect(try database.queryInt(
        "SELECT rowid FROM clipboard_items_fts WHERE item_id = ?",
        values: [.text(original.id.uuidString)]
    ) == originalFTSRowID)
    #expect(try database.queryInt(
        "SELECT COUNT(*) FROM item_assets WHERE item_id = ? AND asset_type = 'rich_text'",
        values: [.text(original.id.uuidString)]
    ) == 0)

    let searchableChange = attachmentOnlyChange.updatingEditableContent(
        text: "new searchable text"
    )
    try SQLiteItemDAO.updateItem(
        ClipboardHistoryItemMutation(
            item: searchableChange,
            fields: [.content]
        ),
        in: database
    )

    #expect(try database.queryInt(
        "SELECT rowid FROM clipboard_items_fts WHERE item_id = ?",
        values: [.text(original.id.uuidString)]
    ) != originalFTSRowID)
    let row = try #require(database.query(
        """
        SELECT plain_text, content_hash, length(content_digest) AS digest_length, digest_version
        FROM clipboard_items
        WHERE id = ?
        """,
        values: [.text(original.id.uuidString)]
    ).first)
    let expectedContentHash = try #require(searchableChange.contentHash)
    #expect(row.requiredText("plain_text") == "new searchable text")
    #expect(row.requiredText("content_hash") == expectedContentHash)
    #expect(row.requiredInt("digest_length") == 32)
    #expect(row.requiredInt("digest_version") == SQLiteContentDigest.currentVersion)
}

@Test func sqliteNarrowMutationRejectsAMissingItem() throws {
    let fixture = try SQLiteItemMutationFixture.make()
    defer { fixture.remove() }
    let database = try fixture.openReadyDatabase()
    defer { database.close() }
    let missing = ClipboardItem.text("missing", sourceApp: .clipease)

    #expect(throws: SQLiteItemMutationError.self) {
        try SQLiteItemDAO.updateItem(
            ClipboardHistoryItemMutation(item: missing, fields: [.pin]),
            in: database
        )
    }
}

private struct SQLiteItemMutationFixture {
    let directory: URL
    let databaseURL: URL
    let store: SQLiteClipboardStore

    static func make() throws -> SQLiteItemMutationFixture {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("clipease-item-mutation-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let databaseURL = directory.appendingPathComponent("ClipEase.sqlite")
        return SQLiteItemMutationFixture(
            directory: directory,
            databaseURL: databaseURL,
            store: SQLiteClipboardStore(databaseURL: databaseURL)
        )
    }

    func openReadyDatabase() throws -> SQLiteDatabase {
        try store.initialize()
        return try SQLiteDatabase(url: databaseURL)
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}
