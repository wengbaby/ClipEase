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
    private let pasteExecutor: PasteExecutor
    private var window: NSWindow?

    init(
        store: ClipboardHistoryStore,
        recordingController: RecordingController,
        loginItemController: LoginItemController,
        ignoredAppSettings: IgnoredAppSettings,
        globalShortcutSettings: GlobalShortcutSettings,
        pasteExecutor: PasteExecutor
    ) {
        self.store = store
        self.recordingController = recordingController
        self.loginItemController = loginItemController
        self.ignoredAppSettings = ignoredAppSettings
        self.globalShortcutSettings = globalShortcutSettings
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
            window?.performClose(nil)
        }
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
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
