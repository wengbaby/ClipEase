enum HistoryPagingService {
    static let startupItemPageSize = 1_000
    static let incrementalItemPageSize = 1_000

    struct State: Equatable {
        var didLoadAll: Bool
        var isLoadingNextPage: Bool
    }

    struct PageRequest: Equatable {
        let offset: Int
        let limit: Int
    }

    enum MergeResult: Equatable {
        case stale
        case append(didLoadAll: Bool)
    }

    static func didLoadAllAfterStartup(
        itemCount: Int,
        limit: Int = startupItemPageSize
    ) -> Bool {
        itemCount < limit
    }

    static func shouldLoadMoreItems(
        state: State,
        visibleUpperBound: Int,
        itemCount: Int,
        preloadMargin: Int
    ) -> Bool {
        !state.didLoadAll
            && !state.isLoadingNextPage
            && visibleUpperBound + preloadMargin >= itemCount
    }

    static func nextPageRequest(
        itemCount: Int,
        limit: Int = incrementalItemPageSize
    ) -> PageRequest {
        PageRequest(offset: itemCount, limit: limit)
    }

    static func mergeResult(
        pageCount: Int,
        requestedOffset: Int,
        currentItemCount: Int,
        limit: Int
    ) -> MergeResult {
        guard requestedOffset == currentItemCount else {
            return .stale
        }
        return .append(didLoadAll: pageCount < limit)
    }
}
