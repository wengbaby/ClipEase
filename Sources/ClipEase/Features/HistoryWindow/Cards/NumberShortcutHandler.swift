import SwiftUI
import AppKit

struct NumberShortcutHandler: NSViewRepresentable {
    let inputState: HistoryWindowInputState
    let isEnabled: Bool
    let onCommandStateChange: (Bool) -> Void
    let onNumber: (Int) -> Void

    func makeNSView(context: Context) -> ShortcutNSView {
        let view = ShortcutNSView()
        view.inputState = inputState
        view.onCommandStateChange = onCommandStateChange
        view.onNumber = onNumber
        view.setEnabled(isEnabled)
        return view
    }

    func updateNSView(_ nsView: ShortcutNSView, context: Context) {
        nsView.inputState = inputState
        nsView.onCommandStateChange = onCommandStateChange
        nsView.onNumber = onNumber
        nsView.setEnabled(isEnabled)
    }

    static func dismantleNSView(_ nsView: ShortcutNSView, coordinator: ()) {
        nsView.dismantle()
    }

    final class ShortcutNSView: NSView {
        weak var inputState: HistoryWindowInputState?
        var onCommandStateChange: ((Bool) -> Void)?
        var onNumber: ((Int) -> Void)?
        private let injectedMonitorLifecycle: HistoryEventMonitorLifecycle?
        private var requestedEnabled = false
        private var isDismantled = false
        private lazy var monitorLifecycle = injectedMonitorLifecycle ?? HistoryEventMonitorLifecycle(
            requiredTokenCount: 2,
            install: { [weak self] in
                guard let self else {
                    return []
                }
                var monitors: [Any] = []
                if let keyMonitor = NSEvent.addLocalMonitorForEvents(
                    matching: .keyDown,
                    handler: { [weak self] event in
                        guard let self,
                              !self.isPreviewContentActive(),
                              self.window?.isKeyWindow == true,
                              !self.isHistoryTextInputActive(),
                              event.modifierFlags.contains(.command),
                              let characters = event.charactersIgnoringModifiers,
                              characters.count == 1,
                              let number = Int(characters),
                              (1...9).contains(number) else {
                            return event
                        }

                        self.onNumber?(number)
                        return nil
                    }
                ) {
                    monitors.append(keyMonitor)
                }
                if let flagsMonitor = NSEvent.addLocalMonitorForEvents(
                    matching: .flagsChanged,
                    handler: { [weak self] event in
                        guard let self,
                              !self.isPreviewContentActive(),
                              self.window?.isKeyWindow == true else {
                            self?.onCommandStateChange?(false)
                            return event
                        }

                        let isTextInputActive = self.isHistoryTextInputActive()
                        self.onCommandStateChange?(
                            event.modifierFlags.contains(.command) && !isTextInputActive
                        )
                        return event
                    }
                ) {
                    monitors.append(flagsMonitor)
                }
                return monitors
            },
            remove: { monitor in
                NSEvent.removeMonitor(monitor)
            }
        )

        init(monitorLifecycle: HistoryEventMonitorLifecycle? = nil) {
            injectedMonitorLifecycle = monitorLifecycle
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            nil
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            synchronizeMonitorLifecycle()
        }

        func setEnabled(_ enabled: Bool) {
            guard !isDismantled else {
                return
            }
            requestedEnabled = enabled
            synchronizeMonitorLifecycle()
        }

        func dismantle() {
            guard !isDismantled else {
                return
            }
            isDismantled = true
            requestedEnabled = false
            monitorLifecycle.dismantle()
            reportCommandStateChange(false, asynchronously: true)
            onCommandStateChange = nil
            onNumber = nil
            inputState = nil
        }

        private func synchronizeMonitorLifecycle() {
            let shouldEnable = requestedEnabled && window != nil && !isDismantled
            monitorLifecycle.setEnabled(shouldEnable)
            if !shouldEnable {
                reportCommandStateChange(false, asynchronously: true)
            }
        }

        private func reportCommandStateChange(_ isPressed: Bool, asynchronously: Bool) {
            guard asynchronously else {
                onCommandStateChange?(isPressed)
                return
            }

            let handler = onCommandStateChange
            DispatchQueue.main.async {
                handler?(isPressed)
            }
        }

        private func isPreviewContentActive() -> Bool {
            inputState?.isPreviewActiveSnapshot == true
        }

        private func isHistoryTextInputActive() -> Bool {
            inputState?.isHistoryTextInputActiveSnapshot == true || Self.isTextInputActive()
        }

        private static func isTextInputActive() -> Bool {
            guard let responder = NSApp.keyWindow?.firstResponder else {
                return false
            }

            return responder is NSTextView
        }
    }
}
