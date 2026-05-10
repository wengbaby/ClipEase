import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let store: ClipboardHistoryStore
    private let recordingController: RecordingController
    private let loginItemController: LoginItemController
    private let pasteExecutor: PasteExecutor
    private var window: NSWindow?

    init(
        store: ClipboardHistoryStore,
        recordingController: RecordingController,
        loginItemController: LoginItemController,
        pasteExecutor: PasteExecutor
    ) {
        self.store = store
        self.recordingController = recordingController
        self.loginItemController = loginItemController
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
            pasteExecutor: pasteExecutor
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 430),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "轻贴设置"
        window.contentView = NSHostingView(rootView: settingsView)
        window.center()
        window.delegate = self
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}
