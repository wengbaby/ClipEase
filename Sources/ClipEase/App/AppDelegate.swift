import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    private var historyWindowController: HistoryWindowController?
    private var clipboardMonitor: ClipboardMonitor?
    private var appMenuController: AppMenuController?
    private let historyStore = ClipboardHistoryStore()
    private let recordingController = RecordingController()
    private lazy var pasteExecutor = PasteExecutor(store: historyStore)

    func applicationDidFinishLaunching(_ notification: Notification) {
        let appMenuController = AppMenuController(
            historyStore: historyStore,
            recordingController: recordingController
        )
        self.appMenuController = appMenuController
        let historyWindowController = HistoryWindowController(
            store: historyStore,
            pasteExecutor: pasteExecutor,
            recordingController: recordingController,
            appMenuController: appMenuController
        )
        self.historyWindowController = historyWindowController
        self.statusBarController = StatusBarController(
            historyWindowController: historyWindowController,
            appMenuController: appMenuController
        )
        let clipboardMonitor = ClipboardMonitor(
            store: historyStore,
            recordingController: recordingController
        )
        self.clipboardMonitor = clipboardMonitor
        clipboardMonitor.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        clipboardMonitor?.stop()
    }
}
