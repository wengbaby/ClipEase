import SwiftUI
import UniformTypeIdentifiers

private enum SettingsCategory: String, CaseIterable, Identifiable {
    case general
    case shortcut
    case recording
    case groups
    case history
    case performance
    case permissions
    case about

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .general:
            "通用"
        case .shortcut:
            "快捷键"
        case .recording:
            "记录"
        case .groups:
            "分组"
        case .history:
            "历史数据"
        case .performance:
            "性能/日志"
        case .permissions:
            "权限"
        case .about:
            "关于"
        }
    }

    var subtitle: String {
        switch self {
        case .general:
            "保存期限和启动方式"
        case .shortcut:
            "打开或关闭底部历史窗口"
        case .recording:
            "记录状态和忽略 App"
        case .groups:
            "管理分组、颜色和排序"
        case .history:
            "导入、导出、备份和本地文件"
        case .performance:
            "采样、图表和日志文件"
        case .permissions:
            "自动粘贴需要的系统权限"
        case .about:
            "版本信息和项目入口"
        }
    }

    var iconName: String {
        switch self {
        case .general:
            "gearshape"
        case .shortcut:
            "keyboard"
        case .recording:
            "record.circle"
        case .groups:
            "square.grid.2x2"
        case .history:
            "externaldrive"
        case .performance:
            "chart.xyaxis.line"
        case .permissions:
            "lock.shield"
        case .about:
            "info.circle"
        }
    }
}

struct SettingsView: View {
    @ObservedObject var store: ClipboardHistoryStore
    @ObservedObject var recordingController: RecordingController
    @ObservedObject var loginItemController: LoginItemController
    @ObservedObject var ignoredAppSettings: IgnoredAppSettings
    @ObservedObject var globalShortcutSettings: GlobalShortcutSettings
    @ObservedObject var accessibilityPermissionState: AccessibilityPermissionState
    @ObservedObject private var performanceDiagnostics = PerformanceDiagnosticsService.shared
    let pasteExecutor: PasteExecutor

    @State private var isClearConfirmationPresented = false
    @State private var isClearIconCacheConfirmationPresented = false
    @State private var isClearThumbnailCacheConfirmationPresented = false
    @State private var isCleanOrphanedAttachmentsConfirmationPresented = false
    @State private var statusText: String?
    @State private var isRecordingShortcut = false
    @State private var isHistoryTransferInProgress = false
    @State private var isDebugToolsVisible = false
    @State private var versionTapCount = 0
    @State private var selectedCategory: SettingsCategory = .general
    @State private var groupSelection = Set<ClipboardGroup.ID>()
    @State private var groupPendingDeletion: ClipboardGroup?
    @State private var isBulkGroupDeleteConfirmationPresented = false
    @State private var groupAppearancePickerGroupID: ClipboardGroup.ID?
    @State private var groupAppearanceColor = Color(red: 0.18, green: 0.55, blue: 1.0)
    @State private var groupIconSearchText = ""
    @State private var isGroupIconSearchFocused = false
    @State private var focusedSettingsGroupNameID: ClipboardGroup.ID?
    @State private var editingSettingsGroupNames: [ClipboardGroup.ID: String] = [:]
    @StateObject private var historyDataViewModel = SettingsHistoryDataViewModel()
    private let groupAppearancePopoverWidth: CGFloat = 304
    private let groupAppearanceIconGridHeight: CGFloat = 178

