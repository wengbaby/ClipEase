import Foundation
import Testing
@testable import ClipEase

@Test func sqliteHistoryKeysetPaginationStaysStableWhenANewerItemArrives() throws {
    let fixture = try SQLiteStablePaginationFixture.make()
    defer { fixture.remove() }

    let timestamp = Date(timeIntervalSince1970: 1_000)
    let originalItems = (0..<5).map { index in
        ClipboardItem.debugText(
            "original \(index)",
            createdAt: timestamp,
            sourceApp: .clipease
        )
    }
    try fixture.store.insertItems(originalItems)

    let firstPage = try fixture.store.loadItemPage(limit: 2, after: nil)
    let newerItem = ClipboardItem.debugText(
        "newer",
        createdAt: timestamp.addingTimeInterval(10),
        sourceApp: .clipease
    )
    try fixture.store.insertItems([newerItem])

    let secondPage = try fixture.store.loadItemPage(
        limit: 2,
        after: firstPage.nextCursor
    )
    let thirdPage = try fixture.store.loadItemPage(
        limit: 2,
        after: secondPage.nextCursor
    )
    let loadedIDs = (firstPage.items + secondPage.items + thirdPage.items).map(\.id)

    #expect(loadedIDs.count == originalItems.count)
    #expect(Set(loadedIDs).count == originalItems.count)
    #expect(Set(loadedIDs) == Set(originalItems.map(\.id)))
    #expect(!loadedIDs.contains(newerItem.id))
    #expect(thirdPage.items.count == 1)
}

@Test func sqliteEmptyTextSearchFiltersTheWholeDatabaseWithoutFTS() throws {
    let fixture = try SQLiteStablePaginationFixture.make()
    defer { fixture.remove() }

    var pinned = ClipboardItem.debugText(
        "pinned",
        createdAt: Date(timeIntervalSince1970: 200),
        sourceApp: .clipease
    )
    pinned.isPinned = true
    pinned.pinnedAt = Date(timeIntervalSince1970: 300)
    let unpinned = ClipboardItem.debugText(
        "unpinned",
        createdAt: Date(timeIntervalSince1970: 100),
        sourceApp: .clipease
    )
    try fixture.store.insertItems([unpinned, pinned])

    let page = try fixture.store.searchPage(
        ClipboardSearchQuery(
            text: "   ",
            limit: 10,
            filters: ClipboardSearchQueryFilters(requiresPinned: true)
        ),
        after: nil
    )
    let compatibilityResults = try fixture.store.searchItems(
        ClipboardSearchQuery(
            text: "\n",
            limit: 10,
            filters: ClipboardSearchQueryFilters(requiresPinned: true)
        )
    )

    #expect(page.items.map(\.id) == [pinned.id])
    #expect(page.nextCursor?.rank == nil)
    #expect(compatibilityResults.map(\.id) == [pinned.id])
}

@Test func sqliteFTSKeysetCursorCoversEqualRankRowsExactlyOnce() throws {
    let fixture = try SQLiteStablePaginationFixture.make()
    defer { fixture.remove() }

    let timestamp = Date(timeIntervalSince1970: 1_000)
    let items = (0..<5).map { index in
        ClipboardItem.debugText(
            "shared token \(index)",
            createdAt: timestamp,
            sourceApp: .clipease
        )
    }
    try fixture.store.insertItems(items)

    let query = ClipboardSearchQuery(text: "shared", limit: 2)
    let firstPage = try fixture.store.searchPage(query, after: nil)
    let secondPage = try fixture.store.searchPage(query, after: firstPage.nextCursor)
    let thirdPage = try fixture.store.searchPage(query, after: secondPage.nextCursor)
    let loadedIDs = (firstPage.items + secondPage.items + thirdPage.items).map(\.id)

    #expect(firstPage.nextCursor?.rank != nil)
    #expect(loadedIDs.count == items.count)
    #expect(Set(loadedIDs).count == items.count)
    #expect(Set(loadedIDs) == Set(items.map(\.id)))
}

@Test func sqliteProductionHistoryAndFTSQueriesHaveMeasuredPlans() throws {
    let fixture = try SQLiteStablePaginationFixture.make()
    defer { fixture.remove() }
    try fixture.store.initialize()

    let database = try SQLiteDatabase(url: fixture.databaseURL)
    defer { database.close() }

    let item = ClipboardItem.debugText(
        "plan token",
        createdAt: Date(timeIntervalSince1970: 100),
        sourceApp: .clipease
    )
    try SQLiteItemDAO.insert(item, in: database)
    try SQLiteSearchIndexDAO.insert(item, in: database)

    let historyPlan = try SQLiteHistoryPageQuery.explainQueryPlan(
        after: nil,
        limit: 50,
        in: database
    )
    let ftsPlan = try SQLiteSearchIndexDAO.explainQueryPlan(
        ClipboardSearchQuery(text: "plan", limit: 50),
        after: nil,
        in: database
    )

    #expect(historyPlan.contains { $0.contains("idx_clipboard_items_live_order") })
    #expect(ftsPlan.contains { $0.localizedCaseInsensitiveContains("VIRTUAL TABLE INDEX") })
}

@Test func sqlitePagedSearchUsesReadOnlyReaderOnReadOnlyDatabase() throws {
    let fixture = try SQLiteStablePaginationFixture.make()
    defer { fixture.remove() }

    let item = ClipboardItem.debugText(
        "read only page",
        createdAt: Date(timeIntervalSince1970: 100),
        sourceApp: .clipease
    )
    try fixture.store.insertItems([item])
    try FileManager.default.setAttributes(
        [.posixPermissions: NSNumber(value: 0o444)],
        ofItemAtPath: fixture.databaseURL.path
    )
    try FileManager.default.setAttributes(
        [.posixPermissions: NSNumber(value: 0o555)],
        ofItemAtPath: fixture.directory.path
    )
    defer {
        try? FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0o755)],
            ofItemAtPath: fixture.directory.path
        )
        try? FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0o644)],
            ofItemAtPath: fixture.databaseURL.path
        )
    }

    let page = try fixture.store.loadItemPage(limit: 1, after: nil)
    #expect(page.items.map(\.id) == [item.id])
    #expect(fixture.store.coordinatedReaderConnectionsAreReadOnlyForTesting)
}

@Test func sqliteSnapshotReadsUseTheReadOnlyReaderPool() throws {
    let fixture = try SQLiteStablePaginationFixture.make()
    defer { fixture.remove() }

    let item = ClipboardItem.debugText(
        "read only snapshot",
        createdAt: Date(timeIntervalSince1970: 100),
        sourceApp: .clipease
    )
    try fixture.store.insertItems([item])

    let snapshot = try fixture.store.loadSnapshot(itemLimit: 1, offset: 0)

    #expect(snapshot.items.map(\.id) == [item.id])
    #expect(fixture.store.coordinatedReaderConnectionsAreReadOnlyForTesting)
}

private struct SQLiteStablePaginationFixture {
    let directory: URL
    let databaseURL: URL
    let store: SQLiteClipboardStore

    static func make() throws -> SQLiteStablePaginationFixture {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("clipease-stable-pagination-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let databaseURL = directory.appendingPathComponent("ClipEase.sqlite")
        return SQLiteStablePaginationFixture(
            directory: directory,
            databaseURL: databaseURL,
            store: SQLiteClipboardStore(databaseURL: databaseURL)
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}
