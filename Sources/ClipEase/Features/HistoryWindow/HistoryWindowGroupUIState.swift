import Foundation

struct HistoryWindowGroupUIState {
    var selectedGroup: HistoryGroupSelection = .all
    var isClearConfirmationPresented = false
    var groupPendingDeletion: ClipboardGroup?
    var renameTargetID: ClipboardGroup.ID?
    var renameText = ""
    var renameOriginalText = ""
    var isRenameCancelPending = false
    var renameFocusRequestID = 0
    var renameInputScreenFrame: CGRect?
    var isIconSearchFocused = false
    var moveToGroupMenuSnapshot: [MoveToGroupMenuEntry] = []
    var moveToGroupPickerTarget: MoveToGroupPickerTarget?
    var pendingGroupTrackScrollID: String?

    var selectedGroupID: ClipboardGroup.ID? {
        selectedGroup.groupID
    }

    mutating func restoreSelectedGroup(from storageValue: String, groups: [ClipboardGroup]) {
        let restoredSelection = HistoryGroupSelection(storageValue: storageValue)
        switch restoredSelection {
        case .all, .pinned:
            selectedGroup = restoredSelection
        case .group(let groupID):
            selectedGroup = groups.contains(where: { $0.id == groupID }) ? restoredSelection : .all
        }
    }

    mutating func repairSelectedGroupIfNeeded(groups: [ClipboardGroup]) {
        if case .group(let groupID) = selectedGroup,
           !groups.contains(where: { $0.id == groupID }) {
            selectedGroup = .all
        }
    }

    mutating func beginRename(_ group: ClipboardGroup) {
        renameText = group.name
        renameOriginalText = group.name
        isRenameCancelPending = false
        renameTargetID = group.id
        renameFocusRequestID += 1
    }

    mutating func requestRenameFocus() {
        renameFocusRequestID += 1
    }

    mutating func finishRename() {
        renameTargetID = nil
        isRenameCancelPending = false
        renameInputScreenFrame = nil
    }

    mutating func cancelRename() {
        renameTargetID = nil
        renameText = renameOriginalText
        isRenameCancelPending = false
        renameInputScreenFrame = nil
    }

    mutating func markRenameCancelPending() {
        isRenameCancelPending = true
    }

    mutating func refreshMoveToGroupMenuSnapshot(groups: [ClipboardGroup]) {
        let snapshot = groups.map { MoveToGroupMenuEntry(group: $0) }
        if moveToGroupMenuSnapshot != snapshot {
            moveToGroupMenuSnapshot = snapshot
        }
    }

    mutating func presentMoveToGroupPicker(for item: HistoryPreviewItem) {
        moveToGroupPickerTarget = MoveToGroupPickerTarget(itemID: item.id, currentGroupID: item.groupID)
    }
}

struct MoveToGroupMenuEntry: Identifiable, Equatable {
    let id: ClipboardGroup.ID
    let name: String
    let iconName: String

    init(group: ClipboardGroup) {
        self.id = group.id
        self.name = group.name
        self.iconName = group.iconName
    }
}

struct MoveToGroupPickerTarget: Identifiable, Equatable {
    let itemID: ClipboardItem.ID
    let currentGroupID: ClipboardGroup.ID?

    var id: ClipboardItem.ID {
        itemID
    }
}
