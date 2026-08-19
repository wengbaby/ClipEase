import Foundation
import Testing
@testable import ClipEase

@Test func previewItemsStateAppliesFilteredAndUnfilteredResults() {
    let first = previewStateItem(id: UUID(), text: "first", createdAt: 1)
    let second = previewStateItem(id: UUID(), text: "second", createdAt: 2)
    var state = HistoryWindowPreviewItemsState()
    state.allItems = [first, second].map(HistoryPreviewItem.init)
    let filtered = HistorySearchFilterResult(items: [HistoryPreviewItem(item: second)])

    state.applyFilteredResult(filtered)

    #expect(!state.isUsingUnfilteredResult)
    #expect(state.visibleItems.map(\.id) == [second.id])
    #expect(state.containsFilteredItem(second.id, unfilteredContains: { _ in false }))
    #expect(state.filteredItemIndex(for: second.id, unfilteredIndex: { _ in nil }) == 0)
    #expect(state.filteredItem(for: second.id, unfilteredIndex: { _ in nil })?.id == second.id)

    state.applyUnfilteredResult()

    #expect(state.isUsingUnfilteredResult)
    #expect(state.visibleItems.map(\.id) == [first.id, second.id])
    #expect(state.filteredItems.isEmpty)
    #expect(state.containsFilteredItem(first.id, unfilteredContains: { $0 == first.id }))
    #expect(state.filteredItemIndex(for: second.id, unfilteredIndex: { $0 == second.id ? 1 : nil }) == 1)
}

@Test func previewItemsStateAppliesFullRebuildResult() throws {
    let first = previewStateItem(id: UUID(), text: "first", createdAt: 1)
    let second = previewStateItem(id: UUID(), text: "second", createdAt: 2)
    let sourceItems = [first, second]
    let sourceSignature = sourceItems.map(HistoryPreviewSourceSignature.init)
    let result = try HistoryPreviewBuildCoordinator.rebuild(
        sourceItems: sourceItems,
        sourceSignature: sourceSignature,
        currentPreviewItems: [],
        currentSourceSignature: [],
        currentPreviewItemCache: [:],
        retainedCacheIDs: Set(sourceItems.map(\.id))
    )
    var state = HistoryWindowPreviewItemsState()

    let summary = state.applyRebuildResult(
        result,
        sourceSignature: sourceSignature,
        sourceGeneration: 7
    )

    #expect(summary.mode == .full)
    #expect(summary.resultCount == 2)
    #expect(summary.cacheStored == 2)
    #expect(summary.sourceAppSnapshot.options.map(\.name) == ["ClipEase"])
    #expect(state.allItems.map(\.id) == sourceItems.map(\.id))
    #expect(state.previewItemsSourceSignature == sourceSignature)
    #expect(state.appliedPreviewItemsMutationGeneration == 7)
    #expect(state.previewItemCache.count == 2)
    #expect(state.sourceAppFilterOptions.map(\.name) == ["ClipEase"])
}

@Test func previewItemsStateAppliesPrependRebuildResult() throws {
    let existing = previewStateItem(id: UUID(), text: "existing", createdAt: 1)
    let inserted = previewStateItem(id: UUID(), text: "inserted", createdAt: 2)
    let sourceItems = [inserted, existing]
    let sourceSignature = sourceItems.map(HistoryPreviewSourceSignature.init)
    let currentPreviewItems = [HistoryPreviewItem(item: existing)]
    let currentSourceSignature = [HistoryPreviewSourceSignature(item: existing)]
    let result = try HistoryPreviewBuildCoordinator.rebuild(
        sourceItems: sourceItems,
        sourceSignature: sourceSignature,
        currentPreviewItems: currentPreviewItems,
        currentSourceSignature: currentSourceSignature,
        currentPreviewItemCache: [:],
        retainedCacheIDs: Set(sourceItems.map(\.id))
    )
    var state = HistoryWindowPreviewItemsState()
    state.allItems = currentPreviewItems
    state.previewItemsSourceSignature = currentSourceSignature

    let summary = state.applyRebuildResult(
        result,
        sourceSignature: sourceSignature,
        sourceGeneration: 8
    )

    #expect(summary.mode == .incrementalPrepend)
    #expect(summary.resultCount == 2)
    #expect(summary.cacheMisses == 1)
    #expect(state.allItems.map(\.id) == [inserted.id, existing.id])
    #expect(state.previewItemsSourceSignature == sourceSignature)
    #expect(state.appliedPreviewItemsMutationGeneration == 8)
    #expect(state.canSkipPreviewRebuild(sourceItems: sourceItems, sourceGeneration: 8))
}

@Test func previewItemsStateSyncItemGroupMutationUpdatesAllItemsAndClearsFilteredEntry() {
    let groupID = UUID()
    var groupedItem = previewStateItem(id: UUID(), text: "grouped", createdAt: 1)
    groupedItem.groupID = groupID
    groupedItem.groupedAt = Date(timeIntervalSince1970: 5)
    let regularItem = previewStateItem(id: UUID(), text: "regular", createdAt: 2)
    var state = HistoryWindowPreviewItemsState()
    state.allItems = [groupedItem, regularItem].map(HistoryPreviewItem.init)

    let filtered = HistorySearchFilterResult(items: [HistoryPreviewItem(item: groupedItem)])
    state.applyFilteredResult(filtered)
    #expect(state.visibleItems.map(\.id) == [groupedItem.id])
    #expect(state.filteredItems.first?.groupID == groupID)

    var removedFromGroup = groupedItem
    removedFromGroup.groupID = nil
    removedFromGroup.groupedAt = nil
    state.syncItemGroupMutation(removedFromGroup)

    #expect(state.allItems.first(where: { $0.id == groupedItem.id })?.groupID == nil)
    #expect(state.allItems.first(where: { $0.id == groupedItem.id })?.groupedAt == nil)
    #expect(state.previewItemCache[groupedItem.id] == nil)
    #expect(state.filteredItems.first(where: { $0.id == groupedItem.id }) == nil)
    #expect(!state.filteredItemIDs.contains(groupedItem.id))
}

private func previewStateItem(id: UUID, text: String, createdAt: TimeInterval) -> ClipboardItem {
    ClipboardItem(
        id: id,
        type: .text,
        text: text,
        url: nil,
        linkTitle: nil,
        linkSubtitle: nil,
        imageFileName: nil,
        imageWidth: nil,
        imageHeight: nil,
        imageHash: nil,
        richTextFileName: nil,
        fileReferences: [],
        createdAt: Date(timeIntervalSince1970: createdAt),
        sourceAppName: "ClipEase",
        sourceBundleID: "com.clipease.test",
        iconName: "app.fill",
        iconFileName: nil,
        headerColorHex: "#2E8CFF",
        isPinned: false,
        pinnedAt: nil,
        groupID: nil,
        groupedAt: nil
    )
}
