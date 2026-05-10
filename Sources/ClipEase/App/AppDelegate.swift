import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    private var historyWindowController: HistoryWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let historyWindowController = HistoryWindowController()
        self.historyWindowController = historyWindowController
        self.statusBarController = StatusBarController(
            historyWindowController: historyWindowController
        )
    }

    func applicationWillTerminate(_ notification: Notification) {}
}
