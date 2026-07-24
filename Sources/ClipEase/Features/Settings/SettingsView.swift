import AppKit
import SwiftUI
import UniformTypeIdentifiers

private enum SettingsCategory: String, CaseIterable, Identifiable {
    case general
    case appearance
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
            L("通用")
        case .appearance:
            L("外观")
        case .shortcut:
            L("快捷键")
        case .recording:
            L("记录")
        case .groups:
            L("分组")
        case .history:
            L("历史数据")
        case .performance:
            L("性能/日志")
        case .permissions:
            L("权限")
        case .about:
            L("关于")
        }
    }

    var subtitle: String {
        switch self {
        case .general:
            L("保存期限和启动方式")
        case .appearance:
            L("主题、玻璃、卡片和字体")
        case .shortcut:
            L("打开或关闭底部历史窗口")
        case .recording:
            L("记录状态和忽略 App")
        case .groups:
            L("管理分组、颜色和排序")
        case .history:
            L("导入、导出、备份和本地文件")
        case .performance:
            L("采样、图表和日志文件")
        case .permissions:
            L("自动粘贴需要的系统权限")
        case .about:
            L("版本信息和项目入口")
        }
    }

    var iconName: String {
        switch self {
        case .general:
            "gearshape"
        case .appearance:
            "paintbrush"
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
    @ObservedObject var appearanceSettings: AppearanceSettings
    @ObservedObject private var performanceDiagnostics = PerformanceDiagnosticsService.shared
    @ObservedObject private var languageSettings = AppLanguageSettings.shared
    let pasteExecutor: PasteExecutor
    let clipboardWriter: ClipboardWriteCoordinator

    @State private var isClearConfirmationPresented = false
    @State private var isClearIconCacheConfirmationPresented = false
    @State private var isClearThumbnailCacheConfirmationPresented = false
    @State private var isCleanOrphanedAttachmentsConfirmationPresented = false
    @State private var statusText: String?
    @State private var isRecordingShortcut = false
    @State private var isHistoryTransferInProgress = false
    @State private var isDebugToolsVisible = false
    @State private var isWindowEffectGalleryExpanded = false
    @State private var isCardStyleGalleryExpanded = false
    @State private var versionTapCount = 0
    @State private var selectedCategory: SettingsCategory = .general
    @State private var groupSelection = Set<ClipboardGroup.ID>()
    @State private var groupPendingDeletion: ClipboardGroup?
    @State private var groupPendingDeletionAssessment: SettingsHistoryDataActionCoordinator.GroupDeletionAssessment?
    @State private var isBulkGroupDeleteConfirmationPresented = false
    @State private var bulkGroupPendingDeletionIDs = Set<ClipboardGroup.ID>()
    @State private var bulkGroupPendingDeletionAssessment: SettingsHistoryDataActionCoordinator.GroupDeletionAssessment?
    @State private var isGroupDeletionAssessmentInProgress = false
    @State private var groupAppearancePickerGroupID: ClipboardGroup.ID?
    @State private var groupAppearanceColor = Color(red: 0.18, green: 0.55, blue: 1.0)
    @State private var groupIconSearchText = ""
    @State private var isGroupIconSearchFocused = false
    @State private var focusedSettingsGroupNameID: ClipboardGroup.ID?
    @State private var editingSettingsGroupNames: [ClipboardGroup.ID: String] = [:]
    @StateObject private var historyDataViewModel = SettingsHistoryDataViewModel()
    @StateObject private var updateViewModel = SettingsUpdateViewModel()
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
                .background(settingsContentBackdrop)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 820, minHeight: 560)
        .background(settingsWindowBackdrop)
        .preferredColorScheme(appearanceSettings.preferredColorScheme)
        .onAppear {
            accessibilityPermissionState.refresh()
            loginItemController.refresh()
            historyDataViewModel.refreshStorageUsage()
            if selectedCategory == .about {
                updateViewModel.checkAutomaticallyIfNeeded()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            accessibilityPermissionState.refresh()
        }
        .confirmationDialog(
            L("清理孤立附件？"),
            isPresented: $isCleanOrphanedAttachmentsConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button(L("清理孤立附件"), role: .destructive) {
                cleanOrphanedAttachments()
            }

            Button(L("取消"), role: .cancel) {}
        } message: {
            Text(L("此操作只会删除没有被当前历史记录引用的图片、缩略图和富文本文件，不会删除历史记录。"))
        }
        .confirmationDialog(
            L("清空全部历史？"),
            isPresented: $isClearConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button(L("清空历史"), role: .destructive) {
                store.clearAllItems()
                historyDataViewModel.refreshStorageUsage()
                showStatus(L("已清空历史"))
            }

            Button(L("取消"), role: .cancel) {}
        } message: {
            Text(L("此操作会删除所有普通和置顶记录，以及已保存的图片文件。"))
        }
        .confirmationDialog(
            L("清空图标缓存？"),
            isPresented: $isClearIconCacheConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button(L("清空图标缓存"), role: .destructive) {
                AppIconCache.clearCache()
                historyDataViewModel.refreshStorageUsage()
                showStatus(L("已清空图标缓存"))
            }

            Button(L("取消"), role: .cancel) {}
        } message: {
            Text(L("此操作只会删除来源 App 图标缓存，不会删除历史记录。后续新复制内容会重新生成图标缓存。"))
        }
        .confirmationDialog(
            L("清空缩略图缓存？"),
            isPresented: $isClearThumbnailCacheConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button(L("清空缩略图缓存"), role: .destructive) {
                ClipboardHistoryPersistence.clearThumbnailCache()
                historyDataViewModel.refreshStorageUsage()
                showStatus(L("已清空缩略图缓存"))
            }

            Button(L("取消"), role: .cancel) {}
        } message: {
            Text(L("此操作只会删除图片卡片使用的缩略图缓存，不会删除原始图片或历史记录。后续显示图片卡片时会重新生成。"))
        }
        .confirmationDialog(
            L("删除分组？"),
            isPresented: Binding(
                get: { groupPendingDeletion != nil },
                set: { isPresented in
                    if !isPresented {
                        groupPendingDeletion = nil
                        groupPendingDeletionAssessment = nil
                    }
                }
            ),
            titleVisibility: .visible,
            presenting: groupPendingDeletion
        ) { group in
            Button(L("删除分组和内容"), role: .destructive) {
                confirmDeleteGroup(group)
            }

            Button(L("取消"), role: .cancel) {}
        } message: { group in
            Text(L("会删除“\(group.name)”中的 \(groupPendingDeletionAssessment?.itemCount ?? 0) 条内容，无法恢复。"))
        }
        .confirmationDialog(
            L("删除所选分组？"),
            isPresented: Binding(
                get: { isBulkGroupDeleteConfirmationPresented },
                set: { isPresented in
                    isBulkGroupDeleteConfirmationPresented = isPresented
                    if !isPresented {
                        bulkGroupPendingDeletionIDs.removeAll()
                        bulkGroupPendingDeletionAssessment = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            Button(L("删除分组和内容"), role: .destructive) {
                confirmDeleteSelectedGroups()
            }

            Button(L("取消"), role: .cancel) {}
        } message: {
            Text(L("会删除所选分组中的 \(bulkGroupPendingDeletionAssessment?.itemCount ?? 0) 条内容，无法恢复。"))
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 9) {
                Image(nsImage: ClipEaseAppIcon.roundedImage(ClipEaseAppIcon.image(size: NSSize(width: 28, height: 28)), size: NSSize(width: 28, height: 28)))
                    .resizable()
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(L("轻贴"))
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
        .background(settingsSidebarBackdrop)
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
            languageSection
            retentionSection
            launchAtLoginSection
        case .appearance:
            appearanceSection
            typographySection
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

    private var languageSection: some View {
        settingsSection(title: L("语言"), subtitle: L("界面语言会立即切换；首次安装默认跟随系统语言。")) {
            Picker(L("语言"), selection: $languageSettings.preference) {
                Text(L("跟随系统")).tag(AppLanguage.system)
                Text(L("简体中文")).tag(AppLanguage.simplifiedChinese)
                Text(L("英文")).tag(AppLanguage.english)
            }
            .pickerStyle(.segmented)
        }
    }

    private var appearanceSection: some View {
        settingsSection(title: L("外观"), subtitle: L("立即预览并自动保存")) {
            VStack(alignment: .leading, spacing: 12) {
                Picker(L("主题"), selection: $appearanceSettings.colorTheme) {
                    ForEach(AppearanceColorTheme.allCases) { theme in
                        Text(theme.title).tag(theme)
                    }
                }
                .pickerStyle(.segmented)

                Text(L("窗口效果"))
                    .font(.system(size: 12, weight: .semibold))

                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6),
                    spacing: 8
                ) {
                    ForEach(visibleMaterialThemes) { theme in
                        appearanceMaterialTile(theme)
                    }
                }

                appearanceGalleryToggle(
                    isExpanded: isWindowEffectGalleryExpanded,
                    hiddenCount: AppearanceMaterialTheme.allCases.count - appearanceGalleryCollapsedCount
                ) {
                    isWindowEffectGalleryExpanded.toggle()
                }

                Toggle(L("液态玻璃效果"), isOn: $appearanceSettings.liquidGlassEnabled)

                opacitySlider(
                    title: L("窗口效果透明度"),
                    value: $appearanceSettings.windowEffectOpacity
                )

                Toggle(L("动态玻璃效果"), isOn: $appearanceSettings.glassMotionEnabled)

                Text(L("卡片样式"))
                    .font(.system(size: 12, weight: .semibold))

                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6),
                    spacing: 8
                ) {
                    ForEach(visibleCardStyles) { style in
                        appearanceStyleTile(style)
                    }
                }

                appearanceGalleryToggle(
                    isExpanded: isCardStyleGalleryExpanded,
                    hiddenCount: AppearanceCardStyle.allCases.count - appearanceGalleryCollapsedCount
                ) {
                    isCardStyleGalleryExpanded.toggle()
                }

                opacitySlider(
                    title: L("卡片效果透明度"),
                    value: $appearanceSettings.cardEffectOpacity
                )

                opacitySlider(
                    title: L("卡片顶部颜色强度"),
                    value: $appearanceSettings.cardHeaderColorIntensity
                )

                opacitySlider(
                    title: L("窗口分组颜色强度"),
                    value: $appearanceSettings.groupColorIntensity
                )

                opacitySlider(
                    title: L("顶部文字对比度"),
                    value: $appearanceSettings.toolbarTextContrast
                )

                if let reason = appearanceSettings.liquidGlassUnavailableReason {
                    Text(reason)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Button(L("恢复默认外观")) {
                    appearanceSettings.resetToDefaults()
                }
                .buttonStyle(.link)
            }
        }
    }

    private func appearanceStyleTile(_ style: AppearanceCardStyle) -> some View {
        let isSelected = appearanceSettings.cardStyle == style

        return Button {
            appearanceSettings.cardStyle = style
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(style.materialTheme.gradient)
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(
                                isSelected ? Color.accentColor : Color.primary.opacity(0.18),
                                lineWidth: isSelected ? 2 : 1
                            )
                    }
                    .overlay(alignment: .topLeading) {
                        Capsule()
                            .fill(Color.white.opacity(0.72))
                            .frame(width: 30, height: 4)
                            .padding(8)
                    }
                    .frame(height: 42)
                    .shadow(color: style == .deepSpace || style == .obsidian ? Color.black.opacity(0.42) : .clear, radius: 6, y: 3)

                Text(style.title)
                    .font(.system(size: 10, weight: isSelected ? .bold : .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 62, alignment: .topLeading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, minHeight: 62, alignment: .topLeading)
        .contentShape(Rectangle())
        .accessibilityLabel(L("卡片样式：\(style.title)"))
        .accessibilityValue(isSelected ? L("已选择") : L("未选择"))
    }

    private func appearanceMaterialTile(_ theme: AppearanceMaterialTheme) -> some View {
        let isSelected = appearanceSettings.materialTheme == theme
        let isUnavailableNativeGlass = appearanceSettings.liquidGlassEnabled && !HistoryGlassRuntime.supportsNativeGlass

        return Button {
            appearanceSettings.materialTheme = theme
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(theme.gradient)
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(
                                isSelected ? Color.accentColor : Color.primary.opacity(0.18),
                                lineWidth: isSelected ? 2 : 1
                            )
                    }
                    .overlay(alignment: .topLeading) {
                        Capsule()
                            .fill(Color.white.opacity(0.74))
                            .frame(width: 28, height: 4)
                            .padding(8)
                    }
                    .frame(height: 42)
                    .shadow(color: theme == .deepSpace || theme == .obsidian ? Color.black.opacity(0.42) : .clear, radius: 6, y: 3)

                Text(theme.title)
                    .font(.system(size: 10, weight: isSelected ? .bold : .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 62, alignment: .topLeading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, minHeight: 62, alignment: .topLeading)
        .contentShape(Rectangle())
        .opacity(isUnavailableNativeGlass ? 0.58 : 1)
        .accessibilityLabel(L("窗口效果：\(theme.title)"))
        .accessibilityValue(isSelected ? L("已选择") : L("未选择"))
        .help(isUnavailableNativeGlass ? L("当前系统会以兼容玻璃呈现") : theme.title)
    }

    private let appearanceGalleryCollapsedCount = 12

    private var visibleMaterialThemes: [AppearanceMaterialTheme] {
        isWindowEffectGalleryExpanded ? AppearanceMaterialTheme.allCases : Array(AppearanceMaterialTheme.allCases.prefix(appearanceGalleryCollapsedCount))
    }

    private var visibleCardStyles: [AppearanceCardStyle] {
        isCardStyleGalleryExpanded ? AppearanceCardStyle.allCases : Array(AppearanceCardStyle.allCases.prefix(appearanceGalleryCollapsedCount))
    }

    private func appearanceGalleryToggle(
        isExpanded: Bool,
        hiddenCount: Int,
        action: @escaping () -> Void
    ) -> some View {
        Button(isExpanded ? L("收起") : L("显示更多（\(hiddenCount) 项）"), action: action)
            .buttonStyle(.link)
    }

    private var typographyControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(AppearanceTypographyRole.allCases) { role in
                typographyControl(for: role)
            }
        }
    }

    private var typographySection: some View {
        settingsSection(title: L("文字样式"), subtitle: L("窗口与卡片文字分别设置")) {
            typographyControls
        }
    }

    private func typographyControl(for role: AppearanceTypographyRole) -> some View {
        let typography = appearanceSettings.typography(for: role)
        return VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(role.title)
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text(L("预览：轻贴 · 搜索 · 分组"))
                    .font(typography.swiftUIFont)
                    .lineLimit(1)
            }

            HStack(spacing: 8) {
                AppearanceFontFamilyPicker(family: typographyBinding(role, \.family))
                    .frame(minWidth: 190, maxWidth: .infinity)

                Picker(L("字重"), selection: typographyBinding(role, \.weight)) {
                    ForEach(AppearanceTypographyWeight.allCases) { weight in
                        Text(weight.title).tag(weight)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 80)
            }

            HStack(spacing: 10) {
                Text(L("字号"))
                    .font(.system(size: 11, weight: .medium))
                Slider(value: typographyBinding(role, \.size), in: 10...32, step: 1)
                Text("\(Int(typography.size)) pt")
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 42, alignment: .trailing)
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func typographyBinding<Value>(
        _ role: AppearanceTypographyRole,
        _ keyPath: WritableKeyPath<AppearanceTypography, Value>
    ) -> Binding<Value> {
        Binding(
            get: { appearanceSettings.typography(for: role)[keyPath: keyPath] },
            set: { value in
                var typography = appearanceSettings.typography(for: role)
                typography[keyPath: keyPath] = value
                appearanceSettings.updateTypography(typography, for: role)
            }
        )
    }

    private func opacitySlider(title: String, value: Binding<Double>) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
            Slider(value: value, in: 0...1)
            Text("\(Int(value.wrappedValue * 100))%")
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
    }

    private var settingsWindowBackdrop: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            appearanceSettings.materialTheme.gradient
                .opacity(appearanceSettings.windowEffectOpacity * 0.62)
        }
    }

    private var settingsContentBackdrop: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor).opacity(0.62)
            appearanceSettings.materialTheme.gradient
                .opacity(appearanceSettings.windowEffectOpacity * 0.36)
        }
    }

    private var settingsSidebarBackdrop: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor).opacity(0.78)
            appearanceSettings.materialTheme.gradient
                .opacity(appearanceSettings.windowEffectOpacity * 0.28)
        }
    }

    private var retentionSection: some View {
        settingsSection(title: L("保存期限"), subtitle: L("置顶内容不会被自动清理")) {
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
            showStatus(L("保存期限已改为：\(policy.title)"))
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
        settingsSection(title: L("记录状态"), subtitle: recordingSubtitle) {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4),
                spacing: 8
            ) {
                recordingControlButton(
                    recordingController.isPaused ? L("恢复记录") : L("暂停记录"),
                    isActive: recordingController.isPaused
                ) {
                    recordingController.togglePaused()
                    showStatus(recordingController.isPaused ? L("已暂停记录") : L("已恢复记录"))
                }

                ForEach(RecordingPausePreset.allCases, id: \.self) { preset in
                    recordingControlButton(
                        preset.title,
                        isActive: recordingController.activePausePreset == preset
                    ) {
                        if preset == .untilEndOfToday {
                            recordingController.pauseUntilEndOfToday()
                            showStatus(L("已暂停到今日结束"))
                        } else if let interval = preset.interval {
                            recordingController.pause(for: interval, preset: preset)
                            showStatus(pauseStatusMessage(for: preset))
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func recordingControlButton(
        _ title: String,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        if isActive {
            Button(title, action: action)
                .buttonStyle(.borderedProminent)
        } else {
            Button(title, action: action)
                .buttonStyle(.bordered)
        }
    }

    private func pauseStatusMessage(for preset: RecordingPausePreset) -> String {
        switch preset {
        case .fifteenMinutes: L("已暂停 15 分钟")
        case .thirtyMinutes: L("已暂停 30 分钟")
        case .oneHour: L("已暂停 1 小时")
        case .threeHours: L("已暂停 3 小时")
        case .sixHours: L("已暂停 6 小时")
        case .untilEndOfToday: L("已暂停到今日结束")
        }
    }

    private var launchAtLoginSection: some View {
        settingsSection(title: L("开机自动启动"), subtitle: loginItemController.statusText) {
            Toggle(L("启动 macOS 后自动打开轻贴"), isOn: Binding(
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
        settingsSection(title: L("快捷键"), subtitle: isRecordingShortcut ? L("请按下新的快捷键组合，Esc 取消") : L("用于打开或关闭底部历史窗口")) {
            ZStack {
                HStack(spacing: 10) {
                    Label(globalShortcutSettings.shortcut.displayText, systemImage: "keyboard")
                        .font(.system(size: 13, weight: .medium))

                    Spacer()

                    Button(isRecordingShortcut ? L("录制中...") : L("修改")) {
                        isRecordingShortcut = true
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isRecordingShortcut)

                    Button(L("恢复默认")) {
                        globalShortcutSettings.resetToDefault()
                        isRecordingShortcut = false
                        showStatus(L("已恢复默认快捷键"))
                    }
                    .buttonStyle(.bordered)
                }

                if isRecordingShortcut {
                    ShortcutRecorderView { keyCode, modifierFlags in
                        if globalShortcutSettings.update(keyCode: keyCode, modifierFlags: modifierFlags) {
                            showStatus(L("已更新快捷键"))
                        } else {
                            showStatus(L("快捷键需要包含 Command、Control 或 Option"))
                        }
                        isRecordingShortcut = false
                    } onCancel: {
                        isRecordingShortcut = false
                        showStatus(L("已取消修改快捷键"))
                    }
                    .frame(width: 1, height: 1)
                    .opacity(0.01)
                }
            }
        }
    }

    private var permissionsSection: some View {
        settingsSection(title: L("自动粘贴权限"), subtitle: accessibilityPermissionState.isTrusted ? L("已授权，可以自动粘贴到当前 App") : L("未授权时只会复制到剪贴板")) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(accessibilityPermissionState.isTrusted ? L("已授权") : L("需授权"), systemImage: accessibilityPermissionState.isTrusted ? "checkmark.circle.fill" : "exclamationmark.lock")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(accessibilityPermissionState.isTrusted ? Color.green : Color.orange)

                    Spacer()

                    Button(L("打开系统设置")) {
                        accessibilityPermissionState.openSystemSettings()
                        accessibilityPermissionState.refresh(promptIfNeeded: true)
                        showStatus(L("已打开系统设置"))
                    }
                    .buttonStyle(.bordered)

                    Button(L("刷新状态")) {
                        accessibilityPermissionState.refresh()
                        showStatus(accessibilityPermissionState.isTrusted ? L("已授权自动粘贴") : L("仍需授权"))
                    }
                    .buttonStyle(.bordered)
                }

                if !accessibilityPermissionState.isTrusted {
                    Text(L("如果已授权但仍显示需权限，请确认系统设置中授权的是当前运行的 ClipEase.app。开发版本可能和旧路径中的 App 被 macOS 识别为不同应用。"))
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(.secondary)
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text(L("当前运行 App"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)

                    Text(accessibilityPermissionState.currentAppPath)
                        .font(.system(size: 12, weight: .regular, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .textSelection(.enabled)

                    HStack(spacing: 10) {
                        Button(L("显示当前 App")) {
                            accessibilityPermissionState.revealCurrentAppInFinder()
                            showStatus(L("已显示当前 App"))
                        }
                        .buttonStyle(.bordered)

                        Button(L("复制 App 路径")) {
                            accessibilityPermissionState.copyCurrentAppPath(using: clipboardWriter)
                            showStatus(L("已复制 App 路径"))
                        }
                        .buttonStyle(.bordered)

                        Spacer()
                    }
                }
            }
        }
    }

    private var ignoredAppsSection: some View {
        settingsSection(title: L("忽略 App"), subtitle: ignoredAppsSubtitle) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Button(L("添加 App")) {
                        addIgnoredAppFromPanel()
                    }
                    .buttonStyle(.borderedProminent)

                    Button(L("清空")) {
                        ignoredAppSettings.removeAll()
                        showStatus(L("已清空忽略 App"))
                    }
                    .buttonStyle(.bordered)
                    .disabled(ignoredAppSettings.apps.isEmpty)

                    Spacer()
                }

                if ignoredAppSettings.apps.isEmpty {
                    Text(L("暂未忽略任何 App。可点击添加，或在历史卡片右键菜单中添加。"))
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

                                Button(L("移除")) {
                                    ignoredAppSettings.remove(bundleID: app.bundleID)
                                    showStatus(L("已移除忽略 App"))
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
                showStatus(L("已新建“\(group.name)”"))
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
                Text(L("颜色与图标"))
                    .font(.system(size: 14, weight: .semibold))

                Spacer()

                Button(L("关闭")) {
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
                placeholder: L("搜索图标")
            )
            .frame(height: 24)

            ScrollView {
                if icons.isEmpty {
                    Text(L("没有匹配的图标"))
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(.secondary)
                        .frame(width: 268, height: groupAppearanceIconGridHeight)
                } else {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(38), spacing: 8), count: 6), spacing: 8) {
                        ForEach(icons, id: \.self) { iconName in
                            Button {
                                store.updateGroupAppearance(group.id, iconName: iconName)
                                showStatus(L("已更新分组图标"))
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

            Button(L("确认")) {
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
                showStatus(L("正在生成 \(count.formatted()) 条测试数据"))
            },
            onClearDebugItems: {
                let removedCount = store.clearDebugTextItems()
                historyDataViewModel.refreshStorageUsage()
                showStatus(removedCount > 0 ? L("已清理 \(removedCount) 条测试数据") : L("没有测试数据"))
            },
            onShowStatus: showStatus
        )
    }

    private var performanceSection: some View {
        SettingsDiagnosticsSection(
            diagnostics: performanceDiagnostics,
            onOpenLogsDirectory: {
                performanceDiagnostics.openLogsDirectory()
                showStatus(L("已打开诊断数据目录"))
            },
            onCleanupLogs: {
                performanceDiagnostics.cleanupOldLogs()
                showStatus(L("已按当前策略清理诊断日志"))
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
            updateViewModel: updateViewModel,
            onOpenGitHub: openGitHub,
            onOpenSupportCommunity: openSupportCommunity,
            onCopyVersion: copyVersion,
            onRevealDebugTools: revealDebugToolsIfNeeded,
            onCheckForUpdates: checkForUpdates,
            onOpenRelease: openRelease,
            onDownloadUpdate: downloadUpdate
        )
        .onAppear {
            updateViewModel.checkAutomaticallyIfNeeded()
        }
    }

    private var recordingSubtitle: String {
        if recordingController.isPaused {
            return recordingController.pauseMenuPrimaryTitle()
        }

        return L("正在记录新的剪贴板内容")
    }

    private var ignoredAppsSubtitle: String {
        if ignoredAppSettings.apps.isEmpty {
            return L("被忽略 App 中复制的内容不会进入历史")
        }

        return L("已忽略 \(ignoredAppSettings.apps.count) 个 App")
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
            .help(L("选择颜色"))
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
            return L("开机自启动已开启，登录 macOS 后会自动打开轻贴")
        }

        switch loginItemController.statusText {
        case L("需要在系统设置中批准"):
            return L("开机自启动需要在系统设置中批准")
        case L("当前构建暂不可用"):
            return L("当前构建暂不支持开机自启动")
        default:
            return requestedEnabled ? L("开机自启动未能开启") : L("开机自启动已关闭，登录 macOS 后不会自动打开轻贴")
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
            showStatus(L("已显示性能测试入口"))
        }
    }

    private func moveGroups(from source: IndexSet, to destination: Int) {
        store.moveGroup(fromOffsets: source, toOffset: destination)
        showStatus(L("已更新分组排序"))
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
            showStatus(L("已重命名分组"))
        case .duplicate:
            editingSettingsGroupNames[id] = store.group(with: id)?.name
            showStatus(L("已有同名分组"))
        case .empty:
            editingSettingsGroupNames[id] = store.group(with: id)?.name
            showStatus(L("分组名称不能为空"))
        case .unchanged:
            editingSettingsGroupNames[id] = store.group(with: id)?.name
            break
        case .notFound:
            editingSettingsGroupNames.removeValue(forKey: id)
            showStatus(L("分组不存在"))
        }
    }

    private func requestDeleteGroup(_ group: ClipboardGroup) {
        guard !isGroupDeletionAssessmentInProgress else {
            return
        }

        isGroupDeletionAssessmentInProgress = true
        Task {
            defer { isGroupDeletionAssessmentInProgress = false }
            do {
                let assessment = try await SettingsHistoryDataActionCoordinator.groupDeletionAssessment(
                    for: group.id,
                    from: store
                )
                guard store.group(with: group.id) != nil else {
                    return
                }
                if assessment.requiresConfirmation {
                    groupPendingDeletionAssessment = assessment
                    groupPendingDeletion = group
                } else {
                    let result = try await SettingsHistoryDataActionCoordinator.executeGroupDeletion(
                        assessment,
                        for: [group.id],
                        from: store
                    )
                    applyGroupDeletionResult(
                        result,
                        requestedGroupIDs: [group.id],
                        singleGroup: group
                    )
                }
            } catch {
                showOperationError(L("检查分组内容失败"), error: error)
            }
        }
    }

    private func requestDeleteSelectedGroups() {
        let selectedIDs = groupSelection
        guard !selectedIDs.isEmpty,
              !isGroupDeletionAssessmentInProgress else {
            return
        }

        isGroupDeletionAssessmentInProgress = true
        Task {
            defer { isGroupDeletionAssessmentInProgress = false }
            do {
                let assessment = try await SettingsHistoryDataActionCoordinator.groupDeletionAssessment(
                    for: selectedIDs,
                    from: store
                )
                let existingIDs = Set(store.groups.map(\.id)).intersection(selectedIDs)
                guard !existingIDs.isEmpty else {
                    return
                }
                if assessment.requiresConfirmation {
                    bulkGroupPendingDeletionIDs = existingIDs
                    bulkGroupPendingDeletionAssessment = assessment
                    isBulkGroupDeleteConfirmationPresented = true
                } else {
                    let result = try await SettingsHistoryDataActionCoordinator.executeGroupDeletion(
                        assessment,
                        for: existingIDs,
                        from: store
                    )
                    applyGroupDeletionResult(
                        result,
                        requestedGroupIDs: existingIDs
                    )
                }
            } catch {
                showOperationError(L("检查分组内容失败"), error: error)
            }
        }
    }

    private func confirmDeleteGroup(_ group: ClipboardGroup) {
        guard let assessment = groupPendingDeletionAssessment else {
            return
        }

        Task {
            do {
                let result = try await SettingsHistoryDataActionCoordinator.executeGroupDeletion(
                    assessment,
                    for: [group.id],
                    from: store
                )
                applyGroupDeletionResult(
                    result,
                    requestedGroupIDs: [group.id],
                    singleGroup: group
                )
            } catch {
                showOperationError(L("检查分组内容失败"), error: error)
            }
        }
    }

    private func confirmDeleteSelectedGroups() {
        let groupIDs = bulkGroupPendingDeletionIDs
        guard !groupIDs.isEmpty,
              let assessment = bulkGroupPendingDeletionAssessment else {
            return
        }

        Task {
            do {
                let result = try await SettingsHistoryDataActionCoordinator.executeGroupDeletion(
                    assessment,
                    for: groupIDs,
                    from: store
                )
                applyGroupDeletionResult(
                    result,
                    requestedGroupIDs: groupIDs
                )
            } catch {
                showOperationError(L("检查分组内容失败"), error: error)
            }
        }
    }

    private func applyGroupDeletionResult(
        _ result: SettingsHistoryDataActionCoordinator.GroupDeletionExecutionResult,
        requestedGroupIDs: Set<ClipboardGroup.ID>,
        singleGroup: ClipboardGroup? = nil
    ) {
        switch result {
        case .deleted:
            groupSelection.subtract(requestedGroupIDs)
            clearPendingGroupDeletion(singleGroup: singleGroup)
            if let status = SettingsHistoryDataActionCoordinator.groupDeletionStatus(for: result) {
                showStatus(status)
            }
        case .requiresReassessment(let updatedAssessment):
            if let singleGroup {
                guard store.group(with: singleGroup.id) != nil else {
                    groupSelection.remove(singleGroup.id)
                    clearPendingGroupDeletion(singleGroup: singleGroup)
                    showStatus(L("分组不存在"))
                    return
                }
                groupPendingDeletionAssessment = updatedAssessment
                groupPendingDeletion = singleGroup
            } else {
                let existingIDs = Set(store.groups.map(\.id)).intersection(requestedGroupIDs)
                guard !existingIDs.isEmpty else {
                    groupSelection.subtract(requestedGroupIDs)
                    clearPendingGroupDeletion(singleGroup: nil)
                    showStatus(L("分组不存在"))
                    return
                }
                bulkGroupPendingDeletionIDs = existingIDs
                bulkGroupPendingDeletionAssessment = updatedAssessment
                isBulkGroupDeleteConfirmationPresented = true
            }
            showStatus(L("分组内容已变化，请重新确认"))
        case .noGroupsDeleted:
            groupSelection.subtract(requestedGroupIDs)
            clearPendingGroupDeletion(singleGroup: singleGroup)
            if let status = SettingsHistoryDataActionCoordinator.groupDeletionStatus(for: result) {
                showStatus(status)
            }
        }
    }

    private func clearPendingGroupDeletion(singleGroup: ClipboardGroup?) {
        if singleGroup != nil {
            groupPendingDeletion = nil
            groupPendingDeletionAssessment = nil
        } else {
            bulkGroupPendingDeletionIDs.removeAll()
            bulkGroupPendingDeletionAssessment = nil
            isBulkGroupDeleteConfirmationPresented = false
        }
    }

    private func cleanOrphanedAttachments() {
        guard !historyDataViewModel.isCleaningOrphanedAttachments else {
            return
        }

        historyDataViewModel.isCleaningOrphanedAttachments = true
        showProgress(L("正在准备完整历史..."))
        Task {
            do {
                let historyData = try await SettingsHistoryDataActionCoordinator.authoritativeHistoryData(
                    from: store
                )
                let result = try await SettingsHistoryDataActionCoordinator.cleanOrphanedAttachments(
                    historyData: historyData,
                    from: store
                )
                historyDataViewModel.isCleaningOrphanedAttachments = false
                historyDataViewModel.refreshStorageUsage()
                if result.removedFiles > 0 {
                    showStatus(L("已清理 \(result.removedFiles) 个文件，释放 \(result.formattedRemovedSize)"))
                } else {
                    showStatus(L("没有可清理的孤立附件"))
                }
            } catch {
                historyDataViewModel.isCleaningOrphanedAttachments = false
                showOperationError(L("清理孤立附件失败"), error: error)
            }
        }
    }

    private func checkHistoryDataHealth() {
        guard !historyDataViewModel.isCheckingHistoryData else {
            return
        }

        historyDataViewModel.isCheckingHistoryData = true
        showProgress(L("正在准备完整历史..."))
        Task {
            do {
                let historyData = try await SettingsHistoryDataActionCoordinator.authoritativeHistoryData(
                    from: store
                )
                historyDataViewModel.checkHistoryDataHealth(
                    items: historyData.items,
                    showProgress: showProgress
                ) { report in
                    showStatus(report.summary)
                    showHistoryDataHealthReport(report)
                }
            } catch {
                historyDataViewModel.isCheckingHistoryData = false
                showOperationError(L("检查历史数据失败"), error: error)
            }
        }
    }

    private func showHistoryDataHealthReport(_ report: HistoryDataHealthReport) {
        let alert = NSAlert()
        alert.messageText = report.hasIssues ? L("发现数据问题") : L("数据正常")
        alert.informativeText = report.detailText
        alert.alertStyle = report.hasIssues ? .warning : .informational
        if report.hasRepairableIssues {
            alert.addButton(withTitle: L("一键修复"))
        }
        alert.addButton(withTitle: L("好的"))
        let response = alert.runModal()
        if report.hasRepairableIssues,
           response == .alertFirstButtonReturn {
            confirmRepairHistoryData()
        }
    }

    private func confirmRepairHistoryData() {
        let alert = NSAlert()
        alert.messageText = L("修复数据问题？")
        alert.informativeText = L("轻贴会清理没有被当前历史引用的图片、缩略图和富文本附件，不会删除历史记录。")
        alert.alertStyle = .warning
        alert.addButton(withTitle: L("一键修复"))
        alert.addButton(withTitle: L("取消"))

        guard alert.runModal() == .alertFirstButtonReturn else {
            showStatus(L("已取消修复"))
            return
        }

        repairHistoryData()
    }

    private func repairHistoryData() {
        guard !historyDataViewModel.isCheckingHistoryData else {
            return
        }

        historyDataViewModel.isCheckingHistoryData = true
        showProgress(L("正在准备完整历史..."))
        Task {
            do {
                let historyData = try await SettingsHistoryDataActionCoordinator.authoritativeHistoryData(
                    from: store
                )
                showProgress(L("正在修复数据..."))
                let report = try await SettingsHistoryDataActionCoordinator.repairHistoryData(
                    historyData: historyData,
                    from: store
                )
                historyDataViewModel.isCheckingHistoryData = false
                historyDataViewModel.refreshStorageUsage()
                showStatus(report.summary)
                showHistoryDataRepairReport(report)
            } catch {
                historyDataViewModel.isCheckingHistoryData = false
                showOperationError(L("修复历史数据失败"), error: error)
            }
        }
    }

    private func showHistoryDataRepairReport(_ report: HistoryDataRepairReport) {
        let alert = NSAlert()
        alert.messageText = L("修复完成")
        alert.informativeText = report.detailText
        alert.alertStyle = report.after.hasIssues ? .warning : .informational
        alert.addButton(withTitle: L("好的"))
        alert.runModal()
    }

    private func openDirectory(_ url: URL?) {
        guard let url else {
            showStatus(L("无法打开目录"))
            return
        }

        try? FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
        NSWorkspace.shared.open(url)
        showStatus(L("已打开目录"))
    }

    private func exportHistory() {
        let panel = NSSavePanel()
        SettingsImportExportCoordinator.configure(
            panel,
            with: SettingsImportExportCoordinator.exportHistoryPanelConfiguration(dateString: exportDateString())
        )

        guard panel.runModal() == .OK,
              let url = panel.url else {
            return
        }

        isHistoryTransferInProgress = true
        showProgress(L("正在导出历史..."))

        Task {
            let result: Result<Void, Error>
            do {
                let historyData = try await SettingsHistoryDataActionCoordinator.authoritativeHistoryData(
                    from: store
                )
                result = await Task.detached(priority: .utility) {
                    Result {
                        try HistoryExportService.export(
                            items: historyData.items,
                            groups: historyData.groups,
                            to: url
                        )
                    }
                }.value
            } catch {
                result = .failure(error)
            }

            isHistoryTransferInProgress = false
            switch result {
            case .success:
                NSWorkspace.shared.activateFileViewerSelecting([url])
                showStatus(L("已导出历史"))
            case .failure(let error):
                showOperationError(L("导出历史失败"), error: error)
            }
        }
    }

    private func importHistory() {
        let panel = NSOpenPanel()
        SettingsImportExportCoordinator.configure(
            panel,
            with: SettingsImportExportCoordinator.importHistoryPanelConfiguration()
        )

        guard panel.runModal() == .OK,
              let url = panel.url else {
            return
        }

        isHistoryTransferInProgress = true
        showProgress(L("正在导入历史..."))

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
                    showStatus(importedCount > 0 ? L("已导入 \(importedCount) 条历史") : L("没有可导入的新历史"))
                case .failure(let error):
                    showOperationError(L("导入历史失败"), error: error)
                }
            }
        }
    }

    private func exportBackup() {
        let panel = NSSavePanel()
        SettingsImportExportCoordinator.configure(
            panel,
            with: SettingsImportExportCoordinator.exportBackupPanelConfiguration(dateString: exportDateString())
        )

        guard panel.runModal() == .OK,
              let url = panel.url else {
            return
        }

        isHistoryTransferInProgress = true
        showProgress(L("正在导出备份包..."))
        let includesAttachments = historyDataViewModel.includesAttachmentsInBackup

        Task {
            let result: Result<Void, Error>
            do {
                let historyData = try await SettingsHistoryDataActionCoordinator.authoritativeHistoryData(
                    from: store
                )
                result = await Task.detached(priority: .utility) {
                    Result {
                        try HistoryExportService.exportBackup(
                            items: historyData.items,
                            groups: historyData.groups,
                            to: url,
                            includesAttachments: includesAttachments
                        )
                    }
                }.value
            } catch {
                result = .failure(error)
            }

            isHistoryTransferInProgress = false
            switch result {
            case .success:
                NSWorkspace.shared.activateFileViewerSelecting([url])
                showStatus(L("已导出备份包"))
            case .failure(let error):
                showOperationError(L("备份包导出失败"), error: error)
            }
        }
    }

    private func importBackup() {
        let panel = NSOpenPanel()
        SettingsImportExportCoordinator.configure(
            panel,
            with: SettingsImportExportCoordinator.importBackupPanelConfiguration()
        )

        guard panel.runModal() == .OK,
              let url = panel.url else {
            return
        }

        isHistoryTransferInProgress = true
        showProgress(L("正在导入备份包..."))

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
                    showOperationError(L("备份包导入失败"), error: error)
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
                showStatus(L("已取消导入备份包"))
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
            showStatus(L("无法打开 GitHub"))
            return
        }

        NSWorkspace.shared.open(url)
        showStatus(L("已打开 GitHub"))
    }

    private func checkForUpdates() {
        updateViewModel.checkManually()
    }

    private func openRelease(_ url: URL?) {
        guard let releaseURL = url ?? AppVersionInfo.githubReleasesURL else {
            showStatus(L("无法打开 Release"))
            return
        }

        NSWorkspace.shared.open(releaseURL)
        showStatus(L("已打开 Release"))
    }

    private func downloadUpdate(_ url: URL) {
        NSWorkspace.shared.open(url)
        showStatus(L("已打开 DMG 下载"))
    }

    private func copyVersion() {
        Self.copyVersion(using: clipboardWriter)
        showStatus(L("已复制版本号"))
    }

    @discardableResult
    static func copyVersion(using clipboardWriter: ClipboardWriteCoordinator) -> Bool {
        clipboardWriter.writeText(AppVersionInfo.displayVersion)
    }

    private func openSupportCommunity() {
        guard let url = AppVersionInfo.githubSupportURL else {
            showStatus(L("无法打开交流群"))
            return
        }

        NSWorkspace.shared.open(url)
        showStatus(L("已打开交流群"))
    }

    private func exportDateString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmm"
        return formatter.string(from: Date())
    }

    private func addIgnoredAppFromPanel() {
        let panel = NSOpenPanel()
        panel.title = L("选择要忽略的 App")
        panel.prompt = L("添加")
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
            showStatus(L("无法识别所选 App"))
            return
        }

        let appName = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? url.deletingPathExtension().lastPathComponent

        if ignoredAppSettings.add(bundleID: bundleID, name: appName) {
            showStatus(L("已忽略 \(appName)"))
        } else {
            showStatus(L("\(appName) 已在忽略列表"))
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

private struct AppearanceFontFamilyPicker: NSViewRepresentable {
    @Binding var family: String

    private let families = AppearanceTypography.availableFamilies

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSComboBox {
        let comboBox = NSComboBox()
        comboBox.isEditable = true
        comboBox.completes = true
        comboBox.usesDataSource = false
        comboBox.addItems(withObjectValues: families.map(displayName))
        comboBox.delegate = context.coordinator
        comboBox.stringValue = displayName(family)
        return comboBox
    }

    func updateNSView(_ nsView: NSComboBox, context: Context) {
        context.coordinator.parent = self
        let display = displayName(family)
        if nsView.stringValue != display {
            nsView.stringValue = display
        }
    }

    private func displayName(_ family: String) -> String {
        AppearanceTypography(family: family, size: 12, weight: .regular).displayFamilyName
    }

    final class Coordinator: NSObject, NSComboBoxDelegate {
        var parent: AppearanceFontFamilyPicker

        init(parent: AppearanceFontFamilyPicker) {
            self.parent = parent
        }

        func comboBoxSelectionDidChange(_ notification: Notification) {
            guard let comboBox = notification.object as? NSComboBox else {
                return
            }
            let index = comboBox.indexOfSelectedItem
            guard parent.families.indices.contains(index) else {
                return
            }
            parent.family = parent.families[index]
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            guard let comboBox = obj.object as? NSComboBox else {
                return
            }
            let query = comboBox.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let index = parent.families.firstIndex(where: {
                AppearanceTypography(family: $0, size: 12, weight: .regular).displayFamilyName.caseInsensitiveCompare(query) == .orderedSame
            }) else {
                comboBox.stringValue = AppearanceTypography(family: parent.family, size: 12, weight: .regular).displayFamilyName
                return
            }
            parent.family = parent.families[index]
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
