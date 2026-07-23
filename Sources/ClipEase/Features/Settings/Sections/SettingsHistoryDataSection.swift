import SwiftUI

struct SettingsHistoryDataSection: View {
    let subtitle: String
    let hasItems: Bool
    let debugTextItemCount: Int
    let isHistoryTransferInProgress: Bool
    let isDebugToolsVisible: Bool
    @ObservedObject var viewModel: SettingsHistoryDataViewModel
    let onExportHistory: () -> Void
    let onImportHistory: () -> Void
    let onExportBackup: () -> Void
    let onImportBackup: () -> Void
    let onOpenDataDirectory: () -> Void
    let onOpenImagesDirectory: () -> Void
    let onOpenIconCacheDirectory: () -> Void
    let onOpenThumbnailCacheDirectory: () -> Void
    let onRequestClearIconCache: () -> Void
    let onRequestClearThumbnailCache: () -> Void
    let onRequestCleanOrphanedAttachments: () -> Void
    let onRequestClearHistory: () -> Void
    let onCheckHistoryData: () -> Void
    let onGenerateDebugItems: (Int) -> Void
    let onClearDebugItems: () -> Void
    let onShowStatus: (String) -> Void

    var body: some View {
        SettingsSection(title: "历史数据", subtitle: subtitle) {
            VStack(alignment: .leading, spacing: 12) {
                historyActionGroup(title: "导入与导出") {
                    historyButton("导出历史", prominent: true, action: onExportHistory)
                        .disabled(!hasItems || isHistoryTransferInProgress)

                    historyButton("导入历史", action: onImportHistory)
                        .disabled(
                            isHistoryTransferInProgress
                                || viewModel.isCleaningOrphanedAttachments
                                || viewModel.isCheckingHistoryData
                        )

                    historyButton("导出备份包", minWidth: 104, action: onExportBackup)
                        .disabled(!hasItems || isHistoryTransferInProgress)

                    historyButton("导入备份包", minWidth: 104, action: onImportBackup)
                        .disabled(
                            isHistoryTransferInProgress
                                || viewModel.isCleaningOrphanedAttachments
                                || viewModel.isCheckingHistoryData
                        )
                }

                Toggle("导出备份包时包含图片和富文本附件", isOn: $viewModel.includesAttachmentsInBackup)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 12, weight: .regular))

                Divider()

                historyActionGroup(title: "目录与缓存", wrapsContent: true) {
                    historyActionGrid {
                        historyButton("打开数据目录", minWidth: 116, action: onOpenDataDirectory)
                        historyButton("打开图片目录", minWidth: 116, action: onOpenImagesDirectory)
                        historyButton("打开图标缓存", minWidth: 116, action: onOpenIconCacheDirectory)
                        historyButton("打开缩略图缓存", minWidth: 116, action: onOpenThumbnailCacheDirectory)

                        historyButton("刷新用量", minWidth: 116) {
                            viewModel.refreshStorageUsage(onStatus: onShowStatus)
                        }
                        .disabled(viewModel.isStorageUsageRefreshing)

                        historyButton("压缩历史数据库", minWidth: 128) {
                            viewModel.compactHistoryDatabase(showStatus: onShowStatus)
                        }
                        .disabled(viewModel.isCompactingHistoryDatabase)
                    }
                }

                Divider()

                historyActionGroup(title: "清理", wrapsContent: true) {
                    historyActionGrid {
                        historyButton("检查数据", minWidth: 116, action: onCheckHistoryData)
                            .disabled(
                                viewModel.isCheckingHistoryData
                                    || viewModel.isCleaningOrphanedAttachments
                                    || isHistoryTransferInProgress
                            )

                        historyButton("清空图标缓存", minWidth: 116, action: onRequestClearIconCache)
                        historyButton("清空缩略图缓存", minWidth: 116, action: onRequestClearThumbnailCache)

                        historyButton("清理孤立附件", minWidth: 116, action: onRequestCleanOrphanedAttachments)
                            .disabled(
                                viewModel.isCleaningOrphanedAttachments
                                    || viewModel.isCheckingHistoryData
                                    || isHistoryTransferInProgress
                            )

                        Button("清空历史", role: .destructive, action: onRequestClearHistory)
                            .buttonStyle(.bordered)
                            .frame(minWidth: 116)
                            .disabled(!hasItems)
                    }
                }

                if isDebugToolsVisible {
                    Divider()
                    historyActionGroup(title: "性能测试数据") {
                        historyButton("生成 1,000 条", minWidth: 104) {
                            onGenerateDebugItems(1_000)
                        }

                        historyButton("生成 10,000 条", minWidth: 112) {
                            onGenerateDebugItems(10_000)
                        }

                        historyButton("清理测试数据", minWidth: 104, action: onClearDebugItems)
                            .disabled(debugTextItemCount == 0)
                    }
                }
            }
        }
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
}

struct SettingsSection<Content: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)

                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
