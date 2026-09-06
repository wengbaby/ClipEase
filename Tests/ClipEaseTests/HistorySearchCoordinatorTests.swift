import Foundation
import Testing
@testable import ClipEase

@MainActor
@Test func searchCoordinatorSkipsDuplicatePreparedRequest() {
    let coordinator = HistorySearchCoordinator()
    let items = [
        HistoryPreviewItem(item: .text("alpha", sourceApp: .clipease))
    ]

    let first = coordinator.prepareSearch(
        sourceItems: items,
        selectedGroup: .all,
        isSearchVisible: true,
        searchText: "alpha",
        criteria: HistorySearchCriteria(),
        trigger: "typing",
        pageSize: 50
    )
    let second = coordinator.prepareSearch(
        sourceItems: items,
        selectedGroup: .all,
        isSearchVisible: true,
        searchText: "alpha",
        criteria: HistorySearchCriteria(),
        trigger: "typing",
        pageSize: 50
    )

    #expect(first != nil)
    #expect(second == nil)
}

@Test func searchCoordinatorPrefersExistingPreviewItemsWhenMergingRepositoryResults() {
    let existing = HistoryPreviewItem(
        id: UUID(),
        type: .text,
        kind: "文本",
        time: "现在",
        iconName: "text.alignleft",
        headerColor: .blue,
        preview: "existing preview",
        footer: "16 个字符"
    )
    let repositoryItem = ClipboardItem(
        id: existing.id,
        type: .text,
        text: "repository preview",
        url: nil,
        linkTitle: nil,
        linkSubtitle: nil,
        imageFileName: nil,
        imageWidth: nil,
        imageHeight: nil,
        imageHash: nil,
        richTextFileName: nil,
        fileReferences: [],
        createdAt: Date(),
        sourceAppName: SourceAppInfo.clipease.name,
        sourceBundleID: SourceAppInfo.clipease.bundleID,
        iconName: SourceAppInfo.clipease.iconName,
        iconFileName: SourceAppInfo.clipease.iconFileName,
        headerColorHex: SourceAppInfo.clipease.headerColorHex,
        isPinned: false,
        pinnedAt: nil,
        groupID: nil,
        groupedAt: nil
    )

    let result = HistorySearchCoordinator.mergedRepositoryPreviewItems(
        repositoryItems: [repositoryItem],
        sourceItems: [existing]
    )

    #expect(result.map(\.preview) == ["existing preview"])
}

@Test func searchCoordinatorMergesLoadedSearchPageWithoutDuplicates() {
    let first = HistoryPreviewItem(item: .text("first", sourceApp: .clipease))
    let second = HistoryPreviewItem(item: .text("second", sourceApp: .clipease))
    let third = HistoryPreviewItem(item: .text("third", sourceApp: .clipease))

    let result = HistorySearchCoordinator.mergedSearchPage(
        existingItems: [first, second],
        filteredPage: [second, third]
    )

    #expect(result.map(\.id) == [first.id, second.id, third.id])
}

@MainActor
@Test func searchCoordinatorKeepsTheTwentyFirstResultActionable() async throws {
    let coordinator = HistorySearchCoordinator()
    let repositoryItems = (0..<51).map { index in
        ClipboardItem.debugText(
            "shared \(index)",
            createdAt: Date(timeIntervalSince1970: Double(100 - index)),
            sourceApp: .clipease
        )
    }
    let request = try #require(coordinator.prepareSearch(
        sourceItems: [],
        selectedGroup: .all,
        isSearchVisible: true,
        searchText: "shared",
        criteria: HistorySearchCriteria(),
        trigger: "typing",
        pageSize: 50,
        targetResultCount: 20
    ))
    var initialResult: HistorySearchFilterResult?

    let task = coordinator.startSearch(
        request: request,
        immediate: true,
        debounceNanoseconds: 0,
        repositorySearch: { query in Array(repositoryItems[query.offset..<min(query.offset + query.limit, repositoryItems.count)]) },
        onResult: { result in initialResult = result.filterResult }
    )
    await task.value

    let firstPage = try #require(initialResult)
    #expect(firstPage.items.count == 50)
    let twentyFirst = firstPage.items[20]
    #expect(firstPage.sourceItem(with: twentyFirst.id)?.id == twentyFirst.id)
    var loadedResult: HistorySearchFilterResult?
    let pendingLoadMoreTask = coordinator.loadMoreIfNeeded(
        visibleUpperBound: 50,
        preloadMargin: 12,
        existingItems: firstPage.items,
        existingSourceItems: Array(firstPage.sourceItemsByID.values),
        selectedGroup: .all,
        isSearchVisible: true,
        searchText: "shared",
        criteria: HistorySearchCriteria(),
        pageSize: 50,
        repositorySearch: { query in Array(repositoryItems[query.offset..<min(query.offset + query.limit, repositoryItems.count)]) },
        onResult: { loadedResult = $0 }
    )
    let loadMoreTask = try #require(pendingLoadMoreTask)
    await loadMoreTask.value

    let loadedItems = try #require(loadedResult?.items)
    #expect(loadedItems.count == 51)
    let fiftyFirst = loadedItems[50]
    #expect(loadedResult?.sourceItem(with: fiftyFirst.id)?.id == fiftyFirst.id)
}

