import Foundation

struct HistoryWindowPreviewItemsState {
    enum RebuildMode: Equatable {
        case full
        case incrementalPrepend

        var diagnosticsValue: String {
            switch self {
            case .full:
                "full"
            case .incrementalPrepend:
                "incrementalPrepend"
            }
        }
    }

    struct RebuildApplySummary {
        let mode: RebuildMode
        let resultCount: Int
        let cacheMisses: Int
        let cacheHitCount: Int
        let cacheStored: Int
        let buildDurationMS: Double
        let sourceAppSnapshot: HistorySourceAppFilterSnapshot
    }

    var allItems: [HistoryPreviewItem] = []
    var filteredItems: [HistoryPreviewItem] = []
    var filteredItemIDs: Set<HistoryPreviewItem.ID> = []
    var filteredItemIndexByID: [HistoryPreviewItem.ID: Int] = [:]
    var filteredSourceItemsByID: [ClipboardItem.ID: ClipboardItem] = [:]
    var isUsingUnfilteredResult = true
    var sourceAppFilterOptions: [HistorySourceAppFilterOption] = []
    var sourceAppIconFileNameByName: [String: String] = [:]
    var previewItemsSourceSignature: [HistoryPreviewSourceSignature] = []
    var appliedPreviewItemsMutationGeneration: UInt64 = 0
    var previewItemCache: [ClipboardItem.ID: CachedHistoryPreviewItem] = [:]

    var visibleItems: [HistoryPreviewItem] {
        isUsingUnfilteredResult ? allItems : filteredItems
    }

    mutating func syncItemGroupMutation(_ item: ClipboardItem) {
        let targetID = item.id
        let rebuiltPreviewItem = HistoryPreviewItem(item: item)
        if let index = allItems.firstIndex(where: { $0.id == targetID }) {
            allItems[index] = rebuiltPreviewItem
        }
        previewItemCache.removeValue(forKey: targetID)
        if !isUsingUnfilteredResult {
            filteredItems.removeAll { $0.id == targetID }
            filteredItemIDs.remove(targetID)
            filteredItemIndexByID.removeAll(keepingCapacity: true)
            filteredSourceItemsByID.removeValue(forKey: targetID)
        }
    }

    mutating func applyFilteredResult(_ result: HistorySearchFilterResult) {
        guard isUsingUnfilteredResult ||
                filteredItems != result.items ||
                filteredSourceItemsByID != result.sourceItemsByID else {
            return
        }

        isUsingUnfilteredResult = false
        filteredItems = result.items
        filteredItemIDs = result.itemIDs
        filteredItemIndexByID = result.itemIndexByID
        filteredSourceItemsByID = result.sourceItemsByID
    }

    mutating func applyUnfilteredResult() {
        guard !isUsingUnfilteredResult else {
            return
        }

        isUsingUnfilteredResult = true
        filteredItems.removeAll(keepingCapacity: false)
        filteredItemIDs.removeAll(keepingCapacity: true)
        filteredItemIndexByID.removeAll(keepingCapacity: true)
        filteredSourceItemsByID.removeAll(keepingCapacity: true)
    }

    func filteredSourceItem(for id: ClipboardItem.ID?) -> ClipboardItem? {
        guard let id else {
            return nil
        }
        return filteredSourceItemsByID[id]
    }

    mutating func removeFilteredItem(with id: ClipboardItem.ID) {
        guard !isUsingUnfilteredResult else {
            return
        }
        filteredItems.removeAll { $0.id == id }
        filteredItemIDs.remove(id)
        filteredSourceItemsByID.removeValue(forKey: id)
        filteredItemIndexByID = Dictionary(
            uniqueKeysWithValues: filteredItems.enumerated().map { ($0.element.id, $0.offset) }
        )
    }

    func containsFilteredItem(
        _ id: HistoryPreviewItem.ID?,
        unfilteredContains: (HistoryPreviewItem.ID) -> Bool
    ) -> Bool {
        guard let id else {
            return false
        }

        if isUsingUnfilteredResult {
            return unfilteredContains(id)
        }

        return filteredItemIDs.contains(id)
    }

