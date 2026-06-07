import Foundation
import Testing
@testable import ClipEase

@Test func sqliteItemDAORoundTripsAssetsFilesOCRAndPinnedOrder() throws {
    let fixture = try SQLiteItemDAOFixture.make()
    defer { fixture.remove() }

    let database = try SQLiteDatabase(url: fixture.databaseURL)
    defer { database.close() }
    try fixture.store.initialize()

    let older = ClipboardItem.debugText(
        "older",
        createdAt: Date(timeIntervalSince1970: 100),
        sourceApp: .clipease
    )

    var image = ClipboardItem.image(
        fileName: "image.png",
        width: 320,
        height: 180,
        hash: "image-hash",
        sourceApp: .clipease
    )
    image.createdAt = Date(timeIntervalSince1970: 200)
    image.isPinned = true
    image.pinnedAt = Date(timeIntervalSince1970: 300)
    image.ocrStatus = .completed
    image.ocrText = "recognized"
    image.ocrEmails = ["a@example.com"]
    image.ocrPhoneNumbers = ["123"]
    image.ocrURLs = ["https://example.com"]
    image.ocrUpdatedAt = Date(timeIntervalSince1970: 400)

    try SQLiteItemDAO.insert(older, in: database)
    try SQLiteItemDAO.insert(image, in: database)

    let items = try SQLiteItemDAO.loadItems(
        in: database,
        whereSQL: "clipboard_items.is_deleted = 0",
        values: [],
        orderSQL: sqliteItemDAOTestDefaultItemOrderSQL
    )

    #expect(items.map(\.id) == [image.id, older.id])
    #expect(items.first?.imageFileName == "image.png")
    #expect(items.first?.imageWidth == 320)
    #expect(items.first?.imageHash == "image-hash")
    #expect(items.first?.ocrStatus == .completed)
    #expect(items.first?.ocrText == "recognized")
    #expect(items.first?.ocrEmails == ["a@example.com"])
    #expect(items.first?.ocrPhoneNumbers == ["123"])
    #expect(items.first?.ocrURLs == ["https://example.com"])
}

@Test func sqliteItemDAORespectsOrderedIDsAndFileReferences() throws {
    let fixture = try SQLiteItemDAOFixture.make()
    defer { fixture.remove() }

    let database = try SQLiteDatabase(url: fixture.databaseURL)
    defer { database.close() }
    try fixture.store.initialize()

    let fileItemID = UUID()
    let fileReference = ClipboardFileReference(
        itemID: fileItemID,
        orderIndex: 0,
        path: "/tmp/sample.pdf",
        displayName: "sample.pdf",
        contentType: "application/pdf",
        fileSize: 1024,
        modifiedAt: Date(timeIntervalSince1970: 500),
        pathStatus: .available,
        lastCheckedAt: Date(timeIntervalSince1970: 600),
        createdAt: Date(timeIntervalSince1970: 700)
    )
    var fileItem = ClipboardItem.file(references: [fileReference], sourceApp: .clipease)
    fileItem.createdAt = Date(timeIntervalSince1970: 100)

    let textItem = ClipboardItem.debugText(
        "text",
        createdAt: Date(timeIntervalSince1970: 200),
        sourceApp: .clipease
    )

    try SQLiteItemDAO.insert(fileItem, in: database)
    try SQLiteItemDAO.insert(textItem, in: database)

    let orderedItems = try SQLiteItemDAO.loadItems(
        withOrderedIDs: [fileItem.id, textItem.id],
        orderSQL: sqliteItemDAOTestDefaultItemOrderSQL,
        in: database
    )

    #expect(orderedItems.map(\.id) == [fileItem.id, textItem.id])
    #expect(orderedItems.first?.fileReferences.first?.path == "/tmp/sample.pdf")
    #expect(orderedItems.first?.fileReferences.first?.pathStatus == .available)
    #expect(orderedItems.first?.fileReferences.first?.fileSize == 1024)
}

@Test func sqliteItemDAODeletesItemsAndItemsInGroups() throws {
    let fixture = try SQLiteItemDAOFixture.make()
    defer { fixture.remove() }

    let database = try SQLiteDatabase(url: fixture.databaseURL)
    defer { database.close() }
    try fixture.store.initialize()

    let groupID = UUID()
    let grouped = ClipboardItem.debugText(
        "grouped",
        createdAt: Date(timeIntervalSince1970: 100),
        sourceApp: .clipease
    )
    let plain = ClipboardItem.debugText(
        "plain",
        createdAt: Date(timeIntervalSince1970: 200),
        sourceApp: .clipease
    )

    try SQLiteItemDAO.insert(grouped, in: database)
    try SQLiteItemDAO.insert(plain, in: database)
    try database.execute(
        """
        INSERT INTO group_items (id, group_id, item_id, created_at, sort_order)
        VALUES (?, ?, ?, ?, ?)
        """,
        values: [
            .text(UUID().uuidString),
            .text(groupID.uuidString),
            .text(grouped.id.uuidString),
            .double(300),
            .int(0)
        ]
    )

    #expect(try SQLiteItemDAO.loadItemIDs(inGroups: [groupID], in: database) == [grouped.id])

    try SQLiteItemDAO.deleteItems(with: [plain.id], in: database)
    #expect(try database.queryInt("SELECT COUNT(*) FROM clipboard_items WHERE id = ?", values: [.text(plain.id.uuidString)]) == 0)

    try SQLiteItemDAO.deleteItems(inGroups: [groupID], in: database)
    #expect(try database.queryInt("SELECT COUNT(*) FROM clipboard_items WHERE id = ?", values: [.text(grouped.id.uuidString)]) == 0)
}

private struct SQLiteItemDAOFixture {
    let directory: URL
    let databaseURL: URL
    let store: SQLiteClipboardStore

    static func make() throws -> SQLiteItemDAOFixture {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("clipease-item-dao-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let databaseURL = directory.appendingPathComponent("ClipEase.sqlite")
        return SQLiteItemDAOFixture(
            directory: directory,
            databaseURL: databaseURL,
            store: SQLiteClipboardStore(databaseURL: databaseURL)
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}

private let sqliteItemDAOTestDefaultItemOrderSQL = """
    clipboard_items.is_pinned DESC,
    clipboard_items.created_at DESC,
    COALESCE(clipboard_items.pinned_at, clipboard_items.created_at) DESC
    """
