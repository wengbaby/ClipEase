import Combine
import Foundation

enum HistoryKeyboardAction: Equatable {
    case moveLeft
    case moveRight
    case paste
    case pastePlainText
    case togglePreview
    case close
    case selectVisibleCard(Int)
    case openSearch
    case showSettings
    case copy
    case copyPlainText
    case delete
    case togglePinned
    case edit
    case closeWindow
    case createText
    case toggleRecording
    case appendSearchText(String)
    case enterFirstSearchResult
    case focusFirstSearchResult
}

enum HistoryKeyboardShortcutPolicy {
    static func allowsHistoryCommand(
        _ action: HistoryKeyboardAction,
        isTextInputActive: Bool,
        isPreviewContentActive: Bool
    ) -> Bool {
        if isPreviewContentActive {
            return action == .close
        }

        if isTextInputActive {
            switch action {
            case .enterFirstSearchResult, .focusFirstSearchResult:
                return true
            case .moveLeft, .moveRight, .paste, .pastePlainText, .togglePreview, .close, .selectVisibleCard, .openSearch, .showSettings, .copy, .copyPlainText, .delete, .togglePinned, .edit, .closeWindow, .createText, .toggleRecording, .appendSearchText:
                return false
            }
        }

        return true
    }
}

enum HistoryKeyboardInputPolicy {
    static func actionForTextInput(
        keyCode: UInt16,
        hasTextEditingModifier: Bool,
        isShiftPressed: Bool,
        cursorIsAtEnd: Bool
    ) -> HistoryKeyboardAction? {
        guard !hasTextEditingModifier else {
            return nil
        }

        switch keyCode {
        case KeyCode.downArrow, KeyCode.tab:
            return .focusFirstSearchResult
        case KeyCode.rightArrow:
            return cursorIsAtEnd ? .focusFirstSearchResult : nil
        case KeyCode.returnKey, KeyCode.enter:
            return .enterFirstSearchResult
        default:
            return nil
        }
    }
}

enum HistoryCardFocusPolicy {
    static func isCardFocusActive(
        selectedItemID: ClipboardItem.ID?,
        isSearchFieldFocused: Bool,
        searchHasHandedOffFocusToCard: Bool = false
    ) -> Bool {
        selectedItemID != nil && (!isSearchFieldFocused || searchHasHandedOffFocusToCard)
    }
}

struct HistorySearchFocusTransition: Equatable {
    let isSearchFocused: Bool
    let isTextInputFocused: Bool
    let searchHasHandedOffFocusToCard: Bool
    let shouldRefocusSearchField: Bool
}

enum HistorySearchFocusTransitionEvent {
    case searchFieldFocused
    case focusFirstResult
    case searchClosed
}

enum HistorySearchFocusTransitionPolicy {
    static func transition(
        event: HistorySearchFocusTransitionEvent,
        hasSearchResult: Bool,
        isSearchVisible: Bool
    ) -> HistorySearchFocusTransition {
        switch event {
        case .searchFieldFocused:
            return HistorySearchFocusTransition(
                isSearchFocused: true,
                isTextInputFocused: true,
                searchHasHandedOffFocusToCard: false,
                shouldRefocusSearchField: false
            )
        case .focusFirstResult:
            guard hasSearchResult else {
                return HistorySearchFocusTransition(
                    isSearchFocused: isSearchVisible,
                    isTextInputFocused: isSearchVisible,
                    searchHasHandedOffFocusToCard: false,
                    shouldRefocusSearchField: isSearchVisible
                )
            }

            return HistorySearchFocusTransition(
                isSearchFocused: false,
                isTextInputFocused: false,
                searchHasHandedOffFocusToCard: true,
                shouldRefocusSearchField: false
            )
        case .searchClosed:
            return HistorySearchFocusTransition(
                isSearchFocused: false,
                isTextInputFocused: false,
                searchHasHandedOffFocusToCard: false,
                shouldRefocusSearchField: false
            )
        }
    }
}

enum HistorySearchTextFieldFocusPolicy {
    static func shouldRestoreFocusOnKeyEvent(searchHasHandedOffFocusToCard: Bool) -> Bool {
        !searchHasHandedOffFocusToCard
    }
}

enum HistoryPanelSpaceKeyPolicy {
    static func shouldTogglePreview(
        isHistoryTextInputActive: Bool,
        isPreviewActive: Bool
    ) -> Bool {
        !isHistoryTextInputActive && !isPreviewActive
    }
}

enum HistoryTextInputActivityPolicy {
    static func isTextInputActive(
        stateSnapshot: Bool,
        appTextFirstResponderActive: Bool
    ) -> Bool {
        stateSnapshot || appTextFirstResponderActive
    }
}

