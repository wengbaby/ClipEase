import AppKit

enum ApplicationTerminationDrainComponent: Hashable, Sendable {
    case payload
    case history
    case diagnostics
}

enum ApplicationTerminationDrainOutcome: Equatable, Sendable {
    case completed
    case timedOut
}

enum ApplicationTerminationPolicy {
    static let totalBudgetNanoseconds: UInt64 = 300_000_000
    static let coordinatorTimeoutNanoseconds: UInt64 = 250_000_000
    static let diagnosticsTimeoutNanoseconds: UInt64 = 225_000_000
}

struct ApplicationTerminationDrainReport: Equatable, Sendable {
    let outcome: ApplicationTerminationDrainOutcome
    let pendingComponents: Set<ApplicationTerminationDrainComponent>
    let historyDrainResult: ClipboardHistoryWriteDrainResult?
    let diagnosticsDroppedEventCount: Int
    let elapsedMS: Double
}

enum ApplicationTerminationDrainCoordinator {
    static func drain(
        timeoutNanoseconds: UInt64,
        payloadDrain: @escaping @Sendable () async -> Void,
        historyDrain: @escaping @Sendable () async -> ClipboardHistoryWriteDrainResult,
        diagnosticsDrain: @escaping @Sendable () async -> PerformanceDiagnosticsShutdownDrainResult
    ) async -> ApplicationTerminationDrainReport {
        let startedAt = CFAbsoluteTimeGetCurrent()
        let state = ApplicationTerminationDrainState()
        let deadlineOutcome = await PerformanceDiagnosticsDrainDeadline.run(
            timeoutNanoseconds: timeoutNanoseconds
        ) {
            async let diagnosticsResult: Void = {
                let result = await diagnosticsDrain()
                await state.completeDiagnostics(result)
            }()

            await payloadDrain()
            guard !Task.isCancelled else {
                return
            }
            await state.completePayload()

            let historyResult = await historyDrain()
            guard !Task.isCancelled else {
                return
            }
            await state.completeHistory(historyResult)

            _ = await diagnosticsResult
        }
        let snapshot = await state.snapshot()
        let outcome: ApplicationTerminationDrainOutcome
        switch deadlineOutcome {
        case .completed:
            outcome = snapshot.pendingComponents.isEmpty ? .completed : .timedOut
        case .timedOut:
            outcome = .timedOut
        }
        return ApplicationTerminationDrainReport(
            outcome: outcome,
            pendingComponents: snapshot.pendingComponents,
            historyDrainResult: snapshot.historyDrainResult,
            diagnosticsDroppedEventCount: snapshot.diagnosticsDroppedEventCount,
            elapsedMS: (CFAbsoluteTimeGetCurrent() - startedAt) * 1_000
        )
    }
}

private actor ApplicationTerminationDrainState {
    private var completedComponents = Set<ApplicationTerminationDrainComponent>()
    private var historyDrainResult: ClipboardHistoryWriteDrainResult?
    private var diagnosticsDroppedEventCount = 0

    func completePayload() {
        completedComponents.insert(.payload)
    }

    func completeHistory(_ result: ClipboardHistoryWriteDrainResult) {
        historyDrainResult = result
        completedComponents.insert(.history)
    }

    func completeDiagnostics(_ result: PerformanceDiagnosticsShutdownDrainResult) {
        diagnosticsDroppedEventCount = result.droppedEventCount
        if result.outcome != .timedOut {
            completedComponents.insert(.diagnostics)
        }
    }

    func snapshot() -> (
        pendingComponents: Set<ApplicationTerminationDrainComponent>,
        historyDrainResult: ClipboardHistoryWriteDrainResult?,
        diagnosticsDroppedEventCount: Int
    ) {
        (
            Set(ApplicationTerminationDrainComponent.allCases)
                .subtracting(completedComponents),
            historyDrainResult,
            diagnosticsDroppedEventCount
        )
    }
}

private extension ApplicationTerminationDrainComponent {
    static var allCases: [ApplicationTerminationDrainComponent] {
        [.payload, .history, .diagnostics]
    }
}

