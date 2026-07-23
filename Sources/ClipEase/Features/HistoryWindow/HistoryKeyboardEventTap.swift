import AppKit
import ApplicationServices

final class HistoryKeyboardEventTapHandle {
    fileprivate let rawValue: CFMachPort?

    init(rawValue: CFMachPort? = nil) {
        self.rawValue = rawValue
    }
}

final class HistoryKeyboardEventTapRunLoopSource {
    fileprivate let rawValue: CFRunLoopSource?

    init(rawValue: CFRunLoopSource? = nil) {
        self.rawValue = rawValue
    }
}

enum HistoryKeyboardEventPassThroughPolicy {
    static func shouldPassThrough(
        keyCode: UInt16,
        flags: CGEventFlags,
        isButtonFirstResponderActive: Bool
    ) -> Bool {
        if flags.contains(.maskControl),
           flags.contains(.maskAlternate) {
            return true
        }
        return isButtonFirstResponderActive && keyCode == KeyCode.space
    }
}

private struct HistoryKeyboardFirstResponderActivity {
    let isTextActive: Bool
    let isButtonActive: Bool
}

@MainActor
protocol HistoryKeyboardInputOwnership: AnyObject {
    func ownsHistoryInput() -> Bool
}

private final class HistoryKeyboardInputOwnershipBox: @unchecked Sendable {
    let value: any HistoryKeyboardInputOwnership

    init(_ value: any HistoryKeyboardInputOwnership) {
        self.value = value
    }
}

@MainActor
private final class HistoryKeyboardEventTapWindowState: HistoryKeyboardInputOwnership {
    weak var historyWindow: NSWindow?
    private weak var inputState: HistoryWindowInputState?

    init(inputState: HistoryWindowInputState) {
        self.inputState = inputState
    }

    func ownsHistoryInput() -> Bool {
        if inputState?.isPreviewActiveSnapshot == true {
            return true
        }

        guard let historyWindow else {
            return false
        }

        return NSApp?.keyWindow === historyWindow
    }

    func firstResponderActivity() -> HistoryKeyboardFirstResponderActivity {
        HistoryKeyboardFirstResponderActivity(
            isTextActive: historyWindow?.firstResponder is NSTextView ||
                NSApp?.keyWindow?.firstResponder is NSTextView,
            isButtonActive: historyWindow?.firstResponder is NSButton ||
                NSApp?.keyWindow?.firstResponder is NSButton
        )
    }
}

protocol HistoryKeyboardEventTapBackend: AnyObject {
    func createTap(
        eventMask: CGEventMask,
        callback: CGEventTapCallBack,
        userInfo: UnsafeMutableRawPointer?
    ) -> HistoryKeyboardEventTapHandle?
    func createRunLoopSource(
        for tap: HistoryKeyboardEventTapHandle
    ) -> HistoryKeyboardEventTapRunLoopSource?
    func addRunLoopSource(_ source: HistoryKeyboardEventTapRunLoopSource)
    func removeRunLoopSource(_ source: HistoryKeyboardEventTapRunLoopSource)
    func setEnabled(_ enabled: Bool, for tap: HistoryKeyboardEventTapHandle)
    func invalidate(_ tap: HistoryKeyboardEventTapHandle)
}

private final class SystemHistoryKeyboardEventTapBackend: HistoryKeyboardEventTapBackend, @unchecked Sendable {
    static let shared = SystemHistoryKeyboardEventTapBackend()

    private init() {}

    func createTap(
        eventMask: CGEventMask,
        callback: CGEventTapCallBack,
        userInfo: UnsafeMutableRawPointer?
    ) -> HistoryKeyboardEventTapHandle? {
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: callback,
            userInfo: userInfo
        ) else {
            return nil
        }

        return HistoryKeyboardEventTapHandle(rawValue: tap)
    }

    func createRunLoopSource(
        for tap: HistoryKeyboardEventTapHandle
    ) -> HistoryKeyboardEventTapRunLoopSource? {
        guard let rawTap = tap.rawValue,
              let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, rawTap, 0) else {
            return nil
        }

        return HistoryKeyboardEventTapRunLoopSource(rawValue: source)
    }

    func addRunLoopSource(_ source: HistoryKeyboardEventTapRunLoopSource) {
        guard let rawSource = source.rawValue else {
            return
        }

        CFRunLoopAddSource(CFRunLoopGetMain(), rawSource, .commonModes)
    }

    func removeRunLoopSource(_ source: HistoryKeyboardEventTapRunLoopSource) {
        guard let rawSource = source.rawValue else {
            return
        }

        CFRunLoopRemoveSource(CFRunLoopGetMain(), rawSource, .commonModes)
    }

    func setEnabled(_ enabled: Bool, for tap: HistoryKeyboardEventTapHandle) {
        guard let rawTap = tap.rawValue else {
            return
        }

        CGEvent.tapEnable(tap: rawTap, enable: enabled)
    }

    func invalidate(_ tap: HistoryKeyboardEventTapHandle) {
        guard let rawTap = tap.rawValue else {
            return
        }

        CFMachPortInvalidate(rawTap)
    }
}

