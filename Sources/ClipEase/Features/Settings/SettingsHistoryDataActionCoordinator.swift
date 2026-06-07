import Foundation

struct SettingsHistoryDataActionCoordinator {
    struct ConfirmationPrompt: Equatable {
        let title: String
        let message: String
        let confirmTitle: String
        let cancelTitle: String
    }

    static func backupImportDuplicatePrompt(duplicateCount: Int) -> ConfirmationPrompt? {
        guard duplicateCount > 0 else {
            return nil
        }

        return ConfirmationPrompt(
            title: "发现重复历史",
            message: "备份包中有 \(duplicateCount) 条历史已存在。",
            confirmTitle: "跳过重复",
            cancelTitle: "取消导入"
        )
    }

    static func backupImportStatusText(
        importedCount: Int,
        result: BackupImportResult
    ) -> String {
        if importedCount == 0, result.items.isEmpty {
            return result.missingAttachmentCount > 0
                ? "没有可导入的新历史，缺失附件 \(result.missingAttachmentCount) 个"
                : "没有可导入的新历史"
        }

        let duplicateOrSkippedCount = max(0, result.totalItems - importedCount)
        var parts = ["已导入 \(importedCount) 条"]
        if duplicateOrSkippedCount > 0 {
            parts.append("跳过 \(duplicateOrSkippedCount) 条")
        }
        if result.missingAttachmentCount > 0 {
            parts.append("缺失附件 \(result.missingAttachmentCount) 个")
        }
        return parts.joined(separator: "，")
    }
}
