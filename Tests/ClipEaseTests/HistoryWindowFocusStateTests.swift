import Foundation
import Testing
@testable import ClipEase

@Test func focusStatePrimesLatestPresentationGuard() {
    let item = focusStateItem(id: UUID(), text: "latest", createdAt: 10)
    var state = HistoryWindowFocusState()

    state.primeLatestPresentationGuard(sourceItems: [item])

    #expect(state.latestObservation == LatestItemObservation(item: item))
    #expect(state.latestPresentedItemID == item.id)
    #expect(state.latestPresentedItemTimestamp == item.createdAt)
}

@Test func focusStatePreparesAndFinishesLatestFocus() {
    let id = UUID()
    let timestamp = Date(timeIntervalSince1970: 42)
    var state = HistoryWindowFocusState()
    state.pendingNewestItemIDForNextShow = UUID()
    state.latestPresentedItemID = UUID()

    state.prepareLatestFocus(itemID: id, timestamp: timestamp, reason: .inserted)

    #expect(state.pendingLatestFocusItemID == id)
    #expect(state.pendingLatestFocusTimestamp == timestamp)
    #expect(state.pendingLatestFocusReason == .inserted)
    #expect(state.pendingLatestFocusLockID == id)
    #expect(state.pendingProgrammaticJumpItemID == nil)
    #expect(state.pendingNewestItemIDForNextShow == nil)
    #expect(state.latestPresentedItemID == nil)
    #expect(state.latestClipboardFocusGeneration == 1)

    state.scheduleProgrammaticJump(to: id, reason: .inserted)
    #expect(state.pendingProgrammaticJumpItemID == id)

    _ = state.finishLatestFocusIfNeeded(id)

    #expect(state.pendingLatestFocusItemID == nil)
    #expect(state.pendingLatestFocusTimestamp == nil)
    #expect(state.pendingLatestFocusReason == nil)
    #expect(state.pendingLatestFocusLockID == nil)
}

@Test func focusStateIgnoresFinishForDifferentLatestFocus() {
    let pendingID = UUID()
    var state = HistoryWindowFocusState()
    state.prepareLatestFocus(itemID: pendingID, timestamp: nil, reason: .refreshed)

    _ = state.finishLatestFocusIfNeeded(UUID())

    #expect(state.pendingLatestFocusItemID == pendingID)
    #expect(state.pendingLatestFocusReason == .refreshed)
}

private func focusStateItem(id: UUID, text: String, createdAt: TimeInterval) -> ClipboardItem {
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
