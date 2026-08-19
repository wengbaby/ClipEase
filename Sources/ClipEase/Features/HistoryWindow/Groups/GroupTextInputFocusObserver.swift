import SwiftUI
import AppKit

struct GroupTextInputFocusObserver: NSViewRepresentable {
    @Binding var isFocused: Bool

    func makeNSView(context: Context) -> FocusObserverView {
        let view = FocusObserverView()
        view.onFocusChange = { focused in
            if isFocused != focused {
                isFocused = focused
            }
        }
        return view
    }

    func updateNSView(_ nsView: FocusObserverView, context: Context) {
        nsView.onFocusChange = { focused in
            if isFocused != focused {
                isFocused = focused
            }
        }

        DispatchQueue.main.async {
            nsView.refreshFocus()
        }
    }

    final class FocusObserverView: NSView {
        var onFocusChange: ((Bool) -> Void)?
        private var observedWindow: NSWindow?
        private var isObservedFocused = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            updateWindowObservation()
            refreshFocus()
        }

        deinit {
            if let observedWindow {
                NotificationCenter.default.removeObserver(
                    self,
                    name: NSWindow.didUpdateNotification,
                    object: observedWindow
                )
            }
        }

        func refreshFocus() {
            let focused = isFirstResponderInsideObservedTextField()
            guard focused != isObservedFocused else {
                return
            }

            isObservedFocused = focused
            onFocusChange?(focused)
        }

        private func updateWindowObservation() {
            guard observedWindow !== window else {
                return
            }

            if let observedWindow {
                NotificationCenter.default.removeObserver(
                    self,
                    name: NSWindow.didUpdateNotification,
                    object: observedWindow
                )
            }

            observedWindow = window
            if let window {
                NotificationCenter.default.addObserver(
                    self,
                    selector: #selector(windowDidUpdate),
                    name: NSWindow.didUpdateNotification,
                    object: window
                )
            }
        }

        @objc private func windowDidUpdate() {
            refreshFocus()
        }

        private func isFirstResponderInsideObservedTextField() -> Bool {
            guard let window,
                  let textField = enclosingTextField() else {
                return false
            }

            if window.firstResponder === textField {
                return true
            }

            guard let editor = textField.currentEditor() else {
                return false
            }

            return window.firstResponder === editor
        }

        private func enclosingTextField() -> NSTextField? {
            var candidate = superview
            while let view = candidate {
                if let textField = view as? NSTextField {
                    return textField
                }
                candidate = view.superview
            }
            return nil
        }
    }
}