@MainActor
@Test func searchCoordinatorDoesNotApplyCanceledDebouncedSearch() async throws {
    let coordinator = HistorySearchCoordinator()
    let items = [
        HistoryPreviewItem(item: .text("alpha", sourceApp: .clipease))
    ]
    var appliedResultCount = 0

    let firstRequest = try #require(coordinator.prepareSearch(
        sourceItems: items,
        selectedGroup: .all,
        isSearchVisible: true,
        searchText: "alpha",
        criteria: HistorySearchCriteria(),
        trigger: "typing",
        pageSize: 50
    ))
    coordinator.startSearch(
        request: firstRequest,
        immediate: false,
        debounceNanoseconds: 200_000_000,
        repositorySearch: { _ in [] },
        onResult: { _ in
            appliedResultCount += 1
        }
    )

    _ = coordinator.prepareSearch(
        sourceItems: items,
        selectedGroup: .all,
        isSearchVisible: true,
        searchText: "beta",
        criteria: HistorySearchCriteria(),
        trigger: "typing",
        pageSize: 50
    )

    try await Task.sleep(nanoseconds: 300_000_000)
    #expect(appliedResultCount == 0)
}

@MainActor
@Test func searchCoordinatorDoesNotApplyCanceledLoadMoreResults() async throws {
    let coordinator = HistorySearchCoordinator()
    let first = HistoryPreviewItem(item: .text("item one", sourceApp: .clipease))
    let secondItem = ClipboardItem.text("item two", sourceApp: .clipease)
    var initialSearchApplied = false
    var loadMoreAppliedCount = 0

    let request = try #require(coordinator.prepareSearch(
        sourceItems: [first],
        selectedGroup: .all,
        isSearchVisible: true,
        searchText: "item",
        criteria: HistorySearchCriteria(),
        trigger: "typing",
        pageSize: 1
    ))
    let initialSearchTask = coordinator.startSearch(
        request: request,
        immediate: true,
        debounceNanoseconds: 0,
        repositorySearch: { _ in
            [ClipboardItem.text("item one", sourceApp: .clipease)]
        },
        onResult: { _ in
            initialSearchApplied = true
        }
    )
    await initialSearchTask.value
    #expect(initialSearchApplied)

    let loadMoreGate = DispatchSemaphore(value: 0)
    let pendingLoadMoreTask = coordinator.loadMoreIfNeeded(
        visibleUpperBound: 1,
        preloadMargin: 0,
        existingItems: [first],
        selectedGroup: .all,
        isSearchVisible: true,
        searchText: "item",
        criteria: HistorySearchCriteria(),
        pageSize: 1,
        repositorySearch: { _ in
            loadMoreGate.wait()
            return [secondItem]
        },
        onResult: { _ in
            loadMoreAppliedCount += 1
        }
    )
    let loadMoreTask = try #require(pendingLoadMoreTask)

    _ = coordinator.prepareSearch(
        sourceItems: [first],
        selectedGroup: .all,
        isSearchVisible: true,
        searchText: "different",
        criteria: HistorySearchCriteria(),
        trigger: "typing",
        pageSize: 1
    )
    loadMoreGate.signal()

    await loadMoreTask.value
    #expect(loadMoreAppliedCount == 0)
}

@MainActor
@Test func searchCoordinatorDoesNotReapplyDeletedItemFromCanceledLoadMoreSnapshot() async throws {
    let coordinator = HistorySearchCoordinator()
    let first = ClipboardItem.text("item one", sourceApp: .clipease)
    let second = ClipboardItem.text("item two", sourceApp: .clipease)
    let request = try #require(coordinator.prepareSearch(
        sourceItems: [],
        selectedGroup: .all,
        isSearchVisible: true,
        searchText: "item",
        criteria: HistorySearchCriteria(),
        trigger: "typing",
        pageSize: 1,
        targetResultCount: 1
    ))
    var initialResult: HistorySearchFilterResult?
    let initialTask = coordinator.startSearch(
        request: request,
        immediate: true,
        debounceNanoseconds: 0,
        repositorySearch: { _ in [first] },
        onResult: { initialResult = $0.filterResult }
    )
    await initialTask.value

    let firstPage = try #require(initialResult)
    let loadMoreGate = DispatchSemaphore(value: 0)
    var loadedResult: HistorySearchFilterResult?
    let pendingTask = coordinator.loadMoreIfNeeded(
        visibleUpperBound: 1,
        preloadMargin: 0,
        existingItems: firstPage.items,
        existingSourceItems: [first],
        selectedGroup: .all,
        isSearchVisible: true,
        searchText: "item",
        criteria: HistorySearchCriteria(),
        pageSize: 1,
        repositorySearch: { _ in
            loadMoreGate.wait()
            return [second]
        },
        onResult: { loadedResult = $0 }
    )
    let loadMoreTask = try #require(pendingTask)

    coordinator.cancelPendingLoadMore()
    loadMoreGate.signal()
    await loadMoreTask.value

    #expect(loadedResult == nil)
}

