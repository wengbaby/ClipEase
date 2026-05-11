import Combine
import Foundation

enum HistoryKeyboardAction: Equatable {
    case moveLeft
    case moveRight
    case paste
    case togglePreview
    case close
    case selectVisibleCard(Int)
    case openSearch
    case copy
    case delete
    case togglePinned
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

final class HistoryWindowInputState: ObservableObject, @unchecked Sendable {
    @Published private(set) var isCommandKeyPressed = false
    @Published private(set) var request: HistoryKeyboardRequest?

    private let lock = NSLock()
    private var textInputFocused = false
    private var searchVisible = false

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

    func dispatch(_ action: HistoryKeyboardAction) {
        request = HistoryKeyboardRequest(action: action)
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

    func resetTransientState() {
        setCommandKeyPressed(false)
        setTextInputFocused(false)
        setSearchVisible(false)
    }
}
