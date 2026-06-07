import Foundation
import Testing
@testable import ClipEase

@Test func settingsHistoryDataSummaryPreservesThreeLineCategoryLayout() {
    let itemID = UUID()
    let items = [
        ClipboardItem.text("hello", sourceApp: .clipease),
        ClipboardItem(
            id: UUID(),
            type: .link,
            text: "https://example.com",
            url: URL(string: "https://example.com"),
            linkTitle: "Example",
            linkSubtitle: nil,
            imageFileName: nil,
            imageWidth: nil,
            imageHeight: nil,
            imageHash: nil,
            richTextFileName: nil,
            fileReferences: [],
            createdAt: Date(),
            sourceAppName: SourceAppInfo.clipease.name,
            sourceBundleID: SourceAppInfo.clipease.bundleID,
            iconName: SourceAppInfo.clipease.iconName,
            iconFileName: SourceAppInfo.clipease.iconFileName,
            headerColorHex: SourceAppInfo.clipease.headerColorHex,
            isPinned: false,
            pinnedAt: nil
        ),
        ClipboardItem(
            id: itemID,
            type: .file,
            text: "/tmp/report.pdf",
            url: nil,
            linkTitle: nil,
            linkSubtitle: nil,
            imageFileName: nil,
            imageWidth: nil,
            imageHeight: nil,
            imageHash: nil,
            richTextFileName: nil,
            fileReferences: [
                ClipboardFileReference(
                    itemID: itemID,
                    orderIndex: 0,
                    path: "/tmp/report.pdf",
                    displayName: "report.pdf",
                    fileExtension: "pdf",
                    contentType: "application/pdf"
                )
            ],
            createdAt: Date(),
            sourceAppName: SourceAppInfo.clipease.name,
            sourceBundleID: SourceAppInfo.clipease.bundleID,
            iconName: SourceAppInfo.clipease.iconName,
            iconFileName: SourceAppInfo.clipease.iconFileName,
            headerColorHex: SourceAppInfo.clipease.headerColorHex,
            isPinned: true,
            pinnedAt: Date()
        )
    ]

    let summary = SettingsHistoryDataViewModel.historySubtitle(
        items: items,
        storageUsageText: "65.1MB"
    )

    let lines = summary.split(separator: "\n", omittingEmptySubsequences: false)
    #expect(lines.count == 3)
    #expect(lines[0] == "共 3 条，占用 65.1MB")
    #expect(lines[1].contains("文字 "))
    #expect(lines[1].contains("链接 "))
    #expect(lines[1].contains("图片 "))
    #expect(lines[2].contains("文件 "))
    #expect(lines[2].contains("颜色 "))
    #expect(lines[2].contains("置顶 "))
}

@Test func settingsHistoryDataSizeFormatterUsesSmallUnits() {
    #expect(SettingsHistoryDataViewModel.formatCategorySize(512) == "512b")
    #expect(SettingsHistoryDataViewModel.formatCategorySize(1_536) == "1.5KB")
    #expect(SettingsHistoryDataViewModel.formatCategorySize(1_572_864) == "1.50MB")
}
