import AppKit
import Combine

@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let historyWindowController: HistoryWindowController
    private let appMenuController: AppMenuController
    private let recordingController: RecordingController
    private var recordingCancellable: AnyCancellable?
    private var liveMenu: NSMenu?
    private var countdownTimer: Timer?

    init(
        historyWindowController: HistoryWindowController,
        appMenuController: AppMenuController,
        recordingController: RecordingController
    ) {
        self.historyWindowController = historyWindowController
        self.appMenuController = appMenuController
        self.recordingController = recordingController
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        configureStatusItem()
        updateStatusItem()
        recordingCancellable = recordingController.$isPaused
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.updateStatusItem()
                }
            }
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else {
            return
        }

        button.target = self
        button.action = #selector(toggleHistoryWindow)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func updateStatusItem() {
        guard let button = statusItem.button else {
            return
        }

        button.image = ClipEaseAppIcon.statusBarImage(isPaused: recordingController.isPaused)
        button.image?.accessibilityDescription = L("轻贴")
        button.toolTip = recordingController.isPaused ? L("轻贴已暂停记录") : "ClipEase"
    }

    @objc private func toggleHistoryWindow() {
        guard let event = NSApp.currentEvent,
              event.type == .rightMouseUp,
              let button = statusItem.button else {
            historyWindowController.toggle()
            return
        }

        let menu = appMenuController.makeStatusBarMenu()
        menu.delegate = self
        liveMenu = menu
        startCountdownTimerIfNeeded()
        statusItem.menu = menu
        button.performClick(nil)
        statusItem.menu = nil
    }

    private func startCountdownTimerIfNeeded() {
        countdownTimer?.invalidate()
        guard recordingController.isPaused else {
            countdownTimer = nil
            return
        }
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshLiveMenuCountdown()
            }
        }
    }

    private func refreshLiveMenuCountdown() {
        guard let liveMenu,
              let firstItem = liveMenu.items.first else {
            return
        }
        let title = recordingController.pauseMenuPrimaryTitle()
        guard firstItem.title != title else {
            return
        }
        firstItem.title = title
    }

    func menuDidClose(_ menu: NSMenu) {
        countdownTimer?.invalidate()
        countdownTimer = nil
        liveMenu = nil
    }
}