    var body: some View {
        HStack(spacing: 0) {
            sidebar

            Divider()

            VStack(alignment: .leading, spacing: 0) {
                header

                Divider()

                ScrollView {
                    VStack(spacing: 14) {
                        selectedContent
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
                .background(Color(nsColor: .windowBackgroundColor))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 820, minHeight: 560)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            accessibilityPermissionState.refresh()
            loginItemController.refresh()
            historyDataViewModel.refreshStorageUsage()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            accessibilityPermissionState.refresh()
        }
        .confirmationDialog(
            "清理孤立附件？",
            isPresented: $isCleanOrphanedAttachmentsConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("清理孤立附件", role: .destructive) {
                cleanOrphanedAttachments()
            }

            Button("取消", role: .cancel) {}
        } message: {
            Text("此操作只会删除没有被当前历史记录引用的图片、缩略图和富文本文件，不会删除历史记录。")
        }
        .confirmationDialog(
            "清空全部历史？",
            isPresented: $isClearConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("清空历史", role: .destructive) {
                store.clearAllItems()
                historyDataViewModel.refreshStorageUsage()
                showStatus("已清空历史")
            }

            Button("取消", role: .cancel) {}
        } message: {
            Text("此操作会删除所有普通和置顶记录，以及已保存的图片文件。")
        }
        .confirmationDialog(
            "清空图标缓存？",
            isPresented: $isClearIconCacheConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("清空图标缓存", role: .destructive) {
                AppIconCache.clearCache()
                historyDataViewModel.refreshStorageUsage()
                showStatus("已清空图标缓存")
            }

            Button("取消", role: .cancel) {}
        } message: {
            Text("此操作只会删除来源 App 图标缓存，不会删除历史记录。后续新复制内容会重新生成图标缓存。")
        }
        .confirmationDialog(
            "清空缩略图缓存？",
            isPresented: $isClearThumbnailCacheConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("清空缩略图缓存", role: .destructive) {
                ClipboardHistoryPersistence.clearThumbnailCache()
                historyDataViewModel.refreshStorageUsage()
                showStatus("已清空缩略图缓存")
            }

            Button("取消", role: .cancel) {}
        } message: {
            Text("此操作只会删除图片卡片使用的缩略图缓存，不会删除原始图片或历史记录。后续显示图片卡片时会重新生成。")
        }
        .confirmationDialog(
            "删除分组？",
            isPresented: Binding(
                get: { groupPendingDeletion != nil },
                set: { isPresented in
                    if !isPresented {
                        groupPendingDeletion = nil
                    }
                }
            ),
            titleVisibility: .visible,
            presenting: groupPendingDeletion
        ) { group in
            Button("删除分组和内容", role: .destructive) {
                deleteGroup(group)
            }

            Button("取消", role: .cancel) {}
        } message: { group in
            Text("会删除“\(group.name)”中的 \(store.itemCount(inGroup: group.id)) 条内容，无法恢复。")
        }
        .confirmationDialog(
            "删除所选分组？",
            isPresented: $isBulkGroupDeleteConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("删除分组和内容", role: .destructive) {
                deleteSelectedGroups()
            }

            Button("取消", role: .cancel) {}
        } message: {
            Text("会删除所选分组及其中内容，无法恢复。")
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 9) {
                Image(nsImage: ClipEaseAppIcon.roundedImage(ClipEaseAppIcon.image(size: NSSize(width: 28, height: 28)), size: NSSize(width: 28, height: 28)))
                    .resizable()
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text("轻贴")
                        .font(.system(size: 15, weight: .semibold))

                    Text("ClipEase")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 18)
            .padding(.bottom, 8)

            ForEach(SettingsCategory.allCases) { category in
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(selectedCategory == category ? Color(nsColor: .selectedContentBackgroundColor).opacity(0.16) : Color.clear)

                    Label(category.title, systemImage: category.iconName)
                        .font(.system(size: 13, weight: .regular))
                        .imageScale(.medium)
                        .symbolVariant(selectedCategory == category ? .fill : .none)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .foregroundStyle(selectedCategory == category ? Color.primary : .secondary)
                }
                .frame(height: 28)
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedCategory = category
                }
            }

            Spacer()
        }
        .padding(.horizontal, 10)
        .frame(width: 150)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(selectedCategory.title)
                    .font(.system(size: 17, weight: .semibold))

