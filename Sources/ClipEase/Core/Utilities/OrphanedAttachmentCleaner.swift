import Foundation

struct OrphanedAttachmentCleanupResult: Sendable {
    let removedFiles: Int
    let removedBytes: UInt64

    var formattedRemovedSize: String {
        ByteCountFormatter.string(
            fromByteCount: Int64(removedBytes),
            countStyle: .file
        )
    }
}

enum OrphanedAttachmentCleaner {
    static func clean(items: [ClipboardItem], fileManager: FileManager = .default) -> OrphanedAttachmentCleanupResult {
        let referencedImages = Set(items.compactMap(\.imageFileName))
        let referencedRichTexts = Set(items.compactMap(\.richTextFileName))

        var removedFiles = 0
        var removedBytes: UInt64 = 0

        cleanDirectory(
            try? ClipEaseStoragePaths.imagesDirectory(fileManager: fileManager),
            referencedFileNames: referencedImages,
            fileManager: fileManager,
            removedFiles: &removedFiles,
            removedBytes: &removedBytes
        )
        cleanDirectory(
            try? ClipEaseStoragePaths.thumbnailsDirectory(fileManager: fileManager),
            referencedFileNames: referencedImages,
            fileManager: fileManager,
            removedFiles: &removedFiles,
            removedBytes: &removedBytes
        )
        cleanDirectory(
            try? ClipEaseStoragePaths.richTextsDirectory(fileManager: fileManager),
            referencedFileNames: referencedRichTexts,
            fileManager: fileManager,
            removedFiles: &removedFiles,
            removedBytes: &removedBytes
        )

        return OrphanedAttachmentCleanupResult(
            removedFiles: removedFiles,
            removedBytes: removedBytes
        )
    }

    private static func cleanDirectory(
        _ directoryURL: URL?,
        referencedFileNames: Set<String>,
        fileManager: FileManager,
        removedFiles: inout Int,
        removedBytes: inout UInt64
    ) {
        guard let directoryURL,
              let fileURLs = try? fileManager.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
              ) else {
            return
        }

        for fileURL in fileURLs {
            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true,
                  !referencedFileNames.contains(fileURL.lastPathComponent) else {
                continue
            }

            let fileSize = UInt64(values.fileSize ?? 0)
            do {
                try fileManager.removeItem(at: fileURL)
                removedFiles += 1
                removedBytes += fileSize
            } catch {
                NSLog("ClipEase failed to remove orphaned attachment: \(fileURL.path), \(error.localizedDescription)")
            }
        }
    }
}
