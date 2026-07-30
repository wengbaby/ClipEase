import Foundation
import Testing
@testable import ClipEase

@Test @MainActor
func historyStoreLoadsOrdinaryPagesThroughStableRepositoryCursor() async throws {
    let startupItems = (0..<HistoryPagingService.startupItemPageSize).map { index in
        ClipboardItem.debugText(
            "startup \(index)",
            createdAt: Date(timeIntervalSince1970: Double(5_000 - index)),
            sourceApp: .clipease
        )
    }
    let nextItem = ClipboardItem.debugText(
        "next page",
        createdAt: Date(timeIntervalSince1970: 3_000),
        sourceApp: .clipease
    )
    let repository = ProductionCursorRecordingRepository(
        snapshot: ClipboardHistorySnapshot(items: startupItems, groups: []),
        itemPage: HistoryPagingService.ItemPage(items: [nextItem])
    )
    let defaults = makeProductionCursorDefaults()
    defer { defaults.removePersistentDomain(forName: productionCursorSuiteName(defaults)) }
    let store = ClipboardHistoryStore(
        persistence: ClipboardHistoryPersistence(repository: repository),
        userDefaults: defaults,
        externalCopyFeedback: { _ in }
    )

    let task = try #require(store.loadMoreItemsIfNeeded(
        visibleUpperBound: startupItems.count - 1
    ))
    await task.value
    let startupCursor = HistoryPagingService.ItemCursor(
        item: try #require(startupItems.last)
    )

    #expect(repository.legacyPageLoadCount == 0)
    #expect(repository.itemPageLimits == [HistoryPagingService.incrementalItemPageSize])
    #expect(repository.itemPageCursors == [Optional(startupCursor)])
    #expect(store.items.contains(where: { $0.id == nextItem.id }))
    #expect(store.hasLoadedAllPersistedItems)
}

@Test @MainActor
func historyStoreSearchUsesRepositoryCursorForContinuationPages() throws {
    let first = ClipboardItem.debugText(
        "shared first",
        createdAt: Date(timeIntervalSince1970: 300),
        sourceApp: .clipease
    )
    let second = ClipboardItem.debugText(
        "shared second",
        createdAt: Date(timeIntervalSince1970: 200),
        sourceApp: .clipease
    )
    let third = ClipboardItem.debugText(
        "shared third",
        createdAt: Date(timeIntervalSince1970: 100),
        sourceApp: .clipease
    )
    let firstCursor = ClipboardSearchCursor(
        rank: 0,
        isPinned: second.isPinned,
        createdAt: second.createdAt,
        pinnedOrCreatedAt: second.pinnedAt ?? second.createdAt,
        id: second.id
    )
    let repository = ProductionCursorRecordingRepository(
        snapshot: ClipboardHistorySnapshot(items: [], groups: []),
        searchPages: [
            ClipboardSearchPage(items: [first, second], nextCursor: firstCursor),
            ClipboardSearchPage(
                items: [third],
                nextCursor: ClipboardSearchCursor(
                    rank: 0,
                    isPinned: third.isPinned,
                    createdAt: third.createdAt,
                    pinnedOrCreatedAt: third.pinnedAt ?? third.createdAt,
                    id: third.id
                )
            )
        ]
    )
    let defaults = makeProductionCursorDefaults()
    defer { defaults.removePersistentDomain(forName: productionCursorSuiteName(defaults)) }
    let store = ClipboardHistoryStore(
        persistence: ClipboardHistoryPersistence(repository: repository),
        userDefaults: defaults,
        externalCopyFeedback: { _ in }
    )

    let firstPage = store.searchItems(
        ClipboardSearchQuery(text: "shared", limit: 2, offset: 0)
    )
    let secondPage = store.searchItems(
        ClipboardSearchQuery(text: "shared", limit: 2, offset: firstPage.count)
    )

    #expect(firstPage.map(\.id) == [first.id, second.id])
    #expect(secondPage.map(\.id) == [third.id])
    #expect(repository.legacySearchCount == 0)
    #expect(repository.searchPageCursors == [nil, firstCursor])
}

