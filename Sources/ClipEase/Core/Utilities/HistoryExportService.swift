import Foundation

enum HistoryExportService {
    static func export(items: [ClipboardItem], to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let export = HistoryExport(
            exportedAt: Date(),
            itemCount: items.count,
            items: items.map(ExportedClipboardItem.init)
        )
        let data = try encoder.encode(export)
        try data.write(to: url, options: [.atomic])
    }
}

private struct HistoryExport: Codable {
    let exportedAt: Date
    let itemCount: Int
    let items: [ExportedClipboardItem]
}

private struct ExportedClipboardItem: Codable {
    let id: UUID
    let type: String
    let text: String
    let urlString: String?
    let linkTitle: String?
    let linkSubtitle: String?
    let imageFileName: String?
    let imageWidth: Int?
    let imageHeight: Int?
    let richTextFileName: String?
    let createdAt: Date
    let sourceAppName: String
    let sourceBundleID: String?
    let isPinned: Bool
    let pinnedAt: Date?

    init(_ item: ClipboardItem) {
        self.id = item.id
        self.type = item.type.rawValue
        self.text = item.text
        self.urlString = item.url?.absoluteString
        self.linkTitle = item.linkTitle
        self.linkSubtitle = item.linkSubtitle
        self.imageFileName = item.imageFileName
        self.imageWidth = item.imageWidth
        self.imageHeight = item.imageHeight
        self.richTextFileName = item.richTextFileName
        self.createdAt = item.createdAt
        self.sourceAppName = item.sourceAppName
        self.sourceBundleID = item.sourceBundleID
        self.isPinned = item.isPinned
        self.pinnedAt = item.pinnedAt
    }
}
