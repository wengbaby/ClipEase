import SwiftUI

struct MoveToGroupPickerView: View {
    let target: MoveToGroupPickerTarget
    let groupEntries: [MoveToGroupMenuEntry]
    let onMoveToGroup: (ClipboardItem.ID, ClipboardGroup.ID, String?) -> Void
    let onRemoveFromGroup: (ClipboardItem.ID?) -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(target.currentGroupID == nil ? L("加入分组") : L("移动到分组"))
                        .font(.system(size: 15, weight: .semibold))

                    Text(L("选择一个目标分组"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(L("取消")) {
                    onDismiss()
                }
                .keyboardShortcut(.cancelAction)
            }

            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(groupEntries, id: \.id) { group in
                        moveToGroupPickerRow(group, target: target)
                    }
                }
                .padding(.trailing, 4)
            }
            .frame(width: 340)
            .frame(maxHeight: 260)

            if target.currentGroupID != nil {
                Divider()

                Button(role: .destructive) {
                    onRemoveFromGroup(target.itemID)
                    onDismiss()
                } label: {
                    Label(L("移出分组"), systemImage: "tray.and.arrow.up")
                }
            }
        }
        .padding(18)
        .frame(width: 380)
    }

    private func moveToGroupPickerRow(
        _ group: MoveToGroupMenuEntry,
        target: MoveToGroupPickerTarget
    ) -> some View {
        let isCurrentGroup = group.id == target.currentGroupID

        return Button {
            onMoveToGroup(target.itemID, group.id, group.name)
            onDismiss()
        } label: {
            HStack(spacing: 9) {
                Image(systemName: group.iconName)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 18)

                Text(group.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)

                Spacer()

                if isCurrentGroup {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .foregroundStyle(isCurrentGroup ? .secondary : .primary)
            .padding(.horizontal, 10)
            .frame(height: 32)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isCurrentGroup ? Color.black.opacity(0.05) : Color.white.opacity(0.68))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isCurrentGroup)
    }
}
