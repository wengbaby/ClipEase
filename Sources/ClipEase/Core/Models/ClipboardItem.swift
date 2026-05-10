import Foundation
import SwiftUI

enum ClipboardItemType: String {
    case text
    case link
    case image
    case color
}

struct ClipboardItem: Identifiable, Equatable {
    let id: UUID
    let type: ClipboardItemType
    let text: String
    let url: URL?
    let linkTitle: String?
    let linkSubtitle: String?
    let createdAt: Date
    let sourceAppName: String
    let sourceBundleID: String?
    let iconName: String
    let headerColorHex: String
    var isPinned: Bool
    var pinnedAt: Date?

    var headerColor: Color {
        Color.clipeaseHex(headerColorHex)
    }

    var kind: String {
        switch type {
        case .text:
            "文本"
        case .link:
            "链接"
        case .image:
            "图片"
        case .color:
            "颜色"
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
        ClipboardItem(
            id: UUID(),
            type: .text,
            text: text,
            url: nil,
            linkTitle: nil,
            linkSubtitle: nil,
            createdAt: Date(),
            sourceAppName: sourceApp.name,
            sourceBundleID: sourceApp.bundleID,
            iconName: sourceApp.iconName,
            headerColorHex: sourceApp.headerColorHex,
            isPinned: false,
            pinnedAt: nil
        )
    }

    static func link(
        _ url: URL,
        originalText: String,
        sourceApp: SourceAppInfo
    ) -> ClipboardItem {
        let host = url.host(percentEncoded: false) ?? url.absoluteString
        let path = url.path(percentEncoded: false)

        return ClipboardItem(
            id: UUID(),
            type: .link,
            text: originalText,
            url: url,
            linkTitle: host.replacingOccurrences(of: "www.", with: ""),
            linkSubtitle: path.isEmpty || path == "/" ? url.absoluteString : "\(host)\(path)",
            createdAt: Date(),
            sourceAppName: sourceApp.name,
            sourceBundleID: sourceApp.bundleID,
            iconName: sourceApp.iconName,
            headerColorHex: sourceApp.headerColorHex,
            isPinned: false,
            pinnedAt: nil
        )
    }
}
