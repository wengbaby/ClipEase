import Foundation

private let backupSQLiteFileName = "ClipEase.sqlite"
private let backupImagesDirectoryName = "Images"
private let backupRichTextsDirectoryName = "RichTexts"

struct BackupImportResult: Sendable {
    let items: [ClipboardItem]
    let groups: [ClipboardGroup]
    let totalItems: Int
    let missingAttachmentCount: Int

    var skippedItemCount: Int {
        max(0, totalItems - items.count)
    }
}

enum HistoryExportError: LocalizedError {
    case missingSQLiteBackup
    case incompatibleSQLiteBackupSchema(Int)
    case invalidSQLiteBackupFile(String)
    case invalidBackupAttachmentFileName(String)
    case invalidBackupAttachmentPath(String)
    case invalidBackupAttachmentDirectory(String)
    case invalidBackupAttachmentFile(String)

    var errorDescription: String? {
        switch self {
        case .missingSQLiteBackup:
            "备份包缺少 ClipEase.sqlite"
        case .incompatibleSQLiteBackupSchema(let version):
            "备份包 SQLite schema 版本不兼容：\(version)"
        case .invalidSQLiteBackupFile(let fileName):
            "备份包包含非法 SQLite 文件：\(fileName)"
        case .invalidBackupAttachmentFileName(let fileName):
            "备份包包含非法附件文件名：\(fileName)"
        case .invalidBackupAttachmentPath(let fileName):
            "备份包附件路径越界：\(fileName)"
        case .invalidBackupAttachmentDirectory(let directory):
            "备份包包含非法附件目录：\(directory)"
        case .invalidBackupAttachmentFile(let fileName):
            "备份包包含非法附件文件：\(fileName)"
        }
    }
}

enum HistoryExportService {
    static func export(items: [ClipboardItem], to url: URL) throws {
        try export(items: items, groups: [], to: url)
    }

    static func export(items: [ClipboardItem], groups: [ClipboardGroup], to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let export = HistoryExport(
            exportedAt: Date(),
            itemCount: items.count,
            groups: groups.map(ExportedClipboardGroup.init),
            items: items.map(ExportedClipboardItem.init)
        )
        let data = try encoder.encode(export)
        try data.write(to: url, options: [.atomic])
    }

    static func exportBackup(items: [ClipboardItem], to url: URL) throws {
        try exportBackup(items: items, groups: [], to: url, includesAttachments: true)
    }

    static func exportBackup(
        items: [ClipboardItem],
        to url: URL,
        includesAttachments: Bool
    ) throws {
        try exportBackup(items: items, groups: [], to: url, includesAttachments: includesAttachments)
    }

