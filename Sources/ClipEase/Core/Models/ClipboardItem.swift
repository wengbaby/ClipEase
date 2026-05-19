import Foundation
import SwiftUI

enum ClipboardItemType: String, Codable, Sendable {
    case text
    case link
    case image
    case color
    case file
}

enum ClipboardFilePathStatus: String, Codable, Sendable {
    case unknown
    case available
    case missing
    case permissionDenied = "permission_denied"
    case placeholder
}

struct ClipboardFileReference: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    let itemID: UUID
    let orderIndex: Int
    let path: String
    let displayName: String
    let fileExtension: String?
    let contentType: String?
    let fileSize: Int?
    let modifiedAt: Date?
    let isDirectory: Bool
    let isAlias: Bool
    let pathStatus: ClipboardFilePathStatus
    let lastCheckedAt: Date?
    let createdAt: Date

    init(
        id: UUID = UUID(),
        itemID: UUID,
        orderIndex: Int,
        path: String,
        displayName: String? = nil,
        fileExtension: String? = nil,
        contentType: String? = nil,
        fileSize: Int? = nil,
        modifiedAt: Date? = nil,
        isDirectory: Bool = false,
        isAlias: Bool = false,
        pathStatus: ClipboardFilePathStatus = .unknown,
        lastCheckedAt: Date? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.itemID = itemID
        self.orderIndex = orderIndex
        self.path = path
        self.displayName = displayName ?? URL(fileURLWithPath: path).lastPathComponent
        self.fileExtension = fileExtension ?? URL(fileURLWithPath: path).pathExtension.nilIfEmpty
        self.contentType = contentType
        self.fileSize = fileSize
        self.modifiedAt = modifiedAt
        self.isDirectory = isDirectory
        self.isAlias = isAlias
        self.pathStatus = pathStatus
        self.lastCheckedAt = lastCheckedAt
        self.createdAt = createdAt
    }
}

struct ClipboardItem: Identifiable, Equatable, Sendable {
    let id: UUID
    let type: ClipboardItemType
    let text: String
    let url: URL?
    var linkTitle: String?
    let linkSubtitle: String?
    let imageFileName: String?
    let imageWidth: Int?
    let imageHeight: Int?
    let imageHash: String?
    let richTextFileName: String?
    let fileReferences: [ClipboardFileReference]
    var createdAt: Date
    let sourceAppName: String
    let sourceBundleID: String?
    let iconName: String
    let iconFileName: String?
    let headerColorHex: String
    var isPinned: Bool
    var pinnedAt: Date?
    var groupID: UUID?
    var groupedAt: Date?

    var headerColor: Color {
        Color.clipeaseHex(headerColorHex)
    }

    var isFromClipEase: Bool {
        sourceBundleID == SourceAppInfo.currentAppBundleID || sourceBundleID == SourceAppInfo.clipease.bundleID
    }

    var kind: String {
        switch type {
        case .text:
            "文本"
        case .link:
            "链接"
        case .image:
            if let imageWidth, let imageHeight {
                "\(imageWidth) × \(imageHeight)"
            } else {
                "图片"
            }
        case .color:
            "颜色"
        case .file:
            if fileReferences.count > 1 {
                "\(fileReferences.count) 个文件"
            } else if fileReferences.first?.isDirectory == true {
                "文件夹"
            } else {
                "文件"
            }
        }
    }

    var preview: String {
        text
    }

    var footer: String {
        switch type {
        case .text:
            "\(text.count) 个字符"
        case .link:
            linkSubtitle ?? text
        case .image:
            "图片"
        case .color:
            text
        case .file:
            fileReferences.first?.path ?? text
        }
    }

    var relativeTime: String {
        let interval = max(0, Int(Date().timeIntervalSince(createdAt)))
        if interval < 60 {
            return "现在"
        }

        let minutes = interval / 60
        if minutes < 60 {
            return "\(minutes) 分钟前"
        }

        let hours = minutes / 60
        if hours < 24 {
            return "\(hours) 小时前"
        }

        let days = hours / 24
        return "\(days) 天前"
    }
}

extension ClipboardItem {
    static func text(
        _ text: String,
        sourceApp: SourceAppInfo
    ) -> ClipboardItem {
        return ClipboardItem(
            id: UUID(),
            type: .text,
            text: text,
            url: nil,
            linkTitle: nil,
            linkSubtitle: nil,
            imageFileName: nil,
            imageWidth: nil,
            imageHeight: nil,
            imageHash: nil,
            richTextFileName: nil,
            fileReferences: [],
            createdAt: Date(),
            sourceAppName: sourceApp.name,
            sourceBundleID: sourceApp.bundleID,
            iconName: sourceApp.iconName,
            iconFileName: sourceApp.iconFileName,
            headerColorHex: sourceApp.headerColorHex,
            isPinned: false,
            pinnedAt: nil,
            groupID: nil,
            groupedAt: nil
        )
    }

