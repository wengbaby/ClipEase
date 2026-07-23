import AppKit
import SwiftUI

@MainActor
final class HelpWindowController: NSObject, NSWindowDelegate {
    private var window: HelpWindow?

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = HelpWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 660),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "轻贴帮助"
        window.contentView = NSHostingView(rootView: HelpView())
        window.center()
        window.delegate = self
        window.onCommandW = { [weak window] in
            window?.orderOut(nil)
        }
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }
}

private final class HelpWindow: NSWindow {
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
