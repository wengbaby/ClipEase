import Foundation
import Testing
@testable import ClipEase

@Test func settingsHistoryDataActionCoordinatorBuildsDuplicateBackupPrompt() {
    let prompt = SettingsHistoryDataActionCoordinator.backupImportDuplicatePrompt(duplicateCount: 3)

    #expect(prompt?.title == "发现重复历史")
    #expect(prompt?.message == "备份包中有 3 条历史已存在。")
    #expect(prompt?.confirmTitle == "跳过重复")
    #expect(prompt?.cancelTitle == "取消导入")
    #expect(SettingsHistoryDataActionCoordinator.backupImportDuplicatePrompt(duplicateCount: 0) == nil)
}

@Test func settingsHistoryDataActionCoordinatorFormatsBackupImportStatus() {
    let imported = BackupImportResult(
        items: [ClipboardItem.text("hello", sourceApp: .clipease)],
        groups: [],
        totalItems: 3,
        missingAttachmentCount: 2
    )
    let emptyWithMissingAttachment = BackupImportResult(
        items: [],
        groups: [],
        totalItems: 0,
        missingAttachmentCount: 1
    )
    let empty = BackupImportResult(
        items: [],
        groups: [],
        totalItems: 0,
        missingAttachmentCount: 0
    )

    #expect(SettingsHistoryDataActionCoordinator.backupImportStatusText(importedCount: 1, result: imported) == "已导入 1 条，跳过 2 条，缺失附件 2 个")
    #expect(SettingsHistoryDataActionCoordinator.backupImportStatusText(importedCount: 0, result: emptyWithMissingAttachment) == "没有可导入的新历史，缺失附件 1 个")
    #expect(SettingsHistoryDataActionCoordinator.backupImportStatusText(importedCount: 0, result: empty) == "没有可导入的新历史")
}
