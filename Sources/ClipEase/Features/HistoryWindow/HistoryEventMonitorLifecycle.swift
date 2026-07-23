import AppKit
import Combine
import Foundation

enum HistoryWindowMonitorVisibilityPolicy {
    static func isEnabled(
        isWindowVisible: Bool,
        isFeatureActive: Bool
    ) -> Bool {
        isWindowVisible && isFeatureActive
    }
}

@MainActor
final class HistoryEventMonitorLifecycle {
    typealias Installer = @MainActor @Sendable () -> [Any]
    typealias Remover = @MainActor @Sendable (Any) -> Void

    private final class InstalledToken: @unchecked Sendable {
        let value: Any

        init(_ value: Any) {
            self.value = value
        }
    }

    private let install: Installer
    private let remove: Remover
    private let requiredTokenCount: Int
    private var tokens: [InstalledToken] = []
    private var isDismantled = false
    private(set) var isEnabled = false

    init(
        requiredTokenCount: Int = 1,
        install: @escaping Installer,
        remove: @escaping Remover
    ) {
        self.requiredTokenCount = max(requiredTokenCount, 1)
        self.install = install
        self.remove = remove
    }

    func setEnabled(_ enabled: Bool) {
        guard !isDismantled else {
            return
        }

        isEnabled = enabled
        if enabled {
            if tokens.count < requiredTokenCount {
                removeAllTokens()
                tokens = install().map(InstalledToken.init)
            }
        } else {
            removeAllTokens()
        }
    }

    func dismantle() {
        guard !isDismantled else {
            return
        }
        isDismantled = true
        isEnabled = false
        removeAllTokens()
    }

    private func removeAllTokens() {
        let installedTokens = tokens
        tokens.removeAll(keepingCapacity: true)
        for token in installedTokens {
            remove(token.value)
        }
    }

    deinit {
        let installedTokens = tokens
        let remover = remove
        MainActor.assumeIsolated {
            for token in installedTokens {
                remover(token.value)
            }
        }
    }
}

@MainActor
final class HistoryGroupMouseMonitorRegistry: ObservableObject {
    private final class Region {
        weak var view: NSView?
        var isEnabled: Bool
        var onMouseDown: () -> Void
        var onRightMouseDown: (() -> Void)?
        var onDoubleMouseDown: (() -> Void)?

        init(
            view: NSView,
            isEnabled: Bool,
            onMouseDown: @escaping () -> Void,
            onRightMouseDown: (() -> Void)?,
            onDoubleMouseDown: (() -> Void)?
        ) {
            self.view = view
            self.isEnabled = isEnabled
            self.onMouseDown = onMouseDown
            self.onRightMouseDown = onRightMouseDown
            self.onDoubleMouseDown = onDoubleMouseDown
        }

        func update(
            view: NSView,
            isEnabled: Bool,
            onMouseDown: @escaping () -> Void,
            onRightMouseDown: (() -> Void)?,
            onDoubleMouseDown: (() -> Void)?
        ) {
            self.view = view
            self.isEnabled = isEnabled
            self.onMouseDown = onMouseDown
            self.onRightMouseDown = onRightMouseDown
            self.onDoubleMouseDown = onDoubleMouseDown
        }

        func deliver(_ event: NSEvent) {
            switch event.type {
            case .rightMouseDown:
                (onRightMouseDown ?? onMouseDown)()
            default:
                if event.clickCount >= 2, let onDoubleMouseDown {
                    onDoubleMouseDown()
                } else {
                    onMouseDown()
                }
            }
        }
    }

    private let injectedMonitorLifecycle: HistoryEventMonitorLifecycle?
    private var regions: [AnyHashable: Region] = [:]
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

    func register<ID: Hashable>(
        id: ID,
        view: NSView,
        isEnabled: Bool,
        onMouseDown: @escaping () -> Void,
        onRightMouseDown: (() -> Void)? = nil,
        onDoubleMouseDown: (() -> Void)? = nil
    ) {
        let key = AnyHashable(id)
        if let region = regions[key] {
            region.update(
                view: view,
                isEnabled: isEnabled,
                onMouseDown: onMouseDown,
                onRightMouseDown: onRightMouseDown,
                onDoubleMouseDown: onDoubleMouseDown
            )
        } else {
            regions[key] = Region(
                view: view,
                isEnabled: isEnabled,
                onMouseDown: onMouseDown,
                onRightMouseDown: onRightMouseDown,
                onDoubleMouseDown: onDoubleMouseDown
            )
        }
        updateMonitorLifecycle()
    }

    func unregister<ID: Hashable>(id: ID) {
        regions[AnyHashable(id)] = nil
        updateMonitorLifecycle()
    }

    func handle(_ event: NSEvent) {
        pruneReleasedRegions()
        guard let eventWindow = event.window else {
            return
        }

        for region in regions.values where region.isEnabled {
            guard let view = region.view,
                  eventWindow === view.window else {
                continue
            }

            let point = view.convert(event.locationInWindow, from: nil)
            guard view.bounds.contains(point) else {
                continue
            }

            region.deliver(event)
            return
        }
    }

    private func pruneReleasedRegions() {
        let releasedIDs = regions.compactMap { id, region in
            region.view == nil ? id : nil
        }
        guard !releasedIDs.isEmpty else {
            return
        }
        for id in releasedIDs {
            regions[id] = nil
        }
        updateMonitorLifecycle()
    }

    private func updateMonitorLifecycle() {
        monitorLifecycle.setEnabled(
            regions.values.contains { $0.isEnabled && $0.view != nil }
        )
    }
}
