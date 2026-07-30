import Foundation

struct ClipboardHistorySnapshot: Sendable {
    var items: [ClipboardItem]
    var groups: [ClipboardGroup]
}

struct ClipboardHistoryRetentionDeletionResult: Sendable {
    let cleanup: ClipboardAttachmentCleanup
    let removedItemIDs: Set<ClipboardItem.ID>
    let protectedGroupIDs: Set<ClipboardGroup.ID>
}

struct ClipboardSearchQuery: Sendable, Equatable {
    var text: String
    var limit: Int
    var offset: Int
    var filters: ClipboardSearchQueryFilters

    init(
        text: String,
        limit: Int = 500,
        offset: Int = 0,
        filters: ClipboardSearchQueryFilters = ClipboardSearchQueryFilters()
    ) {
        self.text = text
        self.limit = limit
        self.offset = max(0, offset)
        self.filters = filters
    }
}

struct ClipboardSearchQueryFilters: Sendable, Equatable {
    var types: Set<ClipboardItemType>
    var sourceAppNames: Set<String>
    var requiresPinned: Bool
    var requiredGroupIDs: Set<ClipboardGroup.ID>
    var groupCriteria: ClipboardSearchQueryGroupCriteria

    init(
        types: Set<ClipboardItemType> = [],
        sourceAppNames: Set<String> = [],
        requiresPinned: Bool = false,
        requiredGroupIDs: Set<ClipboardGroup.ID> = [],
        groupCriteria: ClipboardSearchQueryGroupCriteria = ClipboardSearchQueryGroupCriteria()
    ) {
        self.types = types
        self.sourceAppNames = sourceAppNames
        self.requiresPinned = requiresPinned
        self.requiredGroupIDs = requiredGroupIDs
        self.groupCriteria = groupCriteria
    }
}

struct ClipboardSearchQueryGroupCriteria: Sendable, Equatable {
    var includesPinned: Bool
    var groupIDs: Set<ClipboardGroup.ID>

    init(includesPinned: Bool = false, groupIDs: Set<ClipboardGroup.ID> = []) {
        self.includesPinned = includesPinned
        self.groupIDs = groupIDs
    }

    var isEmpty: Bool {
        !includesPinned && groupIDs.isEmpty
    }
}

typealias ClipboardSearchCursor = SQLiteSearchCursor

struct ClipboardSearchPage: Equatable, Sendable {
    let items: [ClipboardItem]
    let nextCursor: ClipboardSearchCursor?
}

final class ClipboardSearchCancellationToken: @unchecked Sendable {
    private let lock = NSLock()
    private var cancellationHandlers: [UUID: @Sendable () -> Void] = [:]
    private var storedIsCancelled = false

    var isCancelled: Bool {
        lock.withLock { storedIsCancelled }
    }

    func cancel() {
        let handlers: [@Sendable () -> Void] = lock.withLock {
            guard !storedIsCancelled else {
                return []
            }
            storedIsCancelled = true
            let handlers = Array(cancellationHandlers.values)
            cancellationHandlers.removeAll(keepingCapacity: false)
            return handlers
        }
        for handler in handlers {
            handler()
        }
    }

    func throwIfCancelled() throws {
        guard !isCancelled else {
            throw CancellationError()
        }
    }

    @discardableResult
    func registerCancellationHandler(
        _ handler: @escaping @Sendable () -> Void
    ) -> UUID? {
        let id = UUID()
        let shouldInvokeImmediately = lock.withLock {
            guard !storedIsCancelled else {
                return true
            }
            cancellationHandlers[id] = handler
            return false
        }
        if shouldInvokeImmediately {
            handler()
            return nil
        }
        return id
    }

    func unregisterCancellationHandler(_ id: UUID?) {
        guard let id else {
            return
        }
        lock.withLock {
            cancellationHandlers[id] = nil
        }
    }
}

