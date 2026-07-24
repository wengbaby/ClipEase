import Foundation

struct HistoryDataHealthReport: Sendable {
    let missingImageFiles: Int
    let missingRichTextFiles: Int
    let orphanedAttachmentFiles: Int
    let orphanedAttachmentBytes: UInt64

    var hasIssues: Bool {
        missingImageFiles > 0
            || missingRichTextFiles > 0
            || orphanedAttachmentFiles > 0
    }

    var hasRepairableIssues: Bool {
        orphanedAttachmentFiles > 0
    }

    var formattedOrphanedAttachmentSize: String {
        ByteCountFormatter.string(
            fromByteCount: Int64(orphanedAttachmentBytes),
            countStyle: .file
        )
    }

    var summary: String {
        guard hasIssues else {
            return L("数据正常")
        }

        var parts: [String] = []
        if missingImageFiles > 0 {
            parts.append(L("缺失图片 \(missingImageFiles)"))
        }
        if missingRichTextFiles > 0 {
            parts.append(L("缺失富文本 \(missingRichTextFiles)"))
        }
        if orphanedAttachmentFiles > 0 {
            parts.append(L("孤立附件 \(orphanedAttachmentFiles) 个/\(formattedOrphanedAttachmentSize)"))
        }
        return parts.joined(separator: "，")
    }

    var detailText: String {
        L("""
        缺失图片：\(missingImageFiles)
        缺失富文本：\(missingRichTextFiles)
        孤立附件：\(orphanedAttachmentFiles)
        孤立附件占用：\(formattedOrphanedAttachmentSize)
        """)
    }
}

struct HistoryDataRepairReport: Sendable {
    let before: HistoryDataHealthReport
    let removedFiles: Int
    let removedBytes: UInt64
    let after: HistoryDataHealthReport

    var summary: String {
        if removedFiles > 0 {
            return L("已修复 \(removedFiles) 个孤立附件")
        }

        return after.hasIssues ? L("没有可自动修复的问题") : L("数据正常")
    }

    var detailText: String {
        let removedSize = ByteCountFormatter.string(
            fromByteCount: Int64(removedBytes),
            countStyle: .file
        )
        return L("""
        修复前：
        \(before.detailText)

        本次清理孤立附件：\(removedFiles)
        释放空间：\(removedSize)

        修复后：
        \(after.detailText)
        """)
    }
}

enum HistoryDataHealthChecker {
    static func check(items: [ClipboardItem], fileManager: FileManager = .default) -> HistoryDataHealthReport {
        let referencedImages = Set(items.compactMap(\.imageFileName))
        let referencedRichTexts = Set(items.compactMap(\.richTextFileName))

        let missingImageFiles = referencedImages.filter { fileName in
            guard let fileURL = try? ClipEaseStoragePaths.imageFileURL(
                fileName: fileName,
                fileManager: fileManager
            ) else {
                return true
            }
            return !fileManager.fileExists(atPath: fileURL.path)
        }.count

        let missingRichTextFiles = referencedRichTexts.filter { fileName in
            guard let fileURL = try? ClipEaseStoragePaths.richTextFileURL(
                fileName: fileName,
                fileManager: fileManager
            ) else {
                return true
            }
            return !fileManager.fileExists(atPath: fileURL.path)
        }.count

        let orphaned = orphanedAttachmentUsage(
            referencedImages: referencedImages,
            referencedRichTexts: referencedRichTexts,
            fileManager: fileManager
        )

        return HistoryDataHealthReport(
            missingImageFiles: missingImageFiles,
            missingRichTextFiles: missingRichTextFiles,
            orphanedAttachmentFiles: orphaned.files,
            orphanedAttachmentBytes: orphaned.bytes
        )
    }

    static func repair(items: [ClipboardItem], fileManager: FileManager = .default) -> HistoryDataRepairReport {
        let before = check(items: items, fileManager: fileManager)
        let cleanup = OrphanedAttachmentCleaner.clean(items: items, fileManager: fileManager)
        let after = check(items: items, fileManager: fileManager)
        return HistoryDataRepairReport(
            before: before,
            removedFiles: cleanup.removedFiles,
            removedBytes: cleanup.removedBytes,
            after: after
        )
    }

    private static func orphanedAttachmentUsage(
        referencedImages: Set<String>,
        referencedRichTexts: Set<String>,
        fileManager: FileManager
    ) -> (files: Int, bytes: UInt64) {
        var files = 0
        var bytes: UInt64 = 0

        scanOrphanedDirectory(
            try? ClipEaseStoragePaths.imagesDirectory(fileManager: fileManager),
            referencedFileNames: referencedImages,
            fileManager: fileManager,
            files: &files,
            bytes: &bytes
        )
        scanOrphanedDirectory(
            try? ClipEaseStoragePaths.thumbnailsDirectory(fileManager: fileManager),
            referencedFileNames: referencedImages,
            fileManager: fileManager,
            files: &files,
            bytes: &bytes
        )
        scanOrphanedDirectory(
            try? ClipEaseStoragePaths.richTextsDirectory(fileManager: fileManager),
            referencedFileNames: referencedRichTexts,
            fileManager: fileManager,
            files: &files,
            bytes: &bytes
        )

        return (files, bytes)
    }

    private static func scanOrphanedDirectory(
        _ directoryURL: URL?,
        referencedFileNames: Set<String>,
        fileManager: FileManager,
        files: inout Int,
        bytes: inout UInt64
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

            files += 1
            bytes += UInt64(values.fileSize ?? 0)
        }
    }
}
