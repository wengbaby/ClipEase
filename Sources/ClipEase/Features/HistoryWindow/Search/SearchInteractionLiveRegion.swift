import SwiftUI
import AppKit

struct SearchInteractionLiveRegion: NSViewRepresentable {
    let isActive: Bool
    let onRegister: (NSView) -> Void
    let onUnregister: (NSView) -> Void

    func makeNSView(context: Context) -> RegionView {
        let view = RegionView()
        view.onRegister = onRegister
        view.onUnregister = onUnregister
        view.isActive = isActive
        view.syncRegistration()
        return view
    }

    func updateNSView(_ nsView: RegionView, context: Context) {
        nsView.onRegister = onRegister
        nsView.onUnregister = onUnregister
        nsView.isActive = isActive
        nsView.syncRegistration()
    }

    static func dismantleNSView(_ nsView: RegionView, coordinator: ()) {
        nsView.unregisterIfNeeded()
    }

    final class RegionView: NSView {
        var onRegister: ((NSView) -> Void)?
        var onUnregister: ((NSView) -> Void)?
        var isActive = false
        private var isRegistered = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            syncRegistration()
        }

        func syncRegistration() {
            if isActive, window != nil {
                guard !isRegistered else {
                    return
                }

                isRegistered = true
                onRegister?(self)
            } else {
                unregisterIfNeeded()
            }
        }

        func unregisterIfNeeded() {
            guard isRegistered else {
                return
            }

            isRegistered = false
            onUnregister?(self)
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }
    }
}