final class HistoryKeyboardEventTap {
    private enum LifecycleState {
        case stopped
        case active
        case suspended
    }

    private weak var inputState: HistoryWindowInputState?
    private let keyboardRouter = HistoryKeyboardActionRouter()
    private let backend: any HistoryKeyboardEventTapBackend
    private let windowState: HistoryKeyboardEventTapWindowState
    private let inputOwnership: HistoryKeyboardInputOwnershipBox
    private var eventTap: HistoryKeyboardEventTapHandle?
    private var runLoopSource: HistoryKeyboardEventTapRunLoopSource?
    private var lifecycleState: LifecycleState = .stopped

    @MainActor
    convenience init(inputState: HistoryWindowInputState) {
        self.init(
            inputState: inputState,
            backend: SystemHistoryKeyboardEventTapBackend.shared
        )
    }

    @MainActor
    init(
        inputState: HistoryWindowInputState,
        backend: any HistoryKeyboardEventTapBackend,
        inputOwnership: (any HistoryKeyboardInputOwnership)? = nil
    ) {
        let windowState = HistoryKeyboardEventTapWindowState(inputState: inputState)
        self.inputState = inputState
        self.backend = backend
        self.windowState = windowState
        self.inputOwnership = HistoryKeyboardInputOwnershipBox(inputOwnership ?? windowState)
    }

    deinit {
        if lifecycleState == .active,
           let eventTap {
            backend.setEnabled(false, for: eventTap)
        }

        if let runLoopSource {
            backend.removeRunLoopSource(runLoopSource)
        }

        if let eventTap {
            backend.invalidate(eventTap)
        }
    }

    @MainActor
    func setKeyWindow(_ window: NSWindow?) {
        windowState.historyWindow = window
    }

    static func shouldHandleEvent(isWindowPresented: Bool) -> Bool {
        isWindowPresented
    }

    @MainActor
    func start() {
        switch lifecycleState {
        case .active:
            return
        case .suspended:
            if let eventTap {
                backend.setEnabled(true, for: eventTap)
                lifecycleState = .active
                return
            }
        case .stopped:
            break
        }

        let eventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)

        guard let tap = backend.createTap(
            eventMask: CGEventMask(eventMask),
            callback: HistoryKeyboardEventTap.eventCallback,
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        ) else {
            NSLog("ClipEase: failed to install history keyboard event tap")
            return
        }

        guard let source = backend.createRunLoopSource(for: tap) else {
            backend.invalidate(tap)
            return
        }

