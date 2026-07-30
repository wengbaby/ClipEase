import AppKit
import Darwin
import Foundation
import Testing
@testable import ClipEase

@Test func sqliteCorruptionIsReportedWithoutOverwritingDatabase() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        "ClipEase-Corruption-\(UUID().uuidString)",
        isDirectory: true
    )
    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(at: directory) }
    let databaseURL = directory.appendingPathComponent("history.sqlite3")
    let corruptedBytes = Data("not-a-sqlite-database".utf8)
    try corruptedBytes.write(to: databaseURL, options: .atomic)

    let connection = try SQLiteConnection(url: databaseURL)
    var reportedCorruption = false
    do {
        _ = try connection.query("PRAGMA schema_version")
    } catch let error as SQLiteStoreError {
        reportedCorruption = true
        switch error {
        case .prepareFailed, .executeFailed:
            break
        default:
            Issue.record("Unexpected corruption error: \(error)")
        }
    }
    connection.close()

    #expect(reportedCorruption)
    #expect(try Data(contentsOf: databaseURL) == corruptedBytes)
}

@Test func sqliteWALSurvivesSIGKILLDuringUncommittedWrite() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        "ClipEase-SIGKILL-\(UUID().uuidString)",
        isDirectory: true
    )
    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(at: directory) }
    let databaseURL = directory.appendingPathComponent("history.sqlite3")
    let markerURL = directory.appendingPathComponent("transaction-started")

    let setup = try SQLiteConnection(url: databaseURL)
    try setup.execute("PRAGMA journal_mode = WAL")
    try setup.execute(
        "CREATE TABLE durability (id INTEGER PRIMARY KEY, value TEXT NOT NULL)"
    )
    try setup.execute(
        "INSERT INTO durability (id, value) VALUES (?, ?)",
        values: [.int(1), .text("committed")]
    )
    setup.close()

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
    process.arguments = [databaseURL.path]
    let input = Pipe()
    process.standardInput = input
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run()
    let script = """
    BEGIN IMMEDIATE;
    INSERT INTO durability (id, value) VALUES (2, 'must-rollback');
    .shell /usr/bin/touch "\(markerURL.path)"
    .shell /bin/sleep 30
    COMMIT;
    """
    try input.fileHandleForWriting.write(
        contentsOf: Data((script + "\n").utf8)
    )
    try input.fileHandleForWriting.close()

    let deadline = Date().addingTimeInterval(3)
    while !FileManager.default.fileExists(atPath: markerURL.path),
          Date() < deadline {
        Thread.sleep(forTimeInterval: 0.005)
    }
    #expect(FileManager.default.fileExists(atPath: markerURL.path))
    #expect(Darwin.kill(pid_t(process.processIdentifier), SIGKILL) == 0)
    process.waitUntilExit()
    #expect(process.terminationReason == .uncaughtSignal)

    let recovered = try SQLiteConnection(url: databaseURL)
    #expect(try recovered.queryInt("SELECT COUNT(*) FROM durability") == 1)
    let integrityRows = try recovered.query("PRAGMA integrity_check")
    #expect(integrityRows.first?.requiredText("integrity_check") == "ok")
    recovered.close()
}

