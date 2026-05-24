import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let defaultWindowSize = NSSize(width: 880, height: 640)
    private let minimumWindowSize = NSSize(width: 820, height: 560)
    private let store: ClipboardHistoryStore
    private let recordingController: RecordingController
    private let loginItemController: LoginItemController
    private let ignoredAppSettings: IgnoredAppSettings
    private let globalShortcutSettings: GlobalShortcutSettings
    private let accessibilityPermissionState: AccessibilityPermissionState
    private let pasteExecutor: PasteExecutor
    private var window: SettingsWindow?

    init(
        store: ClipboardHistoryStore,
        recordingController: RecordingController,
        loginItemController: LoginItemController,
        ignoredAppSettings: IgnoredAppSettings,
        globalShortcutSettings: GlobalShortcutSettings,
        accessibilityPermissionState: AccessibilityPermissionState,
        pasteExecutor: PasteExecutor
    ) {
        self.store = store
        self.recordingController = recordingController
        self.loginItemController = loginItemController
        self.ignoredAppSettings = ignoredAppSettings
        self.globalShortcutSettings = globalShortcutSettings
        self.accessibilityPermissionState = accessibilityPermissionState
        self.pasteExecutor = pasteExecutor
        super.init()
    }

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView(
            store: store,
            recordingController: recordingController,
            loginItemController: loginItemController,
            ignoredAppSettings: ignoredAppSettings,
            globalShortcutSettings: globalShortcutSettings,
            accessibilityPermissionState: accessibilityPermissionState,
            pasteExecutor: pasteExecutor
        )
        let window = SettingsWindow(
            contentRect: NSRect(origin: .zero, size: defaultWindowSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "轻贴设置"
        window.minSize = minimumWindowSize
        window.contentView = NSHostingView(rootView: settingsView)
        window.center()
        window.delegate = self
        window.onCommandW = { [weak window] in
            GroupColorPanelController.shared.close()
            GroupColorPanelController.closeSharedColorPanel()
            window?.orderOut(nil)
        }
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        GroupColorPanelController.shared.close()
        GroupColorPanelController.closeSharedColorPanel()
        sender.orderOut(nil)
        return false
    }
}

private final class SettingsWindow: NSWindow {
    var onCommandW: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers?.lowercased() == "w" {
            onCommandW?()
            return
        }

        super.keyDown(with: event)
    }
}
