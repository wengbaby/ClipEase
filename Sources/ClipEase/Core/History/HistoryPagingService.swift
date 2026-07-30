import Foundation

enum HistoryPagingService {
    static let startupItemPageSize = 1_000
    static let incrementalItemPageSize = 1_000

    struct ItemCursor: Equatable, Sendable {
        let isPinned: Bool
        let createdAt: Date
        let pinnedOrCreatedAt: Date
        let id: ClipboardItem.ID

        init(item: ClipboardItem) {
            isPinned = item.isPinned
            createdAt = item.createdAt
            pinnedOrCreatedAt = item.pinnedAt ?? item.createdAt
            id = item.id
        }
    }

    struct ItemPage: Equatable, Sendable {
        let items: [ClipboardItem]
        let nextCursor: ItemCursor?

        init(items: [ClipboardItem]) {
            self.items = items
            nextCursor = items.last.map(ItemCursor.init(item:))
        }
    }

    struct State: Equatable {
        var didLoadAll: Bool
        var isLoadingNextPage: Bool
    }

    struct PageRequest: Equatable {
        let offset: Int
        let limit: Int
        let cursor: ItemCursor?
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
        lastItem: ClipboardItem? = nil,
        limit: Int = incrementalItemPageSize
    ) -> PageRequest {
        PageRequest(
            offset: itemCount,
            limit: limit,
            cursor: lastItem.map(ItemCursor.init(item:))
        )
    }

    static func nextPageRequest(
        itemCount: Int,
        cursor: ItemCursor?,
        limit: Int = incrementalItemPageSize
    ) -> PageRequest {
        PageRequest(
            offset: itemCount,
            limit: limit,
            cursor: cursor
        )
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

    static func mergeResult(
        pageCount: Int,
        requestedCursor: ItemCursor?,
        currentCursor: ItemCursor?,
        limit: Int
    ) -> MergeResult {
        guard requestedCursor == currentCursor else {
            return .stale
        }
        return .append(didLoadAll: pageCount < limit)
    }
}
