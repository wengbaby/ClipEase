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
    let targetResultCount: Int?
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
        pageSize: Int,
        targetResultCount: Int? = nil
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
            maxResultCount: usesUnfilteredSource ? nil : (targetResultCount ?? pageSize),
            pageSize: pageSize,
            targetResultCount: targetResultCount
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
            let filterTask = Task.detached(priority: .userInitiated) {
                try Self.searchAndFilterInitialResults(
                    request: request,
                    repositorySearch: repositorySearch
                )
            }

            let result: HistorySearchFilterResult
            do {
                result = try await withTaskCancellationHandler {
                    try await filterTask.value
                } onCancel: {
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

    nonisolated private static func searchAndFilterInitialResults(
        request: HistoryPreparedSearchRequest,
        repositorySearch: @escaping @Sendable (ClipboardSearchQuery) -> [ClipboardItem]
    ) throws -> HistorySearchFilterResult {
        let targetResultCount = request.targetResultCount ?? request.maxResultCount ?? request.pageSize
        var repositoryItems: [ClipboardItem] = []
        var filteredItems: [HistoryPreviewItem] = []
        var repositoryResultCount = 0
        var canLoadMore = false
        var offset = 0

        repeat {
            try Task.checkCancellation()
            let page = repositorySearch(
                ClipboardSearchQuery(
                    text: request.searchText,
                    limit: request.pageSize,
                    offset: offset,
                    filters: request.repositoryFilters
                )
            )
            try Task.checkCancellation()

            repositoryItems.append(contentsOf: page)
            repositoryResultCount += page.count
            offset += page.count

            let mergedSourceItems = mergedRepositoryPreviewItems(
                repositoryItems: repositoryItems,
                sourceItems: request.sourceItems
            )
            let itemsToFilter = mergedSourceItems.isEmpty ? request.sourceItems : mergedSourceItems
            filteredItems = try HistorySearchController.filterItems(
                itemsToFilter,
                selectedGroup: request.selectedGroup,
                searchText: request.searchText,
                criteria: request.criteria,
                maxResultCount: request.maxResultCount,
                now: Date()
            )
            canLoadMore = page.count == request.pageSize
        } while HistorySearchPaginationPolicy.shouldLoadMore(
            filteredCount: filteredItems.count,
            targetCount: targetResultCount,
            repositoryResultCount: repositoryResultCount,
            pageSize: request.pageSize,
            canLoadMore: canLoadMore
        )

        return HistorySearchFilterResult(
            items: filteredItems,
            repositoryResultCount: repositoryResultCount,
            canLoadMore: canLoadMore
        )
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
                        offset: offset,
                        filters: Self.repositoryFilters(
                            selectedGroup: currentGroup,
                            criteria: criteria
                        )
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

private extension HistoryPreparedSearchRequest {
    var repositoryFilters: ClipboardSearchQueryFilters {
        HistorySearchCoordinator.repositoryFilters(
            selectedGroup: selectedGroup,
            criteria: criteria
        )
    }
}

private extension HistorySearchCoordinator {
    nonisolated static func repositoryFilters(
        selectedGroup: HistoryGroupSelection,
        criteria: HistorySearchCriteria
    ) -> ClipboardSearchQueryFilters {
        var requiredGroupIDs = Set<ClipboardGroup.ID>()
        var requiresPinned = false
        switch selectedGroup {
        case .all:
            break
        case .pinned:
            requiresPinned = true
        case .group(let groupID):
            requiredGroupIDs.insert(groupID)
        }

        var groupCriteria = ClipboardSearchQueryGroupCriteria()
        for group in criteria.groups {
            switch group {
            case .pinned:
                groupCriteria.includesPinned = true
            case .group(let groupID):
                groupCriteria.groupIDs.insert(groupID)
            }
        }

        return ClipboardSearchQueryFilters(
            types: Set(criteria.types.map(\.clipboardItemType)),
            sourceAppNames: criteria.sourceAppNames,
            requiresPinned: requiresPinned,
            requiredGroupIDs: requiredGroupIDs,
            groupCriteria: groupCriteria
        )
    }
}

private extension HistorySearchItemType {
    var clipboardItemType: ClipboardItemType {
        switch self {
        case .text:
            .text
        case .link:
            .link
        case .image:
            .image
        case .color:
            .color
        case .file:
            .file
        }
    }
}
