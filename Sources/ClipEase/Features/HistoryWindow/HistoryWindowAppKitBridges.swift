import AppKit
import SwiftUI

struct SearchOutsideWindowMouseDownObserver: NSViewRepresentable {
    let isEnabled: Bool
    let hostWindow: NSWindow?
    let excludedFrames: [CGRect]
    let onMouseDown: () -> Void

    func makeNSView(context: Context) -> ObservingView {
        let view = ObservingView()
        view.coordinator = context.coordinator
        context.coordinator.view = view
        context.coordinator.hostWindow = hostWindow
        context.coordinator.excludedFrames = excludedFrames
        context.coordinator.onMouseDown = onMouseDown
        context.coordinator.setEnabled(isEnabled)
        return view
    }

    func updateNSView(_ nsView: ObservingView, context: Context) {
        nsView.coordinator = context.coordinator
        context.coordinator.view = nsView
        context.coordinator.hostWindow = hostWindow
        context.coordinator.excludedFrames = excludedFrames
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
        var excludedFrames: [CGRect] = []
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
            excludedFrames = []
            hostWindow = nil
            view = nil
            monitorLifecycle.dismantle()
        }

        @MainActor
        private func handle(_ event: NSEvent) {
            guard isEnabled,
                  let view else {
                return
            }

            guard let activeHostWindow = hostWindow ?? view.window else {
                return
            }

            let screenPoint: NSPoint
            if let eventWindow = event.window {
                guard eventWindow === activeHostWindow || !isSearchRelatedPanel(eventWindow) else {
                    return
                }
                screenPoint = eventWindow.convertPoint(toScreen: event.locationInWindow)
            } else {
                screenPoint = NSEvent.mouseLocation
            }

            guard !excludedFrames.contains(where: { $0.contains(screenPoint) }) else {
                return
            }

            guard !SearchInteractionRegionRegistry.shared.contains(screenPoint: screenPoint, in: activeHostWindow) else {
                return
            }

            guard activeHostWindow.frame.contains(screenPoint) else {
                onMouseDown?()
                return
            }

            guard event.window === activeHostWindow else {
                onMouseDown?()
                return
            }

            guard !isInteractiveControlHit(event) else {
                return
            }

            onMouseDown?()
        }

        private func isInteractiveControlHit(_ event: NSEvent) -> Bool {
            guard let contentView = event.window?.contentView else {
                return false
            }

            let contentPoint = contentView.convert(event.locationInWindow, from: nil)
            var candidate = contentView.hitTest(contentPoint)
            while let view = candidate {
                if view is NSControl || view is NSTextView {
                    return true
                }
                candidate = view.superview
            }

            return false
        }

        private func isSearchRelatedPanel(_ window: NSWindow) -> Bool {
            let className = String(describing: type(of: window))
            return className.contains("Popover") || window.level.rawValue >= NSWindow.Level.popUpMenu.rawValue
        }
    }

    final class ObservingView: NSView {
        weak var coordinator: Coordinator?

        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }
    }
}

@MainActor
final class SearchInteractionRegionRegistry {
    static let shared = SearchInteractionRegionRegistry()
    private let views = NSHashTable<NSView>.weakObjects()

    func register(_ view: NSView) {
        views.add(view)
    }

    func unregister(_ view: NSView) {
        views.remove(view)
    }

    func contains(screenPoint: NSPoint, in hostWindow: NSWindow) -> Bool {
        for view in views.allObjects {
            guard let window = view.window,
                  window === hostWindow,
                  !view.isHidden,
                  view.bounds.width > 0,
                  view.bounds.height > 0 else {
                continue
            }

            let rectInWindow = view.convert(view.bounds, to: nil)
            let origin = window.convertPoint(toScreen: rectInWindow.origin)
            let screenFrame = CGRect(origin: origin, size: rectInWindow.size)
                .standardized
                .insetBy(dx: -8, dy: -8)
            if screenFrame.contains(screenPoint) {
                return true
            }
        }

        return false
    }
}

struct HorizontalScrollWheelRedirector: NSViewRepresentable {
    enum Scope {
        case cardRail
        case auxiliaryRail
    }

    let scope: Scope
    let isEnabled: Bool

    init(scope: Scope, isEnabled: Bool = true) {
        self.scope = scope
        self.isEnabled = isEnabled
    }

    func makeNSView(context: Context) -> ScrollRedirectView {
        let view = ScrollRedirectView(scope: scope)
        view.setEnabled(isEnabled)
        return view
    }

    func updateNSView(_ nsView: ScrollRedirectView, context: Context) {
        nsView.scope = scope
        nsView.setEnabled(isEnabled)
        nsView.updateCoordinatorBindingIfNeeded()
    }

    static func dismantleNSView(_ nsView: ScrollRedirectView, coordinator: ()) {
        nsView.dismantle()
    }

