import Foundation
import Testing
@testable import ClipEase

@Test func previewGenerationHandlesOneThousandTextItemsWithinBudget() {
    let items = PerformanceFixture.textItems(count: 1_000)

    let result = PerformanceBudget.measure {
        items.map(HistoryPreviewItem.init)
    }

    #expect(result.value.count == 1_000)
    #expect(result.durationMS < 150)
}

@Test func searchFilterHandlesThreeThousandMixedItemsWithinBudget() throws {
    let previewItems = PerformanceFixture.mixedItems(count: 3_000).map(HistoryPreviewItem.init)

    let result = try PerformanceBudget.measure {
        try HistorySearchController.filterItems(
            previewItems,
            selectedGroup: .all,
            searchText: "性能测试 29",
            criteria: HistorySearchCriteria(),
            maxResultCount: 50,
            now: Date(timeIntervalSince1970: 4_000)
        )
    }

    #expect(!result.value.isEmpty)
    #expect(result.value.count <= 50)
    #expect(result.durationMS < 180)
}

@Test func searchFilterHandlesOneThousandRichImageFileItemsWithinBudget() throws {
    let previewItems = PerformanceFixture.richImageFileItems(count: 1_000).map(HistoryPreviewItem.init)

    let result = try PerformanceBudget.measure {
        try HistorySearchController.filterItems(
            previewItems,
            selectedGroup: .all,
            searchText: "报告 88",
            criteria: HistorySearchCriteria(),
            maxResultCount: 50,
            now: Date(timeIntervalSince1970: 4_000)
        )
    }

    #expect(!result.value.isEmpty)
    #expect(result.value.count <= 50)
    #expect(result.durationMS < 120)
}

@Test func renderWindowPolicyHandlesThreeThousandItemsWithinBudget() {
    let result = PerformanceBudget.measure {
        HistoryRailRenderWindowPolicy.visibleWindow(
            itemCount: 3_000,
            visibleRect: CGRect(x: 120_000, y: 0, width: 1_080, height: 300),
            hasReliableVisibleRect: true,
            itemStride: 270,
            horizontalContentPadding: 28,
            bufferItemCount: 6,
            renderedItemLimit: 20
        )
    }

    #expect(result.value.count <= 20)
    #expect(!result.value.isEmpty)
    #expect(result.durationMS < 5)
}

private enum PerformanceBudget {
    struct Result<T> {
        let value: T
        let durationMS: Double
    }

    static func measure<T>(_ operation: () throws -> T) rethrows -> Result<T> {
        let startedAt = CFAbsoluteTimeGetCurrent()
        let value = try operation()
        return Result(
            value: value,
            durationMS: (CFAbsoluteTimeGetCurrent() - startedAt) * 1_000
        )
    }
}

private enum PerformanceFixture {
    static func textItems(count: Int) -> [ClipboardItem] {
        (0..<count).map { index in
            ClipboardItem.text(
                "轻贴性能测试 \(index) abc 8899 快速搜索",
                sourceApp: .clipease
            )
        }
    }

    static func mixedItems(count: Int) -> [ClipboardItem] {
        (0..<count).map { index in
            switch index % 5 {
            case 0:
                return ClipboardItem.text("性能测试 \(index) 文本 abc", sourceApp: .clipease)
            case 1:
                return ClipboardItem.link(
                    URL(string: "https://example.com/item/\(index)")!,
                    originalText: "https://example.com/item/\(index)",
                    sourceApp: .clipease
                )
            case 2:
                return ClipboardItem.color("#8899AA", sourceApp: .clipease)
            case 3:
                return ClipboardItem.file(
                    references: [fileReference(index: index, name: "性能测试文件-\(index).txt")],
                    sourceApp: .clipease
                )
            default:
                return ClipboardItem.text("性能测试 \(index) 备用内容", sourceApp: .clipease)
            }
        }
    }

    static func richImageFileItems(count: Int) -> [ClipboardItem] {
        (0..<count).map { index in
            switch index % 3 {
            case 0:
                return ClipboardItem.richText(
                    plainText: "报告 88 富文本 \(index)",
                    fileName: "rich-\(index).rtf",
                    sourceApp: .clipease
                )
            case 1:
                return ClipboardItem.image(
                    fileName: "image-\(index).png",
                    width: 640,
                    height: 360,
                    hash: "image-hash-\(index)",
                    sourceApp: .clipease
                )
            default:
                return ClipboardItem.file(
                    references: [fileReference(index: index, name: "报告 88 文件-\(index).pdf")],
                    sourceApp: .clipease
                )
            }
        }
    }

    private static func fileReference(index: Int, name: String) -> ClipboardFileReference {
        ClipboardFileReference(
            itemID: UUID(),
            orderIndex: 0,
            path: "/tmp/\(name)",
            displayName: name,
            fileExtension: (name as NSString).pathExtension,
            contentType: nil,
            fileSize: 1_024 + index,
            modifiedAt: nil,
            isDirectory: false,
            isAlias: false,
            pathStatus: .available
        )
    }
}