    static func exportBackup(
        items: [ClipboardItem],
        groups: [ClipboardGroup],
        to url: URL,
        includesAttachments: Bool
    ) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }

        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        try exportSQLiteBackup(items: items, groups: groups, to: url.appendingPathComponent(backupSQLiteFileName))

        if includesAttachments {
            try copyAttachments(
                for: items,
                fromImagesDirectory: try? ClipEaseStoragePaths.imagesDirectory(),
                fromRichTextsDirectory: try? ClipEaseStoragePaths.richTextsDirectory(),
                toImagesDirectory: url.appendingPathComponent(backupImagesDirectoryName, isDirectory: true),
                toRichTextsDirectory: url.appendingPathComponent(backupRichTextsDirectoryName, isDirectory: true)
            )
        }
    }

    static func importItems(from url: URL) throws -> [ClipboardItem] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let data = try Data(contentsOf: url)
        if let export = try? decoder.decode(HistoryExport.self, from: data) {
            return export.items.compactMap(\.clipboardItem)
        }

        return try decoder
            .decode([ExportedClipboardItem].self, from: data)
            .compactMap(\.clipboardItem)
    }

    static func importBackup(from url: URL) throws -> BackupImportResult {
        let sqliteURL = url.appendingPathComponent(backupSQLiteFileName)
        if FileManager.default.fileExists(atPath: sqliteURL.path) {
            return try importSQLiteBackup(from: url, sqliteURL: sqliteURL)
        }

        throw HistoryExportError.missingSQLiteBackup
    }

    private static func exportSQLiteBackup(items: [ClipboardItem], to url: URL) throws {
        try exportSQLiteBackup(items: items, groups: [], to: url)
    }

    private static func exportSQLiteBackup(items: [ClipboardItem], groups: [ClipboardGroup], to url: URL) throws {
        let store = SQLiteClipboardStore(databaseURL: url)
        try store.replaceAllItems(with: items, groups: groups)
    }

    private static func importSQLiteBackup(from backupURL: URL, sqliteURL: URL) throws -> BackupImportResult {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("clipease-backup-import-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let temporarySQLiteURL = temporaryDirectory.appendingPathComponent(backupSQLiteFileName)
        try copySQLiteBackupFiles(from: sqliteURL, to: temporarySQLiteURL)
        try validateBackupSchemaVersion(at: temporarySQLiteURL)

        let store = SQLiteClipboardStore(databaseURL: temporarySQLiteURL)
        let snapshot = try store.loadSnapshot()
        let items = snapshot.items
        var missingAttachmentCount = 0
        let restoredItems = try items.compactMap { item throws -> ClipboardItem? in
            try restoreBackupAttachments(
                for: item,
                backupURL: backupURL,
                missingAttachmentCount: &missingAttachmentCount
            )
        }

        return BackupImportResult(
            items: restoredItems,
            groups: snapshot.groups,
            totalItems: items.count,
            missingAttachmentCount: missingAttachmentCount
        )
    }

    private static func copySQLiteBackupFiles(from sourceURL: URL, to destinationURL: URL) throws {
        let fileManager = FileManager.default
        try validateSQLiteBackupFileIsRegular(sourceURL)
        try fileManager.copyItem(at: sourceURL, to: destinationURL)
        try validateSQLiteBackupFileIsRegular(destinationURL)

        for suffix in ["-wal", "-shm"] {
            let sourceSidecarURL = URL(fileURLWithPath: sourceURL.path + suffix)
            guard fileManager.fileExists(atPath: sourceSidecarURL.path) else {
                continue
            }

            let destinationSidecarURL = URL(fileURLWithPath: destinationURL.path + suffix)
            try validateSQLiteBackupFileIsRegular(sourceSidecarURL)
            try fileManager.copyItem(at: sourceSidecarURL, to: destinationSidecarURL)
            try validateSQLiteBackupFileIsRegular(destinationSidecarURL)
        }
    }

    private static func validateSQLiteBackupFileIsRegular(_ url: URL) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular else {
            throw HistoryExportError.invalidSQLiteBackupFile(url.lastPathComponent)
        }
    }

    private static func validateBackupSchemaVersion(at sqliteURL: URL) throws {
        let database = try SQLiteDatabase(url: sqliteURL)
        let userVersion = try database.queryInt("PRAGMA user_version")
        database.close()

        guard userVersion >= SQLiteClipboardStore.currentSchemaVersion else {
            throw HistoryExportError.incompatibleSQLiteBackupSchema(userVersion)
        }
    }

    private static func restoreBackupAttachments(
        for item: ClipboardItem,
        backupURL: URL,
        missingAttachmentCount: inout Int
    ) throws -> ClipboardItem? {
        if let imageFileName = item.imageFileName {
            guard try restoreBackupImageAttachment(
                fileName: imageFileName,
                backupURL: backupURL,
                missingAttachmentCount: &missingAttachmentCount
            ) else {
                return nil
            }
        }

        if let richTextFileName = item.richTextFileName {
            _ = try restoreBackupRichTextAttachment(
                fileName: richTextFileName,
                backupURL: backupURL,
                missingAttachmentCount: &missingAttachmentCount
            )
        }

        return item
    }

    fileprivate static func restoreBackupImageAttachment(
        fileName: String,
        backupURL: URL,
        missingAttachmentCount: inout Int
    ) throws -> Bool {
        let backupImagesDirectory = backupURL.appendingPathComponent(backupImagesDirectoryName, isDirectory: true)
        let liveImagesDirectory = try ClipEaseStoragePaths.imagesDirectory()
        guard try validateBackupAttachmentDirectory(backupImagesDirectory) else {
            missingAttachmentCount += 1
            return false
        }

        let backupImageURL = try backupAttachmentFileURL(fileName: fileName, in: backupImagesDirectory)
        let liveImageURL = try backupAttachmentFileURL(fileName: fileName, in: liveImagesDirectory)
        guard FileManager.default.fileExists(atPath: backupImageURL.path) else {
            missingAttachmentCount += 1
            return false
        }

        try validateLiveAttachmentDirectory(liveImagesDirectory)
        try restoreAttachment(
            from: backupImageURL,
            sourceDirectoryURL: backupImagesDirectory,
            to: liveImageURL,
            destinationDirectoryURL: liveImagesDirectory,
            fileName: fileName
        )
        return true
    }

    fileprivate static func restoreBackupRichTextAttachment(
        fileName: String,
        backupURL: URL,
        missingAttachmentCount: inout Int
    ) throws -> Bool {
        let backupRichTextsDirectory = backupURL.appendingPathComponent(backupRichTextsDirectoryName, isDirectory: true)
        let liveRichTextsDirectory = try ClipEaseStoragePaths.richTextsDirectory()
        guard try validateBackupAttachmentDirectory(backupRichTextsDirectory) else {
            missingAttachmentCount += 1
            return false
        }

        let backupRichTextURL = try backupAttachmentFileURL(fileName: fileName, in: backupRichTextsDirectory)
        let liveRichTextURL = try backupAttachmentFileURL(fileName: fileName, in: liveRichTextsDirectory)
        guard FileManager.default.fileExists(atPath: backupRichTextURL.path) else {
            missingAttachmentCount += 1
            return false
        }

        try validateLiveAttachmentDirectory(liveRichTextsDirectory)
        try restoreAttachment(
            from: backupRichTextURL,
            sourceDirectoryURL: backupRichTextsDirectory,
            to: liveRichTextURL,
            destinationDirectoryURL: liveRichTextsDirectory,
            fileName: fileName
        )
        return true
    }

    private static func backupAttachmentFileURL(fileName: String, in directoryURL: URL) throws -> URL {
        do {
            return try ClipEaseStoragePaths.attachmentFileURL(fileName: fileName, in: directoryURL)
        } catch ClipEaseStoragePathError.invalidAttachmentFileName(_) {
            throw HistoryExportError.invalidBackupAttachmentFileName(fileName)
        } catch ClipEaseStoragePathError.attachmentPathOutsideDirectory(_, _) {
            throw HistoryExportError.invalidBackupAttachmentPath(fileName)
        }
    }

    private static func validateAttachmentURL(_ fileURL: URL, isInside directoryURL: URL, fileName: String) throws {
        do {
            try ClipEaseStoragePaths.validateAttachmentURL(fileURL, isInside: directoryURL, fileName: fileName)
        } catch {
            throw HistoryExportError.invalidBackupAttachmentPath(fileName)
        }
    }

    private static func validateBackupAttachmentDirectory(_ directoryURL: URL) throws -> Bool {
        let fileManager = FileManager.default
        if (try? fileManager.destinationOfSymbolicLink(atPath: directoryURL.path)) != nil {
            throw HistoryExportError.invalidBackupAttachmentDirectory(directoryURL.lastPathComponent)
        }

        var isDirectory = ObjCBool(false)
        guard fileManager.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory) else {
            return false
        }

        guard isDirectory.boolValue else {
            throw HistoryExportError.invalidBackupAttachmentDirectory(directoryURL.lastPathComponent)
        }

        return true
    }

    private static func validateLiveAttachmentDirectory(_ directoryURL: URL) throws {
        do {
            try ClipEaseStoragePaths.validateLiveAttachmentDirectory(directoryURL)
        } catch {
            throw HistoryExportError.invalidBackupAttachmentDirectory(directoryURL.lastPathComponent)
        }
    }

    fileprivate static func restoreAttachment(
        from sourceURL: URL,
        sourceDirectoryURL: URL,
        to destinationURL: URL,
        destinationDirectoryURL: URL,
        fileName: String
    ) throws {
        let fileManager = FileManager.default
        try validateAttachmentURL(sourceURL, isInside: sourceDirectoryURL, fileName: fileName)
        try validateAttachmentURL(destinationURL, isInside: destinationDirectoryURL, fileName: fileName)
        try validateBackupAttachmentFileIsRegular(sourceURL, fileName: fileName)
        try fileManager.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try validateLiveAttachmentDirectory(destinationDirectoryURL)
        try validateAttachmentURL(destinationURL, isInside: destinationDirectoryURL, fileName: fileName)

        if fileManager.fileExists(atPath: destinationURL.path) {
            return
        }

        try fileManager.copyItem(at: sourceURL, to: destinationURL)
    }

    private static func validateBackupAttachmentFileIsRegular(_ url: URL, fileName: String) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular else {
            throw HistoryExportError.invalidBackupAttachmentFile(fileName)
        }
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
                let sourceURL = try ClipEaseStoragePaths.attachmentFileURL(fileName: fileName, in: fromImagesDirectory)
                let destinationURL = try ClipEaseStoragePaths.attachmentFileURL(fileName: fileName, in: toImagesDirectory)
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
                let sourceURL = try ClipEaseStoragePaths.attachmentFileURL(fileName: fileName, in: fromRichTextsDirectory)
                let destinationURL = try ClipEaseStoragePaths.attachmentFileURL(fileName: fileName, in: toRichTextsDirectory)
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
    let groups: [ExportedClipboardGroup]?
    let items: [ExportedClipboardItem]
}

