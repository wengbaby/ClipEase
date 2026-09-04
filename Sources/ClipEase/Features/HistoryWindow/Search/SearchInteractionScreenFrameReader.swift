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
        private var lastReportedFrame: CGRect?
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
                if lastReportedFrame != nil {
                    lastReportedFrame = nil
                    onFrameChange?(nil)
                }
                return
            }

            let rectInWindow = convert(bounds, to: nil)
            let origin = window.convertPoint(toScreen: rectInWindow.origin)
            let frame = CGRect(origin: origin, size: rectInWindow.size)
            guard lastReportedFrame.map({ !Self.isNearlyEqual($0, frame) }) ?? true else {
                return
            }
            lastReportedFrame = frame
            onFrameChange?(frame)
        }

        private static func isNearlyEqual(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
            abs(lhs.minX - rhs.minX) <= 0.5 &&
                abs(lhs.minY - rhs.minY) <= 0.5 &&
                abs(lhs.width - rhs.width) <= 0.5 &&
                abs(lhs.height - rhs.height) <= 0.5
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }
    }
}