protocol ClipboardHistoryRepository {
    func loadSnapshot() throws -> ClipboardHistorySnapshot
    func loadSnapshot(itemLimit: Int, offset: Int) throws -> ClipboardHistorySnapshot
    func loadItems(limit: Int, offset: Int) throws -> [ClipboardItem]
    func loadItemPage(
        limit: Int,
        after cursor: HistoryPagingService.ItemCursor?
    ) throws -> HistoryPagingService.ItemPage
    func loadItems(contentHash: String, sourceBundleID: String?) throws -> [ClipboardItem]
    func backfillContentDigests(limit: Int) throws -> Int
    func prepareSearchIndex() throws
    func searchItems(_ query: ClipboardSearchQuery) throws -> [ClipboardItem]
    func searchPage(
        _ query: ClipboardSearchQuery,
        after cursor: ClipboardSearchCursor?,
        cancellation: ClipboardSearchCancellationToken
    ) throws -> ClipboardSearchPage
    func saveSnapshot(_ snapshot: ClipboardHistorySnapshot) throws
    func insertItems(_ items: [ClipboardItem]) throws
    func upsertGroups(_ groups: [ClipboardGroup]) throws
    func upsertItem(_ item: ClipboardItem, deleting deletedIDs: Set<ClipboardItem.ID>, groups: [ClipboardGroup]) throws
    func applyMutations(_ mutations: [ClipboardHistoryRepositoryMutation]) throws
    @discardableResult
    func compensateImportedItem(
        insertedItemID: ClipboardItem.ID,
        restoring displacedItems: [ClipboardItem]
    ) throws -> ClipboardAttachmentCleanup
    @discardableResult
    func deleteItems(
        with ids: Set<ClipboardItem.ID>,
        deletingGroups groupIDs: Set<ClipboardGroup.ID>
    ) throws -> ClipboardAttachmentCleanup
    @discardableResult
    func deleteAllItems(preserving groups: [ClipboardGroup]) throws -> ClipboardAttachmentCleanup
    @discardableResult
    func deleteExpiredItems(before cutoff: Date) throws -> ClipboardAttachmentCleanup
    func deleteExpiredItemsWithResult(
        before cutoff: Date
    ) throws -> ClipboardHistoryRetentionDeletionResult
    func compactIfNeeded(policy: ClipboardDatabaseCompactionPolicy) throws -> ClipboardDatabaseCompactionResult
    func referencedAttachments(in candidates: ClipboardAttachmentCleanup) throws -> ClipboardAttachmentCleanup
}

extension ClipboardHistoryRepository {
    func backfillContentDigests(limit: Int) throws -> Int {
        0
    }

    func deleteExpiredItemsWithResult(
        before cutoff: Date
    ) throws -> ClipboardHistoryRetentionDeletionResult {
        let snapshot = try loadSnapshot()
        let protectedGroupIDs = Set(snapshot.groups.map(\.id))
        let removedItemIDs: Set<ClipboardItem.ID> = Set(snapshot.items.compactMap { item -> ClipboardItem.ID? in
            guard !item.isPinned,
                  item.createdAt < cutoff,
                  item.groupID.map(protectedGroupIDs.contains) != true else {
                return nil
            }
            return item.id
        })
        let cleanup = try deleteExpiredItems(before: cutoff)
        return ClipboardHistoryRetentionDeletionResult(
            cleanup: cleanup,
            removedItemIDs: removedItemIDs,
            protectedGroupIDs: protectedGroupIDs
        )
    }

    @discardableResult
    func compensateImportedItem(
        insertedItemID: ClipboardItem.ID,
        restoring displacedItems: [ClipboardItem]
    ) throws -> ClipboardAttachmentCleanup {
        var snapshot = try loadSnapshot()
        let removedItems = snapshot.items.filter { $0.id == insertedItemID }
        snapshot.items.removeAll { $0.id == insertedItemID }
        let currentIDs = Set(snapshot.items.map(\.id))
        let restorations = displacedItems.filter { !currentIDs.contains($0.id) }
        snapshot.items.insert(contentsOf: restorations, at: 0)
        try saveSnapshot(snapshot)
        return ClipboardAttachmentCleanup(items: removedItems)
    }

    func compactIfNeeded(policy: ClipboardDatabaseCompactionPolicy) throws -> ClipboardDatabaseCompactionResult {
        .skipped
    }

