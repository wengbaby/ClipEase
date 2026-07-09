import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    private var historyWindowController: HistoryWindowController?
    private var clipboardMonitor: ClipboardMonitor?
    private var appMenuController: AppMenuController?
    private var globalHotKeyController: GlobalHotKeyController?
    private var historyStore: ClipboardHistoryStore?
    private let recordingController = RecordingController()
    private let loginItemController = LoginItemController()
    private let ignoredAppSettings = IgnoredAppSettings()
    private let globalShortcutSettings = GlobalShortcutSettings()
    private let accessibilityPermissionState = AccessibilityPermissionState()
    private lazy var pasteExecutor = PasteExecutor(
        store: requireHistoryStore(),
        permissionState: accessibilityPermissionState
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.applicationIconImage = ClipEaseAppIcon.image(size: NSSize(width: 512, height: 512))
        PerformanceDiagnosticsService.shared.startSession(reason: "app.launch")

        let historyStore = ClipboardHistoryStore()
        self.historyStore = historyStore

        let appMenuController = AppMenuController(
            historyStore: historyStore,
            recordingController: recordingController,
            loginItemController: loginItemController,
            ignoredAppSettings: ignoredAppSettings,
            globalShortcutSettings: globalShortcutSettings,
            accessibilityPermissionState: accessibilityPermissionState,
            pasteExecutor: pasteExecutor
        )
        self.appMenuController = appMenuController
        let historyWindowController = HistoryWindowController(
            store: historyStore,
            pasteExecutor: pasteExecutor,
            accessibilityPermissionState: accessibilityPermissionState,
            recordingController: recordingController,
            appMenuController: appMenuController
        )
        self.historyWindowController = historyWindowController
        appMenuController.attachHistoryWindowController(historyWindowController)
        pasteExecutor.beforeAutoPaste = { [weak historyWindowController] in
            historyWindowController?.hideImmediatelyForAutoPaste()
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
        ClipEaseSoundPlayer.shared.preloadFeedbackSounds()
        let clipboardMonitor = ClipboardMonitor(
            store: historyStore,
            recordingController: recordingController,
            ignoredAppSettings: ignoredAppSettings
        )
        self.clipboardMonitor = clipboardMonitor
        clipboardMonitor.shouldSuppressRecording = { [weak historyWindowController] in
            historyWindowController?.isPreviewInteractionActive == true
        }
        clipboardMonitor.start()
        Task { @MainActor in
            let delay = HistoryWindowLifecycleScheduler.launchPreloadDelayNanoseconds
            if delay > 0 {
                try? await Task.sleep(nanoseconds: delay)
            } else {
                await Task.yield()
            }
            historyWindowController.preloadHistoryDataAfterLaunch()
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: HistoryWindowLifecycleScheduler.launchAccessibilityPromptDelayNanoseconds)
            if !accessibilityPermissionState.refresh() {
                appMenuController.showPermissionGuide()
            }
        }

        if CommandLine.arguments.contains("--show-settings") {
            appMenuController.showSettings()
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        accessibilityPermissionState.refresh()
    }

    func applicationWillTerminate(_ notification: Notification) {
        historyStore?.flushPendingSave()
        globalHotKeyController?.stop()
        clipboardMonitor?.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func requireHistoryStore() -> ClipboardHistoryStore {
        guard let historyStore else {
            fatalError("ClipboardHistoryStore is not initialized")
        }

        return historyStore
    }
}
