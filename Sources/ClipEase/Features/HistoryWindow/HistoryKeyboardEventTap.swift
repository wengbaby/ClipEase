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
                let shouldShowCommandOverlay = isCommandPressed && inputState?.isPreviewActiveSnapshot != true
                inputState?.setCommandKeyPressed(shouldShowCommandOverlay)
            }
            return Unmanaged.passUnretained(event)

        case .keyDown:
            let isTextInputActive = inputState?.isHistoryTextInputActiveSnapshot == true
            let isPreviewActive = inputState?.isPreviewActiveSnapshot == true
            guard let action = Self.action(for: event, isTextInputActive: isTextInputActive) else {
                return Unmanaged.passUnretained(event)
            }

            if !HistoryKeyboardShortcutPolicy.allowsHistoryCommand(
                action,
                isTextInputActive: isTextInputActive,
                isPreviewContentActive: isPreviewActive
            ) {
                return Unmanaged.passUnretained(event)
            }

            if inputState?.shouldSuppressHistoryCommandShortcutsSnapshot == true,
               Self.shouldSuppressForPresentedInputLayer(action) {
                return Unmanaged.passUnretained(event)
            }

            if inputState?.isWindowPinnedOpenSnapshot == true,
               Self.shouldPassThroughWhileWindowPinned(action) {
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

    private static func action(for event: CGEvent, isTextInputActive: Bool) -> HistoryKeyboardAction? {
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags
        let isCommandPressed = flags.contains(.maskCommand)
        let isShiftPressed = flags.contains(.maskShift)
        let hasTextEditingModifier = flags.contains(.maskCommand) ||
            flags.contains(.maskControl) ||
            flags.contains(.maskAlternate)

        if isTextInputActive {
            return HistoryKeyboardInputPolicy.actionForTextInput(
                keyCode: keyCode,
                hasTextEditingModifier: hasTextEditingModifier,
                isShiftPressed: isShiftPressed,
                cursorIsAtEnd: false
            )
        }

        if isCommandPressed {
            if let number = numberShortcut(for: keyCode) {
                return .selectVisibleCard(number)
            }

            switch keyCode {
            case KeyCode.f:
                return .openSearch
            case KeyCode.c:
                return isShiftPressed ? .copyPlainText : .copy
            case KeyCode.n:
                return .createText
            case KeyCode.p:
                return .togglePinned
            case KeyCode.e:
                return .edit
            case KeyCode.t:
                return .toggleRecording
            case KeyCode.w:
                return .closeWindow
            case commaKeyCode:
                return .showSettings
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
            return isShiftPressed ? .pastePlainText : .paste
        case KeyCode.space:
            return .togglePreview
        case KeyCode.escape:
            return .close
        case KeyCode.delete:
            return .delete
        default:
            guard let text = printableCharacters(from: event) else {
                return nil
            }
            return .appendSearchText(text)
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

    private static func shouldSuppressForPresentedInputLayer(_ action: HistoryKeyboardAction) -> Bool {
        switch action {
        case .edit, .toggleRecording, .copy, .copyPlainText, .paste, .pastePlainText, .togglePreview:
            return true
        case .moveLeft, .moveRight, .close, .selectVisibleCard, .openSearch, .showSettings, .delete, .togglePinned, .closeWindow, .createText, .enterFirstSearchResult, .focusFirstSearchResult:
            return false
        case .appendSearchText:
            return true
        }
    }

    private static func shouldPassThroughWhileWindowPinned(_ action: HistoryKeyboardAction) -> Bool {
        switch action {
        case .copy, .copyPlainText, .selectVisibleCard, .openSearch, .showSettings, .edit, .togglePinned, .createText, .toggleRecording, .appendSearchText:
            return true
        case .moveLeft, .moveRight, .paste, .pastePlainText, .togglePreview, .close, .delete, .closeWindow, .enterFirstSearchResult, .focusFirstSearchResult:
            return false
        }
    }

    private static let commaKeyCode: UInt16 = 43

    private static func printableCharacters(from event: CGEvent) -> String? {
        var actualLength = 0
        var buffer = [UniChar](repeating: 0, count: 8)
        event.keyboardGetUnicodeString(
            maxStringLength: buffer.count,
            actualStringLength: &actualLength,
            unicodeString: &buffer
        )

        guard actualLength > 0 else {
            return nil
        }

        let text = String(utf16CodeUnits: buffer, count: actualLength)
        guard text.rangeOfCharacter(from: .newlines) == nil,
              text.rangeOfCharacter(from: .controlCharacters) == nil,
              text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return nil
        }

        return text
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
