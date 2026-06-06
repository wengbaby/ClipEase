import Foundation
import Testing
@testable import ClipEase

private struct TestClipboardHistoryRepository: ClipboardHistoryRepository {
    let items: [ClipboardItem]

    func loadSnapshot() throws -> ClipboardHistorySnapshot {
        ClipboardHistorySnapshot(items: items, groups: [])
    }

    func saveSnapshot(_ snapshot: ClipboardHistorySnapshot) throws {}
}

@Test func searchQueryBoundsNegativeOffsetToZero() {
    let query = ClipboardSearchQuery(text: "hello", limit: 50, offset: -10)

    #expect(query.offset == 0)
}

@Test func searchQueryKeepsPositiveOffset() {
    let query = ClipboardSearchQuery(text: "hello", limit: 50, offset: 50)

    #expect(query.offset == 50)
}

@Test func defaultRepositorySearchAppliesOffsetAfterMatchingItems() throws {
    let repository = TestClipboardHistoryRepository(items: [
        .text("skip", sourceApp: .clipease),
        .text("match one", sourceApp: .clipease),
        .text("match two", sourceApp: .clipease),
        .text("match three", sourceApp: .clipease),
    ])

    let result = try repository.searchItems(ClipboardSearchQuery(text: "match", limit: 2, offset: 1))

    #expect(result.map(\.text) == ["match two", "match three"])
}

@Test func defaultRepositorySearchMatchesCardContentOnly() throws {
    let footerOnlyMatch = ClipboardItem.text(String(repeating: "x", count: 88), sourceApp: .clipease)
    let contentMatch = ClipboardItem.richText(plainText: "8899", fileName: "sample.rtfd", sourceApp: .clipease)
    let repository = TestClipboardHistoryRepository(items: [footerOnlyMatch, contentMatch])

    let result = try repository.searchItems(ClipboardSearchQuery(text: "88", limit: 10))

    #expect(result.map(\.id) == [contentMatch.id])
}

@Test func sqliteRepositorySearchMatchesCardContentOnly() throws {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("ClipEaseTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let store = SQLiteClipboardStore(databaseURL: directory.appendingPathComponent("ClipEase.sqlite"))
    let footerOnlyMatch = ClipboardItem.text(String(repeating: "x", count: 88), sourceApp: .clipease)
    let contentMatch = ClipboardItem.richText(plainText: "8899", fileName: "sample.rtfd", sourceApp: .clipease)
    try store.insertItems([footerOnlyMatch, contentMatch])

    let result = try store.searchItems(ClipboardSearchQuery(text: "88", limit: 10))

    #expect(result.map(\.id) == [contentMatch.id])
}

@Test func historySearchControllerUsesUnfilteredSourceWhenSearchIsEmpty() {
    #expect(HistorySearchController.usesUnfilteredSearchSource(
        selectedGroup: .all,
        searchText: " ",
        criteria: HistorySearchCriteria()
    ))
}

@Test func historySearchControllerSortsSelectedGroupByGroupedAt() throws {
    let groupID = UUID()
    var older = ClipboardItem.text("older", sourceApp: .clipease)
    older.groupID = groupID
    older.groupedAt = Date(timeIntervalSince1970: 100)
    var newer = ClipboardItem.text("newer", sourceApp: .clipease)
    newer.groupID = groupID
    newer.groupedAt = Date(timeIntervalSince1970: 200)

    let result = try HistorySearchController.filterItems(
        [HistoryPreviewItem(item: older), HistoryPreviewItem(item: newer)],
        selectedGroup: .group(groupID),
        searchText: "",
        criteria: HistorySearchCriteria(),
        now: Date(timeIntervalSince1970: 300)
    )

    #expect(result.map(\.id) == [newer.id, older.id])
}

@Test func searchPaginationRequestsAnotherPageWhenFilteredPageIsShort() {
    #expect(HistorySearchPaginationPolicy.shouldLoadMore(
        filteredCount: 8,
        targetCount: 20,
        repositoryResultCount: 50,
        pageSize: 50,
        canLoadMore: true
    ))
}

@Test func searchPaginationStopsWhenFilteredPageReachesTarget() {
    #expect(!HistorySearchPaginationPolicy.shouldLoadMore(
        filteredCount: 20,
        targetCount: 20,
        repositoryResultCount: 50,
        pageSize: 50,
        canLoadMore: true
    ))
}

@Test func searchPaginationStopsWhenRepositoryHasNoMoreResults() {
    #expect(!HistorySearchPaginationPolicy.shouldLoadMore(
        filteredCount: 8,
        targetCount: 20,
        repositoryResultCount: 12,
        pageSize: 50,
        canLoadMore: false
    ))
}