private struct ExportedClipboardGroup: Codable {
    let id: UUID
    let name: String
    let colorHex: String
    let iconName: String
    let sortOrder: Int
    let createdAt: Date
    let updatedAt: Date

    init(_ group: ClipboardGroup) {
        self.id = group.id
        self.name = group.name
        self.colorHex = group.colorHex
        self.iconName = group.iconName
        self.sortOrder = group.sortOrder
        self.createdAt = group.createdAt
        self.updatedAt = group.updatedAt
    }

    var clipboardGroup: ClipboardGroup {
        ClipboardGroup(
            id: id,
            name: name,
            colorHex: colorHex,
            iconName: iconName,
            sortOrder: sortOrder,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
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
    let fileReferences: [ExportedClipboardFileReference]?
    let createdAt: Date
    let sourceAppName: String
    let sourceBundleID: String?
    let isPinned: Bool
    let pinnedAt: Date?
    let groupID: UUID?
    let groupedAt: Date?

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
        self.fileReferences = item.fileReferences.map(ExportedClipboardFileReference.init)
        self.createdAt = item.createdAt
        self.sourceAppName = item.sourceAppName
        self.sourceBundleID = item.sourceBundleID
        self.isPinned = item.isPinned
        self.pinnedAt = item.pinnedAt
        self.groupID = item.groupID
        self.groupedAt = item.groupedAt
    }

    var clipboardItem: ClipboardItem? {
        switch ClipboardItemType(rawValue: type) ?? .text {
        case .image:
            return nil
        case .text, .link, .color, .file:
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
                fileReferences: restoredFileReferences(itemID: id),
                createdAt: createdAt,
                sourceAppName: sourceAppName,
                sourceBundleID: sourceBundleID,
                iconName: "doc.on.clipboard",
                iconFileName: nil,
                headerColorHex: "#0A84FF",
                isPinned: isPinned,
                pinnedAt: pinnedAt,
                groupID: groupID,
                groupedAt: groupedAt
            )
        }
    }

