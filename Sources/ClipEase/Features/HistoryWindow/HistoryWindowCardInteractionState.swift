import Foundation

struct HistoryWindowCardInteractionState {
    var selectedItemID: HistoryPreviewItem.ID?
    var enteringItemIDs: Set<ClipboardItem.ID> = []
    var enteringItemClearTask: Task<Void, Never>?
    var entranceSheenItemIDs: Set<ClipboardItem.ID> = []
    var entranceSheenStartTime: CFTimeInterval?
    var entranceSheenClearTask: Task<Void, Never>?
    var hoveredCardID: HistoryPreviewItem.ID?
    var pressedCardID: HistoryPreviewItem.ID?

    mutating func select(_ id: HistoryPreviewItem.ID?) {
        selectedItemID = id
    }

    mutating func setHover(_ id: HistoryPreviewItem.ID, isHovered: Bool) {
        if isHovered {
            hoveredCardID = id
        } else if hoveredCardID == id {
            hoveredCardID = nil
        }
    }

    mutating func setPress(_ id: HistoryPreviewItem.ID, isPressed: Bool) {
        if isPressed {
            pressedCardID = id
        } else if pressedCardID == id {
            pressedCardID = nil
        }
    }

    mutating func startEntranceAnimation(for id: ClipboardItem.ID, startTime: CFTimeInterval) {
        enteringItemClearTask?.cancel()
        entranceSheenClearTask?.cancel()
        enteringItemIDs = [id]
        entranceSheenItemIDs = [id]
        entranceSheenStartTime = startTime
    }

    mutating func finishEntranceSheen(for id: ClipboardItem.ID) {
        entranceSheenItemIDs.remove(id)
        entranceSheenStartTime = nil
        entranceSheenClearTask = nil
    }

    mutating func finishEntering(for id: ClipboardItem.ID) {
        enteringItemIDs.remove(id)
        enteringItemClearTask = nil
    }

    mutating func clearTransientState() {
        enteringItemClearTask?.cancel()
        entranceSheenClearTask?.cancel()
        enteringItemClearTask = nil
        entranceSheenClearTask = nil
        enteringItemIDs.removeAll()
        entranceSheenItemIDs.removeAll()
        entranceSheenStartTime = nil
        hoveredCardID = nil
        pressedCardID = nil
    }
}
