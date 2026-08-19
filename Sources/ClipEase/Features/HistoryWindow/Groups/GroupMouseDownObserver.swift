import SwiftUI
import AppKit

struct GroupMouseDownObserver: NSViewRepresentable {
    let registry: HistoryGroupMouseMonitorRegistry
    let isEnabled: Bool
    let onMouseDown: () -> Void
    var onRightMouseDown: (() -> Void)?
    var onDoubleMouseDown: (() -> Void)?

    init(
        registry: HistoryGroupMouseMonitorRegistry,
        isEnabled: Bool,
        onMouseDown: @escaping () -> Void
    ) {
        self.registry = registry
        self.isEnabled = isEnabled
        self.onMouseDown = onMouseDown
        onRightMouseDown = nil
        onDoubleMouseDown = nil
    }

    init(
        registry: HistoryGroupMouseMonitorRegistry,
        isEnabled: Bool,
        onMouseDown: @escaping () -> Void,
        onRightMouseDown: (() -> Void)?,
        onDoubleMouseDown: (() -> Void)? = nil
    ) {
        self.registry = registry
        self.isEnabled = isEnabled
        self.onMouseDown = onMouseDown
        self.onRightMouseDown = onRightMouseDown
        self.onDoubleMouseDown = onDoubleMouseDown
    }

    func onRightMouseDown(_ action: @escaping () -> Void) -> Self {
        var observer = self
        observer.onRightMouseDown = action
        return observer
    }

    func onDoubleMouseDown(_ action: @escaping () -> Void) -> Self {
        var observer = self
        observer.onDoubleMouseDown = action
        return observer
    }

    func makeNSView(context: Context) -> ObservingView {
        let view = ObservingView()
        view.coordinator = context.coordinator
        context.coordinator.update(
            registry: registry,
            view: view,
            isEnabled: isEnabled,
            onMouseDown: onMouseDown,
            onRightMouseDown: onRightMouseDown,
            onDoubleMouseDown: onDoubleMouseDown
        )
        return view
    }

    func updateNSView(_ nsView: ObservingView, context: Context) {
        nsView.coordinator = context.coordinator
        context.coordinator.update(
            registry: registry,
            view: nsView,
            isEnabled: isEnabled,
            onMouseDown: onMouseDown,
            onRightMouseDown: onRightMouseDown,
            onDoubleMouseDown: onDoubleMouseDown
        )
    }

    static func dismantleNSView(_ nsView: ObservingView, coordinator: Coordinator) {
        coordinator.dismantle()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    @MainActor
    final class Coordinator {
        private let regionID = UUID()
        private weak var registry: HistoryGroupMouseMonitorRegistry?
        private var isDismantled = false

        func update(
            registry: HistoryGroupMouseMonitorRegistry,
            view: ObservingView,
            isEnabled: Bool,
            onMouseDown: @escaping () -> Void,
            onRightMouseDown: (() -> Void)?,
            onDoubleMouseDown: (() -> Void)?
        ) {
            guard !isDismantled else {
                return
            }

            if self.registry !== registry {
                self.registry?.unregister(id: regionID)
                self.registry = registry
            }
            registry.register(
                id: regionID,
                view: view,
                isEnabled: isEnabled,
                onMouseDown: onMouseDown,
                onRightMouseDown: onRightMouseDown,
                onDoubleMouseDown: onDoubleMouseDown
            )
        }

        func dismantle() {
            guard !isDismantled else {
                return
            }
            isDismantled = true
            registry?.unregister(id: regionID)
            registry = nil
        }
    }

    final class ObservingView: NSView {
        weak var coordinator: Coordinator?

        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }
    }
}