    func referencedAttachments(in candidates: ClipboardAttachmentCleanup) throws -> ClipboardAttachmentCleanup {
        guard !candidates.isEmpty else {
            return .empty
        }

        let referenced = ClipboardAttachmentCleanup(items: try loadSnapshot().items)
        return ClipboardAttachmentCleanup(
            imageFileNames: candidates.imageFileNames.intersection(referenced.imageFileNames),
            richTextFileNames: candidates.richTextFileNames.intersection(referenced.richTextFileNames)
        )
    }

    func loadItems() throws -> [ClipboardItem] {
        try loadSnapshot().items
    }

    func loadSnapshot(itemLimit: Int, offset: Int) throws -> ClipboardHistorySnapshot {
        ClipboardHistorySnapshot(
            items: try loadItems(limit: itemLimit, offset: offset),
            groups: try loadSnapshot().groups
        )
    }

    func loadItems(limit: Int, offset: Int) throws -> [ClipboardItem] {
        let boundedLimit = max(0, limit)
        let boundedOffset = max(0, offset)
        guard boundedLimit > 0 else {
            return []
        }

        return Array(try loadSnapshot().items.dropFirst(boundedOffset).prefix(boundedLimit))
    }

    func loadItemPage(
        limit: Int,
        after cursor: HistoryPagingService.ItemCursor?
    ) throws -> HistoryPagingService.ItemPage {
        guard limit > 0 else {
            return HistoryPagingService.ItemPage(items: [])
        }

        let sortedItems = try loadSnapshot().items.sorted(by: clipboardHistoryStableOrder)
        let eligibleItems: [ClipboardItem]
        if let cursor {
            eligibleItems = sortedItems.filter {
                clipboardHistoryItem($0, appearsAfter: cursor)
            }
        } else {
            eligibleItems = sortedItems
        }
        return HistoryPagingService.ItemPage(
            items: Array(eligibleItems.prefix(limit))
        )
    }

    func loadItems(contentHash: String, sourceBundleID: String?) throws -> [ClipboardItem] {
        try loadSnapshot().items.filter { item in
            guard item.contentHash == contentHash else {
                return false
            }
            guard let sourceBundleID else {
                return true
            }
            return item.sourceBundleID == sourceBundleID
        }
    }

    func prepareSearchIndex() throws {}

    func searchItems(_ query: ClipboardSearchQuery) throws -> [ClipboardItem] {
        let normalizedQuery = query.text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        guard !normalizedQuery.isEmpty,
              query.limit > 0 else {
            return []
        }

        var result: [ClipboardItem] = []
        result.reserveCapacity(min(max(query.limit, 0), 500))
        var skippedMatches = 0
        for item in try loadSnapshot().items {
            guard item.matchesSearchFilters(query.filters) else {
                continue
            }

            guard item.cardSearchText.contains(normalizedQuery) else {
                continue
            }

            if skippedMatches < query.offset {
                skippedMatches += 1
                continue
            }

            result.append(item)
            if result.count >= query.limit {
                break
            }
        }
        return result
    }

    func searchPage(
        _ query: ClipboardSearchQuery,
        after cursor: ClipboardSearchCursor?,
        cancellation: ClipboardSearchCancellationToken
    ) throws -> ClipboardSearchPage {
        let normalizedQuery = query.text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let usesTextSearch = !normalizedQuery.isEmpty
        guard query.limit > 0,
              usesTextSearch || query.filters.hasDatabaseFilters else {
            return ClipboardSearchPage(items: [], nextCursor: nil)
        }

        var matches: [ClipboardItem] = []
        for item in try loadSnapshot().items {
            try cancellation.throwIfCancelled()
            guard item.matchesSearchFilters(query.filters) else {
                continue
            }
            guard !usesTextSearch || item.cardSearchText.contains(normalizedQuery) else {
                continue
            }
            matches.append(item)
        }
        matches.sort(by: clipboardHistoryStableOrder)

        let rank: Double? = usesTextSearch ? 0 : nil
        let eligibleMatches: [ClipboardItem]
        if let cursor {
            eligibleMatches = matches.filter {
                clipboardHistoryItem($0, rank: rank, appearsAfter: cursor)
            }
        } else {
            eligibleMatches = matches
        }
        let pageItems = Array(eligibleMatches.prefix(query.limit))
        try cancellation.throwIfCancelled()
        return ClipboardSearchPage(
            items: pageItems,
            nextCursor: pageItems.last.map {
                ClipboardSearchCursor(
                    rank: rank,
                    isPinned: $0.isPinned,
                    createdAt: $0.createdAt,
                    pinnedOrCreatedAt: $0.pinnedAt ?? $0.createdAt,
                    id: $0.id
                )
            }
        )
    }

