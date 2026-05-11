import AppKit

@MainActor
final class AppMenuController: NSObject {
    private let historyStore: ClipboardHistoryStore
    private let recordingController: RecordingController
    private let loginItemController: LoginItemController
    private let ignoredAppSettings: IgnoredAppSettings
    private let globalShortcutSettings: GlobalShortcutSettings
    private let accessibilityPermissionState: AccessibilityPermissionState
    private let pasteExecutor: PasteExecutor
    private var richTextEditorController: RichTextEditorController?
    private var settingsWindowController: SettingsWindowController?
    private var helpWindowController: HelpWindowController?

    init(
        historyStore: ClipboardHistoryStore,
        recordingController: RecordingController,
        loginItemController: LoginItemController,
        ignoredAppSettings: IgnoredAppSettings,
        globalShortcutSettings: GlobalShortcutSettings,
        accessibilityPermissionState: AccessibilityPermissionState,
        pasteExecutor: PasteExecutor
    ) {
        self.historyStore = historyStore
        self.recordingController = recordingController
        self.loginItemController = loginItemController
        self.ignoredAppSettings = ignoredAppSettings
        self.globalShortcutSettings = globalShortcutSettings
        self.accessibilityPermissionState = accessibilityPermissionState
        self.pasteExecutor = pasteExecutor
        super.init()
    }

    func createTextItem() {
        let editorController = RichTextEditorController { [weak self] data, plainText in
            self?.historyStore.addRichText(
                data,
                plainText: plainText,
                sourceApp: .clipease
            )
        }
        richTextEditorController = editorController
        editorController.show()
    }

    func showHelp() {
        let helpWindowController = helpWindowController ?? HelpWindowController()
        self.helpWindowController = helpWindowController
        helpWindowController.show()
    }

    func showSettings() {
        let settingsWindowController = settingsWindowController ?? SettingsWindowController(
            store: historyStore,
            recordingController: recordingController,
            loginItemController: loginItemController,
            ignoredAppSettings: ignoredAppSettings,
            globalShortcutSettings: globalShortcutSettings,
            accessibilityPermissionState: accessibilityPermissionState,
            pasteExecutor: pasteExecutor
        )
        self.settingsWindowController = settingsWindowController
        settingsWindowController.show()
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

    func ignoreSourceApp(for item: ClipboardItem) {
        ignoredAppSettings.add(
            bundleID: item.sourceBundleID,
            name: item.sourceAppName
        )
    }

    func addDebugTextItems(count: Int) {
        historyStore.addDebugTextItems(count: count)
    }

    func clearDebugTextItems() -> Int {
        historyStore.clearDebugTextItems()
    }

    func showAbout() {
        let alert = NSAlert()
        alert.messageText = "关于轻贴"
        alert.informativeText = "轻贴 ClipEase\n简洁好用的 macOS 粘贴板历史助手\n版本 \(AppVersionInfo.displayVersion)"
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

        let pauseItem = NSMenuItem(title: "暂停 轻贴", action: nil, keyEquivalent: "")
        pauseItem.submenu = makePauseMenu()
        menu.addItem(pauseItem)

        menu.addItem(.separator())
        menu.addItem(makeItem("退出", action: #selector(quitAction)))
        menu.addItem(makeItem("关于轻贴", action: #selector(aboutAction)))
        return menu
    }

    private func makePauseMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(makeItem(recordingController.pauseMenuPrimaryTitle(), action: #selector(togglePauseAction)))
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

    @objc private func newTextAction() {
        createTextItem()
    }

    @objc private func helpAction() {
        showHelp()
    }

    @objc private func settingsAction() {
        showSettings()
    }

    @objc private func togglePauseAction() {
        if recordingController.isPaused {
            resumeRecording()
        } else {
            pauseRecording()
        }
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