    func clipboardItemForBackupImport(
        backupURL: URL,
        missingAttachmentCount: inout Int
    ) throws -> ClipboardItem? {
        let itemType = ClipboardItemType(rawValue: type) ?? .text
        switch itemType {
        case .image:
            guard let imageFileName,
                  let imageWidth,
                  let imageHeight else {
                return nil
            }

            guard try HistoryExportService.restoreBackupImageAttachment(
                fileName: imageFileName,
                backupURL: backupURL,
                missingAttachmentCount: &missingAttachmentCount
            ) else {
                return nil
            }

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
                fileReferences: [],
                createdAt: createdAt,
                sourceAppName: sourceAppName,
                sourceBundleID: sourceBundleID,
                iconName: "photo",
                iconFileName: nil,
                headerColorHex: "#0A84FF",
                isPinned: isPinned,
                pinnedAt: pinnedAt,
                groupID: groupID,
                groupedAt: groupedAt
            )
        case .text, .link, .color, .file:
            var restoredRichTextFileName: String?
            if let richTextFileName {
                if try HistoryExportService.restoreBackupRichTextAttachment(
                    fileName: richTextFileName,
                    backupURL: backupURL,
                    missingAttachmentCount: &missingAttachmentCount
                ) {
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
                fileReferences: restoredFileReferences(itemID: id),
                createdAt: createdAt,
                sourceAppName: sourceAppName,
                sourceBundleID: sourceBundleID,
                iconName: "doc.on.clipboard",
                iconFileName: nil,
                headerColorHex: "#0A84FF",
                isPinned: isPinned,
                pinnedAt: pinnedAt,
                groupID: groupID,
                groupedAt: groupedAt
            )
        }
    }

