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
    private var previewActive = false
    private var previewKeyWindowActive = false

    var isTextInputFocusedSnapshot: Bool {
        lock.lock()
        defer { lock.unlock() }
        return textInputFocused
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
        return textInputFocused || presentedInputLayerActive
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

    func setCommandKeyPressed(_ isPressed: Bool) {
        guard isCommandKeyPressed != isPressed else {
            return
        }

        isCommandKeyPressed = isPressed
    }

    func setTextInputFocused(_ isFocused: Bool) {
        lock.lock()
        textInputFocused = isFocused
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
        setPreviewActive(false)
        setPreviewKeyWindowActive(false)
        if isPreviewContentActive {
            isPreviewContentActive = false
        }
    }
}
