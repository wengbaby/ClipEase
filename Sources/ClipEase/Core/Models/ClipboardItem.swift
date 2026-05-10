import Foundation
import SwiftUI

enum ClipboardItemType {
    case text
    case image
    case color
}

struct ClipboardItem: Identifiable, Equatable {
    let id: UUID
    let type: ClipboardItemType
    let text: String
    let createdAt: Date
    let sourceAppName: String
    let sourceBundleID: String?
    let iconName: String
    let headerColor: Color

    var kind: String {
        switch type {
        case .text:
            "文本"
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

