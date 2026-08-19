import SwiftUI
import AppKit

struct GroupRenameOutsideMouseDownObserver: NSViewRepresentable {
    let isEnabled: Bool
    let hostWindow: NSWindow?
    let excludedScreenFrame: CGRect?
    let onMouseDown: () -> Void

    func makeNSView(context: Context) -> ObservingView {
        let view = ObservingView()
        view.coordinator = context.coordinator
        context.coordinator.view = view
        context.coordinator.hostWindow = hostWindow
        context.coordinator.excludedScreenFrame = excludedScreenFrame
        context.coordinator.onMouseDown = onMouseDown
        context.coordinator.setEnabled(isEnabled)
        return view
    }

    func updateNSView(_ nsView: ObservingView, context: Context) {
        nsView.coordinator = context.coordinator
        context.coordinator.view = nsView
        context.coordinator.hostWindow = hostWindow
        context.coordinator.excludedScreenFrame = excludedScreenFrame
        context.coordinator.onMouseDown = onMouseDown
        context.coordinator.setEnabled(isEnabled)
    }

    static func dismantleNSView(_ nsView: ObservingView, coordinator: Coordinator) {
        coordinator.dismantle()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    @MainActor
    final class Coordinator {
        weak var view: ObservingView?
        private(set) var isEnabled = false
        weak var hostWindow: NSWindow?
        var excludedScreenFrame: CGRect?
        var onMouseDown: (() -> Void)?
        private let injectedMonitorLifecycle: HistoryEventMonitorLifecycle?
        private var isDismantled = false
        private lazy var monitorLifecycle = injectedMonitorLifecycle ?? HistoryEventMonitorLifecycle(
            install: { [weak self] in
                guard let self,
                      let monitor = NSEvent.addLocalMonitorForEvents(
                          matching: [.leftMouseDown, .rightMouseDown],
                          handler: { [weak self] event in
                              self?.handle(event)
                              return event
                          }
                      ) else {
                    return []
                }
                return [monitor]
            },
            remove: { monitor in
                NSEvent.removeMonitor(monitor)
            }
        )

        init(monitorLifecycle: HistoryEventMonitorLifecycle? = nil) {
            injectedMonitorLifecycle = monitorLifecycle
        }

        func setEnabled(_ enabled: Bool) {
            guard !isDismantled else {
                return
            }
            isEnabled = enabled
            monitorLifecycle.setEnabled(enabled)
        }

        func dismantle() {
            guard !isDismantled else {
                return
            }
            isDismantled = true
            isEnabled = false
            onMouseDown = nil
            excludedScreenFrame = nil
            hostWindow = nil
            view = nil
            monitorLifecycle.dismantle()
        }

        @MainActor
        private func handle(_ event: NSEvent) {
            guard isEnabled,
                  let activeHostWindow = hostWindow ?? view?.window,
                  event.window === activeHostWindow else {
                return
            }

            if isExcludedScreenFrameHit(event, in: activeHostWindow) {
                return
            }

            guard !isCurrentRenameTextFieldHit(event) else {
                return
            }

            onMouseDown?()
        }

        private func isExcludedScreenFrameHit(_ event: NSEvent, in window: NSWindow) -> Bool {
            guard let excludedScreenFrame else {
                return false
            }

            let screenPoint = window.convertPoint(toScreen: event.locationInWindow)
            return excludedScreenFrame.insetBy(dx: -4, dy: -4).contains(screenPoint)
        }

        private func isCurrentRenameTextFieldHit(_ event: NSEvent) -> Bool {
            guard let contentView = event.window?.contentView else {
                return false
            }

            let contentPoint = contentView.convert(event.locationInWindow, from: nil)
            var candidate = contentView.hitTest(contentPoint)
            while let view = candidate {
                if let textField = view as? GroupInlineTextField.InlineNSTextField,
                   textField.isGroupRenameField {
                    return true
                }
                candidate = view.superview
            }

            return false
        }
    }

    final class ObservingView: NSView {
        weak var coordinator: Coordinator?

        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }
    }
}
