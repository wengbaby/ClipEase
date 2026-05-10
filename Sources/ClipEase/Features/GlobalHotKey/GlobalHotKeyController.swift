import Carbon
import Combine
import Foundation

@MainActor
final class GlobalHotKeyController {
    private static weak var activeController: GlobalHotKeyController?

    private weak var historyWindowController: HistoryWindowController?
    private let shortcutSettings: GlobalShortcutSettings
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var shortcutCancellable: AnyCancellable?

    init(
        historyWindowController: HistoryWindowController,
        shortcutSettings: GlobalShortcutSettings
    ) {
        self.historyWindowController = historyWindowController
        self.shortcutSettings = shortcutSettings
    }

    func start() {
        Self.activeController = self
        installEventHandlerIfNeeded()
        registerHotKey()
        shortcutCancellable = shortcutSettings.$shortcut
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.reregisterHotKey()
                }
            }
    }

    func stop() {
        unregisterHotKey()

        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }

        shortcutCancellable = nil
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandlerRef == nil else {
            return
        }

        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            Self.hotKeyHandler,
            1,
            &eventSpec,
            nil,
            &eventHandlerRef
        )

        if status != noErr {
            NSLog("ClipEase failed to install global hotkey handler: \(status)")
        }
    }

    private func registerHotKey() {
        guard hotKeyRef == nil else {
            return
        }

        let hotKeyID = EventHotKeyID(
            signature: Self.fourCharacterCode("CLPE"),
            id: 1
        )
        let shortcut = shortcutSettings.shortcut
        let status = RegisterEventHotKey(
            UInt32(shortcut.keyCode),
            shortcut.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if status != noErr {
            NSLog("ClipEase failed to register \(shortcut.displayText) hotkey: \(status)")
        }
    }

    private func unregisterHotKey() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }

    private func reregisterHotKey() {
        unregisterHotKey()
        registerHotKey()
    }

    private static let hotKeyHandler: EventHandlerUPP = { _, eventRef, _ in
        guard let eventRef else {
            return OSStatus(eventNotHandledErr)
        }

        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            eventRef,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        guard status == noErr, hotKeyID.id == 1 else {
            return OSStatus(eventNotHandledErr)
        }

        Task { @MainActor in
            activeController?.historyWindowController?.toggle()
        }
        return noErr
    }

    private static func fourCharacterCode(_ string: String) -> OSType {
        string.utf8.reduce(0) { partialResult, character in
            (partialResult << 8) + OSType(character)
        }
    }
}
