import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    private var historyWindowController: HistoryWindowController?
    private var clipboardMonitor: ClipboardMonitor?
    private let historyStore = ClipboardHistoryStore()
    private lazy var pasteExecutor = PasteExecutor(store: historyStore)

    func applicationDidFinishLaunching(_ notification: Notification) {
        let historyWindowController = HistoryWindowController(
            store: historyStore,
            pasteExecutor: pasteExecutor
        )
        self.historyWindowController = historyWindowController
        self.statusBarController = StatusBarController(
            historyWindowController: historyWindowController
        )
        let clipboardMonitor = ClipboardMonitor(store: historyStore)
        self.clipboardMonitor = clipboardMonitor
        clipboardMonitor.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        clipboardMonitor?.stop()
    }
}
