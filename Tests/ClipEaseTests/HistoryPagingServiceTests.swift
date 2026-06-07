import Testing
@testable import ClipEase

@Test func historyPagingServiceMarksStartupCompleteWhenSnapshotIsShort() {
    #expect(HistoryPagingService.didLoadAllAfterStartup(itemCount: 999))
    #expect(!HistoryPagingService.didLoadAllAfterStartup(itemCount: 1_000))
}

@Test func historyPagingServiceRequestsNextPageNearVisibleEnd() {
    let state = HistoryPagingService.State(didLoadAll: false, isLoadingNextPage: false)

    #expect(HistoryPagingService.shouldLoadMoreItems(
        state: state,
        visibleUpperBound: 850,
        itemCount: 1_000,
        preloadMargin: 160
    ))
    #expect(!HistoryPagingService.shouldLoadMoreItems(
        state: state,
        visibleUpperBound: 700,
        itemCount: 1_000,
        preloadMargin: 160
    ))
    #expect(!HistoryPagingService.shouldLoadMoreItems(
        state: .init(didLoadAll: true, isLoadingNextPage: false),
        visibleUpperBound: 999,
        itemCount: 1_000,
        preloadMargin: 160
    ))
}

@Test func historyPagingServiceBuildsNextPageRequest() {
    let request = HistoryPagingService.nextPageRequest(itemCount: 250)

    #expect(request.offset == 250)
    #expect(request.limit == 1_000)
}

@Test func historyPagingServiceMergeResultIgnoresStaleOffsetAndTracksCompletion() {
    let stale = HistoryPagingService.mergeResult(
        pageCount: 100,
        requestedOffset: 90,
        currentItemCount: 100,
        limit: 1_000
    )
    let shortPage = HistoryPagingService.mergeResult(
        pageCount: 10,
        requestedOffset: 100,
        currentItemCount: 100,
        limit: 1_000
    )
    let fullPage = HistoryPagingService.mergeResult(
        pageCount: 1_000,
        requestedOffset: 100,
        currentItemCount: 100,
        limit: 1_000
    )

    #expect(stale == .stale)
    #expect(shortPage == .append(didLoadAll: true))
    #expect(fullPage == .append(didLoadAll: false))
}
