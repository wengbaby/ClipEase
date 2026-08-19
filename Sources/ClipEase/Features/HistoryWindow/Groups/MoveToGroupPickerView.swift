import SwiftUI

struct MoveToGroupPickerView: View {
    let target: MoveToGroupPickerTarget
    let groupEntries: [MoveToGroupMenuEntry]
    let onMoveToGroup: (ClipboardItem.ID, ClipboardGroup.ID, String?) -> Void
    let onRemoveFromGroup: (ClipboardItem.ID?) -> Void
    let onDismiss: () -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

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
                LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                    ForEach(Array(groupEntries.enumerated()), id: \.element.id) { index, group in
                        moveToGroupPickerRow(group, target: target)

                        if index < groupEntries.count - 1 {
                            Rectangle()
                                .fill(Color.clear)
                                .frame(height: 0)
                        }
                    }
                }
                .padding(.trailing, 4)
            }
            .frame(width: 340)
            .frame(maxHeight: 220)

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
        let groupColor = Color.clipeaseHex(group.colorHex)

        return Button {
            onMoveToGroup(target.itemID, group.id, group.name)
            onDismiss()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: group.iconName)
                    .font(.system(size: 12, weight: .semibold))

                Text(group.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)

                if isCurrentGroup {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                }
            }
            .foregroundStyle(isCurrentGroup ? .white : .primary)
            .padding(.horizontal, 8)
            .frame(height: 30)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isCurrentGroup
                    ? groupColor
                    : groupColor.opacity(0.18)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(groupColor.opacity(0.4), lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isCurrentGroup)
    }
}
