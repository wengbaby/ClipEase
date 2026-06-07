import Foundation
import Testing
import UniformTypeIdentifiers
@testable import ClipEase

@Test func settingsImportExportCoordinatorBuildsExportPanelConfigurations() {
    let dateString = "260608-0330"

    let history = SettingsImportExportCoordinator.exportHistoryPanelConfiguration(dateString: dateString)
    #expect(history.title == "导出轻贴历史")
    #expect(history.prompt == "导出")
    #expect(history.defaultFileName == "ClipEase-History-260608-0330.json")
    #expect(history.allowedContentTypes == [.json])
    #expect(history.canCreateDirectories == nil)

    let backup = SettingsImportExportCoordinator.exportBackupPanelConfiguration(dateString: dateString)
    #expect(backup.title == "导出轻贴备份包")
    #expect(backup.prompt == "导出")
    #expect(backup.defaultFileName == "ClipEase-Backup-260608-0330.clipeasebackup")
    #expect(backup.allowedContentTypes.isEmpty)
    #expect(backup.canCreateDirectories == true)
}

@Test func settingsImportExportCoordinatorBuildsImportPanelConfigurations() {
    let history = SettingsImportExportCoordinator.importHistoryPanelConfiguration()
    #expect(history.title == "导入轻贴历史")
    #expect(history.prompt == "导入")
    #expect(history.allowedContentTypes == [.json])
    #expect(!history.allowsMultipleSelection)
    #expect(!history.canChooseDirectories)
    #expect(history.canChooseFiles)

    let backup = SettingsImportExportCoordinator.importBackupPanelConfiguration()
    #expect(backup.title == "导入轻贴备份包")
    #expect(backup.prompt == "导入")
    #expect(backup.allowedContentTypes.isEmpty)
    #expect(!backup.allowsMultipleSelection)
    #expect(backup.canChooseDirectories)
    #expect(!backup.canChooseFiles)
}
