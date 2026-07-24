import SwiftUI

struct HelpView: View {
    @ObservedObject private var appearanceSettings = AppearanceSettings.shared
    @State private var selectedTopic: HelpTopic = .quickStart

    var body: some View {
        HStack(spacing: 0) {
            sidebar

            Divider()

            article
        }
        .frame(minWidth: 860, minHeight: 620)
        .background(helpBackground)
        .preferredColorScheme(appearanceSettings.preferredColorScheme)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                Label(L("轻贴帮助"), systemImage: "questionmark.circle.fill")
                    .font(titleFont)
                    .foregroundStyle(primaryForeground)

                Text(L("从这里开始，快速找到你想做的事"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(secondaryForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 18)
            .padding(.top, 20)
            .padding(.bottom, 16)

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(HelpTopic.allCases) { topic in
                        Button {
                            selectedTopic = topic
                        } label: {
                            Label(topic.title, systemImage: topic.symbolName)
                                .font(.system(size: 13, weight: selectedTopic == topic ? .semibold : .medium))
                                .foregroundStyle(selectedTopic == topic ? .white : primaryForeground)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 11)
                                .padding(.vertical, 9)
                                .background {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(selectedTopic == topic ? selectedTopicFill : Color.clear)
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(topic.title)
                        .accessibilityAddTraits(selectedTopic == topic ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 14)
            }

            Divider()

            Label(L("提示：⌘W 可关闭本帮助窗口"), systemImage: "keyboard")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(secondaryForeground)
                .padding(14)
        }
        .frame(width: 220)
        .background(sidebarBackground)
    }

    private var article: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                articleHeader

                HelpCallout(
                    title: selectedTopic.calloutTitle,
                    message: selectedTopic.calloutMessage,
                    symbolName: selectedTopic.calloutSymbolName
                )

                ForEach(selectedTopic.sections) { section in
                    HelpArticleSection(section: section)
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.55))
    }

    private var articleHeader: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: selectedTopic.symbolName)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .background(selectedTopicFill)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text(selectedTopic.title)
                    .font(titleFont)
                    .foregroundStyle(primaryForeground)

                Text(selectedTopic.subtitle)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(secondaryForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var helpBackground: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            appearanceSettings.materialTheme.gradient
                .opacity(appearanceSettings.windowEffectOpacity * 0.36)
        }
    }

    private var sidebarBackground: some View {
        Color(nsColor: .controlBackgroundColor)
            .opacity(0.80)
    }

    private var selectedTopicFill: Color {
        Color(red: 0.18, green: 0.55, blue: 1.0)
            .opacity(max(0.56, appearanceSettings.groupColorIntensity))
    }

    private var titleFont: Font {
        var typography = appearanceSettings.typography(for: .windowTitle)
        typography.size = max(18, typography.size + 3)
        return typography.swiftUIFont
    }

    private var primaryForeground: Color {
        Color.primary.opacity(0.92)
    }

    private var secondaryForeground: Color {
        Color.secondary.opacity(0.94)
    }
}

private struct HelpArticleSection: View {
    let section: HelpSection

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text(section.title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(section.items) { item in
                    HelpArticleItem(item: item)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.68))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08))
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct HelpArticleItem: View {
    let item: HelpItem

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: item.symbolName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(red: 0.18, green: 0.55, blue: 1.0))
                .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text(item.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)

                    if let shortcut = item.shortcut {
                        HelpShortcutLabel(text: shortcut)
                    }
                }

                Text(item.message)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct HelpCallout: View {
    let title: String
    let message: String
    let symbolName: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbolName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color(red: 0.18, green: 0.55, blue: 1.0))
                .frame(width: 26, height: 26)
                .background(Color(red: 0.18, green: 0.55, blue: 1.0).opacity(0.14))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(message)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(13)
        .background(Color(red: 0.18, green: 0.55, blue: 1.0).opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
    }
}

private struct HelpShortcutLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.primary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            .accessibilityLabel(L("快捷键 \(text)"))
    }
}

private enum HelpTopic: String, CaseIterable, Identifiable {
    case quickStart
    case history
    case searchAndGroups
    case preview
    case appearance
    case dataAndRecording
    case permissions
    case shortcuts

    var id: Self { self }

    var title: String {
        switch self {
        case .quickStart: L("快速开始")
        case .history: L("历史与卡片")
        case .searchAndGroups: L("搜索与分组")
        case .preview: L("预览与文件")
        case .appearance: L("外观与字体")
        case .dataAndRecording: L("记录与数据")
        case .permissions: L("权限与常见问题")
        case .shortcuts: L("快捷键一览")
        }
    }

