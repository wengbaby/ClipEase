import SwiftUI
import AppKit

struct GroupRenameInputFrameReader: NSViewRepresentable {
    let onChange: (CGRect?) -> Void

    func makeNSView(context: Context) -> FrameView {
        let view = FrameView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ nsView: FrameView, context: Context) {
        nsView.onChange = onChange
        DispatchQueue.main.async {
            nsView.reportFrame()
        }
    }

    static func dismantleNSView(_ nsView: FrameView, coordinator: ()) {
        nsView.onChange?(nil)
    }

    final class FrameView: NSView {
        var onChange: ((CGRect?) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            DispatchQueue.main.async { [weak self] in
                self?.reportFrame()
            }
        }

        override func setFrameSize(_ newSize: NSSize) {
            super.setFrameSize(newSize)
            DispatchQueue.main.async { [weak self] in
                self?.reportFrame()
            }
        }

        func reportFrame() {
            guard let window else {
                onChange?(nil)
                return
            }

            let frameInWindow = convert(bounds, to: nil)
            onChange?(window.convertToScreen(frameInWindow))
        }
    }
}
