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
