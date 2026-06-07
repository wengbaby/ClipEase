import Foundation
import Testing
@testable import ClipEase

@MainActor
@Test func historyViewportStoreUpdatesVisibleRectOnlyForMeaningfulChanges() {
    let store = HistoryViewportStore(
        visibleRect: CGRect(x: 0, y: 0, width: 800, height: 300),
        mode: .visibleArea
    )

    let unchanged = store.updateVisibleRectIfNeeded(
        CGRect(x: 10, y: 0, width: 800.2, height: 300),
        itemStride: 270
    )
    let changed = store.updateVisibleRectIfNeeded(
        CGRect(x: 280, y: 0, width: 800.2, height: 300),
        itemStride: 270
    )

    #expect(!unchanged)
    #expect(changed)
    #expect(store.visibleRect.minX == 280)
    #expect(store.mode == .automatic)
}

@Test func renderWindowCoordinatorKeepsExistingContentWidthCalculation() {
    let width = RenderWindowCoordinator.contentWidth(
        itemCount: 3,
        cardWidth: 250,
        cardSpacing: 20,
        horizontalPadding: 28
    )

    #expect(width == 846)
}

@Test func renderWindowCoordinatorReturnsVisibleWindowSlice() {
    let items = HistoryPreviewItem.samples
    let range = 2..<5
    let slice = RenderWindowCoordinator.renderedWindowItems(items: items, visibleWindow: range)

    #expect(slice.map(\.id) == items[range].map(\.id))
}

@Test func previewAssetPreheaterExpandsVisibleWindowByEightItems() {
    let items = Array(HistoryPreviewItem.samples.prefix(7))
    let selected = PreviewAssetPreheater.itemsToPreheat(
        items: items,
        visibleWindow: 2..<4,
        sideBuffer: 2
    )

    #expect(selected.map(\.id) == items[0..<6].map(\.id))
}

@MainActor
@Test func historyPreviewCoordinatorClearsPendingFollowAfterRetries() async {
    let coordinator = HistoryPreviewCoordinator(retryDelaysNanoseconds: [1, 1])
    let id = UUID()
    var movedFrames: [CGRect] = []

    coordinator.scheduleFollow(
        itemID: id,
        isPreviewVisible: { true },
        currentPreviewItemID: { id },
        frameForItem: { _ in CGRect(x: 12, y: 34, width: 250, height: 270) },
        onMovePreview: { frame in movedFrames.append(frame) }
    )

    try? await Task.sleep(nanoseconds: 80_000_000)

    #expect(movedFrames == [
        CGRect(x: 12, y: 34, width: 250, height: 270),
        CGRect(x: 12, y: 34, width: 250, height: 270)
    ])
    #expect(coordinator.pendingFollowItemID == nil)
}