    static func color(
        _ hex: String,
        sourceApp: SourceAppInfo
    ) -> ClipboardItem {
        ClipboardItem(
            id: UUID(),
            type: .color,
            text: hex,
            url: nil,
            linkTitle: nil,
            linkSubtitle: nil,
            imageFileName: nil,
            imageWidth: nil,
            imageHeight: nil,
            imageHash: nil,
            richTextFileName: nil,
            fileReferences: [],
            createdAt: Date(),
            sourceAppName: sourceApp.name,
            sourceBundleID: sourceApp.bundleID,
            iconName: sourceApp.iconName,
            iconFileName: sourceApp.iconFileName,
            headerColorHex: sourceApp.headerColorHex,
            isPinned: false,
            pinnedAt: nil,
            groupID: nil,
            groupedAt: nil
        )
    }

    static func link(
        _ url: URL,
        originalText: String,
        sourceApp: SourceAppInfo
    ) -> ClipboardItem {
        let path = url.path(percentEncoded: false)
        let title = path.isEmpty || path == "/" ? "/" : URL(fileURLWithPath: path).lastPathComponent

        return ClipboardItem(
            id: UUID(),
            type: .link,
            text: originalText,
            url: url,
            linkTitle: title,
            linkSubtitle: url.absoluteString,
            imageFileName: nil,
            imageWidth: nil,
            imageHeight: nil,
            imageHash: nil,
            richTextFileName: nil,
            fileReferences: [],
            createdAt: Date(),
            sourceAppName: sourceApp.name,
            sourceBundleID: sourceApp.bundleID,
            iconName: sourceApp.iconName,
            iconFileName: sourceApp.iconFileName,
            headerColorHex: sourceApp.headerColorHex,
            isPinned: false,
            pinnedAt: nil,
            groupID: nil,
            groupedAt: nil
        )
    }

    static func image(
        fileName: String,
        width: Int,
        height: Int,
        hash: String,
        sourceApp: SourceAppInfo
    ) -> ClipboardItem {
        ClipboardItem(
            id: UUID(),
            type: .image,
            text: "",
            url: nil,
            linkTitle: nil,
            linkSubtitle: nil,
            imageFileName: fileName,
            imageWidth: width,
            imageHeight: height,
            imageHash: hash,
            richTextFileName: nil,
            fileReferences: [],
            createdAt: Date(),
            sourceAppName: sourceApp.name,
            sourceBundleID: sourceApp.bundleID,
            iconName: sourceApp.iconName,
            iconFileName: sourceApp.iconFileName,
            headerColorHex: sourceApp.headerColorHex,
            isPinned: false,
            pinnedAt: nil,
            groupID: nil,
            groupedAt: nil
        )
    }

    static func richText(
        plainText: String,
        fileName: String,
        sourceApp: SourceAppInfo
    ) -> ClipboardItem {
        ClipboardItem(
            id: UUID(),
            type: .text,
            text: plainText,
            url: nil,
            linkTitle: nil,
            linkSubtitle: nil,
            imageFileName: nil,
            imageWidth: nil,
            imageHeight: nil,
            imageHash: nil,
            richTextFileName: fileName,
            fileReferences: [],
            createdAt: Date(),
            sourceAppName: sourceApp.name,
            sourceBundleID: sourceApp.bundleID,
            iconName: sourceApp.iconName,
            iconFileName: sourceApp.iconFileName,
            headerColorHex: sourceApp.headerColorHex,
            isPinned: false,
            pinnedAt: nil,
            groupID: nil,
            groupedAt: nil
        )
    }

    static func file(
        references: [ClipboardFileReference],
        sourceApp: SourceAppInfo
    ) -> ClipboardItem {
        let itemID = references.first?.itemID ?? UUID()
        let normalizedReferences = references.enumerated().map { index, reference in
            ClipboardFileReference(
                id: reference.id,
                itemID: itemID,
                orderIndex: index,
                path: reference.path,
                displayName: reference.displayName,
                fileExtension: reference.fileExtension,
                contentType: reference.contentType,
                fileSize: reference.fileSize,
                modifiedAt: reference.modifiedAt,
                isDirectory: reference.isDirectory,
                isAlias: reference.isAlias,
                pathStatus: reference.pathStatus,
                lastCheckedAt: reference.lastCheckedAt,
                createdAt: reference.createdAt
            )
        }

        return ClipboardItem(
            id: itemID,
            type: .file,
            text: fileSummary(for: normalizedReferences),
            url: nil,
            linkTitle: normalizedReferences.first?.displayName,
            linkSubtitle: normalizedReferences.first?.path,
            imageFileName: nil,
            imageWidth: nil,
            imageHeight: nil,
            imageHash: nil,
            richTextFileName: nil,
            fileReferences: normalizedReferences,
            createdAt: Date(),
            sourceAppName: sourceApp.name,
            sourceBundleID: sourceApp.bundleID,
            iconName: sourceApp.iconName,
            iconFileName: sourceApp.iconFileName,
            headerColorHex: sourceApp.headerColorHex,
            isPinned: false,
            pinnedAt: nil,
            groupID: nil,
            groupedAt: nil
        )
    }

