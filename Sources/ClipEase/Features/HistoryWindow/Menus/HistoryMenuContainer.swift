import SwiftUI
import AppKit

extension HistoryWindowView {
    func cardMenu(for item: HistoryPreviewItem) -> NSMenu {
        let menu = NSMenu()

        HistoryMenuBuilder.addMenuItem(HistoryCommand.paste.title, to: menu) { pasteItem(item.id) }

        if item.type == .text || item.type == .link || item.type == .color {
            HistoryMenuBuilder.addMenuItem(HistoryCommand.pastePlainText.title, to: menu) { pastePlainTextItem(item.id) }
        }

        HistoryMenuBuilder.addMenuItem(HistoryCommand.preview.title, to: menu) { showPreview(item.id) }

        if isEditable(item) {
            HistoryMenuBuilder.addMenuItem(HistoryCommand.edit.title, to: menu) { beginEditItem(item.id) }
        }

        HistoryMenuBuilder.addMenuItem(item.isPinned ? L("取消置顶") : L("置顶"), to: menu) { togglePinned(item.id) }
        menu.addItem(.separator())

        addTypeSpecificMenuItems(for: item, to: menu)

        if !groupUIState.moveToGroupMenuSnapshot.isEmpty {
            HistoryMenuBuilder.addMenuItem(item.groupID == nil ? L("加入分组...") : L("移动到分组..."), to: menu) {
                presentMoveToGroupPicker(for: item)
            }
        }

        if item.groupID != nil {
            HistoryMenuBuilder.addMenuItem(L("移出分组"), to: menu) { removeItemFromGroup(item.id) }
        }

        HistoryMenuBuilder.addMenuItem(L("删除"), to: menu) { deleteItem(item.id) }

        if let sourceItem = displayedSourceItem(with: item.id),
           sourceItem.sourceBundleID != nil {
            menu.addItem(.separator())
            if !sourceItem.isFromClipEase {
                HistoryMenuBuilder.addMenuItem(sourceAppIgnoreMenuTitle(for: sourceItem), to: menu) { toggleSourceAppIgnored(item.id) }
            }
            HistoryMenuBuilder.addMenuItem(L("复制来源 App 名称"), to: menu) { copySourceAppName(item.id) }
            HistoryMenuBuilder.addMenuItem(L("复制来源 Bundle ID"), to: menu) { copySourceBundleID(item.id) }
        }

        return menu
    }

    func addTypeSpecificMenuItems(for item: HistoryPreviewItem, to menu: NSMenu) {
        switch item.type {
        case .link:
            HistoryMenuBuilder.addMenuItem(L("打开链接"), to: menu) { openLink(item.id) }
            HistoryMenuBuilder.addMenuItem(L("复制链接地址"), to: menu) { copyLinkURL(item.id) }
            HistoryMenuBuilder.addMenuItem(L("复制为 Markdown 链接"), to: menu) { copyMarkdownLink(item.id) }
            menu.addItem(.separator())
        case .color:
            HistoryMenuBuilder.addMenuItem(L("复制 HEX"), to: menu) { copyColorHex(item.id) }
            HistoryMenuBuilder.addMenuItem(L("复制 RGB"), to: menu) { copyColorRGB(item.id) }
            menu.addItem(.separator())
        case .image:
            HistoryMenuBuilder.addMenuItem(L("打开图片"), to: menu) { openImage(item.id) }
            HistoryMenuBuilder.addMenuItem(L("复制图像"), to: menu) { copyImage(item.id) }
            HistoryMenuBuilder.addMenuItem(L("复制图片路径"), to: menu) { copyImagePath(item.id) }
            HistoryMenuBuilder.addMenuItem(L("在 Finder 中显示"), to: menu) { revealImageInFinder(item.id) }
            menu.addItem(.separator())
        case .file:
            HistoryMenuBuilder.addMenuItem(L("打开文件"), to: menu) { openFile(item.id) }
            HistoryMenuBuilder.addMenuItem(L("复制文件"), to: menu) { copyFile(item.id) }
            HistoryMenuBuilder.addMenuItem(L("复制路径"), to: menu) { copyFilePaths(item.id) }
            HistoryMenuBuilder.addMenuItem(L("在 Finder 中显示"), to: menu) { revealFilesInFinder(item.id) }
            menu.addItem(.separator())
        case .text:
            break
        }
    }

    func makeMoreMenu() -> NSMenu {
        let menu = NSMenu()

        HistoryMenuBuilder.addMenuItem(HistoryCommand.newText.title, to: menu) {
            createTextFromMenu()
        }

        menu.addItem(.separator())

        HistoryMenuBuilder.addMenuItem(HistoryCommand.help.title, to: menu) {
            appMenuController.showHelp()
        }

        HistoryMenuBuilder.addMenuItem(HistoryCommand.settings.title, to: menu) {
            appMenuController.showSettings()
        }

        let pauseItem = NSMenuItem(title: L("暂停 轻贴"), action: nil, keyEquivalent: "")
        pauseItem.submenu = makePauseNSMenu()
        menu.addItem(pauseItem)

        menu.addItem(.separator())

        let clearItem = NSMenuItem(title: L("清空历史"), action: nil, keyEquivalent: "")
        let clearTarget = ClosureMenuItemTarget {
            groupUIState.isClearConfirmationPresented = true
        }
        clearItem.target = clearTarget
        clearItem.representedObject = clearTarget
        clearItem.action = #selector(ClosureMenuItemTarget.performAction)
        clearItem.isEnabled = !store.items.isEmpty
        menu.addItem(clearItem)

        menu.addItem(.separator())

        HistoryMenuBuilder.addMenuItem(HistoryCommand.quit.title, to: menu) {
            appMenuController.quit()
        }

        HistoryMenuBuilder.addMenuItem(HistoryCommand.about.title, to: menu) {
            appMenuController.showAbout()
        }

        return menu
    }

    func makePauseNSMenu() -> NSMenu {
        let menu = NSMenu()

        HistoryMenuBuilder.addMenuItem(recordingController.pauseMenuPrimaryTitle(), to: menu) {
            togglePauseFromMenu()
        }
        HistoryMenuBuilder.addMenuItem(L("暂停 15 分钟"), to: menu) {
            pauseRecording(for: 15 * 60, message: L("已暂停 15 分钟"))
        }
        HistoryMenuBuilder.addMenuItem(L("暂停 30 分钟"), to: menu) {
            pauseRecording(for: 30 * 60, message: L("已暂停 30 分钟"))
        }
        HistoryMenuBuilder.addMenuItem(L("暂停 1 小时"), to: menu) {
            pauseRecording(for: 60 * 60, message: L("已暂停 1 小时"))
        }
        HistoryMenuBuilder.addMenuItem(L("暂停 3 小时"), to: menu) {
            pauseRecording(for: 3 * 60 * 60, message: L("已暂停 3 小时"))
        }
        HistoryMenuBuilder.addMenuItem(L("暂停 6 小时"), to: menu) {
            pauseRecording(for: 6 * 60 * 60, message: L("已暂停 6 小时"))
        }
        HistoryMenuBuilder.addMenuItem(L("截止到今日"), to: menu) {
            appMenuController.pauseUntilEndOfToday()
        }

        return menu
    }
}
