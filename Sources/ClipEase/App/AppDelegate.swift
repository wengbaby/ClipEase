import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    private var historyWindowController: HistoryWindowController?
    private var clipboardMonitor: ClipboardMonitor?
    private var appMenuController: AppMenuController?
    private var globalHotKeyController: GlobalHotKeyController?
    private let historyStore = ClipboardHistoryStore()
    private let recordingController = RecordingController()
    private let loginItemController = LoginItemController()
    private let ignoredAppSettings = IgnoredAppSettings()
    private let globalShortcutSettings = GlobalShortcutSettings()
    private lazy var pasteExecutor = PasteExecutor(store: historyStore)

    func applicationDidFinishLaunching(_ notification: Notification) {
        let appMenuController = AppMenuController(
            historyStore: historyStore,
            recordingController: recordingController,
            loginItemController: loginItemController,
            ignoredAppSettings: ignoredAppSettings,
            globalShortcutSettings: globalShortcutSettings,
            pasteExecutor: pasteExecutor
        )
        self.appMenuController = appMenuController
        let historyWindowController = HistoryWindowController(
            store: historyStore,
            pasteExecutor: pasteExecutor,
            recordingController: recordingController,
            appMenuController: appMenuController
        )
        self.historyWindowController = historyWindowController
        pasteExecutor.beforeAutoPaste = { [weak historyWindowController] in
            historyWindowController?.close()
        }
        self.statusBarController = StatusBarController(
            historyWindowController: historyWindowController,
            appMenuController: appMenuController,
            recordingController: recordingController
        )
        let globalHotKeyController = GlobalHotKeyController(
            historyWindowController: historyWindowController,
            shortcutSettings: globalShortcutSettings
        )
        self.globalHotKeyController = globalHotKeyController
        globalHotKeyController.start()
        let clipboardMonitor = ClipboardMonitor(
            store: historyStore,
            recordingController: recordingController,
            ignoredAppSettings: ignoredAppSettings
        )
        self.clipboardMonitor = clipboardMonitor
        clipboardMonitor.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        globalHotKeyController?.stop()
        clipboardMonitor?.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