    static func debugText(
        _ text: String,
        createdAt: Date,
        sourceApp: SourceAppInfo
    ) -> ClipboardItem {
        ClipboardItem(
            id: UUID(),
            type: .text,
            text: text,
            url: nil,
            linkTitle: nil,
            linkSubtitle: nil,
            imageFileName: nil,
            imageWidth: nil,
            imageHeight: nil,
            imageHash: nil,
            richTextFileName: nil,
            fileReferences: [],
            createdAt: createdAt,
            sourceAppName: sourceApp.name,
            sourceBundleID: sourceApp.bundleID,
            iconName: sourceApp.iconName,
            iconFileName: sourceApp.iconFileName,
            headerColorHex: sourceApp.headerColorHex,
            isPinned: false,
            pinnedAt: nil,
            groupID: nil,
            groupedAt: nil
        )
    }

    func updatingEditableContent(
        text newText: String,
        url newURL: URL? = nil,
        linkTitle newLinkTitle: String? = nil,
        linkSubtitle newLinkSubtitle: String? = nil,
        richTextFileName newRichTextFileName: String? = nil
    ) -> ClipboardItem {
        ClipboardItem(
            id: id,
            type: type,
            text: newText,
            url: newURL,
            linkTitle: newLinkTitle,
            linkSubtitle: newLinkSubtitle,
            imageFileName: imageFileName,
            imageWidth: imageWidth,
            imageHeight: imageHeight,
            imageHash: imageHash,
            richTextFileName: newRichTextFileName ?? richTextFileName,
            fileReferences: fileReferences,
            createdAt: createdAt,
            sourceAppName: sourceAppName,
            sourceBundleID: sourceBundleID,
            iconName: iconName,
            iconFileName: iconFileName,
            headerColorHex: headerColorHex,
            isPinned: isPinned,
            pinnedAt: pinnedAt,
            groupID: groupID,
            groupedAt: groupedAt
        )
    }

    func refreshingFromClipboard(
        _ latestItem: ClipboardItem,
        createdAt refreshedAt: Date,
        richTextFileName refreshedRichTextFileName: String? = nil
    ) -> ClipboardItem {
        ClipboardItem(
            id: id,
            type: latestItem.type,
            text: latestItem.text,
            url: latestItem.url,
            linkTitle: latestItem.linkTitle,
            linkSubtitle: latestItem.linkSubtitle,
            imageFileName: latestItem.type == .image ? (imageFileName ?? latestItem.imageFileName) : latestItem.imageFileName,
            imageWidth: latestItem.type == .image ? (imageWidth ?? latestItem.imageWidth) : latestItem.imageWidth,
            imageHeight: latestItem.type == .image ? (imageHeight ?? latestItem.imageHeight) : latestItem.imageHeight,
            imageHash: latestItem.type == .image ? (imageHash ?? latestItem.imageHash) : latestItem.imageHash,
            richTextFileName: refreshedRichTextFileName ?? latestItem.richTextFileName ?? richTextFileName,
            fileReferences: latestItem.fileReferences.isEmpty ? fileReferences : latestItem.fileReferences,
            createdAt: refreshedAt,
            sourceAppName: latestItem.sourceAppName,
            sourceBundleID: latestItem.sourceBundleID,
            iconName: latestItem.iconName,
            iconFileName: latestItem.iconFileName,
            headerColorHex: latestItem.headerColorHex,
            isPinned: isPinned,
            pinnedAt: pinnedAt,
            groupID: groupID,
            groupedAt: groupedAt
        )
    }

    private static func fileSummary(for references: [ClipboardFileReference]) -> String {
        guard let first = references.first else {
            return ""
        }

        if references.count == 1 {
            return "\(first.displayName)\n\(first.path)"
        }

        let paths = references.map(\.path).joined(separator: "\n")
        return "\(first.displayName) 等 \(references.count) 个文件\n\(paths)"
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