    final class ScrollRedirectView: NSView {
        var scope: Scope
        private let injectedMonitorLifecycle: HistoryEventMonitorLifecycle?
        private var isDismantled = false
        private lazy var monitorLifecycle = injectedMonitorLifecycle ?? HistoryEventMonitorLifecycle(
            install: { [weak self] in
                guard let self,
                      let monitor = NSEvent.addLocalMonitorForEvents(
                          matching: .scrollWheel,
                          handler: { [weak self] event in
                              guard let self,
                                    self.redirect(event) else {
                                  return event
                              }
                              return nil
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

        init(
            scope: Scope,
            monitorLifecycle: HistoryEventMonitorLifecycle? = nil
        ) {
            self.scope = scope
            injectedMonitorLifecycle = monitorLifecycle
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) {
            self.scope = .auxiliaryRail
            injectedMonitorLifecycle = nil
            super.init(coder: coder)
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard !isDismantled,
                  window != nil else {
                return
            }
            updateCoordinatorBindingIfNeeded()
        }

        func updateCoordinatorBindingIfNeeded() {
            guard let scrollView = horizontalScrollableEnclosingScrollView() else {
                return
            }

            updateCardRailCoordinatorIfNeeded(scrollView)
        }

        func setEnabled(_ enabled: Bool) {
            guard !isDismantled else {
                return
            }
            monitorLifecycle.setEnabled(enabled)
            if enabled {
                updateCoordinatorBindingIfNeeded()
            }
        }

        func dismantle() {
            guard !isDismantled else {
                return
            }
            isDismantled = true
            monitorLifecycle.dismantle()
        }

        override func scrollWheel(with event: NSEvent) {
            guard redirect(event) else {
                super.scrollWheel(with: event)
                return
            }
        }

        private func redirect(_ event: NSEvent) -> Bool {
            guard abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX),
                  let window,
                  event.window === window,
                  let scrollView = horizontalScrollView(at: event.locationInWindow) else {
                return false
            }

            let clipView = scrollView.contentView
            let documentWidth = scrollView.documentView?.bounds.width ?? 0
            let maxX = max(documentWidth - clipView.bounds.width, 0)
            let multiplier: CGFloat = event.hasPreciseScrollingDeltas ? 5.0 : 18.0
            let delta = -event.scrollingDeltaY * multiplier
            let nextX = min(max(clipView.bounds.minX + delta, 0), maxX)
            clipView.scroll(to: NSPoint(x: nextX, y: clipView.bounds.minY))
            scrollView.reflectScrolledClipView(clipView)
            saveCardRailOffsetIfNeeded(nextX)
            return true
        }

        private func updateCardRailCoordinatorIfNeeded(_ scrollView: NSScrollView) {
            guard scope == .cardRail else {
                return
            }

            HistoryScrollCoordinator.shared.update(scrollView: scrollView)
        }

        private func saveCardRailOffsetIfNeeded(_ nextX: CGFloat) {
            guard scope == .cardRail else {
                return
            }

            HistoryScrollCoordinator.shared.saveOffset(nextX)
        }

        private func horizontalScrollView(at locationInWindow: NSPoint) -> NSScrollView? {
            guard let contentView = window?.contentView else {
                return nil
            }

            let contentPoint = contentView.convert(locationInWindow, from: nil)
            guard let hitView = contentView.hitTest(contentPoint) else {
                return nil
            }

            let hitScrollView = nearestHorizontalScrollView(from: hitView)
            guard let enclosingScrollView = horizontalScrollableEnclosingScrollView() else {
                return hitScrollView
            }

            // A parent redirector must not consume wheel input meant for a
            // nested horizontal surface such as the search-token rail.
            return hitScrollView === enclosingScrollView ? hitScrollView : nil
        }

        private func nearestHorizontalScrollView(from view: NSView) -> NSScrollView? {
            var candidate: NSView? = view
            while let currentView = candidate {
                if let scrollView = currentView as? NSScrollView,
                   isHorizontallyScrollable(scrollView) {
                    return scrollView
                }
                candidate = currentView.superview
            }

            return nil
        }

        private func horizontalScrollableEnclosingScrollView() -> NSScrollView? {
            var candidate: NSView? = self
            while let view = candidate {
                if let scrollView = view as? NSScrollView,
                   isHorizontallyScrollable(scrollView) {
                    return scrollView
                }
                candidate = view.superview
            }

            return nil
        }

        private func isHorizontallyScrollable(_ scrollView: NSScrollView) -> Bool {
            guard let documentView = scrollView.documentView else {
                return false
            }

            return documentView.bounds.width > scrollView.contentView.bounds.width + 2
        }
    }
}

struct HistoryWindowHostWindowReader: NSViewRepresentable {
    @Binding var window: NSWindow?

    func makeNSView(context: Context) -> WindowReaderView {
        let view = WindowReaderView()
        view.onWindowChange = { window in
            if self.window !== window {
                self.window = window
            }
        }
        return view
    }

    func updateNSView(_ nsView: WindowReaderView, context: Context) {
        nsView.onWindowChange = { window in
            if self.window !== window {
                self.window = window
            }
        }

        nsView.reportWindowSoon()
    }

    final class WindowReaderView: NSView {
        var onWindowChange: ((NSWindow?) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            reportWindowSoon()
        }

        func reportWindowSoon() {
            let window = window
            DispatchQueue.main.async { [weak self] in
                self?.onWindowChange?(window)
            }
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }
    }
}