@MainActor
@Test func searchCoordinatorFillsInitialFilteredSearchPageBeforeApplying() async throws {
    let coordinator = HistorySearchCoordinator()
    let targetApp = SourceAppInfo(name: "Target", bundleID: "com.example.target", iconName: "app.fill", iconFileName: nil, headerColorHex: "#2E8CFF")
    let otherApp = SourceAppInfo(name: "Other", bundleID: "com.example.other", iconName: "app.fill", iconFileName: nil, headerColorHex: "#8E8E93")
    var criteria = HistorySearchCriteria()
    criteria.sourceAppNames.insert(targetApp.name)

    let request = try #require(coordinator.prepareSearch(
        sourceItems: [],
        selectedGroup: .all,
        isSearchVisible: true,
        searchText: "shared",
        criteria: criteria,
        trigger: "typing",
        pageSize: 2,
        targetResultCount: 2
    ))

    let queryRecorder = SearchQueryRecorder()
    var appliedResult: HistorySearchFilterResult?
    let searchTask = coordinator.startSearch(
        request: request,
        immediate: true,
        debounceNanoseconds: 0,
        repositorySearch: { query in
            queryRecorder.append(query)
            switch query.offset {
            case 0:
                return [
                    ClipboardItem.text("shared first miss", sourceApp: otherApp),
                    ClipboardItem.text("shared first hit", sourceApp: targetApp)
                ]
            case 2:
                return [
                    ClipboardItem.text("shared second hit", sourceApp: targetApp)
                ]
            default:
                return []
            }
        },
        onResult: { result in
            appliedResult = result.filterResult
        }
    )

    await searchTask.value
    #expect(appliedResult != nil)

    #expect(queryRecorder.queries.map(\.offset) == [0, 2])
    #expect(appliedResult?.items.map(\.sourceAppName) == [targetApp.name, targetApp.name])
    #expect(appliedResult?.repositoryResultCount == 3)
    #expect(appliedResult?.canLoadMore == false)
}

@MainActor
@Test func searchCoordinatorPushesStableFiltersIntoRepositoryQuery() async throws {
    let coordinator = HistorySearchCoordinator()
    let groupID = UUID()
    let targetApp = SourceAppInfo(name: "Target", bundleID: "com.example.target", iconName: "app.fill", iconFileName: nil, headerColorHex: "#2E8CFF")
    var criteria = HistorySearchCriteria()
    criteria.types.insert(.image)
    criteria.sourceAppNames.insert(targetApp.name)
    criteria.groups.insert(.pinned)

    let request = try #require(coordinator.prepareSearch(
        sourceItems: [],
        selectedGroup: .group(groupID),
        isSearchVisible: false,
        searchText: "shared",
        criteria: criteria,
        trigger: "typing",
        pageSize: 20,
        targetResultCount: 20
    ))

    let queryRecorder = SearchQueryRecorder()
    var appliedResult: HistorySearchFilterResult?
    let searchTask = coordinator.startSearch(
        request: request,
        immediate: true,
        debounceNanoseconds: 0,
        repositorySearch: { query in
            queryRecorder.append(query)
            return []
        },
        onResult: { result in
            appliedResult = result.filterResult
        }
    )

    await searchTask.value
    #expect(appliedResult != nil)
    let query = try #require(queryRecorder.queries.first)
    #expect(query.filters.types == [.image])
    #expect(query.filters.sourceAppNames == [targetApp.name])
    #expect(query.filters.requiredGroupIDs == [groupID])
    #expect(query.filters.groupCriteria.includesPinned)
    #expect(query.filters.groupCriteria.groupIDs.isEmpty)
}

private final class SearchQueryRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storedQueries: [ClipboardSearchQuery] = []

    var queries: [ClipboardSearchQuery] {
        lock.lock()
        defer { lock.unlock() }
        return storedQueries
    }

    func append(_ query: ClipboardSearchQuery) {
        lock.lock()
        defer { lock.unlock() }
        storedQueries.append(query)
    }
}
