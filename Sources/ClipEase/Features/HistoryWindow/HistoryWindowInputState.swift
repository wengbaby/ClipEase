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

enum HistoryCardFocusPolicy {
    static func isCardFocusActive(
        selectedItemID: ClipboardItem.ID?,
        isSearchFieldFocused: Bool
    ) -> Bool {
        selectedItemID != nil && !isSearchFieldFocused
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

enum HistoryRailRenderWindowPolicy {
    static func focusedID(
        pendingLatestFocusItemID: ClipboardItem.ID?,
        pendingProgrammaticJumpItemID: ClipboardItem.ID?,
        pendingItemScrollID: ClipboardItem.ID?,
        selectedItemID: ClipboardItem.ID?,
        visibleRect: CGRect
    ) -> ClipboardItem.ID? {
        if let pendingLatestFocusItemID {
            return pendingLatestFocusItemID
        }
        if let pendingProgrammaticJumpItemID {
            return pendingProgrammaticJumpItemID
        }
        if let pendingItemScrollID {
            return pendingItemScrollID
        }
        return nil
    }

    static func visibleWindow(
        itemCount: Int,
        visibleRect: CGRect,
        hasReliableVisibleRect: Bool = true,
        itemStride: CGFloat,
        horizontalContentPadding: CGFloat,
        bufferItemCount: Int,
        renderedItemLimit: Int
    ) -> Range<Int> {
        guard itemCount > 0 else {
            return 0..<0
        }

        guard hasReliableVisibleRect else {
            return 0..<min(itemCount, renderedItemLimit)
        }

        guard visibleRect.width > 0, itemStride > 0 else {
            return 0..<min(itemCount, renderedItemLimit)
        }

        let visibleMinX = max(visibleRect.minX - horizontalContentPadding, 0)
        guard visibleRect.width >= itemStride else {
            let centerIndex = min(max(Int(floor(visibleMinX / itemStride)), 0), itemCount - 1)
            let start = min(
                max(0, centerIndex - renderedItemLimit / 2),
                max(0, itemCount - renderedItemLimit)
            )
            let end = min(itemCount, start + renderedItemLimit)
            return start..<end
        }

        let visibleMaxX = max(visibleRect.maxX - horizontalContentPadding, visibleMinX)
        let rawStart = Int(floor(visibleMinX / itemStride)) - bufferItemCount
        let rawEnd = Int(ceil(visibleMaxX / itemStride)) + bufferItemCount + 1
        let clampedStart = min(max(0, rawStart), max(itemCount - 1, 0))
        let clampedEnd = min(itemCount, max(clampedStart + 1, rawEnd))
        guard clampedEnd - clampedStart > renderedItemLimit else {
            return clampedStart..<clampedEnd
        }

        let visibleCenter = (visibleMinX + visibleMaxX) / 2
        let centerIndex = min(max(Int(floor(visibleCenter / itemStride)), 0), itemCount - 1)
        let limitedStart = min(
            max(0, centerIndex - renderedItemLimit / 2),
            max(0, itemCount - renderedItemLimit)
        )
        let limitedEnd = min(itemCount, limitedStart + renderedItemLimit)
        return limitedStart..<limitedEnd
    }

    static func focusedWindow(
        focusedIndex: Int,
        itemCount: Int,
        renderedItemLimit: Int,
        edgeBufferItemCount: Int
    ) -> Range<Int> {
        guard itemCount > 0 else {
            return 0..<0
        }

        let clampedIndex = min(max(focusedIndex, 0), itemCount - 1)
        let start = min(
            max(0, clampedIndex - renderedItemLimit / 2 - edgeBufferItemCount),
            max(0, itemCount - renderedItemLimit)
        )
        let end = min(itemCount, start + renderedItemLimit)
        return start..<max(start + 1, end)
    }
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
