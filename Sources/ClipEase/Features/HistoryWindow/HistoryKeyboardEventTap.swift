import ApplicationServices
import AppKit

final class HistoryKeyboardEventTap: @unchecked Sendable {
    private weak var inputState: HistoryWindowInputState?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    init(inputState: HistoryWindowInputState) {
        self.inputState = inputState
    }

    func start() {
        guard eventTap == nil else {
            return
        }

        let eventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: HistoryKeyboardEventTap.eventCallback,
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        ) else {
            NSLog("ClipEase: failed to install history keyboard event tap")
            return
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stop() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
            self.eventTap = nil
        }

        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            self.runLoopSource = nil
        }

        DispatchQueue.main.async { [weak inputState] in
            inputState?.resetTransientState()
        }
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)

        case .flagsChanged:
            let isCommandPressed = event.flags.contains(.maskCommand)
            DispatchQueue.main.async { [weak inputState] in
                inputState?.setCommandKeyPressed(isCommandPressed)
            }
            return Unmanaged.passUnretained(event)

        case .keyDown:
            guard let action = Self.action(for: event) else {
                return Unmanaged.passUnretained(event)
            }

            if inputState?.isTextInputFocusedSnapshot == true,
               !Self.shouldHandleWhileTextInputFocused(action) {
                return Unmanaged.passUnretained(event)
            }

            DispatchQueue.main.async { [weak inputState] in
                inputState?.dispatch(action)
            }
            return nil

        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private static func action(for event: CGEvent) -> HistoryKeyboardAction? {
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let isCommandPressed = event.flags.contains(.maskCommand)

        if isCommandPressed {
            if let number = numberShortcut(for: keyCode) {
                return .selectVisibleCard(number)
            }

            switch keyCode {
            case KeyCode.f:
                return .openSearch
            case KeyCode.c:
                return .copy
            case KeyCode.p:
                return .togglePinned
            default:
                return nil
            }
        }

        switch keyCode {
        case KeyCode.leftArrow:
            return .moveLeft
        case KeyCode.rightArrow:
            return .moveRight
        case KeyCode.returnKey, KeyCode.enter:
            return .paste
        case KeyCode.space:
            return .togglePreview
        case KeyCode.escape:
            return .close
        case KeyCode.delete:
            return .delete
        default:
            return nil
        }
    }

    private static func numberShortcut(for keyCode: UInt16) -> Int? {
        switch keyCode {
        case KeyCode.one:
            return 1
        case KeyCode.two:
            return 2
        case KeyCode.three:
            return 3
        case KeyCode.four:
            return 4
        case KeyCode.five:
            return 5
        case KeyCode.six:
            return 6
        case KeyCode.seven:
            return 7
        case KeyCode.eight:
            return 8
        case KeyCode.nine:
            return 9
        default:
            return nil
        }
    }

    private static func shouldHandleWhileTextInputFocused(_ action: HistoryKeyboardAction) -> Bool {
        switch action {
        case .close:
            return true
        case .moveLeft, .moveRight, .paste, .togglePreview, .selectVisibleCard, .openSearch, .copy, .delete, .togglePinned:
            return false
        }
    }

    private static let eventCallback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else {
            return Unmanaged.passUnretained(event)
        }

        let eventTap = Unmanaged<HistoryKeyboardEventTap>
            .fromOpaque(userInfo)
            .takeUnretainedValue()
        return eventTap.handle(type: type, event: event)
    }
}
