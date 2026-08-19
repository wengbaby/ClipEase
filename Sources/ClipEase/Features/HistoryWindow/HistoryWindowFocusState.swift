import Foundation

struct HistoryWindowFocusState {
    var latestPresentedItemID: ClipboardItem.ID?
    var latestPresentedItemTimestamp: Date = .distantPast
    var latestObservation: LatestItemObservation?
    var pendingNewestItemIDForNextShow: ClipboardItem.ID?
    var pendingLatestFocusItemID: ClipboardItem.ID?
    var pendingLatestFocusTimestamp: Date?
    var pendingLatestFocusReason: ClipboardItemFocusRequest.Reason?
    var pendingLatestFocusLockID: ClipboardItem.ID?
    var pendingKeyboardFocusItemID: ClipboardItem.ID?
    var latestClipboardFocusGeneration: UInt64 = 0
    var pendingProgrammaticJumpItemID: ClipboardItem.ID?
    var pendingPastedItemFocusOnNextShow: ClipboardItem.ID?
    var pendingDefaultFocusOnShow = false

    mutating func primeLatestPresentationGuard(sourceItems: [ClipboardItem]) {
        let observation = LatestItemObservation(item: sourceItems.first)
        latestObservation = observation
        latestPresentedItemID = observation?.id
        latestPresentedItemTimestamp = sourceItems.first?.createdAt ?? .distantPast
    }

    mutating func primeLatestPresentationGuard(observation: LatestItemObservation?, timestamp: Date?) {
        latestObservation = observation
        latestPresentedItemID = observation?.id
        latestPresentedItemTimestamp = timestamp ?? .distantPast
    }

    mutating func prepareLatestFocus(
        itemID: ClipboardItem.ID,
        timestamp: Date?,
        reason: ClipboardItemFocusRequest.Reason?
    ) {
        pendingLatestFocusItemID = itemID
        pendingLatestFocusTimestamp = timestamp
        pendingLatestFocusReason = reason
        pendingLatestFocusLockID = itemID
        latestClipboardFocusGeneration &+= 1
        pendingNewestItemIDForNextShow = nil
        latestPresentedItemID = nil
    }

    mutating func scheduleProgrammaticJump(
        to id: ClipboardItem.ID,
        reason: ClipboardItemFocusRequest.Reason?
    ) {
        pendingLatestFocusItemID = id
        pendingLatestFocusReason = reason
        pendingLatestFocusLockID = id
        pendingProgrammaticJumpItemID = id
    }

    mutating func finishLatestFocusIfNeeded(_ id: HistoryPreviewItem.ID) -> Bool {
        guard pendingLatestFocusItemID == id else {
            return false
        }

        pendingLatestFocusItemID = nil
        pendingLatestFocusTimestamp = nil
        pendingLatestFocusReason = nil
        pendingLatestFocusLockID = nil
        return true
    }
}

struct LatestItemObservation: Equatable {
    let id: ClipboardItem.ID
    let createdAt: Date

    init?(item: ClipboardItem?) {
        guard let item else {
            return nil
        }

        self.id = item.id
        self.createdAt = item.createdAt
    }

    static func changedItem(
        previous: LatestItemObservation?,
        current: LatestItemObservation?,
        sourceItems: [ClipboardItem]
    ) -> (id: ClipboardItem.ID, createdAt: Date, reason: ClipboardItemFocusRequest.Reason)? {
        guard let previous, let current else {
            return nil
        }

        if current.id != previous.id {
            return (current.id, current.createdAt, .inserted)
        }

        if current.createdAt > previous.createdAt.addingTimeInterval(0.001) {
            return (current.id, current.createdAt, .refreshed)
        }

        return sourceItems.first { item in
            item.createdAt > previous.createdAt.addingTimeInterval(0.001)
        }.map { item in
            (item.id, item.createdAt, .refreshed)
        }
    }
}
