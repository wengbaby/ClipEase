import SwiftUI

enum HistoryPreviewType {
    case text
    case link
    case image
    case color
}

struct HistoryPreviewItem: Identifiable {
    let id: UUID
    let type: HistoryPreviewType
    let kind: String
    let time: String
    let iconName: String
    let headerColor: Color
    let preview: String
    let footer: String
    let linkTitle: String?
    let linkSubtitle: String?
    let imageFileName: String?
    let isPinned: Bool

    var searchText: String {
        [
            kind,
            preview,
            footer,
            linkTitle,
            linkSubtitle
        ]
        .compactMap { $0 }
        .joined(separator: " ")
    }

    init(item: ClipboardItem) {
        self.id = item.id
        self.type = HistoryPreviewType(item.type)
        self.kind = item.kind
        self.time = item.relativeTime
        self.iconName = item.iconName
        self.headerColor = item.headerColor
        self.preview = item.preview
        self.footer = item.footer
        self.linkTitle = item.linkTitle
        self.linkSubtitle = item.linkSubtitle
        self.imageFileName = item.imageFileName
        self.isPinned = item.isPinned
    }

    init(
        id: UUID,
        type: HistoryPreviewType,
        kind: String,
        time: String,
        iconName: String,
        headerColor: Color,
        preview: String,
        footer: String,
        linkTitle: String? = nil,
        linkSubtitle: String? = nil,
        imageFileName: String? = nil,
        isPinned: Bool = false
    ) {
        self.id = id
        self.type = type
        self.kind = kind
        self.time = time
        self.iconName = iconName
        self.headerColor = headerColor
        self.preview = preview
        self.footer = footer
        self.linkTitle = linkTitle
        self.linkSubtitle = linkSubtitle
        self.imageFileName = imageFileName
        self.isPinned = isPinned
    }

    static let samples: [HistoryPreviewItem] = [
        HistoryPreviewItem(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            type: .image,
            kind: "图片",
            time: "现在",
            iconName: "app.fill",
            headerColor: Color(red: 0.04, green: 0.50, blue: 0.95),
            preview: "",
            footer: "766 × 666"
        ),
        HistoryPreviewItem(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            type: .text,
            kind: "文本",
            time: "7 分钟前",
            iconName: "text.alignleft",
            headerColor: Color(red: 0.04, green: 0.50, blue: 0.95),
            preview: "现在请你规划开发步骤，不要一口气做太多，让项目稳定安全有效的推进。",
            footer: "148 个字符"
        ),
        HistoryPreviewItem(
            id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            type: .image,
            kind: "图片",
            time: "4 分钟前",
            iconName: "safari.fill",
            headerColor: Color(red: 0.00, green: 0.72, blue: 0.66),
            preview: "",
            footer: "3360 × 332"
        ),
        HistoryPreviewItem(
            id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
            type: .color,
            kind: "颜色",
            time: "4 分钟前",
            iconName: "paintpalette.fill",
            headerColor: Color(red: 1.00, green: 0.24, blue: 0.22),
            preview: "#888888",
            footer: "颜色"
        ),
        HistoryPreviewItem(
            id: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!,
            type: .text,
            kind: "文本",
            time: "12 分钟前",
            iconName: "message.fill",
            headerColor: Color(red: 0.04, green: 0.70, blue: 0.38),
            preview: "卡片列表需要支持键盘切换，选中项要清晰，后续接入真实剪贴板数据时可以沿用这一套交互。",
            footer: "52 个字符"
        ),
        HistoryPreviewItem(
            id: UUID(uuidString: "66666666-6666-6666-6666-666666666666")!,
            type: .image,
            kind: "图片",
            time: "18 分钟前",
            iconName: "camera.viewfinder",
            headerColor: Color(red: 0.57, green: 0.38, blue: 0.92),
            preview: "",
            footer: "1440 × 900"
        ),
        HistoryPreviewItem(
            id: UUID(uuidString: "77777777-7777-7777-7777-777777777777")!,
            type: .link,
            kind: "链接",
            time: "现在",
            iconName: "safari.fill",
            headerColor: Color(red: 0.04, green: 0.50, blue: 0.95),
            preview: "https://api.totapp.com/admin/accounts",
            footer: "api.totapp.com/admin/accounts",
            linkTitle: "api.totapp.com",
            linkSubtitle: "api.totapp.com/admin/accounts"
        )
    ]
}

extension HistoryPreviewType {
    init(_ type: ClipboardItemType) {
        switch type {
        case .text:
            self = .text
        case .link:
            self = .link
        case .image:
            self = .image
        case .color:
            self = .color
        }
    }
}
