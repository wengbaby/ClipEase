import SwiftUI
import AppKit

struct GroupAppearanceOutsideMouseDownObserver: NSViewRepresentable {
    let isEnabled: Bool
    let hostWindow: NSWindow?
    let popoverWindow: NSWindow?
    let onMouseDown: () -> Void

    func makeNSView(context: Context) -> ObservingView {
        let view = ObservingView()
        view.coordinator = context.coordinator
        context.coordinator.view = view
        context.coordinator.hostWindow = hostWindow
        context.coordinator.popoverWindow = popoverWindow
        context.coordinator.onMouseDown = onMouseDown
        context.coordinator.setEnabled(isEnabled)
        return view
    }

    func updateNSView(_ nsView: ObservingView, context: Context) {
        nsView.coordinator = context.coordinator
        context.coordinator.view = nsView
        context.coordinator.hostWindow = hostWindow
        context.coordinator.popoverWindow = popoverWindow
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
        weak var popoverWindow: NSWindow?
        var onMouseDown: (() -> Void)?
        private let injectedMonitorLifecycle: HistoryEventMonitorLifecycle?
        private var isDismantled = false
        private lazy var monitorLifecycle = injectedMonitorLifecycle ?? HistoryEventMonitorLifecycle(
            requiredTokenCount: 2,
            install: { [weak self] in
                guard let self else {
                    return []
                }
                var monitors: [Any] = []
                if let localMonitor = NSEvent.addLocalMonitorForEvents(
                    matching: [.leftMouseDown, .rightMouseDown],
                    handler: { [weak self] event in
                        self?.handle(event)
                        return event
                    }
                ) {
                    monitors.append(localMonitor)
                }
                if let globalMonitor = NSEvent.addGlobalMonitorForEvents(
                    matching: [.leftMouseDown, .rightMouseDown],
                    handler: { [weak self] event in
                        Task { @MainActor [weak self] in
                            self?.handle(event)
                        }
                    }
                ) {
                    monitors.append(globalMonitor)
                }
                return monitors
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
            popoverWindow = nil
            hostWindow = nil
            view = nil
            monitorLifecycle.dismantle()
        }

        @MainActor
        private func handle(_ event: NSEvent) {
            let role = eventWindowRole(for: event)
            handle(eventWindowRole: role)
        }

        func handle(eventWindowRole role: HistoryGroupAppearanceEventWindowRole) {
            guard HistoryGroupAppearanceOutsideClickPolicy.shouldClose(
                isEnabled: isEnabled,
                eventWindowRole: role
            ) else {
                return
            }

            onMouseDown?()
        }

        private func eventWindowRole(for event: NSEvent) -> HistoryGroupAppearanceEventWindowRole {
            guard let eventWindow = event.window else {
                return .outsideApp
            }

            if let hostWindow = hostWindow ?? view?.window,
               eventWindow === hostWindow {
                return .hostWindow
            }

            if eventWindow === NSColorPanel.shared {
                return .colorPanel
            }

            if let popoverWindow,
               eventWindow === popoverWindow {
                return .popover
            }

            return .outsideApp
        }
    }

    final class ObservingView: NSView {
        weak var coordinator: Coordinator?

        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }
    }
}
