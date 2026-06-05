import Testing
@testable import ClipEase

@Test func historyDataPagesRemainLargerThanRenderWindow() {
    #expect(ClipboardHistoryStore.startupItemPageSize == 1_000)
    #expect(ClipboardHistoryStore.incrementalItemPageSize == 1_000)
}