                Text(selectedCategory.subtitle)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let statusText {
                Text(statusText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(red: 0.18, green: 0.55, blue: 1.0))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.8))
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private var selectedContent: some View {
        switch selectedCategory {
        case .general:
            retentionSection
            launchAtLoginSection
        case .shortcut:
            shortcutSection
        case .recording:
            recordingSection
            ignoredAppsSection
        case .groups:
            groupsSection
        case .history:
            historySection
        case .performance:
            performanceSection
        case .permissions:
            permissionsSection
        case .about:
            aboutSection
        }
    }

    private var retentionSection: some View {
        settingsSection(title: "保存期限", subtitle: "置顶内容不会被自动清理") {
            HStack(spacing: 8) {
                ForEach(HistoryRetentionPolicy.allCases) { policy in
                    retentionPolicyButton(policy)
                }
            }
        }
    }

    private func retentionPolicyButton(_ policy: HistoryRetentionPolicy) -> some View {
        let isSelected = store.retentionPolicy == policy

        return Button {
            guard store.retentionPolicy != policy else {
                return
            }

            store.retentionPolicy = policy
            showStatus("保存期限已改为：\(policy.title)")
        } label: {
            Text(policy.shortTitle)
                .font(.system(size: 12, weight: .semibold))
                .frame(minWidth: 52, minHeight: 28)
                .padding(.horizontal, 4)
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .background(isSelected ? Color.accentColor : Color.white.opacity(0.72))
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(isSelected ? Color.accentColor : Color.black.opacity(0.08), lineWidth: 1)
                }
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var recordingSection: some View {
        settingsSection(title: "记录状态", subtitle: recordingSubtitle) {
            HStack(spacing: 10) {
                Button(recordingController.isPaused ? "恢复记录" : "暂停记录") {
                    recordingController.togglePaused()
                    showStatus(recordingController.isPaused ? "已暂停记录" : "已恢复记录")
                }
                .buttonStyle(.borderedProminent)

                Button("暂停 15 分钟") {
                    recordingController.pause(for: 15 * 60)
                    showStatus("已暂停 15 分钟")
                }
                .buttonStyle(.bordered)

                Button("暂停 30 分钟") {
                    recordingController.pause(for: 30 * 60)
                    showStatus("已暂停 30 分钟")
                }
                .buttonStyle(.bordered)

                Button("暂停 1 小时") {
                    recordingController.pause(for: 60 * 60)
                    showStatus("已暂停 1 小时")
                }
                .buttonStyle(.bordered)

                Button("暂停 3 小时") {
                    recordingController.pause(for: 3 * 60 * 60)
                    showStatus("已暂停 3 小时")
                }
                .buttonStyle(.bordered)

                Button("暂停 6 小时") {
                    recordingController.pause(for: 6 * 60 * 60)
                    showStatus("已暂停 6 小时")
                }
                .buttonStyle(.bordered)

                Button("暂停到今日结束") {
                    recordingController.pauseUntilEndOfToday()
                    showStatus("已暂停到今日结束")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var launchAtLoginSection: some View {
        settingsSection(title: "开机自动启动", subtitle: loginItemController.statusText) {
            Toggle("启动 macOS 后自动打开轻贴", isOn: Binding(
                get: { loginItemController.isEnabled },
                set: { enabled in
                    loginItemController.setEnabled(enabled)
                    showStatus(loginItemStatusMessage(requestedEnabled: enabled))
                }
            ))
            .toggleStyle(.switch)
        }
    }

    private var shortcutSection: some View {
        settingsSection(title: "快捷键", subtitle: isRecordingShortcut ? "请按下新的快捷键组合，Esc 取消" : "用于打开或关闭底部历史窗口") {
            ZStack {
                HStack(spacing: 10) {
                    Label(globalShortcutSettings.shortcut.displayText, systemImage: "keyboard")
                        .font(.system(size: 13, weight: .medium))

                    Spacer()

                    Button(isRecordingShortcut ? "录制中..." : "修改") {
                        isRecordingShortcut = true
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isRecordingShortcut)

                    Button("恢复默认") {
                        globalShortcutSettings.resetToDefault()
                        isRecordingShortcut = false
                        showStatus("已恢复默认快捷键")
                    }
                    .buttonStyle(.bordered)
                }

                if isRecordingShortcut {
                    ShortcutRecorderView { keyCode, modifierFlags in
                        if globalShortcutSettings.update(keyCode: keyCode, modifierFlags: modifierFlags) {
                            showStatus("已更新快捷键")
                        } else {
                            showStatus("快捷键需要包含 Command、Control 或 Option")
                        }
                        isRecordingShortcut = false
                    } onCancel: {
                        isRecordingShortcut = false
                        showStatus("已取消修改快捷键")
                    }
                    .frame(width: 1, height: 1)
                    .opacity(0.01)
                }
            }
        }
    }

    private var permissionsSection: some View {
        settingsSection(title: "自动粘贴权限", subtitle: accessibilityPermissionState.isTrusted ? "已授权，可以自动粘贴到当前 App" : "未授权时只会复制到剪贴板") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(accessibilityPermissionState.isTrusted ? "已授权" : "需授权", systemImage: accessibilityPermissionState.isTrusted ? "checkmark.circle.fill" : "exclamationmark.lock")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(accessibilityPermissionState.isTrusted ? Color.green : Color.orange)

                    Spacer()

                    Button("打开系统设置") {
                        accessibilityPermissionState.openSystemSettings()
                        accessibilityPermissionState.refresh(promptIfNeeded: true)
                        showStatus("已打开系统设置")
                    }
                    .buttonStyle(.bordered)

                    Button("刷新状态") {
                        accessibilityPermissionState.refresh()
                        showStatus(accessibilityPermissionState.isTrusted ? "已授权自动粘贴" : "仍需授权")
                    }
                    .buttonStyle(.bordered)
                }

                if !accessibilityPermissionState.isTrusted {
                    Text("如果已授权但仍显示需权限，请确认系统设置中授权的是当前运行的 ClipEase.app。开发版本可能和旧路径中的 App 被 macOS 识别为不同应用。")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(.secondary)
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("当前运行 App")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)

                    Text(accessibilityPermissionState.currentAppPath)
                        .font(.system(size: 12, weight: .regular, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .textSelection(.enabled)

                    HStack(spacing: 10) {
                        Button("显示当前 App") {
                            accessibilityPermissionState.revealCurrentAppInFinder()
                            showStatus("已显示当前 App")
                        }
                        .buttonStyle(.bordered)

                        Button("复制 App 路径") {
                            accessibilityPermissionState.copyCurrentAppPath()
                            showStatus("已复制 App 路径")
                        }
                        .buttonStyle(.bordered)

                        Spacer()
                    }
                }
            }
        }
    }

    private var ignoredAppsSection: some View {
        settingsSection(title: "忽略 App", subtitle: ignoredAppsSubtitle) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Button("添加 App") {
                        addIgnoredAppFromPanel()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("清空") {
                        ignoredAppSettings.removeAll()
                        showStatus("已清空忽略 App")
                    }
                    .buttonStyle(.bordered)
                    .disabled(ignoredAppSettings.apps.isEmpty)

                    Spacer()
                }

                if ignoredAppSettings.apps.isEmpty {
                    Text("暂未忽略任何 App。可点击添加，或在历史卡片右键菜单中添加。")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 8) {
                        ForEach(ignoredAppSettings.apps) { app in
                            HStack(spacing: 10) {
                                Image(systemName: "app.dashed")
                                    .font(.system(size: 14, weight: .regular))
                                    .foregroundStyle(Color(red: 0.18, green: 0.55, blue: 1.0))

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(app.name)
                                        .font(.system(size: 13, weight: .regular))

                                    Text(app.bundleID)
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }

                                Spacer()

                                Button("移除") {
                                    ignoredAppSettings.remove(bundleID: app.bundleID)
                                    showStatus("已移除忽略 App")
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                            .padding(10)
                            .background(Color(nsColor: .windowBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        }
                    }
                }
            }
        }
    }

    private var groupsSection: some View {
        SettingsGroupsSection(
            subtitle: groupsSubtitle,
            groups: store.groups,
            groupSelection: groupSelection,
            focusedGroupNameID: $focusedSettingsGroupNameID,
            editingGroupNames: $editingSettingsGroupNames,
            appearancePickerGroupID: $groupAppearancePickerGroupID,
            groupName: { group in
                store.group(with: group.id)?.name ?? group.name
            },
            itemCount: store.itemCount(inGroup:),
            onCreateGroup: {
                let group = store.createGroup()
                groupSelection = [group.id]
                showStatus("已新建“\(group.name)”")
            },
            onRequestDeleteSelectedGroups: requestDeleteSelectedGroups,
            onToggleGroupSelection: toggleGroupSelection,
            onCommitGroupName: commitSettingsGroupName,
            onCancelGroupNameEditing: { group in
                editingSettingsGroupNames[group.id] = store.group(with: group.id)?.name ?? group.name
            },
            onBeginAppearanceEditing: { group in
                groupAppearanceColor = Color.clipeaseHex(store.group(with: group.id)?.colorHex ?? group.colorHex)
                groupIconSearchText = ""
                groupAppearancePickerGroupID = group.id
            },
            onDismissAppearancePicker: closeGroupAppearancePicker,
            onRequestDeleteGroup: requestDeleteGroup
        ) { group in
            groupAppearancePicker(for: group)
        }
    }

    private func groupAppearancePicker(for group: ClipboardGroup) -> some View {
        let currentGroup = store.group(with: group.id) ?? group
        let icons = filteredGroupIcons

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("颜色与图标")
                    .font(.system(size: 14, weight: .semibold))

                Spacer()

                Button("关闭") {
                    closeGroupAppearancePicker()
                }
            }

            HStack(spacing: 10) {
                groupColorPanelSquare(
                    color: groupAppearanceColor,
                    iconName: currentGroup.iconName
                ) { color in
                    groupAppearanceColor = Color(nsColor: color)
                    store.updateGroupAppearance(group.id, colorHex: Color(nsColor: color).clipeaseHexString)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(currentGroup.name)
                        .font(.system(size: 14, weight: .semibold))
                }
            }

            groupColorSwatches { color in
                groupAppearanceColor = color
                store.updateGroupAppearance(group.id, colorHex: color.clipeaseHexString)
            }

            SettingsTextField(
                text: $groupIconSearchText,
                isFocused: $isGroupIconSearchFocused,
                placeholder: "搜索图标"
            )
            .frame(height: 24)

            ScrollView {
                if icons.isEmpty {
                    Text("没有匹配的图标")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(.secondary)
                        .frame(width: 268, height: groupAppearanceIconGridHeight)
                } else {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(38), spacing: 8), count: 6), spacing: 8) {
                        ForEach(icons, id: \.self) { iconName in
                            Button {
                                store.updateGroupAppearance(group.id, iconName: iconName)
                                showStatus("已更新分组图标")
                            } label: {
                                Image(systemName: iconName)
                                    .font(.system(size: 15, weight: .semibold))
                                    .frame(width: 36, height: 36)
                                    .foregroundStyle(currentGroup.iconName == iconName ? .white : .primary)
                                    .background(currentGroup.iconName == iconName ? Color.accentColor : Color.white.opacity(0.45))
                                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .help(iconName)
                        }
                    }
                }
            }
            .frame(width: 268, height: groupAppearanceIconGridHeight)

            Button("确认") {
                closeGroupAppearancePicker()
            }
            .keyboardShortcut(.defaultAction)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(18)
        .frame(width: groupAppearancePopoverWidth)
    }

    private var historySection: some View {
        SettingsHistoryDataSection(
            subtitle: historySubtitle,
            hasItems: !store.items.isEmpty,
            debugTextItemCount: store.debugTextItemCount,
            isHistoryTransferInProgress: isHistoryTransferInProgress,
            isDebugToolsVisible: isDebugToolsVisible,
            viewModel: historyDataViewModel,
            onExportHistory: exportHistory,
            onImportHistory: importHistory,
            onExportBackup: exportBackup,
            onImportBackup: importBackup,
            onOpenDataDirectory: {
                openDirectory(try? ClipEaseStoragePaths.applicationSupportDirectory())
            },
            onOpenImagesDirectory: {
                openDirectory(try? ClipEaseStoragePaths.imagesDirectory())
            },
            onOpenIconCacheDirectory: {
                openDirectory(try? ClipEaseStoragePaths.appIconsDirectory())
            },
            onOpenThumbnailCacheDirectory: {
                openDirectory(try? ClipEaseStoragePaths.thumbnailsDirectory())
            },
            onRequestClearIconCache: {
                isClearIconCacheConfirmationPresented = true
            },
            onRequestClearThumbnailCache: {
                isClearThumbnailCacheConfirmationPresented = true
            },
            onRequestCleanOrphanedAttachments: {
                isCleanOrphanedAttachmentsConfirmationPresented = true
            },
            onRequestClearHistory: {
                isClearConfirmationPresented = true
            },
            onCheckHistoryData: checkHistoryDataHealth,
            onGenerateDebugItems: { count in
                store.addDebugTextItems(count: count)
                showStatus("正在生成 \(count.formatted()) 条测试数据")
            },
            onClearDebugItems: {
                let removedCount = store.clearDebugTextItems()
                historyDataViewModel.refreshStorageUsage()
                showStatus(removedCount > 0 ? "已清理 \(removedCount) 条测试数据" : "没有测试数据")
            },
            onShowStatus: showStatus
        )
    }

    private var performanceSection: some View {
        SettingsDiagnosticsSection(
            diagnostics: performanceDiagnostics,
            onOpenLogsDirectory: {
                performanceDiagnostics.openLogsDirectory()
                showStatus("已打开诊断数据目录")
            },
            onCleanupLogs: {
                performanceDiagnostics.cleanupOldLogs()
                showStatus("已按当前策略清理诊断日志")
            }
        )
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

    private func historyActionGrid<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        LazyVGrid(
            columns: [
                GridItem(.adaptive(minimum: 116, maximum: 156), spacing: 12, alignment: .leading)
            ],
            alignment: .leading,
            spacing: 10
        ) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

    private var aboutSection: some View {
        AboutSettingsSection(
            onOpenGitHub: openGitHub,
            onOpenSupportCommunity: openSupportCommunity,
            onCopyVersion: copyVersion,
            onRevealDebugTools: revealDebugToolsIfNeeded
        )
    }

    private var recordingSubtitle: String {
        if recordingController.isPaused {
            return recordingController.pauseMenuPrimaryTitle()
        }

        return "正在记录新的剪贴板内容"
    }

    private var ignoredAppsSubtitle: String {
        if ignoredAppSettings.apps.isEmpty {
            return "被忽略 App 中复制的内容不会进入历史"
        }

        return "已忽略 \(ignoredAppSettings.apps.count) 个 App"
    }

    private var historySubtitle: String {
        SettingsHistoryDataViewModel.historySubtitle(
            items: store.items,
            storageUsageText: historyDataViewModel.storageUsageText
        )
    }

    private var groupsSubtitle: String {
        SettingsGroupsViewModel.subtitle(groups: store.groups, itemCount: store.itemCount(inGroup:))
    }

    private var filteredGroupIcons: [String] {
        SettingsGroupsViewModel.filteredIcons(query: groupIconSearchText)
    }

    private func closeGroupAppearancePicker() {
        groupAppearancePickerGroupID = nil
        groupIconSearchText = ""
        isGroupIconSearchFocused = false
        GroupColorPanelController.shared.close()
        GroupColorPanelController.closeSharedColorPanel()
    }

    private func groupColorPanelSquare(
        color: Color,
        iconName: String,
        onChange: @escaping (NSColor) -> Void
    ) -> some View {
        GroupColorWell(color: NSColor(color), onChange: onChange)
            .frame(width: 42, height: 42)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay {
                Image(systemName: iconName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .allowsHitTesting(false)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.white.opacity(0.35), lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .buttonStyle(.plain)
            .help("选择颜色")
    }

    private func groupColorSwatches(onSelect: @escaping (Color) -> Void) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 18, maximum: 18), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(ClipboardGroup.defaultColors, id: \.self) { hex in
                let color = Color.clipeaseHex(hex)
                Button {
                    onSelect(color)
                } label: {
                    Circle()
                        .fill(color)
                        .frame(width: 18, height: 18)
                        .overlay {
                            Circle()
                                .stroke(
                                    Color.white.opacity(groupAppearanceColor.clipeaseHexString == hex ? 0.95 : 0.45),
                                    lineWidth: groupAppearanceColor.clipeaseHexString == hex ? 2 : 1
                                )
                        }
                }
                .buttonStyle(.plain)
                .help(hex)
            }
        }
    }

    private func settingsSection<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))

                Text(subtitle)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineSpacing(4)
            }

            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func showStatus(_ text: String) {
        statusText = text
        GlobalStatusToastController.shared.show(text, relativeTo: NSApp.keyWindow)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            if statusText == text {
                statusText = nil
            }
        }
    }

    private func showProgress(_ text: String) {
        statusText = text
        GlobalStatusToastController.shared.show(text, relativeTo: NSApp.keyWindow)
    }

    private func loginItemStatusMessage(requestedEnabled: Bool) -> String {
        if loginItemController.isEnabled {
            return "开机自启动已开启，登录 macOS 后会自动打开轻贴"
        }

        switch loginItemController.statusText {
        case "需要在系统设置中批准":
            return "开机自启动需要在系统设置中批准"
        case "当前构建暂不可用":
            return "当前构建暂不支持开机自启动"
        default:
            return requestedEnabled ? "开机自启动未能开启" : "开机自启动已关闭，登录 macOS 后不会自动打开轻贴"
        }
    }

    private func revealDebugToolsIfNeeded() {
        guard !isDebugToolsVisible else {
            return
        }

        versionTapCount += 1
        if versionTapCount >= 5 {
            isDebugToolsVisible = true
            selectedCategory = .history
            showStatus("已显示性能测试入口")
        }
    }

    private func moveGroups(from source: IndexSet, to destination: Int) {
        store.moveGroup(fromOffsets: source, toOffset: destination)
        showStatus("已更新分组排序")
    }

    private func toggleGroupSelection(_ id: ClipboardGroup.ID) {
        if groupSelection.contains(id) {
            groupSelection.remove(id)
        } else {
            groupSelection.insert(id)
        }
    }

    private func commitSettingsGroupName(_ id: ClipboardGroup.ID, name: String) {
        switch store.renameGroup(id, name: name) {
        case .renamed:
            editingSettingsGroupNames[id] = store.group(with: id)?.name
            showStatus("已重命名分组")
        case .duplicate:
            editingSettingsGroupNames[id] = store.group(with: id)?.name
            showStatus("已有同名分组")
        case .empty:
            editingSettingsGroupNames[id] = store.group(with: id)?.name
            showStatus("分组名称不能为空")
        case .unchanged:
            editingSettingsGroupNames[id] = store.group(with: id)?.name
            break
        case .notFound:
            editingSettingsGroupNames.removeValue(forKey: id)
            showStatus("分组不存在")
        }
    }

    private func requestDeleteGroup(_ group: ClipboardGroup) {
        if store.itemCount(inGroup: group.id) == 0 {
            deleteGroup(group)
        } else {
            groupPendingDeletion = group
        }
    }

    private func requestDeleteSelectedGroups() {
        switch SettingsGroupsViewModel.bulkDeleteDecision(
            selectedIDs: groupSelection,
            itemCount: store.itemCount(inGroup:)
        ) {
        case .none:
            return
        case .confirm:
            isBulkGroupDeleteConfirmationPresented = true
        case .deleteImmediately:
            deleteSelectedGroups()
        }
    }

    private func deleteSelectedGroups() {
        let removedGroupIDs = groupSelection
        let removedItemCount = store.deleteGroups(removedGroupIDs)
        groupSelection.removeAll()
        showStatus(removedItemCount > 0 ? "已删除分组和 \(removedItemCount) 条内容" : "已删除分组")
    }

    private func deleteGroup(_ group: ClipboardGroup) {
        let removedItemCount = store.deleteGroup(group.id)
        groupSelection.remove(group.id)
        groupPendingDeletion = nil
        showStatus(removedItemCount > 0 ? "已删除分组和 \(removedItemCount) 条内容" : "已删除分组")
    }

    private func cleanOrphanedAttachments() {
        historyDataViewModel.cleanOrphanedAttachments(
            items: store.items,
            showStatus: showStatus
        )
    }

    private func checkHistoryDataHealth() {
        historyDataViewModel.checkHistoryDataHealth(
            items: store.items,
            showProgress: showProgress
        ) { report in
            showStatus(report.summary)
            showHistoryDataHealthReport(report)
        }
    }

    private func showHistoryDataHealthReport(_ report: HistoryDataHealthReport) {
        let alert = NSAlert()
        alert.messageText = report.hasIssues ? "发现数据问题" : "数据正常"
        alert.informativeText = report.detailText
        alert.alertStyle = report.hasIssues ? .warning : .informational
        if report.hasRepairableIssues {
            alert.addButton(withTitle: "一键修复")
        }
        alert.addButton(withTitle: "好的")
        let response = alert.runModal()
        if report.hasRepairableIssues,
           response == .alertFirstButtonReturn {
            confirmRepairHistoryData()
        }
    }

    private func confirmRepairHistoryData() {
        let alert = NSAlert()
        alert.messageText = "修复数据问题？"
        alert.informativeText = "轻贴会清理没有被当前历史引用的图片、缩略图和富文本附件，不会删除历史记录。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "一键修复")
        alert.addButton(withTitle: "取消")

        guard alert.runModal() == .alertFirstButtonReturn else {
            showStatus("已取消修复")
            return
        }

        repairHistoryData()
    }

    private func repairHistoryData() {
        historyDataViewModel.repairHistoryData(
            items: store.items,
            showProgress: showProgress
        ) { report in
            showStatus(report.summary)
            showHistoryDataRepairReport(report)
        }
    }

    private func showHistoryDataRepairReport(_ report: HistoryDataRepairReport) {
        let alert = NSAlert()
        alert.messageText = "修复完成"
        alert.informativeText = report.detailText
        alert.alertStyle = report.after.hasIssues ? .warning : .informational
        alert.addButton(withTitle: "好的")
        alert.runModal()
    }

    private func openDirectory(_ url: URL?) {
        guard let url else {
            showStatus("无法打开目录")
            return
        }

        try? FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
        NSWorkspace.shared.open(url)
        showStatus("已打开目录")
    }

    private func exportHistory() {
        let panel = NSSavePanel()
        panel.title = "导出轻贴历史"
        panel.prompt = "导出"
        panel.nameFieldStringValue = "ClipEase-History-\(exportDateString()).json"
        panel.allowedContentTypes = [.json]

        guard panel.runModal() == .OK,
              let url = panel.url else {
            return
        }

        isHistoryTransferInProgress = true
        showProgress("正在导出历史...")
        let items = store.items
        let groups = store.groups

        Task {
            let result = await Task.detached(priority: .utility) {
                Result {
                    try HistoryExportService.export(items: items, groups: groups, to: url)
                }
            }.value

            await MainActor.run {
                isHistoryTransferInProgress = false
                switch result {
                case .success:
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                    showStatus("已导出历史")
                case .failure(let error):
                    showOperationError("导出历史失败", error: error)
                }
            }
        }
    }

    private func importHistory() {
        let panel = NSOpenPanel()
        panel.title = "导入轻贴历史"
        panel.prompt = "导入"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        guard panel.runModal() == .OK,
              let url = panel.url else {
            return
        }

        isHistoryTransferInProgress = true
        showProgress("正在导入历史...")

        Task {
            let result = await Task.detached(priority: .utility) {
                Result {
                    try HistoryExportService.importItems(from: url)
                }
            }.value

            await MainActor.run {
                isHistoryTransferInProgress = false
                switch result {
                case .success(let importedItems):
                    let importedCount = store.importItems(importedItems)
                    historyDataViewModel.refreshStorageUsage()
                    showStatus(importedCount > 0 ? "已导入 \(importedCount) 条历史" : "没有可导入的新历史")
                case .failure(let error):
                    showOperationError("导入历史失败", error: error)
                }
            }
        }
    }

    private func exportBackup() {
        let panel = NSSavePanel()
        panel.title = "导出轻贴备份包"
        panel.prompt = "导出"
        panel.nameFieldStringValue = "ClipEase-Backup-\(exportDateString()).clipeasebackup"
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK,
              let url = panel.url else {
            return
        }

        isHistoryTransferInProgress = true
        showProgress("正在导出备份包...")
        let items = store.items
        let groups = store.groups
        let includesAttachments = historyDataViewModel.includesAttachmentsInBackup

        Task {
            let result = await Task.detached(priority: .utility) {
                Result {
                    try HistoryExportService.exportBackup(
                        items: items,
                        groups: groups,
                        to: url,
                        includesAttachments: includesAttachments
                    )
                }
            }.value

            await MainActor.run {
                isHistoryTransferInProgress = false
                switch result {
                case .success:
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                    showStatus("已导出备份包")
                case .failure(let error):
                    showOperationError("备份包导出失败", error: error)
                }
            }
        }
    }

    private func importBackup() {
        let panel = NSOpenPanel()
        panel.title = "导入轻贴备份包"
        panel.prompt = "导入"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false

        guard panel.runModal() == .OK,
              let url = panel.url else {
            return
        }

        isHistoryTransferInProgress = true
        showProgress("正在导入备份包...")

        Task {
            let result = await Task.detached(priority: .utility) {
                Result {
                    try HistoryExportService.importBackup(from: url)
                }
            }.value

            await MainActor.run {
                isHistoryTransferInProgress = false
                switch result {
                case .success(let importResult):
                    importBackupResult(importResult)
                case .failure(let error):
                    showOperationError("备份包导入失败", error: error)
                }
            }
        }
    }

    private func importBackupResult(_ importResult: BackupImportResult) {
        let duplicateCount = store.duplicateCount(for: importResult.items)
        if let prompt = SettingsHistoryDataActionCoordinator.backupImportDuplicatePrompt(duplicateCount: duplicateCount) {
            let alert = NSAlert()
            alert.messageText = prompt.title
            alert.informativeText = prompt.message
            alert.alertStyle = .informational
            alert.addButton(withTitle: prompt.confirmTitle)
            alert.addButton(withTitle: prompt.cancelTitle)

            guard alert.runModal() == .alertFirstButtonReturn else {
                showStatus("已取消导入备份包")
                return
            }
        }

        let importedCount = store.importBackupItems(importResult.items, groups: importResult.groups)
        historyDataViewModel.refreshStorageUsage()
        showStatus(backupImportStatusText(
            importedCount: importedCount,
            result: importResult
        ))
    }

    private func backupImportStatusText(
        importedCount: Int,
        result: BackupImportResult
    ) -> String {
        SettingsHistoryDataActionCoordinator.backupImportStatusText(
            importedCount: importedCount,
            result: result
        )
    }

    private func showOperationError(_ title: String, error: Error) {
        let message = error.localizedDescription
        NSLog("ClipEase \(title): \(message)")
        showStatus("\(title)：\(message)")
    }

    private func openGitHub() {
        guard let url = AppVersionInfo.githubURL else {
            showStatus("无法打开 GitHub")
            return
        }

        NSWorkspace.shared.open(url)
        showStatus("已打开 GitHub")
    }

    private func copyVersion() {
        ClipboardWriteCoordinator.generalTextWriter().writeText(AppVersionInfo.displayVersion)
        showStatus("已复制版本号")
    }

    private func openSupportCommunity() {
        guard let url = AppVersionInfo.githubSupportURL else {
            showStatus("无法打开交流群")
            return
        }

        NSWorkspace.shared.open(url)
        showStatus("已打开交流群")
    }

    private func exportDateString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmm"
        return formatter.string(from: Date())
    }

    private func addIgnoredAppFromPanel() {
        let panel = NSOpenPanel()
        panel.title = "选择要忽略的 App"
        panel.prompt = "添加"
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        guard panel.runModal() == .OK,
              let url = panel.url else {
            return
        }

        guard let bundle = Bundle(url: url),
              let bundleID = bundle.bundleIdentifier else {
            showStatus("无法识别所选 App")
            return
        }

        let appName = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? url.deletingPathExtension().lastPathComponent

        if ignoredAppSettings.add(bundleID: bundleID, name: appName) {
            showStatus("已忽略 \(appName)")
        } else {
            showStatus("\(appName) 已在忽略列表")
        }
    }
}

