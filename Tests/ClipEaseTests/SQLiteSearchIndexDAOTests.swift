import Foundation
import Testing
@testable import ClipEase

@Test func sqliteSearchIndexDAOFindsIDsUsingExistingSortAndPagination() throws {
    let fixture = try SQLiteSearchIndexDAOFixture.make()
    defer { fixture.remove() }

    let database = try SQLiteDatabase(url: fixture.databaseURL)
    defer { database.close() }
    try fixture.store.initialize()

    var older = ClipboardItem.debugText(
        "match shared",
        createdAt: Date(timeIntervalSince1970: 100),
        sourceApp: .clipease
    )
    var newer = ClipboardItem.debugText(
        "match shared",
        createdAt: Date(timeIntervalSince1970: 200),
        sourceApp: .clipease
    )
    newer.isPinned = true
    newer.pinnedAt = Date(timeIntervalSince1970: 300)
    older.isPinned = false

    try SQLiteItemDAO.insert(older, in: database)
    try SQLiteSearchIndexDAO.insert(older, in: database)
    try SQLiteItemDAO.insert(newer, in: database)
    try SQLiteSearchIndexDAO.insert(newer, in: database)

    let firstPage = try SQLiteSearchIndexDAO.searchItemIDs(
        ClipboardSearchQuery(text: "match", limit: 1, offset: 0),
        in: database
    )
    let secondPage = try SQLiteSearchIndexDAO.searchItemIDs(
        ClipboardSearchQuery(text: "match", limit: 1, offset: 1),
        in: database
    )

    #expect(firstPage == [newer.id])
    #expect(secondPage == [older.id])
}

@Test func sqliteSearchIndexDAODeletesExistingIndexRows() throws {
    let fixture = try SQLiteSearchIndexDAOFixture.make()
    defer { fixture.remove() }

    let database = try SQLiteDatabase(url: fixture.databaseURL)
    defer { database.close() }
    try fixture.store.initialize()

    let item = ClipboardItem.debugText(
        "delete token",
        createdAt: Date(timeIntervalSince1970: 100),
        sourceApp: .clipease
    )

    try SQLiteItemDAO.insert(item, in: database)
    try SQLiteSearchIndexDAO.insert(item, in: database)
    #expect(try SQLiteSearchIndexDAO.searchItemIDs(ClipboardSearchQuery(text: "delete", limit: 10), in: database) == [item.id])

    try SQLiteSearchIndexDAO.delete(with: [item.id], in: database)

    #expect(try SQLiteSearchIndexDAO.searchItemIDs(ClipboardSearchQuery(text: "delete", limit: 10), in: database).isEmpty)
}

@Test func sqliteSearchIndexDAOEnsureReadyIndexesMissingRowsAndPrunesDeletedRows() throws {
    let fixture = try SQLiteSearchIndexDAOFixture.make()
    defer { fixture.remove() }

    let database = try SQLiteDatabase(url: fixture.databaseURL)
    defer { database.close() }
    try fixture.store.initialize()

    let live = ClipboardItem.debugText(
        "live token",
        createdAt: Date(timeIntervalSince1970: 100),
        sourceApp: .clipease
    )
    let deleted = ClipboardItem.debugText(
        "deleted token",
        createdAt: Date(timeIntervalSince1970: 200),
        sourceApp: .clipease
    )

    try SQLiteItemDAO.insert(live, in: database)
    try SQLiteItemDAO.insert(deleted, in: database)
    try SQLiteSearchIndexDAO.insertText("deleted token", for: deleted.id, in: database)
    try database.execute(
        "UPDATE clipboard_items SET is_deleted = 1 WHERE id = ?",
        values: [.text(deleted.id.uuidString)]
    )

    try SQLiteSearchIndexDAO.ensureReady(in: database)

    #expect(try SQLiteSearchIndexDAO.searchItemIDs(ClipboardSearchQuery(text: "live", limit: 10), in: database) == [live.id])
    #expect(try SQLiteSearchIndexDAO.searchItemIDs(ClipboardSearchQuery(text: "deleted", limit: 10), in: database).isEmpty)
    #expect(try database.queryInt("SELECT COUNT(*) FROM clipboard_search_index_state WHERE key = 'last_rebuild_count'") == 1)
}

@Test func sqliteSearchIndexDAOKeysetTailPlanHasNoCandidateMaterialization() throws {
    let fixture = try SQLiteSearchIndexDAOFixture.make()
    defer { fixture.remove() }

    let database = try SQLiteDatabase(url: fixture.databaseURL)
    defer { database.close() }
    try fixture.store.initialize()

    let item = ClipboardItem.debugText(
        "tail plan token",
        createdAt: Date(timeIntervalSince1970: 100),
        sourceApp: .clipease
    )
    try SQLiteItemDAO.insert(item, in: database)
    try SQLiteSearchIndexDAO.insert(item, in: database)

    let firstPage = try SQLiteSearchIndexDAO.searchPage(
        ClipboardSearchQuery(text: "tail", limit: 1),
        after: nil,
        in: database
    )
    let plan = try SQLiteSearchIndexDAO.explainQueryPlan(
        ClipboardSearchQuery(text: "tail", limit: 50),
        after: firstPage.nextCursor,
        in: database
    )
    #expect(!plan.contains { $0.localizedCaseInsensitiveContains("MATERIALIZE search_candidates") }, "\(plan)")
    #expect(!plan.contains { $0.localizedCaseInsensitiveContains("CO-ROUTINE search_candidates") }, "\(plan)")
}

@Test func sqliteSearchIndexDAOCompatibilityPagesUseStableIDTieBreaker() throws {
    let fixture = try SQLiteSearchIndexDAOFixture.make()
    defer { fixture.remove() }

    let database = try SQLiteDatabase(url: fixture.databaseURL)
    defer { database.close() }
    try fixture.store.initialize()

    let timestamp = Date(timeIntervalSince1970: 500)
    let first = ClipboardItem.debugText(
        "same rank token",
        createdAt: timestamp,
        sourceApp: .clipease
    )
    let second = ClipboardItem.debugText(
        "same rank token",
        createdAt: timestamp,
        sourceApp: .clipease
    )
    try SQLiteItemDAO.insert(second, in: database)
    try SQLiteSearchIndexDAO.insert(second, in: database)
    try SQLiteItemDAO.insert(first, in: database)
    try SQLiteSearchIndexDAO.insert(first, in: database)

    let expected = [first.id, second.id].sorted { $0.uuidString > $1.uuidString }
    let firstPage = try SQLiteSearchIndexDAO.searchItemIDs(
        ClipboardSearchQuery(text: "same rank", limit: 1, offset: 0),
        in: database
    )
    let secondPage = try SQLiteSearchIndexDAO.searchItemIDs(
        ClipboardSearchQuery(text: "same rank", limit: 1, offset: 1),
        in: database
    )

    #expect(firstPage == [expected[0]])
    #expect(secondPage == [expected[1]])
}

private struct SQLiteSearchIndexDAOFixture {
    let directory: URL
    let databaseURL: URL
    let store: SQLiteClipboardStore

    static func make() throws -> SQLiteSearchIndexDAOFixture {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("clipease-search-index-dao-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let databaseURL = directory.appendingPathComponent("ClipEase.sqlite")
        return SQLiteSearchIndexDAOFixture(
            directory: directory,
            databaseURL: databaseURL,
            store: SQLiteClipboardStore(databaseURL: databaseURL)
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}
