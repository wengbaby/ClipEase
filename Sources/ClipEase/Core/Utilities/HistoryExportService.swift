import Foundation

private let backupManifestFileName = "history.json"
private let backupImagesDirectoryName = "Images"
private let backupRichTextsDirectoryName = "RichTexts"

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

    static func exportBackup(items: [ClipboardItem], to url: URL) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }

        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        try export(items: items, to: url.appendingPathComponent(backupManifestFileName))
        try copyAttachments(
            for: items,
            fromImagesDirectory: try? ClipEaseStoragePaths.imagesDirectory(),
            fromRichTextsDirectory: try? ClipEaseStoragePaths.richTextsDirectory(),
            toImagesDirectory: url.appendingPathComponent(backupImagesDirectoryName, isDirectory: true),
            toRichTextsDirectory: url.appendingPathComponent(backupRichTextsDirectoryName, isDirectory: true)
        )
    }

    static func importItems(from url: URL) throws -> [ClipboardItem] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let data = try Data(contentsOf: url)
        if let export = try? decoder.decode(HistoryExport.self, from: data) {
            return export.items.compactMap(\.clipboardItem)
        }

        return try decoder
            .decode([PersistentClipboardItem].self, from: data)
            .compactMap(\.clipboardItemForImport)
    }

    static func importBackup(from url: URL) throws -> [ClipboardItem] {
        let manifestURL = url.appendingPathComponent(backupManifestFileName)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let data = try Data(contentsOf: manifestURL)
        let export = try decoder.decode(HistoryExport.self, from: data)
        let items = try export.items.compactMap { item throws -> ClipboardItem? in
            try item.clipboardItemForBackupImport(backupURL: url)
        }

        return items
    }

    private static func copyAttachments(
        for items: [ClipboardItem],
        fromImagesDirectory: URL?,
        fromRichTextsDirectory: URL?,
        toImagesDirectory: URL,
        toRichTextsDirectory: URL
    ) throws {
        let fileManager = FileManager.default
        let imageNames = Set(items.compactMap(\.imageFileName))
        if let fromImagesDirectory, !imageNames.isEmpty {
            try fileManager.createDirectory(at: toImagesDirectory, withIntermediateDirectories: true)
            try imageNames.forEach { fileName in
                let sourceURL = fromImagesDirectory.appendingPathComponent(fileName)
                let destinationURL = toImagesDirectory.appendingPathComponent(fileName)
                guard fileManager.fileExists(atPath: sourceURL.path) else {
                    return
                }

                try fileManager.copyItem(at: sourceURL, to: destinationURL)
            }
        }

        let richTextNames = Set(items.compactMap(\.richTextFileName))
        if let fromRichTextsDirectory, !richTextNames.isEmpty {
            try fileManager.createDirectory(at: toRichTextsDirectory, withIntermediateDirectories: true)
            try richTextNames.forEach { fileName in
                let sourceURL = fromRichTextsDirectory.appendingPathComponent(fileName)
                let destinationURL = toRichTextsDirectory.appendingPathComponent(fileName)
                guard fileManager.fileExists(atPath: sourceURL.path) else {
                    return
                }

                try fileManager.copyItem(at: sourceURL, to: destinationURL)
            }
        }
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

    var clipboardItem: ClipboardItem? {
        switch ClipboardItemType(rawValue: type) ?? .text {
        case .image:
            return nil
        case .text, .link, .color:
            return ClipboardItem(
                id: id,
                type: ClipboardItemType(rawValue: type) ?? .text,
                text: text,
                url: urlString.flatMap(URL.init(string:)),
                linkTitle: linkTitle,
                linkSubtitle: linkSubtitle,
                imageFileName: nil,
                imageWidth: nil,
                imageHeight: nil,
                imageHash: nil,
                richTextFileName: nil,
                createdAt: createdAt,
                sourceAppName: sourceAppName,
                sourceBundleID: sourceBundleID,
                iconName: "doc.on.clipboard",
                iconFileName: nil,
                headerColorHex: "#0A84FF",
                isPinned: isPinned,
                pinnedAt: pinnedAt
            )
        }
    }

    func clipboardItemForBackupImport(backupURL: URL) throws -> ClipboardItem? {
        let itemType = ClipboardItemType(rawValue: type) ?? .text
        switch itemType {
        case .image:
            guard let imageFileName,
                  let imageWidth,
                  let imageHeight else {
                return nil
            }

            let backupImageURL = backupURL
                .appendingPathComponent(backupImagesDirectoryName, isDirectory: true)
                .appendingPathComponent(imageFileName)
            guard FileManager.default.fileExists(atPath: backupImageURL.path) else {
                return nil
            }

            try restoreAttachment(
                from: backupImageURL,
                to: try ClipEaseStoragePaths.imageFileURL(fileName: imageFileName)
            )

            return ClipboardItem(
                id: id,
                type: .image,
                text: text,
                url: nil,
                linkTitle: linkTitle,
                linkSubtitle: linkSubtitle,
                imageFileName: imageFileName,
                imageWidth: imageWidth,
                imageHeight: imageHeight,
                imageHash: nil,
                richTextFileName: nil,
                createdAt: createdAt,
                sourceAppName: sourceAppName,
                sourceBundleID: sourceBundleID,
                iconName: "photo",
                iconFileName: nil,
                headerColorHex: "#0A84FF",
                isPinned: isPinned,
                pinnedAt: pinnedAt
            )
        case .text, .link, .color:
            var restoredRichTextFileName: String?
            if let richTextFileName {
                let backupRichTextURL = backupURL
                    .appendingPathComponent(backupRichTextsDirectoryName, isDirectory: true)
                    .appendingPathComponent(richTextFileName)
                if FileManager.default.fileExists(atPath: backupRichTextURL.path) {
                    try restoreAttachment(
                        from: backupRichTextURL,
                        to: try ClipEaseStoragePaths.richTextFileURL(fileName: richTextFileName)
                    )
                    restoredRichTextFileName = richTextFileName
                }
            }

            return ClipboardItem(
                id: id,
                type: itemType,
                text: text,
                url: urlString.flatMap(URL.init(string:)),
                linkTitle: linkTitle,
                linkSubtitle: linkSubtitle,
                imageFileName: nil,
                imageWidth: nil,
                imageHeight: nil,
                imageHash: nil,
                richTextFileName: restoredRichTextFileName,
                createdAt: createdAt,
                sourceAppName: sourceAppName,
                sourceBundleID: sourceBundleID,
                iconName: "doc.on.clipboard",
                iconFileName: nil,
                headerColorHex: "#0A84FF",
                isPinned: isPinned,
                pinnedAt: pinnedAt
            )
        }
    }

    private func restoreAttachment(from sourceURL: URL, to destinationURL: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        if fileManager.fileExists(atPath: destinationURL.path) {
            return
        }

        try fileManager.copyItem(at: sourceURL, to: destinationURL)
    }
}

extension PersistentClipboardItem {
    var clipboardItemForImport: ClipboardItem? {
        switch ClipboardItemType(rawValue: type) ?? .text {
        case .image:
            return nil
        case .text, .link, .color:
            return ClipboardItem(
                id: id,
                type: ClipboardItemType(rawValue: type) ?? .text,
                text: text,
                url: urlString.flatMap(URL.init(string:)),
                linkTitle: linkTitle,
                linkSubtitle: linkSubtitle,
                imageFileName: nil,
                imageWidth: nil,
                imageHeight: nil,
                imageHash: nil,
                richTextFileName: nil,
                createdAt: createdAt,
                sourceAppName: sourceAppName,
                sourceBundleID: sourceBundleID,
                iconName: iconName,
                iconFileName: nil,
                headerColorHex: headerColorHex,
                isPinned: isPinned,
                pinnedAt: pinnedAt
            )
        }
    }
}
