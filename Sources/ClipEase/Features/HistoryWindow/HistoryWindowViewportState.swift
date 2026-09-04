import Foundation

struct HistoryWindowViewportState {
    var windowWidth: CGFloat = 0
    var pendingItemScrollID: HistoryPreviewItem.ID?
    var pendingItemScrollRetryCount = 0
    var shouldResetHorizontalOffsetForPendingItemScroll = false
    var shouldAnimatePendingItemScroll = false
    var isPreparingPendingItemScrollMeasurement = false
    var didRestoreRememberedViewport = false
    var itemScrollRequestID = UUID()
    var cardViewportFrames: [HistoryPreviewItem.ID: CGRect] = [:]
    var searchControlScreenFrame: CGRect?
    var searchInteractionScreenFrames: [CGRect] = []
    var cardRailTopInWindow: CGFloat = 68

    mutating func startPendingItemScroll(
        to id: HistoryPreviewItem.ID,
        resetToAll: Bool,
        animated: Bool
    ) {
        pendingItemScrollID = id
        pendingItemScrollRetryCount = 0
        shouldResetHorizontalOffsetForPendingItemScroll = resetToAll
        shouldAnimatePendingItemScroll = animated
        isPreparingPendingItemScrollMeasurement = false
    }

    mutating func clearPendingItemScroll(resetHorizontalOffset: Bool) {
        pendingItemScrollID = nil
        pendingItemScrollRetryCount = 0
        if resetHorizontalOffset {
            shouldResetHorizontalOffsetForPendingItemScroll = false
        }
        shouldAnimatePendingItemScroll = false
        isPreparingPendingItemScrollMeasurement = false
    }

    mutating func beginPendingItemScrollMeasurement(maxRetryCount: Int) -> Bool {
        guard !isPreparingPendingItemScrollMeasurement,
              pendingItemScrollRetryCount < maxRetryCount else {
            return false
        }

        isPreparingPendingItemScrollMeasurement = true
        pendingItemScrollRetryCount += 1
        return true
    }

    mutating func finishPendingItemScrollMeasurement() {
        isPreparingPendingItemScrollMeasurement = false
    }

    mutating func pruneCardViewportFrames(retaining visibleIDs: Set<HistoryPreviewItem.ID>) {
        cardViewportFrames = cardViewportFrames.filter { visibleIDs.contains($0.key) }
    }

    mutating func rebuildSearchInteractionScreenFrames(isSearchActive: Bool) {
        guard isSearchActive else {
            searchInteractionScreenFrames = []
            return
        }

        var frames: [CGRect] = []
        if let searchControlScreenFrame {
            frames.append(searchControlScreenFrame.standardized.insetBy(dx: -6, dy: -6))
        }

        searchInteractionScreenFrames = frames
    }

    mutating func markRememberedViewportNeedsRestore() {
        didRestoreRememberedViewport = false
    }

    mutating func markRememberedViewportRestored() {
        didRestoreRememberedViewport = true
    }
}
