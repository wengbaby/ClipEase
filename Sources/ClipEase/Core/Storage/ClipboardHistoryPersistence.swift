import AppKit
import CryptoKit
import Foundation

struct StoredClipboardImage: Sendable {
    let fileName: String
    let width: Int
    let height: Int
    let hash: String
}

struct StoredRichText: Sendable {
    let fileName: String
}

struct ClipboardHistoryPersistence: @unchecked Sendable {
    private static let thumbnailMaxPixelSize = CGSize(width: 500, height: 360)

    private let fileManager: FileManager
    private let repository: any ClipboardHistoryRepository

    init(
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        let sqliteURL = (try? ClipEaseStoragePaths.sqliteStoreURL(fileManager: fileManager))
            ?? URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("ClipEase.sqlite")
        self.repository = SQLiteClipboardStore(databaseURL: sqliteURL, fileManager: fileManager)
    }

    func loadSnapshot() -> ClipboardHistorySnapshot {
        do {
            return try repository.loadSnapshot()
        } catch {
            NSLog("ClipEase failed to load clipboard history: \(error.localizedDescription)")
            return ClipboardHistorySnapshot(items: [], groups: [])
        }
    }

    func loadItems() -> [ClipboardItem] {
        loadSnapshot().items
    }

    func saveSnapshot(_ snapshot: ClipboardHistorySnapshot) {
        do {
            try saveSnapshotOrThrow(snapshot)
        } catch {
            NSLog("ClipEase failed to save clipboard history: \(error.localizedDescription)")
        }
    }

    func saveSnapshotOrThrow(_ snapshot: ClipboardHistorySnapshot) throws {
        try repository.saveSnapshot(snapshot)
    }

    func upsertItemOrThrow(_ item: ClipboardItem, deleting deletedIDs: Set<ClipboardItem.ID>, groups: [ClipboardGroup]) throws {
        try repository.upsertItem(item, deleting: deletedIDs, groups: groups)
    }

    func saveItems(_ items: [ClipboardItem]) {
        saveSnapshot(ClipboardHistorySnapshot(items: items, groups: []))
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
            saveThumbnail(for: image, fileName: fileName)
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
        deleteThumbnail(fileName: fileName)
    }

    func thumbnailImage(fileName: String) -> NSImage? {
        if let thumbnailURL = try? ClipEaseStoragePaths.thumbnailFileURL(
            fileName: fileName,
            fileManager: fileManager
        ),
           fileManager.fileExists(atPath: thumbnailURL.path),
           let image = NSImage(contentsOf: thumbnailURL) {
            return image
        }

        guard let imageURL = try? ClipEaseStoragePaths.imageFileURL(
            fileName: fileName,
            fileManager: fileManager
        ),
              let image = NSImage(contentsOf: imageURL) else {
            return nil
        }

        saveThumbnail(for: image, fileName: fileName)
        return NSImage(
            contentsOf: (try? ClipEaseStoragePaths.thumbnailFileURL(
                fileName: fileName,
                fileManager: fileManager
            )) ?? imageURL
        ) ?? image
    }

    func deleteThumbnail(fileName: String) {
        guard let thumbnailURL = try? ClipEaseStoragePaths.thumbnailFileURL(
            fileName: fileName,
            fileManager: fileManager
        ) else {
            return
        }

        try? fileManager.removeItem(at: thumbnailURL)
    }

    static func clearThumbnailCache(fileManager: FileManager = .default) {
        guard let directoryURL = try? ClipEaseStoragePaths.thumbnailsDirectory(fileManager: fileManager) else {
            return
        }

        try? fileManager.removeItem(at: directoryURL)
    }

    func saveRichText(_ data: Data) -> StoredRichText? {
        do {
            return try saveRichTextOrThrow(data)
        } catch {
            NSLog("ClipEase failed to save rich text: \(error.localizedDescription)")
            return nil
        }
    }

    func saveRichTextOrThrow(_ data: Data) throws -> StoredRichText {
        let fileName = "\(UUID().uuidString).rtf"

        let directoryURL = try ClipEaseStoragePaths.richTextsDirectory(fileManager: fileManager)
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        let fileURL = directoryURL.appendingPathComponent(fileName)
        try data.write(to: fileURL, options: [.atomic])
        return StoredRichText(fileName: fileName)
    }

    func overwriteRichText(fileName: String, data: Data) -> Bool {
        do {
            let directoryURL = try ClipEaseStoragePaths.richTextsDirectory(fileManager: fileManager)
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
            let fileURL = try ClipEaseStoragePaths.richTextFileURL(
                fileName: fileName,
                fileManager: fileManager
            )
            try data.write(to: fileURL, options: [.atomic])
            return true
        } catch {
            NSLog("ClipEase failed to overwrite rich text: \(error.localizedDescription)")
            return false
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

    private func saveThumbnail(for image: NSImage, fileName: String) {
        guard let thumbnail = image.clipeaseThumbnail(maxPixelSize: Self.thumbnailMaxPixelSize),
              let thumbnailData = thumbnail.pngData() else {
            return
        }

        do {
            let directoryURL = try ClipEaseStoragePaths.thumbnailsDirectory(fileManager: fileManager)
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
            let thumbnailURL = directoryURL.appendingPathComponent(fileName)
            try thumbnailData.write(to: thumbnailURL, options: [.atomic])
        } catch {
            NSLog("ClipEase failed to save clipboard thumbnail: \(error.localizedDescription)")
        }
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

    func clipeaseThumbnail(maxPixelSize: CGSize) -> NSImage? {
        guard let source = cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let sourceWidth = CGFloat(source.width)
        let sourceHeight = CGFloat(source.height)
        guard sourceWidth > 0, sourceHeight > 0 else {
            return nil
        }

        let scale = min(maxPixelSize.width / sourceWidth, maxPixelSize.height / sourceHeight, 1)
        let targetSize = NSSize(
            width: max(1, floor(sourceWidth * scale)),
            height: max(1, floor(sourceHeight * scale))
        )
        let image = NSImage(size: targetSize)
        image.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        NSImage(cgImage: source, size: NSSize(width: sourceWidth, height: sourceHeight))
            .draw(
                in: NSRect(origin: .zero, size: targetSize),
                from: NSRect(origin: .zero, size: NSSize(width: sourceWidth, height: sourceHeight)),
                operation: .copy,
                fraction: 1
            )
        image.unlockFocus()
        return image
    }
}