        eventTap = tap
        runLoopSource = source
        backend.addRunLoopSource(source)
        backend.setEnabled(true, for: tap)
        lifecycleState = .active
    }

    @MainActor
    func suspend() {
        if lifecycleState == .active,
           let eventTap {
            backend.setEnabled(false, for: eventTap)
            lifecycleState = .suspended
        }

        DispatchQueue.main.async { [weak inputState] in
            inputState?.resetTransientState()
        }
    }

    @MainActor
    func stop() {
        if lifecycleState == .active,
           let eventTap {
            backend.setEnabled(false, for: eventTap)
        }

        if let runLoopSource {
            backend.removeRunLoopSource(runLoopSource)
            self.runLoopSource = nil
        }

        if let eventTap {
            backend.invalidate(eventTap)
            self.eventTap = nil
        }

        lifecycleState = .stopped

        DispatchQueue.main.async { [weak inputState] in
            inputState?.resetTransientState()
        }
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if lifecycleState == .active,
               inputState?.isWindowPresentedSnapshot == true,
               let eventTap {
                backend.setEnabled(true, for: eventTap)
            }
            return Unmanaged.passUnretained(event)

        default:
            guard Self.shouldHandleEvent(isWindowPresented: inputState?.isWindowPresentedSnapshot == true),
                  ownsHistoryInput() else {
                setCommandShortcutOverlayVisible(false)
                return Unmanaged.passUnretained(event)
            }
        }

        switch type {
        case .flagsChanged:
            let isCommandPressed = event.flags.contains(.maskCommand)
            setCommandShortcutOverlayVisible(
                isCommandPressed && inputState?.isPreviewActiveSnapshot != true
            )
            return Unmanaged.passUnretained(event)

        case .keyDown:
            let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            if HistoryKeyboardEventPassThroughPolicy.shouldPassThrough(
                keyCode: keyCode,
                flags: event.flags,
                isButtonFirstResponderActive: false
            ) {
                return Unmanaged.passUnretained(event)
            }
            let firstResponderActivity = firstResponderActivity()
            if HistoryKeyboardEventPassThroughPolicy.shouldPassThrough(
                keyCode: keyCode,
                flags: event.flags,
                isButtonFirstResponderActive: firstResponderActivity.isButtonActive
            ) {
                return Unmanaged.passUnretained(event)
            }
            let isTextInputActive = HistoryTextInputActivityPolicy.isTextInputActive(
                stateSnapshot: inputState?.isHistoryTextInputActiveSnapshot == true,
                appTextFirstResponderActive: firstResponderActivity.isTextActive
            )
            let isPreviewActive = inputState?.isPreviewActiveSnapshot == true
            guard let action = Self.action(
                for: event,
                isTextInputActive: isTextInputActive,
                keyboardRouter: keyboardRouter
            ) else {
                return Unmanaged.passUnretained(event)
            }

            if !keyboardRouter.allowsHistoryCommand(
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

            DispatchQueue.main.async { [weak inputState] in
                inputState?.dispatch(action)
            }
            return nil

        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private static func action(
        for event: CGEvent,
        isTextInputActive: Bool,
        keyboardRouter: HistoryKeyboardActionRouter
    ) -> HistoryKeyboardAction? {
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags
        let isCommandPressed = flags.contains(.maskCommand)
        let isShiftPressed = flags.contains(.maskShift)
        let hasTextEditingModifier = flags.contains(.maskCommand) ||
            flags.contains(.maskControl) ||
            flags.contains(.maskAlternate)

        if isTextInputActive {
            return keyboardRouter.actionForTextInput(
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
            guard let pendingTextInput = pendingTextInputEvent(from: event) else {
                return nil
            }
            return HistoryKeyboardTextEntryPolicy.action(
                for: pendingTextInput.characters,
                pendingEvent: pendingTextInput,
                usesMarkedTextInputSource: HistoryKeyboardInputSourcePolicy.usesMarkedTextInputSource()
            )
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
        case .appendSearchText, .beginComposedSearchInput:
            return true
        }
    }

    private static let commaKeyCode: UInt16 = 43

    private func ownsHistoryInput() -> Bool {
        let inputOwnership = inputOwnership
        if Thread.isMainThread {
            return MainActor.assumeIsolated {
                inputOwnership.value.ownsHistoryInput()
            }
        }

        var ownsInput = false
        DispatchQueue.main.sync {
            ownsInput = MainActor.assumeIsolated {
                inputOwnership.value.ownsHistoryInput()
            }
        }
        return ownsInput
    }

    private func setCommandShortcutOverlayVisible(_ isVisible: Bool) {
        let inputState = inputState
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                inputState?.setCommandKeyPressed(isVisible)
            }
            return
        }

        DispatchQueue.main.sync {
            MainActor.assumeIsolated {
                inputState?.setCommandKeyPressed(isVisible)
            }
        }
    }

    private func firstResponderActivity() -> HistoryKeyboardFirstResponderActivity {
        let windowState = windowState
        if Thread.isMainThread {
            return MainActor.assumeIsolated {
                windowState.firstResponderActivity()
            }
        }

        var activity = HistoryKeyboardFirstResponderActivity(
            isTextActive: false,
            isButtonActive: false
        )
        DispatchQueue.main.sync {
            activity = MainActor.assumeIsolated {
                windowState.firstResponderActivity()
            }
        }
        return activity
    }

    private static func pendingTextInputEvent(from event: CGEvent) -> HistoryKeyboardPendingTextInputEvent? {
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
        guard let searchText = HistoryKeyboardCharacterPolicy.searchText(from: text) else {
            return nil
        }

        return HistoryKeyboardPendingTextInputEvent(
            keyCode: UInt16(event.getIntegerValueField(.keyboardEventKeycode)),
            modifierFlags: UInt(event.flags.rawValue),
            characters: searchText
        )
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
