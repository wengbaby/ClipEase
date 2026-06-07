import Foundation
import AppKit
import UniformTypeIdentifiers

struct SettingsImportExportCoordinator {
    struct SavePanelConfiguration: Equatable {
        let title: String
        let prompt: String
        let defaultFileName: String
        let allowedContentTypes: [UTType]
        let canCreateDirectories: Bool?
    }

    struct OpenPanelConfiguration: Equatable {
        let title: String
        let prompt: String
        let allowedContentTypes: [UTType]
        let allowsMultipleSelection: Bool
        let canChooseDirectories: Bool
        let canChooseFiles: Bool
    }

    static func exportHistoryPanelConfiguration(dateString: String) -> SavePanelConfiguration {
        SavePanelConfiguration(
            title: "导出轻贴历史",
            prompt: "导出",
            defaultFileName: "ClipEase-History-\(dateString).json",
            allowedContentTypes: [.json],
            canCreateDirectories: nil
        )
    }

    static func exportBackupPanelConfiguration(dateString: String) -> SavePanelConfiguration {
        SavePanelConfiguration(
            title: "导出轻贴备份包",
            prompt: "导出",
            defaultFileName: "ClipEase-Backup-\(dateString).clipeasebackup",
            allowedContentTypes: [],
            canCreateDirectories: true
        )
    }

    static func importHistoryPanelConfiguration() -> OpenPanelConfiguration {
        OpenPanelConfiguration(
            title: "导入轻贴历史",
            prompt: "导入",
            allowedContentTypes: [.json],
            allowsMultipleSelection: false,
            canChooseDirectories: false,
            canChooseFiles: true
        )
    }

    static func importBackupPanelConfiguration() -> OpenPanelConfiguration {
        OpenPanelConfiguration(
            title: "导入轻贴备份包",
            prompt: "导入",
            allowedContentTypes: [],
            allowsMultipleSelection: false,
            canChooseDirectories: true,
            canChooseFiles: false
        )
    }

    @MainActor
    static func configure(_ panel: NSSavePanel, with configuration: SavePanelConfiguration) {
        panel.title = configuration.title
        panel.prompt = configuration.prompt
        panel.nameFieldStringValue = configuration.defaultFileName
        panel.allowedContentTypes = configuration.allowedContentTypes
        if let canCreateDirectories = configuration.canCreateDirectories {
            panel.canCreateDirectories = canCreateDirectories
        }
    }

    @MainActor
    static func configure(_ panel: NSOpenPanel, with configuration: OpenPanelConfiguration) {
        panel.title = configuration.title
        panel.prompt = configuration.prompt
        panel.allowedContentTypes = configuration.allowedContentTypes
        panel.allowsMultipleSelection = configuration.allowsMultipleSelection
        panel.canChooseDirectories = configuration.canChooseDirectories
        panel.canChooseFiles = configuration.canChooseFiles
    }
}
