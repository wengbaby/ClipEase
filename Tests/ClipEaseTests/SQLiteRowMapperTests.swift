import Foundation
import Testing
@testable import ClipEase

@Test func sqliteRowMapperBuildsClipboardItemWithAssetsGroupAndOCR() {
    let itemID = UUID()
    let groupID = UUID()
    let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
    let pinnedAt = Date(timeIntervalSince1970: 1_700_000_500)
    let groupedAt = Date(timeIntervalSince1970: 1_700_000_600)

    let row = SQLiteRow(values: [
        "id": .text(itemID.uuidString),
        "type": .text("link"),
        "plain_text": .text("https://example.com"),
        "url": .text("https://example.com"),
        "link_title": .text("Example"),
        "link_subtitle": .text("example.com"),
        "source_app_name": .text("Safari"),
        "source_bundle_id": .text("com.apple.Safari"),
        "source_icon_name": .text("safari"),
        "source_icon_file_name": .text("safari.png"),
        "header_color": .text("#0A84FF"),
        "created_at": .double(createdAt.timeIntervalSince1970),
        "pinned_at": .double(pinnedAt.timeIntervalSince1970),
        "is_pinned": .int(1),
        "content_hash": .text("content-hash")
    ])

    let item = SQLiteRowMapper.makeItem(
        from: row,
        id: itemID,
        assets: [
            SQLiteAssetRow(type: "image", fileName: "preview.png", width: 320, height: 180),
            SQLiteAssetRow(type: "rich_text", fileName: "content.rtfd", width: nil, height: nil)
        ],
        fileReferences: [],
        groupInfo: SQLiteGroupItemRow(groupID: groupID, createdAt: groupedAt, sortOrder: 0),
        ocrResult: SQLiteOCRResultRow(
            status: .completed,
            text: "Hello",
            emails: ["a@example.com"],
            phoneNumbers: ["123"],
            urls: ["https://example.com"],
            textRegions: [],
            updatedAt: Date(timeIntervalSince1970: 1_700_000_700)
        )
    )

    #expect(item.id == itemID)
    #expect(item.type == .link)
    #expect(item.url?.absoluteString == "https://example.com")
    #expect(item.linkTitle == "Example")
    #expect(item.imageFileName == "preview.png")
    #expect(item.imageWidth == 320)
    #expect(item.richTextFileName == "content.rtfd")
    #expect(item.imageHash == "content-hash")
    #expect(item.groupID == groupID)
    #expect(item.groupedAt == groupedAt)
    #expect(item.ocrStatus == .completed)
    #expect(item.ocrEmails == ["a@example.com"])
    #expect(item.ocrTextRegions == [])
}

@Test func sqliteRowMapperBuildsFoldedSearchTextFromRow() {
    let row = SQLiteRow(values: [
        "plain_text": .text("Résumé"),
        "url": .text("https://example.com"),
        "link_title": .text("Café"),
        "link_subtitle": .null
    ])

    #expect(SQLiteRowMapper.searchText(from: row).contains("resume"))
    #expect(SQLiteRowMapper.searchText(from: row).contains("cafe"))
}

@Test func sqliteRowMapperEscapesFTS5QueryTokens() {
    #expect(SQLiteRowMapper.escapedFTS5Query(" abc  de\"f ") == "\"abc\"* \"de\"\"f\"*")
    #expect(SQLiteRowMapper.escapedFTS5Query("   ") == "\"\"")
}

@Test func sqliteRowMapperEncodesAndDecodesOCRListsAndRegions() {
    #expect(SQLiteRowMapper.decodeList(SQLiteRowMapper.encodeList(["one", "two"])) == ["one", "two"])
    #expect(SQLiteRowMapper.decodeRegions(SQLiteRowMapper.encodeRegions([])) == [])
    #expect(SQLiteRowMapper.decodeList("not-json").isEmpty)
    #expect(SQLiteRowMapper.decodeRegions("not-json").isEmpty)
}