@MainActor
@Test func historyWindowOneHundredOpenCloseCyclesRemainBoundedAndLeakFree() {
    weak var releasedController: HistoryWindowController?
    weak var releasedPanel: HistoryPanel?
    let probe = HistoryWindowCycleProbe()
    let suiteName = "ClipEase-WindowCycles-\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
        Issue.record("Could not create isolated defaults")
        return
    }
    defer {
        defaults.removePersistentDomain(forName: suiteName)
    }

    autoreleasepool {
        let store = ClipboardHistoryStore(
            persistence: ClipboardHistoryPersistence(
                repository: ClipboardPayloadStagingEmptyRepository()
            )
        )
        let permission = AccessibilityPermissionState { _ in true }
        let recording = RecordingController(userDefaults: defaults)
        let pasteExecutor = PasteExecutor(
            store: store,
            permissionState: permission,
            pasteboard: NSPasteboard(
                name: NSPasteboard.Name(
                    "ClipEase-WindowCycles-\(UUID().uuidString)"
                )
            )
        )
        let menu = AppMenuController(
            historyStore: store,
            recordingController: recording,
            loginItemController: LoginItemController(),
            ignoredAppSettings: IgnoredAppSettings(userDefaults: defaults),
            globalShortcutSettings: GlobalShortcutSettings(userDefaults: defaults),
            accessibilityPermissionState: permission,
            pasteExecutor: pasteExecutor
        )
        let controller = HistoryWindowController(
            store: store,
            pasteExecutor: pasteExecutor,
            accessibilityPermissionState: permission,
            recordingController: recording,
            appMenuController: menu,
            keyboardEventTapBackend: HistoryWindowCycleKeyboardBackend(),
            eventMonitorBackend: probe,
            panelFactory: {
                let panel = HistoryPanel(
                    contentRect: NSRect(x: 0, y: 0, width: 600, height: 280),
                    styleMask: [.borderless, .nonactivatingPanel],
                    backing: .buffered,
                    defer: false
                )
                panel.animationBehavior = .none
                probe.recordPanel(panel)
                return panel
            },
            openAnimationCompletionDriver: probe,
            setOCRInteractiveThrottleActive: { _ in },
            appearanceSettings: AppearanceSettings(userDefaults: defaults)
        )
        releasedController = controller
        for _ in 0..<100 {
            controller.show(accessibilityAlreadyVerified: true)
            controller.hideImmediatelyForAutoPaste()
        }
        controller.shutdown()
        releasedPanel = probe.panel
        #expect(probe.panelCreationCount == 1)
        #expect(probe.activeEventMonitorCount == 0)
    }

    RunLoop.current.run(until: Date().addingTimeInterval(0.01))
    #expect(releasedController == nil)
    #expect(releasedPanel == nil)
}

@MainActor
private final class HistoryWindowCycleProbe:
    HistoryWindowEventMonitorBackend,
    HistoryWindowOpenAnimationCompletionDriver
{
    private(set) weak var panel: HistoryPanel?
    private(set) var panelCreationCount = 0
    private var activeMonitors: Set<ObjectIdentifier> = []

    var activeEventMonitorCount: Int {
        activeMonitors.count
    }

    func recordPanel(_ panel: HistoryPanel) {
        self.panel = panel
        panelCreationCount += 1
    }

    func addGlobalMonitor(
        matching mask: NSEvent.EventTypeMask,
        handler: @escaping (NSEvent) -> Void
    ) -> Any? {
        _ = mask
        _ = handler
        return makeMonitor()
    }

    func addLocalMonitor(
        matching mask: NSEvent.EventTypeMask,
        handler: @escaping (NSEvent) -> NSEvent?
    ) -> Any? {
        _ = mask
        _ = handler
        return makeMonitor()
    }

    func removeMonitor(_ monitor: Any) {
        guard let token = monitor as? NSObject else {
            return
        }
        activeMonitors.remove(ObjectIdentifier(token))
    }

    func scheduleCompletion(_ completion: @escaping @MainActor () -> Void) {
        completion()
    }

    private func makeMonitor() -> NSObject {
        let token = NSObject()
        activeMonitors.insert(ObjectIdentifier(token))
        return token
    }
}

private final class HistoryWindowCycleKeyboardBackend:
    HistoryKeyboardEventTapBackend,
    @unchecked Sendable
{
    func createTap(
        eventMask: CGEventMask,
        callback: CGEventTapCallBack,
        userInfo: UnsafeMutableRawPointer?
    ) -> HistoryKeyboardEventTapHandle? {
        _ = eventMask
        _ = callback
        _ = userInfo
        return HistoryKeyboardEventTapHandle()
    }

    func createRunLoopSource(
        for tap: HistoryKeyboardEventTapHandle
    ) -> HistoryKeyboardEventTapRunLoopSource? {
        _ = tap
        return HistoryKeyboardEventTapRunLoopSource()
    }

    func addRunLoopSource(_ source: HistoryKeyboardEventTapRunLoopSource) {
        _ = source
    }

    func removeRunLoopSource(_ source: HistoryKeyboardEventTapRunLoopSource) {
        _ = source
    }

    func setEnabled(_ enabled: Bool, for tap: HistoryKeyboardEventTapHandle) {
        _ = enabled
        _ = tap
    }

    func invalidate(_ tap: HistoryKeyboardEventTapHandle) {
        _ = tap
    }
}
