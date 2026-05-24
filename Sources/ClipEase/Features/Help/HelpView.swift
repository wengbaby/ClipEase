import SwiftUI

struct HelpView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider()

            ScrollView {
                VStack(spacing: 14) {
                    helpSection(
                        title: "打开和关闭",
                        items: [
                            "点击菜单栏图标打开历史窗口。",
                            "按 Esc 或点击窗口外关闭。",
                            "右键菜单栏图标可打开设置、帮助、暂停记录或退出。"
                        ]
                    )

                    helpSection(
                        title: "卡片操作",
                        items: [
                            "复制文字、链接、图片或文件后会自动记录。",
                            "单击选中卡片，左右方向键切换。",
                            "回车粘贴选中内容；没有辅助功能权限时只复制到剪贴板。",
                            "Command + 1 到 Command + 9 可快速选择可见卡片。",
                            "Command + C 复制，Command + P 置顶或取消置顶，Delete 删除。",
                            "右键卡片可复制、粘贴为纯文本、打开、在 Finder 中显示或加入分组。"
                        ]
                    )

                    helpSection(
                        title: "搜索和分组",
                        items: [
                            "搜索可查文字、链接标题、文件名、路径和来源 App。",
                            "置顶内容会排在最前面。",
                            "可创建分组，并把常用内容加入分组。"
                        ]
                    )

                    helpSection(
                        title: "预览和文件",
                        items: [
                            "按空格打开预览。",
                            "文本、PDF 和可识别图片可选择文字并复制。",
                            "文件预览优先保留原格式；不支持预览时会显示文件名和路径。",
                            "拖动预览窗口标题栏可把预览变成独立窗口。"
                        ]
                    )

                    helpSection(
                        title: "设置和权限",
                        items: [
                            "自动粘贴需要辅助功能权限；未授权时仍可复制到剪贴板。",
                            "保存期限只清理普通历史，置顶内容不会自动清理。",
                            "设置里可暂停记录、忽略 App、导入导出历史和备份包。",
                            "更多菜单的新建文本可手动创建一条历史记录。"
                        ]
                    )
                }
                .padding(18)
            }
        }
        .frame(minWidth: 560, minHeight: 500)
        .background(Color(red: 0.94, green: 0.95, blue: 0.97))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("轻贴帮助")
                .font(.system(size: 20, weight: .semibold))

            Text("常用操作")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func helpSection(title: String, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))

            VStack(alignment: .leading, spacing: 7) {
                ForEach(items, id: \.self) { item in
                    HStack(alignment: .top, spacing: 8) {
                        Circle()
                            .fill(Color(red: 0.18, green: 0.55, blue: 1.0))
                            .frame(width: 5, height: 5)
                            .padding(.top, 6)

                        Text(item)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color(red: 0.20, green: 0.22, blue: 0.25))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.86))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