struct SettingsTextField: NSViewRepresentable {
    @Binding var text: String
    private let isFocused: Binding<Bool>?
    private let focusedID: Binding<ClipboardGroup.ID?>?
    private let id: ClipboardGroup.ID?
    let placeholder: String
    var onCommit: ((String) -> Void)?
    var onCancel: (() -> Void)?

    init(
        text: Binding<String>,
        isFocused: Binding<Bool>,
        placeholder: String,
        onCommit: ((String) -> Void)? = nil,
        onCancel: (() -> Void)? = nil
    ) {
        _text = text
        self.isFocused = isFocused
        self.focusedID = nil
        self.id = nil
        self.placeholder = placeholder
        self.onCommit = onCommit
        self.onCancel = onCancel
    }

    init(
        text: Binding<String>,
        focusedID: Binding<ClipboardGroup.ID?>,
        id: ClipboardGroup.ID,
        placeholder: String,
        onCommit: ((String) -> Void)? = nil,
        onCancel: (() -> Void)? = nil
    ) {
        _text = text
        self.isFocused = nil
        self.focusedID = focusedID
        self.id = id
        self.placeholder = placeholder
        self.onCommit = onCommit
        self.onCancel = onCancel
    }

    func makeNSView(context: Context) -> SettingsNSTextField {
        let textField = SettingsNSTextField()
        textField.delegate = context.coordinator
        textField.coordinator = context.coordinator
        textField.placeholderString = placeholder
        textField.target = context.coordinator
        textField.action = #selector(Coordinator.textFieldAction(_:))
        textField.isBordered = true
        textField.isBezeled = true
        textField.bezelStyle = .roundedBezel
        textField.focusRingType = .default
        textField.cell?.sendsActionOnEndEditing = false
        return textField
    }

