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
    private var richTextEditorControllers: [RichTextEditorController] = []
    private var settingsWindowController: SettingsWindowController?
    private var helpWindowController: HelpWindowController?
    private var permissionGuideWindowController: AccessibilityPermissionGuideWindowController?
    private weak var historyWindowController: HistoryWindowController?
    private var statusToastAnchorWindow: NSWindow?

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

    func attachHistoryWindowController(_ controller: HistoryWindowController) {
        historyWindowController = controller
    }

    func setStatusToastAnchorWindow(_ window: NSWindow?) {
        statusToastAnchorWindow = window
    }

    private func closeHistoryWindowIfNeeded() {
        historyWindowController?.hideImmediatelyForAutoPaste()
    }

    func createTextItem(
        defaultGroupID: ClipboardGroup.ID? = nil,
        onCreated: ((ClipboardItem) -> Void)? = nil
    ) {
        closeHistoryWindowIfNeeded()
        let editorController = Self.makeCreateTextEditorForTesting(
            historyStore: historyStore,
            defaultGroupID: defaultGroupID,
            onCreated: onCreated
        )
        editorController.onClose = { [weak self, weak editorController] in
            guard let editorController else {
                return
            }

            self?.richTextEditorControllers.removeAll { $0 === editorController }
        }
        richTextEditorControllers.append(editorController)
        editorController.show()
    }

    static func makeCreateTextEditorForTesting(
        historyStore: ClipboardHistoryStore,
        defaultGroupID: ClipboardGroup.ID? = nil,
        onCreated: ((ClipboardItem) -> Void)? = nil
    ) -> RichTextEditorController {
        RichTextEditorController(
            groups: historyStore.groups,
            selectedGroupID: defaultGroupID
        ) { [weak historyStore] data, plainText, selectedGroupID in
            guard let historyStore else {
                return nil
            }

            let createdItem = try await historyStore.addRichText(
                data,
                plainText: plainText,
                sourceApp: .clipease,
                groupID: selectedGroupID
            )
            if let createdItem {
                onCreated?(createdItem)
            }
            return createdItem
        }
    }

    func editItem(
        _ item: ClipboardItem,
        onSave: @escaping (ClipboardItem) -> Void,
        onClose: (() -> Void)? = nil
    ) {
        let editorController = RichTextEditorController(
            mode: .edit(item),
            onSaveEdit: { [weak self] id, text in
                let updatedItem = self?.historyStore.updateEditableContent(for: id, text: text)
                if let updatedItem {
                    onSave(updatedItem)
                }
                return updatedItem
            },
            richTextDataProvider: { [weak self] item in
                self?.historyStore.richTextData(for: item)
            },
            onSaveRichTextEdit: { [weak self] id, data, plainText in
                guard let self else {
                    return nil
                }
                let updatedItem = try await self.historyStore.updateRichTextContent(
                    for: id,
                    data: data,
                    plainText: plainText
                )
                if let updatedItem {
                    onSave(updatedItem)
                }
                return updatedItem
            }
        )
        editorController.onClose = { [weak self, weak editorController] in
            guard let editorController else {
                onClose?()
                return
            }

            self?.richTextEditorControllers.removeAll { $0 === editorController }
            onClose?()
        }
        richTextEditorControllers.append(editorController)
        editorController.show()
    }

    func showHelp() {
        closeHistoryWindowIfNeeded()
        let helpWindowController = helpWindowController ?? HelpWindowController()
        self.helpWindowController = helpWindowController
        helpWindowController.show()
    }

    func showSettings() {
        closeHistoryWindowIfNeeded()
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

    func showPermissionGuide() {
        closeHistoryWindowIfNeeded()
        accessibilityPermissionState.refresh()
        if accessibilityPermissionState.isTrusted {
            return
        }

        let permissionGuideWindowController = permissionGuideWindowController ?? AccessibilityPermissionGuideWindowController(
            permissionState: accessibilityPermissionState
        )
        self.permissionGuideWindowController = permissionGuideWindowController
        permissionGuideWindowController.show()
    }

    func pauseRecording() {
        closeHistoryWindowIfNeeded()
        recordingController.setPaused(true)
        showStatus(L("已暂停记录"))
    }

    func resumeRecording() {
        closeHistoryWindowIfNeeded()
        recordingController.setPaused(false)
        showStatus(L("已恢复记录"))
    }

    func pauseRecording(for interval: TimeInterval, preset: RecordingPausePreset? = nil) {
        closeHistoryWindowIfNeeded()
        let resolvedPreset = preset ?? RecordingPausePreset.allCases.first { $0.interval == interval }
        recordingController.pause(for: interval, preset: resolvedPreset)
        showStatus(pauseStatusMessage(for: interval))
    }

    func pauseUntilEndOfToday() {
        closeHistoryWindowIfNeeded()
        recordingController.pauseUntilEndOfToday()
        showStatus(L("已暂停到今日结束"))
    }

    func ignoreSourceApp(for item: ClipboardItem) {
        guard !item.isFromClipEase else {
            return
        }

        ignoredAppSettings.add(
            bundleID: item.sourceBundleID,
            name: item.sourceAppName
        )
    }

    func isSourceAppIgnored(for item: ClipboardItem) -> Bool {
        guard !item.isFromClipEase else {
            return false
        }

        return ignoredAppSettings.contains(bundleID: item.sourceBundleID)
    }

    func unignoreSourceApp(for item: ClipboardItem) {
        guard !item.isFromClipEase,
              let bundleID = item.sourceBundleID else {
            return
        }

        ignoredAppSettings.remove(bundleID: bundleID)
    }

    func addDebugTextItems(count: Int) {
        historyStore.addDebugTextItems(count: count)
    }

    var debugTextItemCount: Int {
        historyStore.debugTextItemCount
    }

    func clearDebugTextItems() -> Int {
        historyStore.clearDebugTextItems()
    }

    func showAbout() {
        closeHistoryWindowIfNeeded()
        let alert = NSAlert()
        alert.messageText = L("关于轻贴")
        alert.informativeText = "ClipEase\n\(L("简洁好用的 macOS 粘贴板历史助手"))\n\(L("版本")) \(AppVersionInfo.displayVersion)"
        alert.icon = ClipEaseAppIcon.roundedImage(ClipEaseAppIcon.image(size: NSSize(width: 64, height: 64)), size: NSSize(width: 64, height: 64))
        alert.addButton(withTitle: L("好的"))
        alert.runModal()
    }

    func quit() {
        NSApplication.shared.terminate(nil)
    }

    func makeStatusBarMenu() -> NSMenu {
        closeHistoryWindowIfNeeded()
        let menu = NSMenu()
        menu.addItem(makeItem(HistoryCommand.newText.title, action: #selector(newTextAction)))
        menu.addItem(.separator())
        menu.addItem(makeItem(HistoryCommand.help.title, action: #selector(helpAction)))
        menu.addItem(makeItem(HistoryCommand.settings.title, action: #selector(settingsAction), shortcut: HistoryCommand.settings.shortcut))
        menu.addItem(.separator())

        let pauseItem = NSMenuItem(title: L("暂停 轻贴"), action: nil, keyEquivalent: "")
        pauseItem.submenu = makePauseMenu()
        menu.addItem(pauseItem)

        menu.addItem(.separator())
        menu.addItem(makeItem(HistoryCommand.quit.title, action: #selector(quitAction)))
        menu.addItem(makeItem(HistoryCommand.about.title, action: #selector(aboutAction)))
        return menu
    }

    private func makePauseMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(makeItem(recordingController.pauseMenuPrimaryTitle(), action: #selector(togglePauseAction)))
        menu.addItem(pausePresetItem(.fifteenMinutes, action: #selector(pause15MinutesAction)))
        menu.addItem(pausePresetItem(.thirtyMinutes, action: #selector(pause30MinutesAction)))
        menu.addItem(pausePresetItem(.oneHour, action: #selector(pause1HourAction)))
        menu.addItem(pausePresetItem(.threeHours, action: #selector(pause3HoursAction)))
        menu.addItem(pausePresetItem(.sixHours, action: #selector(pause6HoursAction)))
        menu.addItem(pausePresetItem(.untilEndOfToday, action: #selector(pauseUntilTodayAction)))
        return menu
    }

    private func pausePresetItem(_ preset: RecordingPausePreset, action: Selector) -> NSMenuItem {
        let item = makeItem(preset.title, action: action)
        item.state = recordingController.activePausePreset == preset ? .on : .off
        return item
    }

    private func makeItem(_ title: String, action: Selector, shortcut: ShortcutDescriptor? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: shortcut?.keyEquivalent ?? "")
        if let shortcut {
            item.keyEquivalentModifierMask = shortcut.modifierMask
        }
        item.target = self
        return item
    }

    private func showStatus(_ text: String) {
        GlobalStatusToastController.shared.show(text, relativeTo: statusToastAnchorWindow ?? NSApp.keyWindow)
    }

    private func pauseStatusMessage(for interval: TimeInterval) -> String {
        switch Int(interval) {
        case 15 * 60:
            L("已暂停 15 分钟")
        case 30 * 60:
            L("已暂停 30 分钟")
        case 60 * 60:
            L("已暂停 1 小时")
        case 3 * 60 * 60:
            L("已暂停 3 小时")
        case 6 * 60 * 60:
            L("已暂停 6 小时")
        default:
            L("已暂停记录")
        }
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
        pauseRecording(for: 15 * 60, preset: .fifteenMinutes)
    }

    @objc private func pause30MinutesAction() {
        pauseRecording(for: 30 * 60, preset: .thirtyMinutes)
    }

    @objc private func pause1HourAction() {
        pauseRecording(for: 60 * 60, preset: .oneHour)
    }

    @objc private func pause3HoursAction() {
        pauseRecording(for: 3 * 60 * 60, preset: .threeHours)
    }

    @objc private func pause6HoursAction() {
        pauseRecording(for: 6 * 60 * 60, preset: .sixHours)
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
