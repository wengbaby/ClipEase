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

@MainActor
@Test func historyViewportStoreDefaultFocusResetDoesNotPinFirstPageMode() {
    let store = HistoryViewportStore(
        visibleRect: CGRect(x: 0, y: 0, width: 800, height: 300),
        mode: .automatic
    )

    store.visibleRect = CGRect(x: 0, y: 0, width: 800, height: 300)
    store.mode = .automatic

    let changed = store.updateVisibleRectIfNeeded(
        CGRect(x: 5_400, y: 0, width: 800, height: 300),
        itemStride: 270
    )

    #expect(changed)
    #expect(store.mode == .automatic)

    let range = HistoryRailViewportContext(
        itemCount: 80,
        visibleRect: store.visibleRect,
        hasReliableVisibleRect: true,
        itemStride: 270,
        horizontalContentPadding: 28,
        bufferItemCount: 6,
        renderedItemLimit: 20,
        edgeBufferItemCount: 3,
        mode: store.mode
    ).visibleWindow(focusedIndex: nil)

    #expect(range.lowerBound > 0)
    #expect(range.contains(20))
}

@Test func scrollOffsetChangesMustUpdateRenderWindowEvenBeforePresentedSnapshotSettles() {
    let staleWindow = HistoryRailViewportContext(
        itemCount: 100,
        visibleRect: .zero,
        hasReliableVisibleRect: true,
        itemStride: 270,
        horizontalContentPadding: 28,
        bufferItemCount: 6,
        renderedItemLimit: 20,
        edgeBufferItemCount: 3
    ).visibleWindow(focusedIndex: nil)
    let scrolledWindow = HistoryRailViewportContext(
        itemCount: 100,
        visibleRect: CGRect(x: 5_400, y: 0, width: 1_080, height: 300),
        hasReliableVisibleRect: true,
        itemStride: 270,
        horizontalContentPadding: 28,
        bufferItemCount: 6,
        renderedItemLimit: 20,
        edgeBufferItemCount: 3
    ).visibleWindow(focusedIndex: nil)

    #expect(staleWindow == 0..<20)
    #expect(scrolledWindow != staleWindow)
    #expect(scrolledWindow.contains(20))
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

    let deadline = Date().addingTimeInterval(1)
    while (movedFrames.count < 2 || coordinator.pendingFollowItemID != nil) && Date() < deadline {
        try? await Task.sleep(nanoseconds: 10_000_000)
    }

    #expect(movedFrames == [
        CGRect(x: 12, y: 34, width: 250, height: 270),
        CGRect(x: 12, y: 34, width: 250, height: 270)
    ])
    #expect(coordinator.pendingFollowItemID == nil)
}
