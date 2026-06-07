import Foundation

struct HistoryPreparedSearchRequest: Sendable {
    let generation: UInt64
    let sourceItems: [HistoryPreviewItem]
    let selectedGroup: HistoryGroupSelection
    let searchText: String
    let criteria: HistorySearchCriteria
    let isSearchActive: Bool
    let trigger: String
    let usesUnfilteredSource: Bool
    let maxResultCount: Int?
    let pageSize: Int
}

struct HistorySearchCoordinatorResult: Sendable {
    let request: HistoryPreparedSearchRequest
    let filterResult: HistorySearchFilterResult
    let filterDurationMS: Double
}

@MainActor
final class HistorySearchCoordinator: ObservableObject {
    private var searchTask: Task<Void, Never>?
    private var loadMoreTask: Task<Void, Never>?
    private var generation: UInt64 = 0
    private var lastRequestSignature: HistorySearchRequestSignature?
    private(set) var loadedRepositoryResultCount = 0
    private(set) var canLoadMoreResults = false

    func cancelAll() {
        searchTask?.cancel()
        searchTask = nil
        loadMoreTask?.cancel()
        loadMoreTask = nil
    }

    func prepareSearch(
        sourceItems: [HistoryPreviewItem],
        selectedGroup: HistoryGroupSelection,
        isSearchVisible: Bool,
        searchText: String,
        criteria: HistorySearchCriteria,
        trigger: String,
        pageSize: Int
    ) -> HistoryPreparedSearchRequest? {
        searchTask?.cancel()
        generation &+= 1

        let currentGroup: HistoryGroupSelection = isSearchVisible ? .all : selectedGroup
        let isSearchActive = !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            criteria.hasActiveFilters
        let usesUnfilteredSource = HistorySearchController.usesUnfilteredSearchSource(
            selectedGroup: currentGroup,
            searchText: searchText,
            criteria: criteria
        )
        let requestSignature = HistorySearchRequestSignature(
            sourceIdentity: HistorySearchSourceIdentity(items: sourceItems),
            selectedGroup: currentGroup.storageValue,
            searchText: searchText,
            criteria: criteria
        )

        guard requestSignature != lastRequestSignature else {
            return nil
        }

        lastRequestSignature = requestSignature
        loadMoreTask?.cancel()
        loadMoreTask = nil
        loadedRepositoryResultCount = 0
        canLoadMoreResults = false

        return HistoryPreparedSearchRequest(
            generation: generation,
            sourceItems: sourceItems,
            selectedGroup: currentGroup,
            searchText: searchText,
            criteria: criteria,
            isSearchActive: isSearchActive,
            trigger: trigger,
            usesUnfilteredSource: usesUnfilteredSource,
            maxResultCount: usesUnfilteredSource ? nil : pageSize,
            pageSize: pageSize
        )
    }

    func markUnfilteredApplied() {
        searchTask = nil
        loadMoreTask = nil
        loadedRepositoryResultCount = 0
        canLoadMoreResults = false
    }

    func startSearch(
        request: HistoryPreparedSearchRequest,
        immediate: Bool,
        debounceNanoseconds: UInt64,
        repositorySearch: @escaping @Sendable (ClipboardSearchQuery) -> [ClipboardItem],
        onResult: @escaping @MainActor (HistorySearchCoordinatorResult) -> Void
    ) {
        searchTask = Task(priority: .userInitiated) {
            if !immediate {
                try? await Task.sleep(nanoseconds: debounceNanoseconds)
            }

            guard !Task.isCancelled else {
                return
            }

            PerformanceDiagnosticsService.shared.recordResourceCheckpoint("search.filter.start")

            let filterStartedAt = CFAbsoluteTimeGetCurrent()
            let repositorySearchTask = Task.detached(priority: .userInitiated) {
                repositorySearch(
                    ClipboardSearchQuery(
                        text: request.searchText,
                        limit: request.maxResultCount ?? request.pageSize
                    )
                )
            }
            let filterTask = Task.detached(priority: .userInitiated) {
                let repositoryItems = await repositorySearchTask.value
                let mergedSourceItems = Self.mergedRepositoryPreviewItems(
                    repositoryItems: repositoryItems,
                    sourceItems: request.sourceItems
                )
                let itemsToFilter = mergedSourceItems.isEmpty ? request.sourceItems : mergedSourceItems
                let filteredItems = try HistorySearchController.filterItems(
                    itemsToFilter,
                    selectedGroup: request.selectedGroup,
                    searchText: request.searchText,
                    criteria: request.criteria,
                    maxResultCount: request.maxResultCount,
                    now: Date()
                )
                return HistorySearchFilterResult(
                    items: filteredItems,
                    repositoryResultCount: repositoryItems.count,
                    canLoadMore: repositoryItems.count == request.pageSize
                )
            }

            let result: HistorySearchFilterResult
            do {
                result = try await withTaskCancellationHandler {
                    try await filterTask.value
                } onCancel: {
                    repositorySearchTask.cancel()
                    filterTask.cancel()
                }
            } catch is CancellationError {
                return
            } catch {
                return
            }

            guard !Task.isCancelled else {
                return
            }

            let filterDurationMS = (CFAbsoluteTimeGetCurrent() - filterStartedAt) * 1_000
            await MainActor.run {
                guard self.generation == request.generation else {
                    return
                }

                self.loadedRepositoryResultCount = result.repositoryResultCount
                self.canLoadMoreResults = result.canLoadMore
                onResult(HistorySearchCoordinatorResult(
                    request: request,
                    filterResult: result,
                    filterDurationMS: filterDurationMS
                ))
            }
        }
    }

