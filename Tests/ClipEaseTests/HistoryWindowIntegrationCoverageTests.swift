import AppKit
import Foundation
import Testing
@testable import ClipEase

@MainActor
@Test func historyWindowRendersSearchesAndReopensWithOnePresentationPlan() async throws {
    let suiteName = "HistoryWindowIntegrationCoverageTests-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let store = ClipboardHistoryStore(
        persistence: ClipboardHistoryPersistence(
            repository: ClipboardPayloadStagingEmptyRepository()
        ),
        userDefaults: defaults
    )
    store.addText("侧悬浮窗口、迷你窗口、主窗口", sourceApp: .clipease)
    store.addText("ordinary clipboard value", sourceApp: .clipease)

    let permission = AccessibilityPermissionState { _ in true }
    let recording = RecordingController(userDefaults: defaults)
    let pasteExecutor = PasteExecutor(
        store: store,
        permissionState: permission,
        pasteboard: NSPasteboard(name: .init("HistoryWindowIntegration-\(UUID().uuidString)"))
    )
    let shortcutSettings = GlobalShortcutSettings(userDefaults: defaults)
    let menu = AppMenuController(
        historyStore: store,
        recordingController: recording,
        loginItemController: LoginItemController(),
        ignoredAppSettings: IgnoredAppSettings(userDefaults: defaults),
        globalShortcutSettings: shortcutSettings,
        accessibilityPermissionState: permission,
        pasteExecutor: pasteExecutor
    )
    let inputState = HistoryWindowInputState()
    let controller = HistoryWindowController(
        store: store,
        pasteExecutor: pasteExecutor,
        accessibilityPermissionState: permission,
        recordingController: recording,
        appMenuController: menu,
        inputState: inputState,
        keyboardEventTapBackend: HistoryWindowIntegrationKeyboardBackend(),
        setOCRInteractiveThrottleActive: { _ in },
        appearanceSettings: AppearanceSettings(userDefaults: defaults)
    )

    controller.show(accessibilityAlreadyVerified: true)
    try await Task.sleep(nanoseconds: 300_000_000)
    inputState.dispatch(.openSearch)
    inputState.dispatch(.appendSearchText("窗口"))
    try await Task.sleep(nanoseconds: 350_000_000)
    inputState.dispatch(.close)
    try await Task.sleep(nanoseconds: 300_000_000)
    controller.show(accessibilityAlreadyVerified: true)
    try await Task.sleep(nanoseconds: 300_000_000)
    controller.hideImmediatelyForAutoPaste()
    controller.shutdown()

    #expect(inputState.presentationRequest?.plan.selectedID != nil)
}

private final class HistoryWindowIntegrationKeyboardBackend: HistoryKeyboardEventTapBackend {
    func createTap(
        eventMask: CGEventMask,
        callback: CGEventTapCallBack,
        userInfo: UnsafeMutableRawPointer?
    ) -> HistoryKeyboardEventTapHandle? {
        nil
    }

    func createRunLoopSource(
        for tap: HistoryKeyboardEventTapHandle
    ) -> HistoryKeyboardEventTapRunLoopSource? {
        nil
    }

    func addRunLoopSource(_ source: HistoryKeyboardEventTapRunLoopSource) {}
    func removeRunLoopSource(_ source: HistoryKeyboardEventTapRunLoopSource) {}
    func setEnabled(_ enabled: Bool, for tap: HistoryKeyboardEventTapHandle) {}
    func invalidate(_ tap: HistoryKeyboardEventTapHandle) {}
}
