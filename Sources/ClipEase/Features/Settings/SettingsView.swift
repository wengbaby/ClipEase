import SwiftUI
import UniformTypeIdentifiers

private enum SettingsCategory: String, CaseIterable, Identifiable {
    case general
    case shortcut
    case recording
    case history
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
        case .history:
            "历史数据"
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
        case .history:
            "导入、导出、备份和本地文件"
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
        case .history:
            "externaldrive"
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
    let pasteExecutor: PasteExecutor

    @State private var isClearConfirmationPresented = false
    @State private var isClearIconCacheConfirmationPresented = false
    @State private var isClearThumbnailCacheConfirmationPresented = false
    @State private var statusText: String?
    @State private var isRecordingShortcut = false
    @State private var storageUsageText = "计算中"
    @State private var selectedCategory: SettingsCategory = .general

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
            refreshStorageUsage()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            accessibilityPermissionState.refresh()
        }
        .confirmationDialog(
            "清空全部历史？",
            isPresented: $isClearConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("清空历史", role: .destructive) {
                store.clearAllItems()
                refreshStorageUsage()
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
                refreshStorageUsage()
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
                refreshStorageUsage()
                showStatus("已清空缩略图缓存")
            }

            Button("取消", role: .cancel) {}
        } message: {
            Text("此操作只会删除图片卡片使用的缩略图缓存，不会删除原始图片或历史记录。后续显示图片卡片时会重新生成。")
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text("轻贴")
                    .font(.system(size: 15, weight: .semibold))

                Text("ClipEase")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
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
        case .history:
            historySection
        case .permissions:
            permissionsSection
        case .about:
            aboutSection
        }
    }

    private var retentionSection: some View {
        settingsSection(title: "保存期限", subtitle: "置顶内容不会被自动清理") {
            Picker("", selection: $store.retentionPolicy) {
                ForEach(HistoryRetentionPolicy.allCases) { policy in
                    Text(policy.shortTitle).tag(policy)
                }
            }
            .pickerStyle(.segmented)
        }
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
                    showStatus(loginItemController.statusText)
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

    private var historySection: some View {
        settingsSection(title: "历史数据", subtitle: historySubtitle) {
            VStack(alignment: .leading, spacing: 12) {
                historyActionGroup(title: "导入与导出") {
                    historyButton("导出历史", prominent: true) {
                        exportHistory()
                    }
                    .disabled(store.items.isEmpty)

                    historyButton("导入历史") {
                        importHistory()
                    }

                    historyButton("导出备份包", minWidth: 104) {
                        exportBackup()
                    }
                    .disabled(store.items.isEmpty)

                    historyButton("导入备份包", minWidth: 104) {
                        importBackup()
                    }
                }

                Divider()

                historyActionGroup(title: "目录与缓存") {
                    historyButton("打开数据目录", minWidth: 104) {
                        openDirectory(try? ClipEaseStoragePaths.applicationSupportDirectory())
                    }

                    historyButton("打开图片目录", minWidth: 104) {
                        openDirectory(try? ClipEaseStoragePaths.imagesDirectory())
                    }

                    historyButton("打开图标缓存", minWidth: 104) {
                        openDirectory(try? ClipEaseStoragePaths.appIconsDirectory())
                    }

                    historyButton("打开缩略图缓存", minWidth: 116) {
                        openDirectory(try? ClipEaseStoragePaths.thumbnailsDirectory())
                    }

                    historyButton("刷新用量") {
                        refreshStorageUsage()
                        showStatus("已刷新存储用量")
                    }
                }

                Divider()

                historyActionGroup(title: "清理") {
                    historyButton("清空图标缓存", minWidth: 104) {
                        isClearIconCacheConfirmationPresented = true
                    }

                    historyButton("清空缩略图缓存", minWidth: 116) {
                        isClearThumbnailCacheConfirmationPresented = true
                    }

                    historyButton("清理孤立附件", minWidth: 116) {
                        cleanOrphanedAttachments()
                    }

                    Button("清空历史", role: .destructive) {
                        isClearConfirmationPresented = true
                    }
                    .buttonStyle(.bordered)
                    .frame(minWidth: 88)
                    .disabled(store.items.isEmpty)
                }
            }
        }
    }

    private func historyActionGroup<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                content()
                Spacer(minLength: 0)
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

    private var aboutSection: some View {
        settingsSection(title: "关于轻贴", subtitle: "ClipEase \(AppVersionInfo.displayVersion)") {
            HStack(spacing: 10) {
                Label("简洁好用的 macOS 粘贴板历史助手", systemImage: "info.circle")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.secondary)

                Spacer()

                Button("打开 GitHub") {
                    openGitHub()
                }
                .buttonStyle(.bordered)

                Button("复制版本号") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(AppVersionInfo.displayVersion, forType: .string)
                    showStatus("已复制版本号")
                }
                .buttonStyle(.bordered)
            }
        }
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
        let textCount = store.items.filter { $0.type == .text }.count
        let linkCount = store.items.filter { $0.type == .link }.count
        let imageCount = store.items.filter { $0.type == .image }.count
        let colorCount = store.items.filter { $0.type == .color }.count
        let pinnedCount = store.items.filter(\.isPinned).count
        return "共 \(store.items.count) 条，占用 \(storageUsageText)，文字 \(textCount)，链接 \(linkCount)，图片 \(imageCount)，颜色 \(colorCount)，置顶 \(pinnedCount)"
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
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            if statusText == text {
                statusText = nil
            }
        }
    }

    private func refreshStorageUsage() {
        storageUsageText = StorageUsageCalculator.formattedApplicationSupportSize()
    }

    private func cleanOrphanedAttachments() {
        let result = OrphanedAttachmentCleaner.clean(items: store.items)
        refreshStorageUsage()
        if result.removedFiles > 0 {
            showStatus("已清理 \(result.removedFiles) 个文件，释放 \(result.formattedRemovedSize)")
        } else {
            showStatus("没有可清理的孤立附件")
        }
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

        do {
            try HistoryExportService.export(items: store.items, to: url)
            NSWorkspace.shared.activateFileViewerSelecting([url])
            showStatus("已导出历史")
        } catch {
            showStatus("导出失败")
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

        do {
            let importedItems = try HistoryExportService.importItems(from: url)
            let importedCount = store.importItems(importedItems)
            refreshStorageUsage()
            showStatus(importedCount > 0 ? "已导入 \(importedCount) 条历史" : "没有可导入的新历史")
        } catch {
            showStatus("导入失败")
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

        do {
            try HistoryExportService.exportBackup(items: store.items, to: url)
            NSWorkspace.shared.activateFileViewerSelecting([url])
            showStatus("已导出备份包")
        } catch {
            showStatus("备份包导出失败")
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

        do {
            let importedItems = try HistoryExportService.importBackup(from: url)
            let importedCount = store.importBackupItems(importedItems)
            refreshStorageUsage()
            showStatus(importedCount > 0 ? "已导入 \(importedCount) 条备份历史" : "没有可导入的新历史")
        } catch {
            showStatus("备份包导入失败")
        }
    }

    private func openGitHub() {
        guard let url = AppVersionInfo.githubURL else {
            showStatus("无法打开 GitHub")
            return
        }

        NSWorkspace.shared.open(url)
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
