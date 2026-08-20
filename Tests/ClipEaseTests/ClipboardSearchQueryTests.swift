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

@Test func defaultRepositorySearchAppliesStableFiltersBeforeOffset() throws {
    let targetApp = SourceAppInfo(name: "Target", bundleID: "com.example.target", iconName: "app.fill", iconFileName: nil, headerColorHex: "#2E8CFF")
    let otherApp = SourceAppInfo(name: "Other", bundleID: "com.example.other", iconName: "app.fill", iconFileName: nil, headerColorHex: "#8E8E93")
    let groupID = UUID()
    var firstMatch = ClipboardItem.link(URL(string: "https://example.com/first")!, originalText: "shared first", sourceApp: targetApp)
    firstMatch.isPinned = true
    firstMatch.groupID = groupID
    firstMatch.createdAt = Date(timeIntervalSince1970: 200)
    var secondMatch = ClipboardItem.link(URL(string: "https://example.com/second")!, originalText: "shared second", sourceApp: targetApp)
    secondMatch.isPinned = true
    secondMatch.groupID = groupID
    secondMatch.createdAt = Date(timeIntervalSince1970: 100)
    var wrongType = ClipboardItem.text("shared wrong type", sourceApp: targetApp)
    wrongType.isPinned = true
    wrongType.groupID = groupID
    var wrongSource = ClipboardItem.link(URL(string: "https://example.com/source")!, originalText: "shared wrong source", sourceApp: otherApp)
    wrongSource.isPinned = true
    wrongSource.groupID = groupID
    var wrongPinned = ClipboardItem.link(URL(string: "https://example.com/pinned")!, originalText: "shared wrong pinned", sourceApp: targetApp)
    wrongPinned.groupID = groupID
    var wrongGroup = ClipboardItem.link(URL(string: "https://example.com/group")!, originalText: "shared wrong group", sourceApp: targetApp)
    wrongGroup.isPinned = true

    let repository = TestClipboardHistoryRepository(items: [
        wrongType,
        firstMatch,
        wrongSource,
        wrongPinned,
        wrongGroup,
        secondMatch
    ])
    let query = ClipboardSearchQuery(
        text: "shared",
        limit: 1,
        offset: 1,
        filters: ClipboardSearchQueryFilters(
            types: [.link],
            sourceAppNames: [targetApp.name],
            requiresPinned: true,
            requiredGroupIDs: [groupID]
        )
    )

    let result = try repository.searchItems(query)

    #expect(result.map(\.id) == [secondMatch.id])
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

@Test func sqliteRepositorySearchAppliesStableFiltersBeforeOffset() throws {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("ClipEaseTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let targetApp = SourceAppInfo(name: "Target", bundleID: "com.example.target", iconName: "app.fill", iconFileName: nil, headerColorHex: "#2E8CFF")
    let otherApp = SourceAppInfo(name: "Other", bundleID: "com.example.other", iconName: "app.fill", iconFileName: nil, headerColorHex: "#8E8E93")
    let group = ClipboardGroup(
        id: UUID(),
        name: "Project",
        colorHex: "#2E8CFF",
        iconName: "folder",
        sortOrder: 0,
        createdAt: Date(),
        updatedAt: Date()
    )
    var firstMatch = ClipboardItem.link(URL(string: "https://example.com/first")!, originalText: "shared first", sourceApp: targetApp)
    firstMatch.isPinned = true
    firstMatch.groupID = group.id
    firstMatch.createdAt = Date(timeIntervalSince1970: 200)
    var secondMatch = ClipboardItem.link(URL(string: "https://example.com/second")!, originalText: "shared second", sourceApp: targetApp)
    secondMatch.isPinned = true
    secondMatch.groupID = group.id
    secondMatch.createdAt = Date(timeIntervalSince1970: 100)
    var wrongType = ClipboardItem.text("shared wrong type", sourceApp: targetApp)
    wrongType.isPinned = true
    wrongType.groupID = group.id
    var wrongSource = ClipboardItem.link(URL(string: "https://example.com/source")!, originalText: "shared wrong source", sourceApp: otherApp)
    wrongSource.isPinned = true
    wrongSource.groupID = group.id
    var wrongPinned = ClipboardItem.link(URL(string: "https://example.com/pinned")!, originalText: "shared wrong pinned", sourceApp: targetApp)
    wrongPinned.groupID = group.id
    var wrongGroup = ClipboardItem.link(URL(string: "https://example.com/group")!, originalText: "shared wrong group", sourceApp: targetApp)
    wrongGroup.isPinned = true

    let store = SQLiteClipboardStore(databaseURL: directory.appendingPathComponent("ClipEase.sqlite"))
    try store.replaceAllItems(
        with: [wrongType, firstMatch, wrongSource, wrongPinned, wrongGroup, secondMatch],
        groups: [group]
    )
    let query = ClipboardSearchQuery(
        text: "shared",
        limit: 1,
        offset: 1,
        filters: ClipboardSearchQueryFilters(
            types: [.link],
            sourceAppNames: [targetApp.name],
            requiresPinned: true,
            requiredGroupIDs: [group.id]
        )
    )

    let result = try store.searchItems(query)

    #expect(result.map(\.id) == [secondMatch.id])
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

@Test func historySearchTokensFollowUserAddedOrder() {
    var criteria = HistorySearchCriteria()
    criteria.sourceAppNames.insert("Safari")
    criteria.types.insert(.image)
    criteria.dateRanges.insert(.last7Days)
    criteria.tokenOrder = [
        .sourceApp("Safari"),
        .date(.last7Days),
        .type(.image)
    ]

    let tokens = HistorySearchToken.tokens(
        criteria: criteria,
        groups: [],
        sourceAppIconFileNameByName: ["Safari": "safari.png"]
    )

    #expect(tokens.first?.iconFileName == "safari.png")
    #expect(tokens.map(\.kind) == [
        .sourceApp("Safari"),
        .date(.last7Days),
        .type(.image)
    ])
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
