import AppKit
import CryptoKit
import Foundation

struct StoredClipboardImage {
    let fileName: String
    let width: Int
    let height: Int
    let hash: String
}

struct StoredRichText {
    let fileName: String
}

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
        guard let fileURL = try? ClipEaseStoragePaths.historyFileURL(fileManager: fileManager),
              fileManager.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let records = try? decoder.decode([PersistentClipboardItem].self, from: data) else {
            return []
        }

        return records.map(\.clipboardItem)
    }

    func saveItems(_ items: [ClipboardItem]) {
        do {
            let fileURL = try ClipEaseStoragePaths.historyFileURL(fileManager: fileManager)
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

    func saveImage(_ image: NSImage) -> StoredClipboardImage? {
        guard let imageData = image.pngData(),
              let bitmap = NSBitmapImageRep(data: imageData) else {
            return nil
        }

        let hash = SHA256.hash(data: imageData)
            .map { String(format: "%02x", $0) }
            .joined()
        let fileName = "\(UUID().uuidString).png"

        do {
            let directoryURL = try ClipEaseStoragePaths.imagesDirectory(fileManager: fileManager)
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
            let imageURL = directoryURL.appendingPathComponent(fileName)
            try imageData.write(to: imageURL, options: [.atomic])
            return StoredClipboardImage(
                fileName: fileName,
                width: bitmap.pixelsWide,
                height: bitmap.pixelsHigh,
                hash: hash
            )
        } catch {
            NSLog("ClipEase failed to save clipboard image: \(error.localizedDescription)")
            return nil
        }
    }

    func imageData(fileName: String) -> Data? {
        guard let imageURL = try? ClipEaseStoragePaths.imageFileURL(
            fileName: fileName,
            fileManager: fileManager
        ) else {
            return nil
        }

        return try? Data(contentsOf: imageURL)
    }

    func deleteImage(fileName: String) {
        guard let imageURL = try? ClipEaseStoragePaths.imageFileURL(
            fileName: fileName,
            fileManager: fileManager
        ) else {
            return
        }

        try? fileManager.removeItem(at: imageURL)
    }

    func saveRichText(_ data: Data) -> StoredRichText? {
        let fileName = "\(UUID().uuidString).rtf"

        do {
            let directoryURL = try ClipEaseStoragePaths.richTextsDirectory(fileManager: fileManager)
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
            let fileURL = directoryURL.appendingPathComponent(fileName)
            try data.write(to: fileURL, options: [.atomic])
            return StoredRichText(fileName: fileName)
        } catch {
            NSLog("ClipEase failed to save rich text: \(error.localizedDescription)")
            return nil
        }
    }

    func richTextData(fileName: String) -> Data? {
        guard let fileURL = try? ClipEaseStoragePaths.richTextFileURL(
            fileName: fileName,
            fileManager: fileManager
        ) else {
            return nil
        }

        return try? Data(contentsOf: fileURL)
    }

    func deleteRichText(fileName: String) {
        guard let fileURL = try? ClipEaseStoragePaths.richTextFileURL(
            fileName: fileName,
            fileManager: fileManager
        ) else {
            return
        }

        try? fileManager.removeItem(at: fileURL)
    }
}

private struct PersistentClipboardItem: Codable {
    let id: UUID
    let type: String
    let text: String
    let urlString: String?
    let linkTitle: String?
    let linkSubtitle: String?
    let imageFileName: String?
    let imageWidth: Int?
    let imageHeight: Int?
    let imageHash: String?
    let richTextFileName: String?
    let createdAt: Date
    let sourceAppName: String
    let sourceBundleID: String?
    let iconName: String
    let iconFileName: String?
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
        self.imageFileName = item.imageFileName
        self.imageWidth = item.imageWidth
        self.imageHeight = item.imageHeight
        self.imageHash = item.imageHash
        self.richTextFileName = item.richTextFileName
        self.createdAt = item.createdAt
        self.sourceAppName = item.sourceAppName
        self.sourceBundleID = item.sourceBundleID
        self.iconName = item.iconName
        self.iconFileName = item.iconFileName
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
            imageFileName: imageFileName,
            imageWidth: imageWidth,
            imageHeight: imageHeight,
            imageHash: imageHash,
            richTextFileName: richTextFileName,
            createdAt: createdAt,
            sourceAppName: sourceAppName,
            sourceBundleID: sourceBundleID,
            iconName: iconName,
            iconFileName: iconFileName,
            headerColorHex: headerColorHex,
            isPinned: isPinned,
            pinnedAt: pinnedAt
        )
    }
}

private extension NSImage {
    func pngData() -> Data? {
        guard let tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffRepresentation) else {
            return nil
        }

        return bitmap.representation(using: .png, properties: [:])
    }
}
