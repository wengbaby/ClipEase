import SwiftUI

struct SettingsGroupsSection<AppearancePicker: View>: View {
    let subtitle: String
    let groups: [ClipboardGroup]
    let groupSelection: Set<ClipboardGroup.ID>
    @Binding var focusedGroupNameID: ClipboardGroup.ID?
    @Binding var editingGroupNames: [ClipboardGroup.ID: String]
    @Binding var appearancePickerGroupID: ClipboardGroup.ID?
    let groupName: (ClipboardGroup) -> String
    let itemCount: (ClipboardGroup.ID) -> Int
    let onCreateGroup: () -> Void
    let onRequestDeleteSelectedGroups: () -> Void
    let onToggleGroupSelection: (ClipboardGroup.ID) -> Void
    let onCommitGroupName: (ClipboardGroup.ID, String) -> Void
    let onCancelGroupNameEditing: (ClipboardGroup) -> Void
    let onBeginAppearanceEditing: (ClipboardGroup) -> Void
    let onDismissAppearancePicker: () -> Void
    let onRequestDeleteGroup: (ClipboardGroup) -> Void
    let appearancePicker: (ClipboardGroup) -> AppearancePicker

    var body: some View {
        SettingsSection(title: L("分组管理"), subtitle: subtitle) {
            VStack(alignment: .leading, spacing: 12) {
                historyActionGroup(title: L("操作")) {
                    historyButton(L("新建分组"), prominent: true, action: onCreateGroup)

                    Button(L("删除所选"), role: .destructive, action: onRequestDeleteSelectedGroups)
                        .buttonStyle(.bordered)
                        .frame(minWidth: 88)
                        .disabled(groupSelection.isEmpty)
                }

                if groups.isEmpty {
                    Text(L("暂无分组"))
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(groups) { group in
                                groupManagementRow(group)
                                    .padding(.horizontal, 8)
                                    .background(
                                        groupSelection.contains(group.id)
                                            ? Color(nsColor: .selectedContentBackgroundColor).opacity(0.12)
                                            : Color.clear
                                    )
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .frame(minHeight: 260)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
            }
        }
    }

    private func groupManagementRow(_ group: ClipboardGroup) -> some View {
        HStack(spacing: 10) {
            Button {
                onToggleGroupSelection(group.id)
            } label: {
                Image(systemName: groupSelection.contains(group.id) ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .foregroundStyle(groupSelection.contains(group.id) ? Color.accentColor : .secondary)

            Image(systemName: group.iconName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Color.clipeaseHex(group.colorHex))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            SettingsTextField(
                text: Binding(
                    get: { editingGroupNames[group.id] ?? groupName(group) },
                    set: { editingGroupNames[group.id] = $0 }
                ),
                focusedID: $focusedGroupNameID,
                id: group.id,
                placeholder: L("分组名称"),
                onCommit: { name in
                    onCommitGroupName(group.id, name)
                },
                onCancel: {
                    onCancelGroupNameEditing(group)
                }
            )
            .frame(height: 24)
            .frame(minWidth: 150)

            Button {
                onBeginAppearanceEditing(group)
            } label: {
                Label(L("颜色与图标"), systemImage: "paintpalette")
            }
            .buttonStyle(.borderless)
            .help(L("调整颜色和图标"))
            .background(
                PersistentPopoverPresenter(
                    isPresented: Binding(
                        get: { appearancePickerGroupID == group.id },
                        set: { isPresented in
                            appearancePickerGroupID = isPresented ? group.id : nil
                            if !isPresented {
                                onDismissAppearancePicker()
                            }
                        }
                    ),
                    arrowEdge: .bottom,
                    onDismiss: onDismissAppearancePicker
                ) {
                    appearancePicker(group)
                }
            )

            Text(L("\(itemCount(group.id)) 条"))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .trailing)

            Button(role: .destructive) {
                onRequestDeleteGroup(group)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help(L("删除分组"))
        }
        .padding(.vertical, 4)
    }

    private func historyActionGroup<Content: View>(
        title: String,
        wrapsContent: Bool = false,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            if wrapsContent {
                content()
            } else {
                HStack(spacing: 10) {
                    content()
                    Spacer(minLength: 0)
                }
            }
        }
    }

    @ViewBuilder
    private func historyButton(
        _ title: String,
        minWidth: CGFloat = 88,
        prominent: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        if prominent {
            Button(title, action: action)
                .buttonStyle(.borderedProminent)
                .frame(minWidth: minWidth)
        } else {
            Button(title, action: action)
                .buttonStyle(.bordered)
                .frame(minWidth: minWidth)
        }
    }
}