    var subtitle: String {
        switch self {
        case .quickStart: L("先完成这几步，就可以把复制过的内容随时找回来。")
        case .history: L("选中、复制、粘贴、置顶和删除，都围绕一张历史卡片完成。")
        case .searchAndGroups: L("用搜索缩小范围，再用分组整理常用内容。")
        case .preview: L("先查看再操作；需要时把预览拖成独立窗口。")
        case .appearance: L("按你的习惯调整颜色、玻璃效果、卡片和字体。")
        case .dataAndRecording: L("掌握暂停记录、保存期限和历史数据管理。")
        case .permissions: L("了解自动粘贴的权限要求，以及遇到问题时先检查什么。")
        case .shortcuts: L("键盘操作可以让查找和粘贴更快。")
        }
    }

    var symbolName: String {
        switch self {
        case .quickStart: "sparkles"
        case .history: "rectangle.stack"
        case .searchAndGroups: "magnifyingglass"
        case .preview: "eye"
        case .appearance: "paintpalette"
        case .dataAndRecording: "externaldrive"
        case .permissions: "checkmark.shield"
        case .shortcuts: "keyboard"
        }
    }

    var calloutTitle: String {
        switch self {
        case .quickStart: L("轻贴会在后台记录新的复制内容")
        case .history: L("先选中，再决定如何使用")
        case .searchAndGroups: L("搜索不会改变你的原始历史")
        case .preview: L("预览可以安全地先看后用")
        case .appearance: L("外观设置会立即应用到窗口")
        case .dataAndRecording: L("暂停记录不会删除已有历史")
        case .permissions: L("没有辅助功能权限也能正常复制")
        case .shortcuts: L("快捷键会随当前焦点自动让位给输入框")
        }
    }

    var calloutMessage: String {
        switch self {
        case .quickStart: L("复制一次，之后就能在轻贴里搜索、预览和再次粘贴。")
        case .history: L("单击卡片或用方向键移动选择，再复制、粘贴、置顶或打开更多操作。")
        case .searchAndGroups: L("先输入关键词；需要长期整理时，再把内容放进分组或置顶。")
        case .preview: L("按空格查看内容，拖动预览顶部区域可把它变成可移动的普通窗口。")
        case .appearance: L("主题、窗口效果、卡片样式、透明度和字体均可独立调整。")
        case .dataAndRecording: L("清空、导入、导出和备份会影响你的历史数据；执行前请留意确认提示。")
        case .permissions: L("只有“自动粘贴到其他 App”需要授权；其他历史浏览和复制功能不受影响。")
        case .shortcuts: L("当搜索框或可编辑文本正在输入时，轻贴会优先保留正常的文字编辑行为。")
        }
    }

    var calloutSymbolName: String {
        switch self {
        case .quickStart: "doc.on.clipboard"
        case .history: "cursorarrow.click"
        case .searchAndGroups: "line.3.horizontal.decrease.circle"
        case .preview: "arrow.up.left.and.arrow.down.right"
        case .appearance: "paintbrush"
        case .dataAndRecording: "tray.full"
        case .permissions: "lock.shield"
        case .shortcuts: "command"
        }
    }

