import Foundation
import Testing
@testable import ClipEase

@Test func previewBuildCoordinatorBuildsFullResultWithCacheHits() throws {
    let first = previewBuildItem(id: UUID(), text: "first", createdAt: 1)
    let second = previewBuildItem(id: UUID(), text: "second", createdAt: 2)
    let sourceItems = [first, second]
    let sourceSignature = sourceItems.map(HistoryPreviewSourceSignature.init)
    let cachedPreview = HistoryPreviewItem(item: first)
    let cache = [
        first.id: CachedHistoryPreviewItem(signature: sourceSignature[0], item: cachedPreview)
    ]

    let result = try HistoryPreviewBuildCoordinator.rebuild(
        sourceItems: sourceItems,
        sourceSignature: sourceSignature,
        currentPreviewItems: [],
        currentSourceSignature: [],
        currentPreviewItemCache: cache,
        retainedCacheIDs: Set(sourceItems.map(\.id))
    )

    guard case .full(let previewItems, let nextCache, let sourceAppSnapshot, let cacheHitCount, _) = result else {
        Issue.record("Expected full rebuild result")
        return
    }

    #expect(previewItems.map(\.id) == sourceItems.map(\.id))
    #expect(previewItems[0] == cachedPreview)
    #expect(nextCache.count == 2)
    #expect(sourceAppSnapshot.options.map(\.name) == ["ClipEase"])
    #expect(cacheHitCount == 1)
}

@Test func previewBuildCoordinatorBuildsPrependResultWhenSourceSignatureIsPrefixed() throws {
    let existing = previewBuildItem(id: UUID(), text: "existing", createdAt: 1)
    let inserted = previewBuildItem(id: UUID(), text: "inserted", createdAt: 2)
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

    guard case .prepend(let insertedItems, let nextCache, let sourceAppSnapshot, let cacheHitCount, _) = result else {
        Issue.record("Expected incremental prepend result")
        return
    }

    #expect(insertedItems.map(\.id) == [inserted.id])
    #expect(nextCache.count == 2)
    #expect(sourceAppSnapshot.options.map(\.name) == ["ClipEase"])
    #expect(cacheHitCount == 1)
}

@Test func previewBuildCoordinatorAppliesOnlyCurrentUncancelledGeneration() {
    #expect(HistoryPreviewBuildCoordinator.shouldApplyResult(
        isTaskCancelled: false,
        generation: 3,
        currentGeneration: 3
    ))
    #expect(!HistoryPreviewBuildCoordinator.shouldApplyResult(
        isTaskCancelled: true,
        generation: 3,
        currentGeneration: 3
    ))
    #expect(!HistoryPreviewBuildCoordinator.shouldApplyResult(
        isTaskCancelled: false,
        generation: 2,
        currentGeneration: 3
    ))
}

@Test func previewBuildCoordinatorBuildsOneHundredThousandSignaturesInDetachedTask() async throws {
    let itemCount = 100_000
    var sourceItems = (0..<itemCount).map { index in
        previewBuildItem(
            id: UUID(),
            text: "item-\(index)",
            createdAt: TimeInterval(index)
        )
    }
    let currentSourceSignature = sourceItems.map(HistoryPreviewSourceSignature.init)
    let changedIndex = itemCount / 2
    sourceItems[changedIndex] = previewBuildItem(
        id: sourceItems[changedIndex].id,
        text: "item-\(changedIndex)-revised",
        createdAt: TimeInterval(changedIndex)
    )

    let update = try await Task.detached(priority: .userInitiated) {
        try HistoryPreviewBuildCoordinator.previewSignatureUpdateCheckingCancellation(
            sourceItems: sourceItems,
            currentSourceSignature: currentSourceSignature
        )
    }.value

    #expect(update.hasChanges)
    #expect(update.sourceSignature.count == itemCount)
    #expect(update.sourceSignature.first?.text == "item-0")
    #expect(update.sourceSignature[changedIndex].text == "item-\(changedIndex)-revised")
    #expect(update.sourceSignature.last?.text == "item-\(itemCount - 1)")
}

private func previewBuildItem(id: UUID, text: String, createdAt: TimeInterval) -> ClipboardItem {
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
