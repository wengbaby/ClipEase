import Foundation

@MainActor
final class SettingsHistoryDataViewModel: ObservableObject {
    @Published var storageUsageText = "计算中"
    @Published var isStorageUsageRefreshing = false
    @Published var isCompactingHistoryDatabase = false
    @Published var isCleaningOrphanedAttachments = false
    @Published var isCheckingHistoryData = false
    @Published var includesAttachmentsInBackup = true

    nonisolated static func historySubtitle(
        items: [ClipboardItem],
        storageUsageText: String
    ) -> String {
        let primarySummaries = [
            historyStorageSummary(for: .text, label: "文字", items: items),
            historyStorageSummary(for: .link, label: "链接", items: items),
            historyStorageSummary(for: .image, label: "图片", items: items)
        ]
        let secondarySummaries = [
            historyStorageSummary(for: .file, label: "文件", items: items),
            historyStorageSummary(for: .color, label: "颜色", items: items),
            historyPinnedStorageSummary(items: items)
        ]

        return """
        共 \(items.count) 条，占用 \(storageUsageText)
        \(primarySummaries.joined(separator: "，"))
        \(secondarySummaries.joined(separator: "，"))
        """
    }

    nonisolated static func formatCategorySize(_ bytes: UInt64) -> String {
        if bytes >= 1_048_576 {
            return String(format: "%.2fMB", Double(bytes) / 1_048_576)
        }
        if bytes >= 1_024 {
            return String(format: "%.1fKB", Double(bytes) / 1_024)
        }
        return "\(bytes)b"
    }

    func refreshStorageUsage(onStatus: ((String) -> Void)? = nil) {
        isStorageUsageRefreshing = true

        Task {
            let usageText = await Task.detached(priority: .utility) {
                StorageUsageCalculator.formattedApplicationSupportSize()
            }.value

            storageUsageText = usageText
            isStorageUsageRefreshing = false
            onStatus?("已刷新存储用量")
        }
    }

    func compactHistoryDatabase(showStatus: @escaping (String) -> Void) {
        isCompactingHistoryDatabase = true

        Task {
            let result = await Task.detached(priority: .utility) {
                let persistence = ClipboardHistoryPersistence()
                return (try? persistence.compactDatabaseIfNeededOrThrow(
                    policy: ClipboardDatabaseCompactionPolicy(
                        minimumFreeRatio: 0,
                        minimumFreeBytes: 1
                    )
                )) ?? .skipped
            }.value
            let usageText = await Task.detached(priority: .utility) {
                StorageUsageCalculator.formattedApplicationSupportSize()
            }.value

            storageUsageText = usageText
            isCompactingHistoryDatabase = false
            if result.reclaimedBytes > 0 {
                showStatus("已压缩历史数据库，释放 \(ByteCountFormatter.string(fromByteCount: Int64(result.reclaimedBytes), countStyle: .file))")
            } else {
                showStatus("历史数据库无需压缩")
            }
        }
    }

    func checkHistoryDataHealth(
        items: [ClipboardItem],
        showProgress: (String) -> Void,
        completion: @escaping (HistoryDataHealthReport) -> Void
    ) {
        isCheckingHistoryData = true
        showProgress("正在检查数据...")

        Task {
            let report = await Task.detached(priority: .utility) {
                HistoryDataHealthChecker.check(items: items)
            }.value

            isCheckingHistoryData = false
            completion(report)
        }
    }

    nonisolated private static func historyStorageSummary(
        for type: ClipboardItemType,
        label: String,
        items: [ClipboardItem]
    ) -> String {
        let matchingItems = items.filter { $0.type == type }
        let bytes = matchingItems.reduce(UInt64(0)) { partialResult, item in
            partialResult + estimatedStoredBytes(for: item)
        }
        return "\(label) \(formatCategorySize(bytes))/\(matchingItems.count)条"
    }

    nonisolated private static func historyPinnedStorageSummary(items: [ClipboardItem]) -> String {
        let pinnedItems = items.filter(\.isPinned)
        let bytes = pinnedItems.reduce(UInt64(0)) { partialResult, item in
            partialResult + estimatedStoredBytes(for: item)
        }
        return "置顶 \(formatCategorySize(bytes))/\(pinnedItems.count)条"
    }

    nonisolated private static func estimatedStoredBytes(for item: ClipboardItem) -> UInt64 {
        var bytes = UInt64(item.text.utf8.count)
        bytes += UInt64(item.url?.absoluteString.utf8.count ?? 0)
        bytes += UInt64(item.linkTitle?.utf8.count ?? 0)
        bytes += UInt64(item.linkSubtitle?.utf8.count ?? 0)
        bytes += UInt64(item.sourceAppName.utf8.count)
        bytes += UInt64(item.sourceBundleID?.utf8.count ?? 0)
        bytes += UInt64(item.iconName.utf8.count)
        bytes += UInt64(item.iconFileName?.utf8.count ?? 0)
        bytes += UInt64(item.headerColorHex.utf8.count)
        bytes += UInt64(item.ocrText.utf8.count)
        bytes += item.ocrEmails.reduce(UInt64(0)) { $0 + UInt64($1.utf8.count) }
        bytes += item.ocrPhoneNumbers.reduce(UInt64(0)) { $0 + UInt64($1.utf8.count) }
        bytes += item.ocrURLs.reduce(UInt64(0)) { $0 + UInt64($1.utf8.count) }

        if let imageFileName = item.imageFileName {
            bytes += fileSize(try? ClipEaseStoragePaths.imageFileURL(fileName: imageFileName))
            bytes += fileSize(try? ClipEaseStoragePaths.thumbnailFileURL(fileName: imageFileName))
        }

        if let richTextFileName = item.richTextFileName {
            bytes += fileSize(try? ClipEaseStoragePaths.richTextFileURL(fileName: richTextFileName))
        }

        for fileReference in item.fileReferences {
            bytes += UInt64(fileReference.path.utf8.count)
            bytes += UInt64(fileReference.displayName.utf8.count)
            bytes += UInt64(fileReference.fileExtension?.utf8.count ?? 0)
            bytes += UInt64(fileReference.contentType?.utf8.count ?? 0)
        }

        return bytes
    }

    nonisolated private static func fileSize(_ url: URL?) -> UInt64 {
        guard let url,
              let values = try? url.resourceValues(forKeys: [.fileSizeKey, .totalFileAllocatedSizeKey]) else {
            return 0
        }

        return UInt64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
    }
}