    func filteredItemIndex(
        for id: HistoryPreviewItem.ID?,
        unfilteredIndex: (HistoryPreviewItem.ID) -> Int?
    ) -> Int? {
        guard let id else {
            return nil
        }

        if isUsingUnfilteredResult {
            return unfilteredIndex(id)
        }

        return filteredItemIndexByID[id]
    }

    func filteredItem(
        for id: HistoryPreviewItem.ID?,
        unfilteredIndex: (HistoryPreviewItem.ID) -> Int?
    ) -> HistoryPreviewItem? {
        guard let index = filteredItemIndex(for: id, unfilteredIndex: unfilteredIndex),
              visibleItems.indices.contains(index) else {
            return nil
        }

        return visibleItems[index]
    }

    mutating func applyRebuildResult(
        _ result: HistoryPreviewBuildCoordinator.RebuildResult,
        sourceSignature: [HistoryPreviewSourceSignature],
        sourceGeneration: UInt64
    ) -> RebuildApplySummary {
        let summary = Self.rebuildApplySummary(result, existingItemCount: allItems.count)
        applyRebuildItems(result)
        applyRebuildMetadata(summary, sourceSignature: sourceSignature, sourceGeneration: sourceGeneration)
        return summary
    }

    static func rebuildApplySummary(
        _ result: HistoryPreviewBuildCoordinator.RebuildResult,
        existingItemCount: Int
    ) -> RebuildApplySummary {
        switch result {
        case .full(let previewItems, let nextCache, let sourceAppSnapshot, let hitCount, let durationMS):
            RebuildApplySummary(
                mode: .full,
                resultCount: previewItems.count,
                cacheMisses: previewItems.count - hitCount,
                cacheHitCount: hitCount,
                cacheStored: nextCache.count,
                buildDurationMS: durationMS,
                sourceAppSnapshot: sourceAppSnapshot
            )
        case .prepend(let insertedItems, let nextCache, let sourceAppSnapshot, let hitCount, let durationMS):
            RebuildApplySummary(
                mode: .incrementalPrepend,
                resultCount: existingItemCount + insertedItems.count,
                cacheMisses: insertedItems.count,
                cacheHitCount: hitCount,
                cacheStored: nextCache.count,
                buildDurationMS: durationMS,
                sourceAppSnapshot: sourceAppSnapshot
            )
        }
    }

    mutating func applyRebuildItems(_ result: HistoryPreviewBuildCoordinator.RebuildResult) {
        switch result {
        case .full(let previewItems, let nextCache, _, _, _):
            previewItemCache = nextCache
            allItems = previewItems
        case .prepend(let insertedItems, let nextCache, _, _, _):
            previewItemCache = nextCache
            allItems.insert(contentsOf: insertedItems, at: 0)
        }
    }

    mutating func applyRebuildMetadata(
        _ summary: RebuildApplySummary,
        sourceSignature: [HistoryPreviewSourceSignature],
        sourceGeneration: UInt64
    ) {
        if sourceAppFilterOptions != summary.sourceAppSnapshot.options {
            sourceAppFilterOptions = summary.sourceAppSnapshot.options
        }
        if sourceAppIconFileNameByName != summary.sourceAppSnapshot.iconFileNameByName {
            sourceAppIconFileNameByName = summary.sourceAppSnapshot.iconFileNameByName
        }
        previewItemsSourceSignature = sourceSignature
        appliedPreviewItemsMutationGeneration = sourceGeneration
    }

    func canSkipPreviewRebuild(sourceItems: [ClipboardItem], sourceGeneration: UInt64) -> Bool {
        guard appliedPreviewItemsMutationGeneration == sourceGeneration,
              allItems.count == sourceItems.count else {
            return false
        }

        if sourceItems.isEmpty {
            return allItems.isEmpty
        }

        return allItems.first?.id == sourceItems.first?.id &&
            allItems.last?.id == sourceItems.last?.id
    }
}