enum HistoryKeyboardCharacterPolicy {
    static func searchText(from text: String?) -> String? {
        guard let text,
              text.rangeOfCharacter(from: .newlines) == nil,
              text.rangeOfCharacter(from: .controlCharacters) == nil,
              text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
              text.unicodeScalars.contains(where: isAppleFunctionKeyScalar) == false else {
            return nil
        }

        return text
    }

    private static func isAppleFunctionKeyScalar(_ scalar: UnicodeScalar) -> Bool {
        (0xF700...0xF8FF).contains(scalar.value)
    }
}

enum HistoryGroupRenameKeyAction: Equatable {
    case submit
    case cancel
}

enum HistoryGroupRenameKeyPolicy {
    static func action(for keyCode: UInt16) -> HistoryGroupRenameKeyAction? {
        switch keyCode {
        case KeyCode.returnKey, KeyCode.enter:
            .submit
        case KeyCode.escape:
            .cancel
        default:
            nil
        }
    }
}

enum HistoryGroupRenameActionPolicy {
    enum Action: Equatable {
        case submit
        case cancel
        case consume
    }

    static func action(for keyboardAction: HistoryKeyboardAction) -> Action {
        switch keyboardAction {
        case .enterFirstSearchResult:
            .submit
        case .close:
            .cancel
        case .moveLeft, .moveRight, .paste, .pastePlainText, .togglePreview, .selectVisibleCard, .openSearch, .showSettings, .copy, .copyPlainText, .delete, .togglePinned, .edit, .closeWindow, .createText, .toggleRecording, .appendSearchText, .focusFirstSearchResult:
            .consume
        }
    }
}

enum PersistentPopoverInitialShowPolicy {
    static func shouldScheduleDeferredInitialShow(
        isPresented: Bool,
        isPopoverShown: Bool,
        isShowScheduled: Bool
    ) -> Bool {
        isPresented && !isPopoverShown && !isShowScheduled
    }
}

enum PersistentPopoverContentSizePolicy {
    static func shouldApply(_ size: CGSize) -> Bool {
        size.width > 0 && size.height > 0
    }
}

enum HistoryGroupAppearanceEventWindowRole {
    case hostWindow
    case popover
    case colorPanel
    case outsideApp
}

enum HistoryGroupAppearanceOutsideClickPolicy {
    static func shouldClose(
        isEnabled: Bool,
        eventWindowRole: HistoryGroupAppearanceEventWindowRole
    ) -> Bool {
        guard isEnabled else {
            return false
        }

        switch eventWindowRole {
        case .hostWindow, .outsideApp:
            return true
        case .popover, .colorPanel:
            return false
        }
    }
}

enum HistorySearchCancelPolicy {
    enum Action: Equatable {
        case clearSearch
        case closeSearchAndFocusFirstResult
    }

    static func action(hasSearchContent: Bool) -> Action {
        hasSearchContent ? .clearSearch : .closeSearchAndFocusFirstResult
    }
}

enum HistoryPreviewFollowPolicy {
    static let retryDelaysNanoseconds: [UInt64] = [
        16_000_000,
        33_000_000,
        66_000_000
    ]
}

enum HistorySearchResultSelectionPolicy {
    static func selectedID(
        currentSelectedID: ClipboardItem.ID?,
        resultIDs: [ClipboardItem.ID],
        isSearchActive: Bool
    ) -> ClipboardItem.ID? {
        if isSearchActive {
            return resultIDs.first
        }

        if let currentSelectedID,
           resultIDs.contains(currentSelectedID) {
            return currentSelectedID
        }

        return resultIDs.first
    }
}

struct HistoryKeyboardRequest: Equatable {
    let id = UUID()
    let action: HistoryKeyboardAction
}

struct HistoryItemFocusRequest: Equatable {
    let id = UUID()
    let itemID: ClipboardItem.ID
    let resetToAll: Bool
}

final class HistoryWindowInputState: ObservableObject, @unchecked Sendable {
    @MainActor static weak var currentForTextEditing: HistoryWindowInputState?

    @Published private(set) var isCommandKeyPressed = false
    @Published private(set) var request: HistoryKeyboardRequest?
    @Published private(set) var itemFocusRequest: HistoryItemFocusRequest?
    @Published private(set) var windowHideRequestID = UUID()
    @Published private(set) var isWindowVisible = false
    @Published private(set) var isWindowPresented = false
    @Published private(set) var isPreviewContentActive = false
    @Published private(set) var isWindowPinnedOpen = false

    private let lock = NSLock()
    private var textInputFocused = false
    private var searchVisible = false
    private var windowVisible = false
    private var windowPresented = false
    private var windowPinnedOpen = false
    private var presentedInputLayerActive = false
    private var appTextFirstResponderActive = false
    private var previewActive = false
    private var previewKeyWindowActive = false
    private var searchHasHandedOffFocusToCard = false

    var isTextInputFocusedSnapshot: Bool {
        lock.lock()
        defer { lock.unlock() }
        return textInputFocused
    }

