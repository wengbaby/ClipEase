import SwiftUI

struct HistoryCardContextMenu<TypeSpecificContent: View>: View {
    let item: HistoryPreviewItem
    let isEditable: Bool
    let hasMoveToGroupSnapshot: Bool
    let sourceItem: ClipboardItem?
    let sourceAppIgnoreTitle: String
    let onPaste: () -> Void
    let onPastePlainText: () -> Void
    let onPreview: () -> Void
    let onEdit: () -> Void
    let onTogglePinned: () -> Void
    let onPresentMoveToGroupPicker: () -> Void
    let onRemoveFromGroup: () -> Void
    let onDelete: () -> Void
    let onToggleSourceAppIgnored: () -> Void
    let onCopySourceAppName: () -> Void
    let onCopySourceBundleID: () -> Void
    @ViewBuilder let typeSpecificContent: () -> TypeSpecificContent

    var body: some View {
        Button(HistoryCommand.paste.title) {
            onPaste()
        }
        .historyKeyboardShortcut(.paste)

        if item.type == .text || item.type == .link || item.type == .color {
            Button(HistoryCommand.pastePlainText.title) {
                onPastePlainText()
            }
            .historyKeyboardShortcut(.pastePlainText)
        }

        Button(HistoryCommand.preview.title) {
            onPreview()
        }
        .historyKeyboardShortcut(.preview)

        if isEditable {
            Button(HistoryCommand.edit.title) {
                onEdit()
            }
            .historyKeyboardShortcut(.edit)
        }

        Button(item.isPinned ? L("取消置顶") : L("置顶")) {
            onTogglePinned()
        }

        Divider()

        typeSpecificContent()

        if hasMoveToGroupSnapshot {
            Button(item.groupID == nil ? L("加入分组...") : L("移动到分组...")) {
                onPresentMoveToGroupPicker()
            }
        }

        if item.groupID != nil {
            Button(L("移出分组")) {
                onRemoveFromGroup()
            }
        }

        Button(L("删除"), role: .destructive) {
            onDelete()
        }

        if let sourceItem, sourceItem.sourceBundleID != nil {
            Divider()

            if !sourceItem.isFromClipEase {
                Button(sourceAppIgnoreTitle) {
                    onToggleSourceAppIgnored()
                }
            }

            Button(L("复制来源 App 名称")) {
                onCopySourceAppName()
            }

            Button(L("复制来源 Bundle ID")) {
                onCopySourceBundleID()
            }
        }
    }
}