    func saveItems(_ items: [ClipboardItem]) throws {
        try saveSnapshot(ClipboardHistorySnapshot(items: items, groups: []))
    }

    func insertItems(_ items: [ClipboardItem]) throws {
        guard !items.isEmpty else {
            return
        }

        var snapshot = try loadSnapshot()
        snapshot.items.insert(contentsOf: items, at: 0)
        try saveSnapshot(snapshot)
    }

    func upsertGroups(_ groups: [ClipboardGroup]) throws {
        guard !groups.isEmpty else {
            return
        }

        var snapshot = try loadSnapshot()
        let incomingIDs = Set(groups.map(\.id))
        snapshot.groups.removeAll { incomingIDs.contains($0.id) }
        snapshot.groups.append(contentsOf: groups)
        snapshot.groups.sort {
            if $0.sortOrder != $1.sortOrder {
                return $0.sortOrder < $1.sortOrder
            }
            return $0.id.uuidString < $1.id.uuidString
        }
        try saveSnapshot(snapshot)
    }

    func upsertItem(_ item: ClipboardItem, deleting deletedIDs: Set<ClipboardItem.ID>, groups: [ClipboardGroup]) throws {
        var snapshot = try loadSnapshot()
        snapshot.items.removeAll { deletedIDs.contains($0.id) || $0.id == item.id }
        snapshot.items.insert(item, at: 0)
        snapshot.groups = groups
        try saveSnapshot(snapshot)
    }

    func applyMutations(_ mutations: [ClipboardHistoryRepositoryMutation]) throws {
        for mutation in mutations {
            switch mutation {
            case .upsert(let upsert):
                try upsertItem(
                    upsert.item,
                    deleting: upsert.deletedIDs,
                    groups: upsert.groups
                )
            case .update(let update):
                var snapshot = try loadSnapshot()
                guard let index = snapshot.items.firstIndex(where: { $0.id == update.item.id }) else {
                    throw ClipboardHistoryWriteMutationError.itemNotFound(update.item.id)
                }
                snapshot.items[index] = update.item
                try saveSnapshot(snapshot)
            }
        }
    }

    @discardableResult
    func deleteItems(
        with ids: Set<ClipboardItem.ID>,
        deletingGroups groupIDs: Set<ClipboardGroup.ID>
    ) throws -> ClipboardAttachmentCleanup {
        guard !ids.isEmpty || !groupIDs.isEmpty else {
            return .empty
        }

        var snapshot = try loadSnapshot()
        let removedItems = snapshot.items.filter { item in
            ids.contains(item.id) || item.groupID.map(groupIDs.contains) == true
        }
        snapshot.items.removeAll { item in
            ids.contains(item.id) || item.groupID.map(groupIDs.contains) == true
        }
        snapshot.groups.removeAll { groupIDs.contains($0.id) }
        try saveSnapshot(snapshot)
        return ClipboardAttachmentCleanup(items: removedItems)
    }

    @discardableResult
    func deleteAllItems(
        preserving groups: [ClipboardGroup]
    ) throws -> ClipboardAttachmentCleanup {
        let snapshot = try loadSnapshot()
        let cleanup = ClipboardAttachmentCleanup(items: snapshot.items)
        try saveSnapshot(ClipboardHistorySnapshot(items: [], groups: groups))
        return cleanup
    }

    @discardableResult
    func deleteExpiredItems(before cutoff: Date) throws -> ClipboardAttachmentCleanup {
        var snapshot = try loadSnapshot()
        let validGroupIDs = Set(snapshot.groups.map(\.id))
        let removedItems = snapshot.items.filter { item in
            !item.isPinned
                && item.createdAt < cutoff
                && item.groupID.map(validGroupIDs.contains) != true
        }
        guard !removedItems.isEmpty else {
            return .empty
        }

        let removedIDs = Set(removedItems.map(\.id))
        snapshot.items.removeAll { removedIDs.contains($0.id) }
        try saveSnapshot(snapshot)
        return ClipboardAttachmentCleanup(items: removedItems)
    }
}