@Test @MainActor
func historyStoreSearchChangeCancelsAndDiscardsInFlightCursorPage() async {
    let replacement = ClipboardItem.debugText(
        "replacement",
        createdAt: Date(timeIntervalSince1970: 100),
        sourceApp: .clipease
    )
    let repository = SearchCancellationRecordingRepository(replacement: replacement)
    let defaults = makeProductionCursorDefaults()
    defer { defaults.removePersistentDomain(forName: productionCursorSuiteName(defaults)) }
    let store = ClipboardHistoryStore(
        persistence: ClipboardHistoryPersistence(repository: repository),
        userDefaults: defaults,
        externalCopyFeedback: { _ in }
    )

    let firstSearch = Task.detached {
        store.searchItems(ClipboardSearchQuery(text: "first", limit: 50))
    }
    await repository.waitUntilFirstSearchStarts()
    #expect(repository.didStartFirstSearch)

    let replacementResult = store.searchItems(
        ClipboardSearchQuery(text: "replacement", limit: 50)
    )
    let staleResult = await firstSearch.value

    #expect(replacementResult.map(\.id) == [replacement.id])
    #expect(staleResult.isEmpty)
    #expect(repository.didObserveFirstCancellation)
}

private final class ProductionCursorRecordingRepository:
    ClipboardHistoryRepository,
    @unchecked Sendable
{
    private let lock = NSLock()
    private var snapshot: ClipboardHistorySnapshot
    private let itemPage: HistoryPagingService.ItemPage
    private var searchPages: [ClipboardSearchPage]
    private var storedItemPageLimits: [Int] = []
    private var storedItemPageCursors: [HistoryPagingService.ItemCursor?] = []
    private var storedSearchPageCursors: [ClipboardSearchCursor?] = []
    private var storedLegacyPageLoadCount = 0
    private var storedLegacySearchCount = 0

    init(
        snapshot: ClipboardHistorySnapshot,
        itemPage: HistoryPagingService.ItemPage = HistoryPagingService.ItemPage(items: []),
        searchPages: [ClipboardSearchPage] = []
    ) {
        self.snapshot = snapshot
        self.itemPage = itemPage
        self.searchPages = searchPages
    }

    var itemPageLimits: [Int] {
        lock.withLock { storedItemPageLimits }
    }

    var itemPageCursors: [HistoryPagingService.ItemCursor?] {
        lock.withLock { storedItemPageCursors }
    }

    var searchPageCursors: [ClipboardSearchCursor?] {
        lock.withLock { storedSearchPageCursors }
    }

    var legacyPageLoadCount: Int {
        lock.withLock { storedLegacyPageLoadCount }
    }

    var legacySearchCount: Int {
        lock.withLock { storedLegacySearchCount }
    }

    func loadSnapshot() throws -> ClipboardHistorySnapshot {
        lock.withLock { snapshot }
    }

    func loadSnapshot(itemLimit: Int, offset: Int) throws -> ClipboardHistorySnapshot {
        lock.withLock {
            ClipboardHistorySnapshot(
                items: Array(snapshot.items.dropFirst(offset).prefix(itemLimit)),
                groups: snapshot.groups
            )
        }
    }

    func loadItems(limit: Int, offset: Int) throws -> [ClipboardItem] {
        lock.withLock {
            storedLegacyPageLoadCount += 1
            return Array(snapshot.items.dropFirst(offset).prefix(limit))
        }
    }

    func loadItemPage(
        limit: Int,
        after cursor: HistoryPagingService.ItemCursor?
    ) throws -> HistoryPagingService.ItemPage {
        lock.withLock {
            storedItemPageLimits.append(limit)
            storedItemPageCursors.append(cursor)
            return itemPage
        }
    }

    func searchItems(_ query: ClipboardSearchQuery) throws -> [ClipboardItem] {
        lock.withLock {
            storedLegacySearchCount += 1
            return []
        }
    }

    func searchPage(
        _ query: ClipboardSearchQuery,
        after cursor: ClipboardSearchCursor?,
        cancellation: ClipboardSearchCancellationToken
    ) throws -> ClipboardSearchPage {
        try cancellation.throwIfCancelled()
        return lock.withLock {
            storedSearchPageCursors.append(cursor)
            guard !searchPages.isEmpty else {
                return ClipboardSearchPage(items: [], nextCursor: nil)
            }
            return searchPages.removeFirst()
        }
    }

    func saveSnapshot(_ snapshot: ClipboardHistorySnapshot) throws {
        lock.withLock {
            self.snapshot = snapshot
        }
    }
}