    func loadMoreIfNeeded(
        visibleUpperBound: Int,
        preloadMargin: Int,
        existingItems: [HistoryPreviewItem],
        selectedGroup: HistoryGroupSelection,
        isSearchVisible: Bool,
        searchText: String,
        criteria: HistorySearchCriteria,
        pageSize: Int,
        repositorySearch: @escaping @Sendable (ClipboardSearchQuery) -> [ClipboardItem],
        onResult: @escaping @MainActor (HistorySearchFilterResult) -> Void
    ) {
        guard canLoadMoreResults,
              loadMoreTask == nil,
              visibleUpperBound + preloadMargin >= existingItems.count else {
            return
        }

        let currentGroup: HistoryGroupSelection = isSearchVisible ? .all : selectedGroup
        guard !HistorySearchController.usesUnfilteredSearchSource(
            selectedGroup: currentGroup,
            searchText: searchText,
            criteria: criteria
        ) else {
            return
        }

        let currentGeneration = generation
        let offset = loadedRepositoryResultCount
        loadMoreTask = Task(priority: .userInitiated) {
            let repositoryItems = await Task.detached(priority: .userInitiated) {
                repositorySearch(
                    ClipboardSearchQuery(
                        text: searchText,
                        limit: pageSize,
                        offset: offset
                    )
                )
            }.value

            guard !Task.isCancelled else {
                return
            }

            let filteredPage: [HistoryPreviewItem]
            do {
                filteredPage = try HistorySearchController.filterItems(
                    repositoryItems.map { HistoryPreviewItem(item: $0) },
                    selectedGroup: currentGroup,
                    searchText: searchText,
                    criteria: criteria,
                    maxResultCount: pageSize,
                    now: Date()
                )
            } catch {
                await MainActor.run {
                    self.loadMoreTask = nil
                }
                return
            }

            await MainActor.run {
                guard self.generation == currentGeneration else {
                    return
                }

                let mergedItems = Self.mergedSearchPage(
                    existingItems: existingItems,
                    filteredPage: filteredPage
                )
                let result = HistorySearchFilterResult(
                    items: mergedItems,
                    repositoryResultCount: offset + repositoryItems.count,
                    canLoadMore: repositoryItems.count == pageSize
                )
                self.loadedRepositoryResultCount = result.repositoryResultCount
                self.canLoadMoreResults = result.canLoadMore
                self.loadMoreTask = nil
                onResult(result)
            }
        }
    }

    nonisolated static func mergedRepositoryPreviewItems(
        repositoryItems: [ClipboardItem],
        sourceItems: [HistoryPreviewItem]
    ) -> [HistoryPreviewItem] {
        let sourceByID = Dictionary(uniqueKeysWithValues: sourceItems.map { ($0.id, $0) })
        return repositoryItems.map { item in
            sourceByID[item.id] ?? HistoryPreviewItem(item: item)
        }
    }

    nonisolated static func mergedSearchPage(
        existingItems: [HistoryPreviewItem],
        filteredPage: [HistoryPreviewItem]
    ) -> [HistoryPreviewItem] {
        let existingIDs = Set(existingItems.map(\.id))
        return existingItems + filteredPage.filter { !existingIDs.contains($0.id) }
    }
}
