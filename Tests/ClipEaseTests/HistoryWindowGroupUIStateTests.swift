import Foundation
import Testing
@testable import ClipEase

@Test func groupUIStateRestoresAndRepairsSelectedGroup() {
    let group = groupUIStateGroup(name: "Work")
    var state = HistoryWindowGroupUIState()

    state.restoreSelectedGroup(from: HistoryGroupSelection.group(group.id).storageValue, groups: [group])
    #expect(state.selectedGroup == .group(group.id))
    #expect(state.selectedGroupID == group.id)

    state.repairSelectedGroupIfNeeded(groups: [])
    #expect(state.selectedGroup == .all)
}

@Test func groupUIStateTracksRenameLifecycle() {
    let group = groupUIStateGroup(name: "Draft")
    var state = HistoryWindowGroupUIState()

    state.beginRename(group)

    #expect(state.renameTargetID == group.id)
    #expect(state.renameText == "Draft")
    #expect(state.renameOriginalText == "Draft")
    #expect(state.isRenameCancelPending == false)
    #expect(state.renameFocusRequestID == 1)

    state.renameText = "Changed"
    state.cancelRename()

    #expect(state.renameTargetID == nil)
    #expect(state.renameText == "Draft")
    #expect(state.isRenameCancelPending == false)
    #expect(state.renameInputScreenFrame == nil)
}

@Test func groupUIStateBuildsMoveMenuAndPickerTarget() {
    let group = groupUIStateGroup(name: "Work", iconName: "briefcase")
    let itemID = UUID()
    var item = ClipboardItem.text("hello", sourceApp: .clipease)
    item.groupID = group.id
    item = ClipboardItem(
        id: itemID,
        type: item.type,
        text: item.text,
        url: item.url,
        linkTitle: item.linkTitle,
        linkSubtitle: item.linkSubtitle,
        imageFileName: item.imageFileName,
        imageWidth: item.imageWidth,
        imageHeight: item.imageHeight,
        imageHash: item.imageHash,
        richTextFileName: item.richTextFileName,
        fileReferences: item.fileReferences,
        createdAt: item.createdAt,
        sourceAppName: item.sourceAppName,
        sourceBundleID: item.sourceBundleID,
        iconName: item.iconName,
        iconFileName: item.iconFileName,
        headerColorHex: item.headerColorHex,
        isPinned: item.isPinned,
        pinnedAt: item.pinnedAt,
        groupID: item.groupID,
        groupedAt: item.groupedAt
    )
    let preview = HistoryPreviewItem(item: item)
    var state = HistoryWindowGroupUIState()

    state.refreshMoveToGroupMenuSnapshot(groups: [group])
    state.presentMoveToGroupPicker(for: preview)

    #expect(state.moveToGroupMenuSnapshot == [MoveToGroupMenuEntry(group: group)])
    #expect(state.moveToGroupPickerTarget == MoveToGroupPickerTarget(itemID: itemID, currentGroupID: group.id))
}

private func groupUIStateGroup(
    id: ClipboardGroup.ID = UUID(),
    name: String,
    iconName: String = "tray.full"
) -> ClipboardGroup {
    ClipboardGroup(
        id: id,
        name: name,
        colorHex: "#2E8CFF",
        iconName: iconName,
        sortOrder: 0,
        createdAt: Date(timeIntervalSince1970: 1),
        updatedAt: Date(timeIntervalSince1970: 1)
    )
}
