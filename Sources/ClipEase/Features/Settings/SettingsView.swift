import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var store: ClipboardHistoryStore
    @ObservedObject var recordingController: RecordingController
    @ObservedObject var loginItemController: LoginItemController
    @ObservedObject var ignoredAppSettings: IgnoredAppSettings
    @ObservedObject var globalShortcutSettings: GlobalShortcutSettings
    let pasteExecutor: PasteExecutor

    @State private var canAutoPaste = false
    @State private var isClearConfirmationPresented = false
    @State private var statusText: String?
    @State private var isRecordingShortcut = false
    @State private var storageUsageText = "计算中"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider()

            ScrollView {
                VStack(spacing: 14) {
                    retentionSection
                    shortcutSection
                    launchAtLoginSection
                    recordingSection
                    ignoredAppsSection
                    permissionsSection
                    historySection
                }
                .padding(18)
            }
        }
        .frame(minWidth: 560, minHeight: 520)
        .background(Color(red: 0.94, green: 0.95, blue: 0.97))
        .onAppear {
            canAutoPaste = pasteExecutor.canAutoPaste
            loginItemController.refresh()
            refreshStorageUsage()
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
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("轻贴设置")
                    .font(.system(size: 20, weight: .semibold))

                Text("管理历史、记录状态和权限")
                    .font(.system(size: 13, weight: .medium))
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
        .padding(18)
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

                Button("暂停 30 分钟") {
                    recordingController.pause(for: 30 * 60)
                    showStatus("已暂停 30 分钟")
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
        settingsSection(title: "自动粘贴权限", subtitle: canAutoPaste ? "已授权，可以自动粘贴到当前 App" : "未授权时只会复制到剪贴板") {
            HStack {
                Label(canAutoPaste ? "已授权" : "需授权", systemImage: canAutoPaste ? "checkmark.circle.fill" : "exclamationmark.lock")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(canAutoPaste ? Color.green : Color.orange)

                Spacer()

                Button("打开系统设置") {
                    pasteExecutor.openAccessibilitySettings()
                    canAutoPaste = pasteExecutor.canAutoPaste
                }
                .buttonStyle(.bordered)

                Button("刷新状态") {
                    canAutoPaste = pasteExecutor.canAutoPaste
                    showStatus(canAutoPaste ? "已授权自动粘贴" : "仍需授权")
                }
                .buttonStyle(.bordered)
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
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 8) {
                        ForEach(ignoredAppSettings.apps) { app in
                            HStack(spacing: 10) {
                                Image(systemName: "app.dashed")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Color(red: 0.18, green: 0.55, blue: 1.0))

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(app.name)
                                        .font(.system(size: 13, weight: .semibold))

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
                            .background(Color(red: 0.96, green: 0.97, blue: 0.99))
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        }
                    }
                }
            }
        }
    }

    private var historySection: some View {
        settingsSection(title: "历史数据", subtitle: historySubtitle) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Button("导出历史") {
                        exportHistory()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.items.isEmpty)

                    Button("打开数据目录") {
                        openDirectory(try? ClipEaseStoragePaths.applicationSupportDirectory())
                    }
                    .buttonStyle(.bordered)

                    Button("打开图片目录") {
                        openDirectory(try? ClipEaseStoragePaths.imagesDirectory())
                    }
                    .buttonStyle(.bordered)

                    Button("打开图标缓存") {
                        openDirectory(try? ClipEaseStoragePaths.appIconsDirectory())
                    }
                    .buttonStyle(.bordered)

                    Button("清空图标缓存") {
                        AppIconCache.clearCache()
                        refreshStorageUsage()
                        showStatus("已清空图标缓存")
                    }
                    .buttonStyle(.bordered)

                    Button("刷新用量") {
                        refreshStorageUsage()
                        showStatus("已刷新存储用量")
                    }
                    .buttonStyle(.bordered)

                    Spacer()
                }

                Button("清空历史", role: .destructive) {
                    isClearConfirmationPresented = true
                }
                .buttonStyle(.bordered)
                .disabled(store.items.isEmpty)
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
                    .font(.system(size: 14, weight: .semibold))

                Text(subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.86))
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
