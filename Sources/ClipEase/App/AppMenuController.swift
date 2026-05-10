import AppKit

@MainActor
final class AppMenuController: NSObject {
    private let historyStore: ClipboardHistoryStore
    private let recordingController: RecordingController

    init(
        historyStore: ClipboardHistoryStore,
        recordingController: RecordingController
    ) {
        self.historyStore = historyStore
        self.recordingController = recordingController
        super.init()
    }

    func createTextItem() {
        let alert = NSAlert()
        alert.messageText = "新建文本"
        alert.informativeText = "输入要保存到轻贴历史的文本。"
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "取消")

        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 420, height: 170))
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder

        let textView = NSTextView(frame: scrollView.bounds)
        textView.font = .systemFont(ofSize: 14)
        textView.isRichText = false
        textView.allowsUndo = true
        textView.textContainerInset = NSSize(width: 8, height: 8)
        scrollView.documentView = textView

        alert.accessoryView = scrollView
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else {
            return
        }

        let text = textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return
        }

        historyStore.addText(text, sourceApp: .clipease)
    }

    func showHelp() {
        openProjectURL(path: "blob/main/docs/PROJECT_GUIDE.md")
    }

    func showSettingsPlaceholder() {
        let alert = NSAlert()
        alert.messageText = "设置"
        alert.informativeText = "设置页会分阶段补充：快捷键、开机启动、忽略 App、保存期限和清空历史。"
        alert.addButton(withTitle: "知道了")
        alert.runModal()
    }

    func pauseRecording() {
        recordingController.setPaused(true)
    }

    func resumeRecording() {
        recordingController.setPaused(false)
    }

    func pauseRecording(for interval: TimeInterval) {
        recordingController.pause(for: interval)
    }

    func pauseUntilEndOfToday() {
        recordingController.pauseUntilEndOfToday()
    }

    func showAbout() {
        let alert = NSAlert()
        alert.messageText = "关于轻贴"
        alert.informativeText = "轻贴 ClipEase\n简洁好用的 macOS 粘贴板历史助手"
        alert.addButton(withTitle: "好的")
        alert.runModal()
    }

    func quit() {
        NSApplication.shared.terminate(nil)
    }

    func makeStatusBarMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(makeItem("新建文本", action: #selector(newTextAction)))
        menu.addItem(.separator())
        menu.addItem(makeItem("帮助", action: #selector(helpAction)))
        menu.addItem(makeItem("设置", action: #selector(settingsAction)))
        menu.addItem(.separator())

        let pauseItem = NSMenuItem(title: "暂停", action: nil, keyEquivalent: "")
        pauseItem.submenu = makePauseMenu()
        menu.addItem(pauseItem)

        menu.addItem(.separator())
        menu.addItem(makeItem("退出", action: #selector(quitAction)))
        menu.addItem(makeItem("关于轻贴", action: #selector(aboutAction)))
        return menu
    }

    private func makePauseMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(makeItem("暂停", action: #selector(pauseAction)))
        menu.addItem(makeItem("暂停 15 分钟", action: #selector(pause15MinutesAction)))
        menu.addItem(makeItem("暂停 30 分钟", action: #selector(pause30MinutesAction)))
        menu.addItem(makeItem("暂停 1 小时", action: #selector(pause1HourAction)))
        menu.addItem(makeItem("暂停 3 小时", action: #selector(pause3HoursAction)))
        menu.addItem(makeItem("暂停 6 小时", action: #selector(pause6HoursAction)))
        menu.addItem(makeItem("截止到今日", action: #selector(pauseUntilTodayAction)))
        return menu
    }

    private func makeItem(_ title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    private func openProjectURL(path: String) {
        guard let url = URL(string: "https://github.com/wengbaby/ClipEase/\(path)") else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    @objc private func newTextAction() {
        createTextItem()
    }

    @objc private func helpAction() {
        showHelp()
    }

    @objc private func settingsAction() {
        showSettingsPlaceholder()
    }

    @objc private func pauseAction() {
        pauseRecording()
    }

    @objc private func pause15MinutesAction() {
        pauseRecording(for: 15 * 60)
    }

    @objc private func pause30MinutesAction() {
        pauseRecording(for: 30 * 60)
    }

    @objc private func pause1HourAction() {
        pauseRecording(for: 60 * 60)
    }

    @objc private func pause3HoursAction() {
        pauseRecording(for: 3 * 60 * 60)
    }

    @objc private func pause6HoursAction() {
        pauseRecording(for: 6 * 60 * 60)
    }

    @objc private func pauseUntilTodayAction() {
        pauseUntilEndOfToday()
    }

    @objc private func quitAction() {
        quit()
    }

    @objc private func aboutAction() {
        showAbout()
    }
}