    var isHistoryTextInputActiveSnapshot: Bool {
        lock.lock()
        defer { lock.unlock() }
        return HistoryTextInputActivityPolicy.isTextInputActive(
            stateSnapshot: textInputFocused && !searchHasHandedOffFocusToCard,
            appTextFirstResponderActive: appTextFirstResponderActive
        )
    }

    var isAnyTextInputActiveSnapshot: Bool {
        lock.lock()
        defer { lock.unlock() }
        return textInputFocused || appTextFirstResponderActive || presentedInputLayerActive
    }

    var isSearchVisibleSnapshot: Bool {
        lock.lock()
        defer { lock.unlock() }
        return searchVisible
    }

    var isWindowVisibleSnapshot: Bool {
        lock.lock()
        defer { lock.unlock() }
        return windowVisible
    }

    var isWindowPresentedSnapshot: Bool {
        lock.lock()
        defer { lock.unlock() }
        return windowPresented
    }

    var isWindowPinnedOpenSnapshot: Bool {
        lock.lock()
        defer { lock.unlock() }
        return windowPinnedOpen
    }

    var shouldSuppressHistoryCommandShortcutsSnapshot: Bool {
        lock.lock()
        defer { lock.unlock() }
        return (textInputFocused && !searchHasHandedOffFocusToCard) || presentedInputLayerActive
    }

    var isPreviewActiveSnapshot: Bool {
        lock.lock()
        defer { lock.unlock() }
        return previewActive && previewKeyWindowActive
    }

    func dispatch(_ action: HistoryKeyboardAction) {
        request = HistoryKeyboardRequest(action: action)
    }

    func requestItemFocus(_ itemID: ClipboardItem.ID, resetToAll: Bool) {
        itemFocusRequest = HistoryItemFocusRequest(itemID: itemID, resetToAll: resetToAll)
    }

    func notifyWindowWillHide() {
        setWindowPresented(false)
        setWindowVisible(false)
        windowHideRequestID = UUID()
    }

    func requestWindowHideCleanup() {
        windowHideRequestID = UUID()
    }

    func setCommandKeyPressed(_ isPressed: Bool) {
        guard isCommandKeyPressed != isPressed else {
            return
        }

        isCommandKeyPressed = isPressed
    }

    func setTextInputFocused(_ isFocused: Bool) {
        lock.lock()
        textInputFocused = isFocused
        if isFocused {
            searchHasHandedOffFocusToCard = false
        }
        lock.unlock()
    }

    func setSearchHasHandedOffFocusToCard(_ hasHandedOff: Bool) {
        lock.lock()
        searchHasHandedOffFocusToCard = hasHandedOff
        lock.unlock()
    }

    func setSearchVisible(_ isVisible: Bool) {
        lock.lock()
        searchVisible = isVisible
        lock.unlock()
    }

    func setWindowVisible(_ isVisible: Bool) {
        lock.lock()
        windowVisible = isVisible
        lock.unlock()

        if isWindowVisible != isVisible {
            isWindowVisible = isVisible
        }
    }

    func setWindowPresented(_ isPresented: Bool) {
        lock.lock()
        windowPresented = isPresented
        lock.unlock()

        if isWindowPresented != isPresented {
            isWindowPresented = isPresented
        }
    }

    func setWindowPinnedOpen(_ isPinned: Bool) {
        lock.lock()
        windowPinnedOpen = isPinned
        lock.unlock()

        if isWindowPinnedOpen != isPinned {
            isWindowPinnedOpen = isPinned
        }
    }

    func toggleWindowPinnedOpen() {
        setWindowPinnedOpen(!isWindowPinnedOpen)
    }

    func setPresentedInputLayerActive(_ isActive: Bool) {
        lock.lock()
        presentedInputLayerActive = isActive
        lock.unlock()
    }

    func setAppTextFirstResponderActive(_ isActive: Bool) {
        lock.lock()
        appTextFirstResponderActive = isActive
        lock.unlock()
    }

    func setPreviewActive(_ isActive: Bool) {
        lock.lock()
        previewActive = isActive
        lock.unlock()
    }

    func setPreviewKeyWindowActive(_ isActive: Bool) {
        lock.lock()
        previewKeyWindowActive = isActive
        let nextPreviewContentActive = previewActive && previewKeyWindowActive
        lock.unlock()

        if isPreviewContentActive != nextPreviewContentActive {
            isPreviewContentActive = nextPreviewContentActive
        }
    }

    func resetTransientState() {
        setCommandKeyPressed(false)
        setTextInputFocused(false)
        setSearchVisible(false)
        setWindowVisible(false)
        setWindowPresented(false)
        setWindowPinnedOpen(false)
        setPresentedInputLayerActive(false)
        setAppTextFirstResponderActive(false)
        setPreviewActive(false)
        setPreviewKeyWindowActive(false)
        if isPreviewContentActive {
            isPreviewContentActive = false
        }
    }
}
