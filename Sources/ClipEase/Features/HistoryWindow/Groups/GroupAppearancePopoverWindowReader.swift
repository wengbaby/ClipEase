import SwiftUI
import AppKit

struct GroupAppearancePopoverWindowReader: NSViewRepresentable {
    @Binding var window: NSWindow?

    func makeNSView(context: Context) -> WindowReaderView {
        let view = WindowReaderView()
        view.onWindowChange = { newWindow in
            if window !== newWindow {
                window = newWindow
            }
        }
        return view
    }

    func updateNSView(_ nsView: WindowReaderView, context: Context) {
        nsView.onWindowChange = { newWindow in
            if window !== newWindow {
                window = newWindow
            }
        }
        nsView.reportWindowSoon()
    }

    static func dismantleNSView(_ nsView: WindowReaderView, coordinator: ()) {
        nsView.reportWindow(nil)
    }

    final class WindowReaderView: NSView {
        var onWindowChange: ((NSWindow?) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            reportWindowSoon()
        }

        func reportWindowSoon() {
            DispatchQueue.main.async { [weak self] in
                guard let self else {
                    return
                }

                self.reportWindow(self.window)
            }
        }

        func reportWindow(_ window: NSWindow?) {
            DispatchQueue.main.async { [weak self] in
                self?.onWindowChange?(window)
            }
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }
    }
}
