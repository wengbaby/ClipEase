import Foundation
import Testing
@testable import ClipEase

@Test func viewportStateStartsAndClearsPendingItemScroll() {
    let id = UUID()
    var state = HistoryWindowViewportState()

    state.startPendingItemScroll(to: id, resetToAll: true, animated: true)

    #expect(state.pendingItemScrollID == id)
    #expect(state.pendingItemScrollRetryCount == 0)
    #expect(state.shouldResetHorizontalOffsetForPendingItemScroll)
    #expect(state.shouldAnimatePendingItemScroll)
    #expect(!state.isPreparingPendingItemScrollMeasurement)

    state.pendingItemScrollRetryCount = 2
    state.isPreparingPendingItemScrollMeasurement = true

    state.clearPendingItemScroll(resetHorizontalOffset: true)

    #expect(state.pendingItemScrollID == nil)
    #expect(state.pendingItemScrollRetryCount == 0)
    #expect(!state.shouldResetHorizontalOffsetForPendingItemScroll)
    #expect(!state.shouldAnimatePendingItemScroll)
    #expect(!state.isPreparingPendingItemScrollMeasurement)
}

@Test func viewportStateTracksPendingItemScrollRetryBudget() {
    var state = HistoryWindowViewportState()

    let firstBegin = state.beginPendingItemScrollMeasurement(maxRetryCount: 2)
    #expect(firstBegin)
    #expect(state.isPreparingPendingItemScrollMeasurement)
    #expect(state.pendingItemScrollRetryCount == 1)

    state.finishPendingItemScrollMeasurement()

    #expect(!state.isPreparingPendingItemScrollMeasurement)
    let secondBegin = state.beginPendingItemScrollMeasurement(maxRetryCount: 2)
    let thirdBegin = state.beginPendingItemScrollMeasurement(maxRetryCount: 2)
    #expect(secondBegin)
    #expect(!thirdBegin)
}

@Test func viewportStatePrunesCardFramesToRetainedIDs() {
    let retained = UUID()
    let removed = UUID()
    var state = HistoryWindowViewportState()
    state.cardViewportFrames = [
        retained: CGRect(x: 1, y: 2, width: 3, height: 4),
        removed: CGRect(x: 5, y: 6, width: 7, height: 8)
    ]

    state.pruneCardViewportFrames(retaining: [retained])

    #expect(state.cardViewportFrames.keys.sorted { $0.uuidString < $1.uuidString } == [retained])
    #expect(state.cardViewportFrames[retained]?.origin.x == 1)
}

@Test func viewportStateRebuildsSearchInteractionScreenFrames() {
    var state = HistoryWindowViewportState()
    state.searchControlScreenFrame = CGRect(x: 10, y: 20, width: 100, height: 30)

    state.rebuildSearchInteractionScreenFrames(isSearchActive: true)

    #expect(state.searchInteractionScreenFrames.count == 1)
    #expect(state.searchInteractionScreenFrames[0] == CGRect(x: 4, y: 14, width: 112, height: 42))

    state.rebuildSearchInteractionScreenFrames(isSearchActive: false)

    #expect(state.searchInteractionScreenFrames.isEmpty)
}

@Test func viewportStateMarksRememberedViewportRestored() {
    var state = HistoryWindowViewportState()

    state.markRememberedViewportNeedsRestore()
    #expect(!state.didRestoreRememberedViewport)

    state.markRememberedViewportRestored()
    #expect(state.didRestoreRememberedViewport)
}
