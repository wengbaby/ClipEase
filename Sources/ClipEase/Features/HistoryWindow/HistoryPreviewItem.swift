import SwiftUI

enum HistoryPreviewType {
    case text
    case image
    case color
}

struct HistoryPreviewItem: Identifiable {
    let id = UUID()
    let type: HistoryPreviewType
    let kind: String
    let time: String
    let iconName: String
    let headerColor: Color
    let preview: String
    let footer: String
    let isSelected: Bool

    static let samples: [HistoryPreviewItem] = [
        HistoryPreviewItem(
            type: .image,
            kind: "图片",
            time: "现在",
            iconName: "app.fill",
            headerColor: Color(red: 0.04, green: 0.50, blue: 0.95),
            preview: "",
            footer: "766 × 666",
            isSelected: true
        ),
        HistoryPreviewItem(
            type: .text,
            kind: "文本",
            time: "7 分钟前",
            iconName: "text.alignleft",
            headerColor: Color(red: 0.04, green: 0.50, blue: 0.95),
            preview: "现在请你规划开发步骤，不要一口气做太多，让项目稳定安全有效的推进。",
            footer: "148 个字符",
            isSelected: false
        ),
        HistoryPreviewItem(
            type: .image,
            kind: "图片",
            time: "4 分钟前",
            iconName: "safari.fill",
            headerColor: Color(red: 0.00, green: 0.72, blue: 0.66),
            preview: "",
            footer: "3360 × 332",
            isSelected: false
        ),
        HistoryPreviewItem(
            type: .color,
            kind: "颜色",
            time: "4 分钟前",
            iconName: "paintpalette.fill",
            headerColor: Color(red: 1.00, green: 0.24, blue: 0.22),
            preview: "#888888",
            footer: "颜色",
            isSelected: false
        )
    ]
}