    var sections: [HelpSection] {
        switch self {
        case .quickStart:
            [
                HelpSection(title: L("第一次使用"), items: [
                    .init(L("打开历史窗口"), L("点击菜单栏中的轻贴图标。历史窗口会显示最近记录的内容。"), "menubar.rectangle", nil),
                    .init(L("复制即可记录"), L("轻贴会记录复制的文字、链接、图片、文件和富文本。"), "doc.on.clipboard", nil),
                    .init(L("选中并粘贴"), L("单击一张卡片后按回车，即可将内容粘贴到先前正在使用的 App。"), "return", "⏎"),
                    .init(L("快速关闭"), L("按 Esc 或点击历史窗口外部即可收起窗口。"), "xmark.circle", "Esc")
                ]),
                HelpSection(title: L("一个简单流程"), items: [
                    .init(L("1. 复制"), L("在任意 App 中复制内容。"), "1.circle", nil),
                    .init(L("2. 查找"), L("打开轻贴，通过卡片或搜索定位需要的内容。"), "2.circle", nil),
                    .init(L("3. 使用"), L("回车粘贴，或先预览、复制、置顶和分组。"), "3.circle", nil)
                ])
            ]
        case .history:
            [
                HelpSection(title: L("常用卡片操作"), items: [
                    .init(L("移动选择"), L("单击卡片，或使用左右方向键在可见卡片间切换。"), "arrow.left.and.right", "← / →"),
                    .init(L("再次粘贴"), L("将选中内容粘贴回之前使用的 App；未授予辅助功能权限时会只复制到剪贴板。"), "arrow.uturn.backward", "⏎"),
                    .init(L("复制与纯文本"), L("复制原内容，或在需要去除格式时复制、粘贴为纯文本。"), "doc.on.doc", "⌘C / ⇧⌘C"),
                    .init(L("置顶常用内容"), L("置顶后的内容会排在前面，也不会因保存期限自动清理。"), "pin", "⌘P"),
                    .init(L("删除不需要的内容"), L("选中卡片后按 Delete，或从右键菜单中删除。"), "trash", "Delete")
                ]),
                HelpSection(title: L("更多操作"), items: [
                    .init(L("右键菜单"), L("可按内容类型执行打开、在 Finder 中显示、复制路径、复制 Markdown、加入分组等操作。"), "contextualmenu.and.cursorarrow", nil),
                    .init(L("新建文本"), L("在更多菜单中选择“新建文本”，可以手动保存一条备忘内容。"), "square.and.pencil", nil),
                    .init(L("快速选中"), L("按 ⌘1 到 ⌘9 可直接选中当前可见区域内对应位置的卡片。"), "numbers", "⌘1–⌘9")
                ])
            ]
        case .searchAndGroups:
            [
                HelpSection(title: L("搜索"), items: [
                    .init(L("直接输入关键词"), L("搜索会查找文本、链接标题、文件名、文件路径和来源 App。"), "magnifyingglass", nil),
                    .init(L("缩小内容范围"), L("配合当前分组和来源 App 筛选，更容易找到以前复制过的内容。"), "line.3.horizontal.decrease.circle", nil),
                    .init(L("清空搜索继续浏览"), L("清除关键词后，会回到当前范围内的完整历史。"), "xmark.circle", nil)
                ]),
                HelpSection(title: L("分组与置顶"), items: [
                    .init(L("创建和管理分组"), L("可为常用内容建立分组，并调整分组名称、图标和颜色。"), "folder.badge.plus", nil),
                    .init(L("把内容加入分组"), L("从卡片右键菜单选择分组；之后可从分组栏快速切换。"), "folder", nil),
                    .init(L("置顶不是分组"), L("置顶用于让单条内容始终靠前；分组用于长期分类整理。"), "pin.circle", nil)
                ])
            ]
        case .preview:
            [
                HelpSection(title: L("打开预览"), items: [
                    .init(L("查看选中内容"), L("选中卡片后按空格，可预览文字、图片、链接和文件。"), "eye", "Space"),
                    .init(L("图片与文字"), L("可识别图片中的文字；富文本、文本和 PDF 会尽量保留可阅读、可选择的内容。"), "text.viewfinder", nil),
                    .init(L("文件预览"), L("支持的文件会显示内容；无法预览时仍会保留文件名、路径和打开方式。"), "doc.richtext", nil)
                ]),
                HelpSection(title: L("把预览变成普通窗口"), items: [
                    .init(L("拖出预览"), L("拖动预览顶部区域，即可将它变成可移动、可调整大小的独立窗口。"), "arrow.up.left.and.arrow.down.right", nil),
                    .init(L("关闭独立预览"), L("独立预览可使用 Esc 或 ⌘W 关闭，不会关闭历史主窗口。"), "xmark.rectangle", "Esc / ⌘W"),
                    .init(L("从预览继续操作"), L("预览中仍可复制、打开、显示到 Finder 或关闭窗口。"), "cursorarrow.click", nil)
                ])
            ]
        case .appearance:
            [
                HelpSection(title: L("窗口和卡片外观"), items: [
                    .init(L("选择颜色主题"), L("可设为浅色、深色或跟随系统；设置窗口和主窗口会同步更新。"), "circle.lefthalf.filled", nil),
                    .init(L("选择窗口效果"), L("可在液态玻璃、普通及更多视觉效果之间切换；默认会折叠较多选项。"), "macwindow", nil),
                    .init(L("选择卡片样式"), L("卡片提供与窗口效果相同的丰富样式，可单独调整。"), "rectangle.stack.fill", nil),
                    .init(L("调节透明度"), L("窗口和卡片的效果透明度可独立调整；部分顶部区域也有单独的强度控制。"), "slider.horizontal.3", nil)
                ]),
                HelpSection(title: L("字体与可读性"), items: [
                    .init(L("分别设置字体"), L("可调整窗口标题、搜索、分组、工具栏按钮和卡片内容的字体、大小及字重。"), "textformat", nil),
                    .init(L("玻璃效果开关"), L("需要更强的视觉效果时可开启液态玻璃；也可关闭以获得更朴素的界面。"), "drop", nil),
                    .init(L("恢复默认外观"), L("在外观设置中可恢复默认配置。"), "arrow.counterclockwise", nil)
                ])
            ]
        case .dataAndRecording:
            [
                HelpSection(title: L("控制记录"), items: [
                    .init(L("暂停或恢复"), L("暂停后，新的复制内容不会写入历史；已有记录不会受到影响。"), "pause.circle", "⌘T"),
                    .init(L("忽略特定 App"), L("可在设置中将 App 加入忽略列表，避免来自该 App 的复制内容被记录。"), "eye.slash", nil),
                    .init(L("开机启动与全局快捷键"), L("可在设置中控制登录时启动和全局快捷键。"), "power", nil)
                ]),
                HelpSection(title: L("历史数据"), items: [
                    .init(L("保存期限"), L("普通历史会按设置的期限自动清理；置顶内容不会自动清理。"), "clock.arrow.circlepath", nil),
                    .init(L("导入、导出与备份"), L("可在设置中导出历史、导入历史或创建/恢复备份包。"), "externaldrive.badge.icloud", nil),
                    .init(L("清理数据"), L("可清空历史，也可清理图标、缩略图缓存或检查孤立附件。执行前会要求确认。"), "trash.circle", nil)
                ])
            ]
        case .permissions:
            [
                HelpSection(title: L("辅助功能权限"), items: [
                    .init(L("为什么需要权限"), L("自动将选中内容粘贴到其他 App 时，macOS 需要辅助功能权限。"), "accessibility", nil),
                    .init(L("没有权限时"), L("轻贴仍能记录、搜索、预览和复制内容；回车操作会改为只复制到剪贴板。"), "doc.on.doc", nil),
                    .init(L("如何授权"), L("打开设置中的权限页面，按提示前往系统设置完成授权。"), "gearshape", nil)
                ]),
                HelpSection(title: L("遇到问题先检查"), items: [
                    .init(L("没有新记录"), L("确认记录未暂停，并检查来源 App 是否被加入忽略列表。"), "exclamationmark.triangle", nil),
                    .init(L("回车没有自动粘贴"), L("确认已授予辅助功能权限，并确保目标 App 仍可接收文本输入。"), "keyboard", nil),
                    .init(L("找不到旧内容"), L("尝试清除搜索条件、切换分组，或检查保存期限和手动清理操作。"), "magnifyingglass.circle", nil)
                ])
            ]
        case .shortcuts:
            [
                HelpSection(title: L("历史窗口"), items: [
                    .init(L("打开预览"), L("预览当前选中的卡片。"), "eye", "Space"),
                    .init(L("粘贴"), L("将选中内容粘贴到之前使用的 App。"), "return", "⏎"),
                    .init(L("粘贴为纯文本"), L("在需要去除格式时使用。"), "textformat", "⇧⏎"),
                    .init(L("复制 / 复制纯文本"), L("复制选中内容，或仅复制其纯文本形式。"), "doc.on.doc", "⌘C / ⇧⌘C"),
                    .init(L("置顶"), L("置顶或取消置顶选中卡片。"), "pin", "⌘P"),
                    .init(L("删除"), L("删除选中卡片。"), "trash", "Delete"),
                    .init(L("切换卡片"), L("在可见卡片之间移动选择。"), "arrow.left.and.right", "← / →"),
                    .init(L("快速选中"), L("选择第 1 到第 9 张可见卡片。"), "numbers", "⌘1–⌘9")
                ]),
                HelpSection(title: L("应用与窗口"), items: [
                    .init(L("设置"), L("打开轻贴设置。"), "gearshape", "⌘,"),
                    .init(L("编辑"), L("编辑当前可编辑内容。"), "square.and.pencil", "⌘E"),
                    .init(L("暂停 / 恢复记录"), L("快速切换记录状态。"), "pause.circle", "⌘T"),
                    .init(L("关闭预览"), L("关闭附着预览；独立预览也支持 ⌘W。"), "xmark.circle", "Esc / ⌘W")
                ])
            ]
        }
    }
}

private struct HelpSection: Identifiable {
    let id = UUID()
    let title: String
    let items: [HelpItem]
}

private struct HelpItem: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let symbolName: String
    let shortcut: String?

    init(_ title: String, _ message: String, _ symbolName: String, _ shortcut: String?) {
        self.title = title
        self.message = message
        self.symbolName = symbolName
        self.shortcut = shortcut
    }
}