enum ApplicationTerminationRequestDecision: Equatable, Sendable {
    case startDrain
    case waitForDrain
    case terminateNow
}

struct ApplicationTerminationRequestState: Sendable {
    private enum Phase: Equatable, Sendable {
        case running
        case draining
        case replyIssued
    }

    private var phase = Phase.running

    mutating func request() -> ApplicationTerminationRequestDecision {
        switch phase {
        case .running:
            phase = .draining
            return .startDrain
        case .draining:
            return .waitForDrain
        case .replyIssued:
            return .terminateNow
        }
    }

    mutating func markReplyIssued() -> Bool {
        guard phase == .draining else {
            return false
        }
        phase = .replyIssued
        return true
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    private var historyWindowController: HistoryWindowController?
    private var clipboardMonitor: ClipboardMonitor?
    private var appMenuController: AppMenuController?
    private var globalHotKeyController: GlobalHotKeyController?
    private var historyStore: ClipboardHistoryStore?
    private var terminationRequestState = ApplicationTerminationRequestState()
    private var terminationTask: Task<Void, Never>?
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
        let startupTrace = HistoryPerformanceTrace(kind: .startup)
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
        startupTrace.mark("listeners-ready")
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
        startupTrace.finish()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        accessibilityPermissionState.refresh()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        switch terminationRequestState.request() {
        case .startDrain:
            beginTerminationDrain(sender: sender)
            return .terminateLater
        case .waitForDrain:
            return .terminateLater
        case .terminateNow:
            return .terminateNow
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        globalHotKeyController?.stop()
        clipboardMonitor?.stop()
        historyWindowController?.shutdown()
        PerformanceDiagnosticsService.shared.shutdown()
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

    private func beginTerminationDrain(sender: NSApplication) {
        globalHotKeyController?.stop()
        historyWindowController?.shutdown()

        let payloadDrain: @Sendable () async -> Void
        if let clipboardMonitor {
            payloadDrain = {
                await clipboardMonitor.stopAndDrainPayloads()
            }
        } else {
            payloadDrain = {}
        }

        let historyDrain: @Sendable () async -> ClipboardHistoryWriteDrainResult
        if let historyStore {
            let handle = historyStore.makeTerminationDrainHandle()
            historyDrain = {
                await handle.drain()
            }
        } else {
            historyDrain = {
                .empty
            }
        }

        let exitTrace = HistoryPerformanceTrace(kind: .exitDrain)
        terminationTask = Task { @MainActor in
            let report = await ApplicationTerminationDrainCoordinator.drain(
                timeoutNanoseconds: ApplicationTerminationPolicy.coordinatorTimeoutNanoseconds,
                payloadDrain: payloadDrain,
                historyDrain: historyDrain,
                diagnosticsDrain: {
                    await PerformanceDiagnosticsService.shared.drainForShutdown(
                        timeoutNanoseconds: ApplicationTerminationPolicy.diagnosticsTimeoutNanoseconds
                    )
                }
            )
            let requiresFullResync = report.historyDrainResult?.requiresFullResync == true
            let didFail = report.outcome == .timedOut || requiresFullResync
            exitTrace.mark(didFail ? "drain-timeout" : "drain-complete")
            exitTrace.finish()
            PerformanceDiagnosticsSignposter.emitEvent(
                name: "application.termination.drain",
                category: "termination",
                isError: didFail
            )
            if didFail {
                NSLog(
                    "ClipEase termination drain incomplete; pending=%d dropped=%d fullResync=%d",
                    report.pendingComponents.count,
                    report.diagnosticsDroppedEventCount,
                    requiresFullResync ? 1 : 0
                )
            }

            PerformanceDiagnosticsService.shared.shutdown()
            let shouldReply = terminationRequestState.markReplyIssued()
            terminationTask = nil
            guard shouldReply else {
                return
            }
            sender.reply(toApplicationShouldTerminate: true)
        }
    }
}
