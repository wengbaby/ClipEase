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
