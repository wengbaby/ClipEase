import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: ClipboardHistoryStore
    @ObservedObject var recordingController: RecordingController
    let pasteExecutor: PasteExecutor

    @State private var canAutoPaste = false
    @State private var isClearConfirmationPresented = false
    @State private var statusText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider()

            ScrollView {
                VStack(spacing: 14) {
                    retentionSection
                    recordingSection
                    permissionsSection
                    historySection
                }
                .padding(18)
            }
        }
        .frame(minWidth: 520, minHeight: 430)
        .background(Color(red: 0.94, green: 0.95, blue: 0.97))
        .onAppear {
            canAutoPaste = pasteExecutor.canAutoPaste
        }
        .confirmationDialog(
            "清空全部历史？",
            isPresented: $isClearConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("清空历史", role: .destructive) {
                store.clearAllItems()
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
            }
        }
    }

    private var historySection: some View {
        settingsSection(title: "历史数据", subtitle: "当前共有 \(store.items.count) 条记录") {
            HStack {
                Button("清空历史", role: .destructive) {
                    isClearConfirmationPresented = true
                }
                .buttonStyle(.bordered)
                .disabled(store.items.isEmpty)

                Spacer()
            }
        }
    }

    private var recordingSubtitle: String {
        if recordingController.isPaused {
            return recordingController.pauseMenuPrimaryTitle()
        }

        return "正在记录新的剪贴板内容"
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
}