    func updateNSView(_ textField: SettingsNSTextField, context: Context) {
        context.coordinator.parent = self
        textField.coordinator = context.coordinator
        textField.target = context.coordinator
        textField.action = #selector(Coordinator.textFieldAction(_:))
        if textField.stringValue != text {
            textField.stringValue = text
        }
        textField.placeholderString = placeholder

        if isCurrentlyFocused {
            if textField.window?.firstResponder !== textField.currentEditor() {
                textField.window?.makeFirstResponder(textField)
            }
        } else if textField.window?.firstResponder === textField.currentEditor() {
            textField.window?.makeFirstResponder(nil)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class SettingsNSTextField: NSTextField {
        weak var coordinator: Coordinator?

        override func mouseDown(with event: NSEvent) {
            coordinator?.focus(self)
            super.mouseDown(with: event)
            coordinator?.focus(self)
        }

        override func keyDown(with event: NSEvent) {
            if event.keyCode == KeyCode.escape {
                coordinator?.cancel(self)
                window?.makeFirstResponder(nil)
                return
            }

            super.keyDown(with: event)
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: SettingsTextField

        init(parent: SettingsTextField) {
            self.parent = parent
        }

        @MainActor
        func focus(_ textField: NSTextField) {
            parent.setFocused(true)
            if textField.window?.firstResponder !== textField.currentEditor() {
                textField.window?.makeFirstResponder(textField)
            }
            focusSoon(textField)
        }

        @objc
        @MainActor
        func textFieldAction(_ sender: NSTextField) {
            parent.text = sender.stringValue
            parent.onCommit?(sender.stringValue)
        }

        @MainActor
        func controlTextDidBeginEditing(_ notification: Notification) {
            parent.setFocused(true)
        }

        @MainActor
        func controlTextDidChange(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else {
                return
            }

            parent.text = textField.stringValue
        }

        @MainActor
        func controlTextDidEndEditing(_ notification: Notification) {
            if let textField = notification.object as? NSTextField {
                parent.text = textField.stringValue
                parent.onCommit?(textField.stringValue)
            }
            parent.setFocused(false)
        }

        @MainActor
        func cancel(_ textField: NSTextField) {
            parent.onCancel?()
            parent.setFocused(false)
        }

        private func focusSoon(_ textField: NSTextField) {
            DispatchQueue.main.async { [weak textField] in
                guard let textField,
                      let window = textField.window else {
                    return
                }

                if window.firstResponder !== textField.currentEditor() {
                    window.makeFirstResponder(textField)
                }
            }
        }
    }

    private var isCurrentlyFocused: Bool {
        if let isFocused {
            return isFocused.wrappedValue
        }

        if let focusedID, let id {
            return focusedID.wrappedValue == id
        }

        return false
    }

    private func setFocused(_ focused: Bool) {
        if let isFocused {
            isFocused.wrappedValue = focused
        }

        if let focusedID, let id {
            focusedID.wrappedValue = focused ? id : (focusedID.wrappedValue == id ? nil : focusedID.wrappedValue)
        }
    }
}

private struct ShortcutRecorderView: NSViewRepresentable {
    let onRecord: (UInt16, NSEvent.ModifierFlags) -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> RecorderNSView {
        let view = RecorderNSView()
        view.onRecord = onRecord
        view.onCancel = onCancel
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }
        return view
    }

    func updateNSView(_ nsView: RecorderNSView, context: Context) {
        nsView.onRecord = onRecord
        nsView.onCancel = onCancel
        DispatchQueue.main.async {
            nsView.window?.makeFirstResponder(nsView)
        }
    }

    final class RecorderNSView: NSView {
        var onRecord: ((UInt16, NSEvent.ModifierFlags) -> Void)?
        var onCancel: (() -> Void)?

        override var acceptsFirstResponder: Bool {
            true
        }

        override func keyDown(with event: NSEvent) {
            if event.keyCode == KeyCode.escape {
                onCancel?()
                return
            }

            onRecord?(event.keyCode, event.modifierFlags)
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.makeFirstResponder(self)
        }
    }
}