private extension ClipboardSearchQueryFilters {
    var hasDatabaseFilters: Bool {
        !types.isEmpty
            || !sourceAppNames.isEmpty
            || requiresPinned
            || !requiredGroupIDs.isEmpty
            || !groupCriteria.isEmpty
    }
}

private func clipboardHistoryStableOrder(
    _ lhs: ClipboardItem,
    _ rhs: ClipboardItem
) -> Bool {
    if lhs.isPinned != rhs.isPinned {
        return lhs.isPinned && !rhs.isPinned
    }
    if lhs.createdAt != rhs.createdAt {
        return lhs.createdAt > rhs.createdAt
    }
    let lhsPinnedOrCreatedAt = lhs.pinnedAt ?? lhs.createdAt
    let rhsPinnedOrCreatedAt = rhs.pinnedAt ?? rhs.createdAt
    if lhsPinnedOrCreatedAt != rhsPinnedOrCreatedAt {
        return lhsPinnedOrCreatedAt > rhsPinnedOrCreatedAt
    }
    return lhs.id.uuidString > rhs.id.uuidString
}

private func clipboardHistoryItem(
    _ item: ClipboardItem,
    appearsAfter cursor: HistoryPagingService.ItemCursor
) -> Bool {
    if item.isPinned != cursor.isPinned {
        return !item.isPinned && cursor.isPinned
    }
    if item.createdAt != cursor.createdAt {
        return item.createdAt < cursor.createdAt
    }
    let pinnedOrCreatedAt = item.pinnedAt ?? item.createdAt
    if pinnedOrCreatedAt != cursor.pinnedOrCreatedAt {
        return pinnedOrCreatedAt < cursor.pinnedOrCreatedAt
    }
    return item.id.uuidString < cursor.id.uuidString
}

private func clipboardHistoryItem(
    _ item: ClipboardItem,
    rank: Double?,
    appearsAfter cursor: ClipboardSearchCursor
) -> Bool {
    if rank != cursor.rank {
        guard let rank,
              let cursorRank = cursor.rank else {
            return false
        }
        return rank > cursorRank
    }
    if item.isPinned != cursor.isPinned {
        return !item.isPinned && cursor.isPinned
    }
    if item.createdAt != cursor.createdAt {
        return item.createdAt < cursor.createdAt
    }
    let pinnedOrCreatedAt = item.pinnedAt ?? item.createdAt
    if pinnedOrCreatedAt != cursor.pinnedOrCreatedAt {
        return pinnedOrCreatedAt < cursor.pinnedOrCreatedAt
    }
    return item.id.uuidString < cursor.id.uuidString
}

extension ClipboardItem {
    func matchesSearchFilters(_ filters: ClipboardSearchQueryFilters) -> Bool {
        if !filters.types.isEmpty,
           !filters.types.contains(type) {
            return false
        }

        if !filters.sourceAppNames.isEmpty,
           !filters.sourceAppNames.contains(sourceAppName) {
            return false
        }

        if filters.requiresPinned,
           !isPinned {
            return false
        }

        if !filters.requiredGroupIDs.isEmpty,
           !groupMatches(filters.requiredGroupIDs) {
            return false
        }

        if !filters.groupCriteria.isEmpty {
            let matchesPinned = filters.groupCriteria.includesPinned && isPinned
            let matchesGroup = groupMatches(filters.groupCriteria.groupIDs)
            if !matchesPinned && !matchesGroup {
                return false
            }
        }

        return true
    }

    private func groupMatches(_ ids: Set<ClipboardGroup.ID>) -> Bool {
        guard !ids.isEmpty,
              let groupID else {
            return false
        }
        return ids.contains(groupID)
    }

    var cardSearchText: String {
        [
            preview,
            linkTitle,
            linkSubtitle,
            fileReferences.map(\.displayName).joined(separator: " "),
            fileReferences.map(\.path).joined(separator: " "),
            ocrText,
            ocrEmails.joined(separator: " "),
            ocrPhoneNumbers.joined(separator: " "),
            ocrURLs.joined(separator: " ")
        ]
        .compactMap { $0 }
        .joined(separator: " ")
        .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}
