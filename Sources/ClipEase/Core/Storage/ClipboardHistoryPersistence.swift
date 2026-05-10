import Foundation

struct ClipboardHistoryPersistence {
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func loadItems() -> [ClipboardItem] {
        guard let fileURL = try? historyFileURL(),
              fileManager.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let records = try? decoder.decode([PersistentClipboardItem].self, from: data) else {
            return []
        }

        return records.map(\.clipboardItem)
    }

    func saveItems(_ items: [ClipboardItem]) {
        do {
            let fileURL = try historyFileURL()
            try fileManager.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let records = items.map(PersistentClipboardItem.init)
            let data = try encoder.encode(records)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            NSLog("ClipEase failed to save clipboard history: \(error.localizedDescription)")
        }
    }

    private func historyFileURL() throws -> URL {
        let baseURL = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return baseURL
            .appendingPathComponent("ClipEase", isDirectory: true)
            .appendingPathComponent("history.json")
    }
}

private struct PersistentClipboardItem: Codable {
    let id: UUID
    let type: String
    let text: String
    let urlString: String?
    let linkTitle: String?
    let linkSubtitle: String?
    let createdAt: Date
    let sourceAppName: String
    let sourceBundleID: String?
    let iconName: String
    let headerColorHex: String
    let isPinned: Bool
    let pinnedAt: Date?

    init(_ item: ClipboardItem) {
        self.id = item.id
        self.type = item.type.rawValue
        self.text = item.text
        self.urlString = item.url?.absoluteString
        self.linkTitle = item.linkTitle
        self.linkSubtitle = item.linkSubtitle
        self.createdAt = item.createdAt
        self.sourceAppName = item.sourceAppName
        self.sourceBundleID = item.sourceBundleID
        self.iconName = item.iconName
        self.headerColorHex = item.headerColorHex
        self.isPinned = item.isPinned
        self.pinnedAt = item.pinnedAt
    }

    var clipboardItem: ClipboardItem {
        ClipboardItem(
            id: id,
            type: ClipboardItemType(rawValue: type) ?? .text,
            text: text,
            url: urlString.flatMap(URL.init(string:)),
            linkTitle: linkTitle,
            linkSubtitle: linkSubtitle,
            createdAt: createdAt,
            sourceAppName: sourceAppName,
            sourceBundleID: sourceBundleID,
            iconName: iconName,
            headerColorHex: headerColorHex,
            isPinned: isPinned,
            pinnedAt: pinnedAt
        )
    }
}

