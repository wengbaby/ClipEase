import SwiftUI
import AppKit

struct SearchInteractionScreenFrameReader: NSViewRepresentable {
    let isActive: Bool
    let onFrameChange: (CGRect?) -> Void

    func makeNSView(context: Context) -> ReadingView {
        let view = ReadingView()
        view.onFrameChange = onFrameChange
        view.isActive = isActive
        return view
    }

    func updateNSView(_ nsView: ReadingView, context: Context) {
        nsView.onFrameChange = onFrameChange
        nsView.isActive = isActive
        DispatchQueue.main.async {
            nsView.reportFrame()
        }
    }

    final class ReadingView: NSView {
        var onFrameChange: ((CGRect?) -> Void)?
        var isActive = false {
            didSet {
                reportFrame()
            }
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            reportFrame()
        }

        override func setFrameSize(_ newSize: NSSize) {
            super.setFrameSize(newSize)
            reportFrame()
        }

        override func setFrameOrigin(_ newOrigin: NSPoint) {
            super.setFrameOrigin(newOrigin)
            reportFrame()
        }

        func reportFrame() {
            guard isActive,
                  let window else {
                onFrameChange?(nil)
                return
            }

            let rectInWindow = convert(bounds, to: nil)
            let origin = window.convertPoint(toScreen: rectInWindow.origin)
            onFrameChange?(CGRect(origin: origin, size: rectInWindow.size))
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }
    }
}
