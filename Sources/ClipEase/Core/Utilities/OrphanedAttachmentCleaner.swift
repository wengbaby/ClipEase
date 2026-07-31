import Foundation

typealias AttachmentResourceValuesProvider = @Sendable (URL, Set<URLResourceKey>) throws -> URLResourceValues

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
    static func candidates(
        items: [ClipboardItem],
        fileManager: FileManager = .default,
        resourceValuesProvider: @escaping AttachmentResourceValuesProvider = { url, keys in
            try url.resourceValues(forKeys: keys)
        }
    ) -> ClipboardAttachmentCleanup {
        let referencedImages = Set(items.compactMap(\.imageFileName))
        let referencedRichTexts = Set(items.compactMap(\.richTextFileName))
        let imageCandidates = fileNames(
            in: try? ClipEaseStoragePaths.imagesDirectory(fileManager: fileManager),
            referencedFileNames: referencedImages,
            fileManager: fileManager,
            resourceValuesProvider: resourceValuesProvider
        ).union(
            fileNames(
                in: try? ClipEaseStoragePaths.thumbnailsDirectory(fileManager: fileManager),
                referencedFileNames: referencedImages,
                fileManager: fileManager,
                resourceValuesProvider: resourceValuesProvider
            )
        ).subtracting(referencedImages)
        let richTextCandidates = fileNames(
            in: try? ClipEaseStoragePaths.richTextsDirectory(fileManager: fileManager),
            referencedFileNames: referencedRichTexts,
            fileManager: fileManager,
            resourceValuesProvider: resourceValuesProvider
        ).subtracting(referencedRichTexts)

        return ClipboardAttachmentCleanup(
            imageFileNames: imageCandidates,
            richTextFileNames: richTextCandidates
        )
    }

    static func clean(
        items: [ClipboardItem],
        fileManager: FileManager = .default,
        resourceValuesProvider: @escaping AttachmentResourceValuesProvider = { url, keys in
            try url.resourceValues(forKeys: keys)
        }
    ) -> OrphanedAttachmentCleanupResult {
        let referencedImages = Set(items.compactMap(\.imageFileName))
        let referencedRichTexts = Set(items.compactMap(\.richTextFileName))

        var removedFiles = 0
        var removedBytes: UInt64 = 0

        cleanDirectory(
            try? ClipEaseStoragePaths.imagesDirectory(fileManager: fileManager),
            referencedFileNames: referencedImages,
            fileManager: fileManager,
            resourceValuesProvider: resourceValuesProvider,
            removedFiles: &removedFiles,
            removedBytes: &removedBytes
        )
        cleanDirectory(
            try? ClipEaseStoragePaths.thumbnailsDirectory(fileManager: fileManager),
            referencedFileNames: referencedImages,
            fileManager: fileManager,
            resourceValuesProvider: resourceValuesProvider,
            removedFiles: &removedFiles,
            removedBytes: &removedBytes
        )
        cleanDirectory(
            try? ClipEaseStoragePaths.richTextsDirectory(fileManager: fileManager),
            referencedFileNames: referencedRichTexts,
            fileManager: fileManager,
            resourceValuesProvider: resourceValuesProvider,
            removedFiles: &removedFiles,
            removedBytes: &removedBytes
        )

        return OrphanedAttachmentCleanupResult(
            removedFiles: removedFiles,
            removedBytes: removedBytes
        )
    }

    private static func fileNames(
        in directoryURL: URL?,
        referencedFileNames: Set<String>,
        fileManager: FileManager,
        resourceValuesProvider: @escaping AttachmentResourceValuesProvider
    ) -> Set<String> {
        guard let directoryURL,
              let fileURLs = try? fileManager.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
              ) else {
            return []
        }

        return Set(fileURLs.compactMap { fileURL in
            guard !referencedFileNames.contains(fileURL.lastPathComponent),
                  let values = try? resourceValuesProvider(fileURL, [.isRegularFileKey]),
                  values.isRegularFile == true else {
                return nil
            }
            return fileURL.lastPathComponent
        })
    }

    private static func cleanDirectory(
        _ directoryURL: URL?,
        referencedFileNames: Set<String>,
        fileManager: FileManager,
        resourceValuesProvider: @escaping AttachmentResourceValuesProvider,
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
            guard !referencedFileNames.contains(fileURL.lastPathComponent),
                  let values = try? resourceValuesProvider(fileURL, [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true else {
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
