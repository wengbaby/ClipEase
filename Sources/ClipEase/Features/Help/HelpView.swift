import SwiftUI

struct HelpView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider()

            ScrollView {
                VStack(spacing: 14) {
                    helpSection(
                        title: "打开轻贴",
                        items: [
                            "点击菜单栏图标打开底部历史窗口。",
                            "菜单栏图标右键可打开更多菜单。",
                            "按 Esc 可关闭底部窗口。"
                        ]
                    )

                    helpSection(
                        title: "使用历史卡片",
                        items: [
                            "复制文字、链接或图片后会自动进入历史。",
                            "单击卡片选中，左右方向键切换。",
                            "按回车会复制选中内容；有辅助功能权限时会自动粘贴。",
                            "右键卡片可复制、置顶、删除、忽略来源 App 或复制来源信息。"
                        ]
                    )

                    helpSection(
                        title: "来源 App",
                        items: [
                            "卡片右上角显示来源 App 图标。",
                            "卡片标题栏颜色取来源 App 图标中心点颜色并加深。",
                            "搜索可以匹配来源 App 名称。"
                        ]
                    )

                    helpSection(
                        title: "搜索和筛选",
                        items: [
                            "顶部搜索可按文字、链接标题和路径查找。",
                            "筛选可查看全部、文字、链接、图片和置顶内容。",
                            "置顶内容始终排在最左侧。"
                        ]
                    )

                    helpSection(
                        title: "新建文本",
                        items: [
                            "更多菜单中的新建文本可创建一条手动历史。",
                            "编辑器支持中文输入、加粗、斜体、下划线、删除线和字号调整。",
                            "创建后会保存到历史，并可再次复制或粘贴。"
                        ]
                    )

                    helpSection(
                        title: "权限说明",
                        items: [
                            "未授权辅助功能权限时，轻贴只会把内容复制回剪贴板。",
                            "授权后，按回车可以自动粘贴到当前正在使用的 App。",
                            "可在设置窗口打开系统辅助功能权限页面。"
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

            Text("快速了解常用操作和权限说明")
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