    private func restoredFileReferences(itemID: UUID) -> [ClipboardFileReference] {
        (fileReferences ?? []).enumerated().map { index, fileReference in
            fileReference.clipboardFileReference(itemID: itemID, fallbackOrderIndex: index)
        }
    }
}

private struct ExportedClipboardFileReference: Codable {
    let id: UUID
    let orderIndex: Int
    let path: String
    let displayName: String
    let fileExtension: String?
    let contentType: String?
    let fileSize: Int?
    let modifiedAt: Date?
    let isDirectory: Bool
    let isAlias: Bool
    let pathStatus: String
    let lastCheckedAt: Date?
    let createdAt: Date

    init(_ fileReference: ClipboardFileReference) {
        self.id = fileReference.id
        self.orderIndex = fileReference.orderIndex
        self.path = fileReference.path
        self.displayName = fileReference.displayName
        self.fileExtension = fileReference.fileExtension
        self.contentType = fileReference.contentType
        self.fileSize = fileReference.fileSize
        self.modifiedAt = fileReference.modifiedAt
        self.isDirectory = fileReference.isDirectory
        self.isAlias = fileReference.isAlias
        self.pathStatus = fileReference.pathStatus.rawValue
        self.lastCheckedAt = fileReference.lastCheckedAt
        self.createdAt = fileReference.createdAt
    }

    func clipboardFileReference(itemID: UUID, fallbackOrderIndex: Int) -> ClipboardFileReference {
        ClipboardFileReference(
            id: id,
            itemID: itemID,
            orderIndex: orderIndex >= 0 ? orderIndex : fallbackOrderIndex,
            path: path,
            displayName: displayName,
            fileExtension: fileExtension,
            contentType: contentType,
            fileSize: fileSize,
            modifiedAt: modifiedAt,
            isDirectory: isDirectory,
            isAlias: isAlias,
            pathStatus: ClipboardFilePathStatus(rawValue: pathStatus) ?? .unknown,
            lastCheckedAt: lastCheckedAt,
            createdAt: createdAt
        )
    }
}
