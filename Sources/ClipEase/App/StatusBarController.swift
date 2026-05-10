import AppKit

@MainActor
final class StatusBarController: NSObject {
    private let statusItem: NSStatusItem
    private let historyWindowController: HistoryWindowController
    private let appMenuController: AppMenuController

    init(
        historyWindowController: HistoryWindowController,
        appMenuController: AppMenuController
    ) {
        self.historyWindowController = historyWindowController
        self.appMenuController = appMenuController
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        configureStatusItem()
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else {
            return
        }

        button.image = NSImage(
            systemSymbolName: "doc.on.clipboard",
            accessibilityDescription: "轻贴"
        )
        button.image?.isTemplate = true
        button.toolTip = "轻贴 ClipEase"
        button.target = self
        button.action = #selector(toggleHistoryWindow)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @objc private func toggleHistoryWindow() {
        guard let event = NSApp.currentEvent,
              event.type == .rightMouseUp,
              let button = statusItem.button else {
            historyWindowController.toggle()
            return
        }

        statusItem.menu = appMenuController.makeStatusBarMenu()
        button.performClick(nil)
        statusItem.menu = nil
    }
}