private final class SearchCancellationRecordingRepository:
    ClipboardHistoryRepository,
    @unchecked Sendable
{
    private let lock = NSLock()
    private let replacement: ClipboardItem
    private let firstSearchStartLatch = SearchCancellationStartLatch()
    private var storedDidStartFirstSearch = false
    private var storedDidObserveFirstCancellation = false

    init(replacement: ClipboardItem) {
        self.replacement = replacement
    }

    var didObserveFirstCancellation: Bool {
        lock.withLock { storedDidObserveFirstCancellation }
    }

    var didStartFirstSearch: Bool {
        lock.withLock { storedDidStartFirstSearch }
    }

    func waitUntilFirstSearchStarts() async {
        await firstSearchStartLatch.wait()
    }

    func loadSnapshot() throws -> ClipboardHistorySnapshot {
        ClipboardHistorySnapshot(items: [], groups: [])
    }

    func searchPage(
        _ query: ClipboardSearchQuery,
        after cursor: ClipboardSearchCursor?,
        cancellation: ClipboardSearchCancellationToken
    ) throws -> ClipboardSearchPage {
        if query.text == "first" {
            lock.withLock {
                storedDidStartFirstSearch = true
            }
            firstSearchStartLatch.signal()
            let cancellationSignal = DispatchSemaphore(value: 0)
            let cancellationHandlerID = cancellation.registerCancellationHandler {
                cancellationSignal.signal()
            }
            let waitResult = cancellationSignal.wait(timeout: .now() + 30)
            cancellation.unregisterCancellationHandler(cancellationHandlerID)
            lock.withLock {
                storedDidObserveFirstCancellation =
                    waitResult == .success && cancellation.isCancelled
            }
            try cancellation.throwIfCancelled()
            return ClipboardSearchPage(items: [], nextCursor: nil)
        }

        try cancellation.throwIfCancelled()
        return ClipboardSearchPage(
            items: [replacement],
            nextCursor: ClipboardSearchCursor(
                rank: 0,
                isPinned: replacement.isPinned,
                createdAt: replacement.createdAt,
                pinnedOrCreatedAt: replacement.pinnedAt ?? replacement.createdAt,
                id: replacement.id
            )
        )
    }

    func saveSnapshot(_ snapshot: ClipboardHistorySnapshot) throws {}
}

private final class SearchCancellationStartLatch: @unchecked Sendable {
    private let lock = NSLock()
    private var isSignaled = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func signal() {
        let waiters = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            guard !isSignaled else {
                return []
            }
            isSignaled = true
            defer { self.waiters.removeAll() }
            return self.waiters
        }
        waiters.forEach { $0.resume() }
    }

    func wait() async {
        if lock.withLock({ isSignaled }) {
            return
        }
        await withCheckedContinuation { continuation in
            let shouldResume = lock.withLock { () -> Bool in
                guard !isSignaled else {
                    return true
                }
                waiters.append(continuation)
                return false
            }
            if shouldResume {
                continuation.resume()
            }
        }
    }
}

private func makeProductionCursorDefaults() -> UserDefaults {
    let suiteName = "production-cursor-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.set(suiteName, forKey: "tests.suiteName")
    defaults.set(HistoryRetentionPolicy.forever.rawValue, forKey: "history.retentionPolicy")
    return defaults
}

private func productionCursorSuiteName(_ defaults: UserDefaults) -> String {
    defaults.string(forKey: "tests.suiteName")!
}
