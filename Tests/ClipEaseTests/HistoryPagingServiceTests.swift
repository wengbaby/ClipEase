import Foundation
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
    #expect(request.cursor == nil)
}

@Test func historyPagingServiceBuildsStableCursorFromLastLoadedItem() {
    var item = ClipboardItem.debugText(
        "cursor",
        createdAt: Date(timeIntervalSince1970: 200),
        sourceApp: .clipease
    )
    item.isPinned = true
    item.pinnedAt = Date(timeIntervalSince1970: 300)

    let request = HistoryPagingService.nextPageRequest(
        itemCount: 250,
        lastItem: item
    )

    #expect(request.offset == 250)
    #expect(request.cursor == HistoryPagingService.ItemCursor(item: item))
    #expect(request.cursor?.isPinned == true)
    #expect(request.cursor?.createdAt == item.createdAt)
    #expect(request.cursor?.pinnedOrCreatedAt == item.pinnedAt)
    #expect(request.cursor?.id == item.id)
}

@Test func historyPagingServiceKeepsAnExistingStableCursorInTheNextRequest() {
    let item = ClipboardItem.debugText(
        "cursor",
        createdAt: Date(timeIntervalSince1970: 200),
        sourceApp: .clipease
    )
    let cursor = HistoryPagingService.ItemCursor(item: item)

    let request = HistoryPagingService.nextPageRequest(
        itemCount: 250,
        cursor: cursor
    )

    #expect(request.offset == 250)
    #expect(request.cursor == cursor)
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

@Test func historyPagingServiceMergeResultRejectsStaleCursor() {
    let currentItem = ClipboardItem.debugText(
        "current",
        createdAt: Date(timeIntervalSince1970: 200),
        sourceApp: .clipease
    )
    let requestedItem = ClipboardItem.debugText(
        "requested",
        createdAt: Date(timeIntervalSince1970: 100),
        sourceApp: .clipease
    )

    let stale = HistoryPagingService.mergeResult(
        pageCount: 10,
        requestedCursor: HistoryPagingService.ItemCursor(item: requestedItem),
        currentCursor: HistoryPagingService.ItemCursor(item: currentItem),
        limit: 1_000
    )
    let current = HistoryPagingService.mergeResult(
        pageCount: 10,
        requestedCursor: HistoryPagingService.ItemCursor(item: currentItem),
        currentCursor: HistoryPagingService.ItemCursor(item: currentItem),
        limit: 1_000
    )

    #expect(stale == .stale)
    #expect(current == .append(didLoadAll: true))
}
