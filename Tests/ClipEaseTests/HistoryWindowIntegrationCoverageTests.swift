import AppKit
import Foundation
import SwiftUI
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
    try await Task.sleep(nanoseconds: 80_000_000)
    inputState.dispatch(.close)
    try await Task.sleep(nanoseconds: 80_000_000)
    store.addText("visible insert", sourceApp: .clipease)
    try await Task.sleep(nanoseconds: 350_000_000)
    let countBeforeDelete = store.items.count
    inputState.dispatch(.delete)
    try await Task.sleep(nanoseconds: 200_000_000)
    #expect(store.items.count == countBeforeDelete - 1)
    inputState.dispatch(.close)
    try await Task.sleep(nanoseconds: 300_000_000)
    controller.show(accessibilityAlreadyVerified: true)
    try await Task.sleep(nanoseconds: 300_000_000)
    controller.hideImmediatelyForAutoPaste()
    controller.shutdown()

    #expect(inputState.presentationRequest?.plan.selectedID != nil)
}

@MainActor
@Test func previewPopoverLaysOutBodyAndMatchingArrowSurface() {
    let item = ClipboardItem.text("preview surface", sourceApp: .clipease)
    let writer = ClipboardWriteCoordinator(
        pasteboard: NSPasteboard(name: .init("PreviewSurface-\(UUID().uuidString)"))
    )
    let view = HistoryPreviewPopoverView(
        item: item,
        ocrResult: nil,
        arrowX: 120,
        size: CGSize(width: 390, height: 260),
        showsArrow: true,
        isContentReady: true,
        onClose: {},
        onCopy: {},
        onOpen: {},
        onReveal: {},
        onCopyURL: {},
        onCopyMarkdown: {},
        onCopyPath: {},
        onCopyRGB: {},
        onDetachDrag: { nil },
        clipboardWriter: writer
    )
    let hostingView = NSHostingView(rootView: view)
    hostingView.frame = CGRect(x: 0, y: 0, width: 390, height: 274)
    hostingView.layoutSubtreeIfNeeded()

    #expect(hostingView.fittingSize.width > 0)
    #expect(hostingView.fittingSize.height > 0)
}

@MainActor
@Test func historyWindowCommandsRemoveGroupMembershipAndDeleteSelectedItem() {
    let suiteName = "HistoryWindowCommandCoverageTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let store = ClipboardHistoryStore(
        persistence: ClipboardHistoryPersistence(repository: ClipboardPayloadStagingEmptyRepository()),
        userDefaults: defaults
    )
    store.addText("grouped", sourceApp: .clipease)
    store.addText("delete me", sourceApp: .clipease)
    let grouped = store.items.first { $0.text == "grouped" }!
    let deletable = store.items.first { $0.text == "delete me" }!
    let group = store.createGroup()
    store.addItem(grouped.id, toGroup: group.id)

    let permission = AccessibilityPermissionState { _ in true }
    let recording = RecordingController(userDefaults: defaults)
    let pasteExecutor = PasteExecutor(
        store: store,
        permissionState: permission,
        pasteboard: NSPasteboard(name: .init("HistoryCommands-\(UUID().uuidString)"))
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
    let inputState = HistoryWindowInputState()
    let view = HistoryWindowView(
        store: store,
        previewState: HistoryPreviewState(),
        renderState: HistoryWindowRenderState(),
        inputState: inputState,
        recordingController: recording,
        accessibilityPermissionState: permission,
        appMenuController: menu,
        pasteExecutor: pasteExecutor,
        onClose: {},
        onPreview: { _, _ in },
        onMovePreview: { _ in },
        onClosePreview: {},
        onCreateText: { _ in }
    )

    view.selectedItemID = grouped.id
    view.removeItemFromGroup(grouped.id)
    #expect(store.item(with: grouped.id)?.groupID == nil)

    view.selectedItemID = deletable.id
    view.deleteItem(deletable.id)
    #expect(store.item(with: deletable.id) == nil)

    view.copyItem(nil)
    view.copyPlainTextItem(nil)
    view.pastePlainTextItem(nil)
    view.copyMarkdownLink(nil)
    view.copyLinkURL(nil)
    view.openLink(nil)
    view.copyColorHex(nil)
    view.copyColorRGB(nil)
    view.pasteItem(nil)
    view.showPreview(nil)
    view.beginEditItem(nil)
    view.removeItemFromGroup(nil)
    view.togglePinned(nil)
    view.toggleSourceAppIgnored(nil)
    view.copySourceAppName(nil)
    view.copySourceBundleID(nil)
    view.revealImageInFinder(nil)
    view.openImage(nil)
    view.copyImage(nil)
    view.copyImagePath(nil)
    view.copyFilePaths(nil)
    view.copyFile(nil)
    view.openFile(nil)
    view.revealFilesInFinder(nil)
}

@MainActor
@Test func historyWindowRendersFilterTokenRail() {
    var criteria = HistorySearchCriteria()
    criteria.types.insert(.text)
    let tokens = HistorySearchToken.tokens(criteria: criteria, groups: [])
    let rail = HistorySearchTokenRail(
        tokens: tokens,
        selectedTokenKind: .type(.text),
        isEnabled: false
    ) { token in
        Text(token.title).frame(height: 24)
    }
    let hostingView = NSHostingView(rootView: rail)
    hostingView.frame = CGRect(x: 0, y: 0, width: 320, height: 34)
    hostingView.layoutSubtreeIfNeeded()

    #expect(hostingView.fittingSize.width > 0)
    #expect(hostingView.fittingSize.height >= 34)
}

@MainActor
@Test func historyWindowTokenRailTracksInsertedAndSelectedTokens() async throws {
    let state = HistorySearchTokenRailTestState()
    let hostingView = NSHostingView(rootView: HistorySearchTokenRailTestView(state: state))
    hostingView.frame = CGRect(x: 0, y: 0, width: 180, height: 34)
    hostingView.layoutSubtreeIfNeeded()

    var criteria = HistorySearchCriteria()
    criteria.types.insert(.text)
    criteria.dateRanges.insert(.today)
    let tokens = HistorySearchToken.tokens(criteria: criteria, groups: [])
    state.tokens = tokens
    try await Task.sleep(nanoseconds: 30_000_000)

    state.selectedTokenKind = .date(.today)
    try await Task.sleep(nanoseconds: 30_000_000)
    hostingView.layoutSubtreeIfNeeded()

    #expect(state.tokens.count == 2)
    #expect(state.selectedTokenKind == .date(.today))
    #expect(hostingView.fittingSize.width > 0)
}

@MainActor
private final class HistorySearchTokenRailTestState: ObservableObject {
    @Published var tokens: [HistorySearchToken] = []
    @Published var selectedTokenKind: HistorySearchTokenKind?
}

private struct HistorySearchTokenRailTestView: View {
    @ObservedObject var state: HistorySearchTokenRailTestState

    var body: some View {
        HistorySearchTokenRail(
            tokens: state.tokens,
            selectedTokenKind: state.selectedTokenKind,
            isEnabled: false
        ) { token in
            Text(token.title).frame(height: 24)
        }
    }
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
