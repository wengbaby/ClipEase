import Foundation
import Testing
@testable import ClipEase

@Test func deleteCommandIsBlockedWhileTextInputIsActive() {
    #expect(!HistoryKeyboardShortcutPolicy.allowsHistoryCommand(
        .delete,
        isTextInputActive: true,
        isPreviewContentActive: false
    ))
}

@Test func deleteCommandIsAllowedWhenNoInputLayerIsActive() {
    #expect(HistoryKeyboardShortcutPolicy.allowsHistoryCommand(
        .delete,
        isTextInputActive: false,
        isPreviewContentActive: false
    ))
}

@Test func cardCommandsAreBlockedWhileTextInputIsActive() {
    for action in [
        HistoryKeyboardAction.moveLeft,
        .moveRight,
        .paste,
        .pastePlainText,
        .togglePreview,
        .close,
        .selectVisibleCard(1),
        .openSearch,
        .showSettings,
        .copy,
        .copyPlainText,
        .delete,
        .togglePinned,
        .edit,
        .closeWindow,
        .createText,
        .toggleRecording,
        .appendSearchText("a")
    ] {
        #expect(!HistoryKeyboardShortcutPolicy.allowsHistoryCommand(
            action,
            isTextInputActive: true,
            isPreviewContentActive: false
        ))
    }
}

@Test func searchFieldExitCommandIsAllowedWhileTextInputIsActive() {
    #expect(HistoryKeyboardShortcutPolicy.allowsHistoryCommand(
        .enterFirstSearchResult,
        isTextInputActive: true,
        isPreviewContentActive: false
    ))
    #expect(HistoryKeyboardShortcutPolicy.allowsHistoryCommand(
        .focusFirstSearchResult,
        isTextInputActive: true,
        isPreviewContentActive: false
    ))
}

@Test func selectedSearchResultIsNotFocusedWhileSearchFieldIsFocused() {
    #expect(!HistoryCardFocusPolicy.isCardFocusActive(
        selectedItemID: UUID(),
        isSearchFieldFocused: true
    ))
}

@Test func selectedSearchResultIsFocusedAfterSearchFieldLosesFocus() {
    #expect(HistoryCardFocusPolicy.isCardFocusActive(
        selectedItemID: UUID(),
        isSearchFieldFocused: false
    ))
}

@Test func escapeClearsSearchBeforeClosingWhenTextExists() {
    #expect(HistorySearchCancelPolicy.action(
        hasSearchContent: true
    ) == .clearSearch)
}

@Test func escapeClosesSearchWhenSearchIsEmpty() {
    #expect(HistorySearchCancelPolicy.action(
        hasSearchContent: false
    ) == .closeSearchAndFocusFirstResult)
}

@Test func initialRailWindowDoesNotFocusRememberedSelectionWithoutPendingJump() {
    let selectedID = UUID()

    #expect(HistoryRailRenderWindowPolicy.focusedID(
        pendingLatestFocusItemID: nil,
        pendingProgrammaticJumpItemID: nil,
        pendingItemScrollID: nil,
        selectedItemID: selectedID,
        visibleRect: .zero
    ) == nil)
}

@Test func initialRailWindowUsesPendingJumpFocus() {
    let pendingID = UUID()

    #expect(HistoryRailRenderWindowPolicy.focusedID(
        pendingLatestFocusItemID: pendingID,
        pendingProgrammaticJumpItemID: nil,
        pendingItemScrollID: nil,
        selectedItemID: UUID(),
        visibleRect: .zero
    ) == pendingID)
}

@Test func initialRailWindowRendersFirstPageWhenVisibleRectIsEmpty() {
    #expect(HistoryRailRenderWindowPolicy.visibleWindow(
        itemCount: 100,
        visibleRect: .zero,
        itemStride: 270,
        horizontalContentPadding: 28,
        bufferItemCount: 6,
        renderedItemLimit: 20
    ) == 0..<20)
}

@Test func staleNarrowRailWindowRendersFullPage() {
    #expect(HistoryRailRenderWindowPolicy.visibleWindow(
        itemCount: 100,
        visibleRect: CGRect(x: 0, y: 0, width: 1, height: 300),
        itemStride: 270,
        horizontalContentPadding: 28,
        bufferItemCount: 6,
        renderedItemLimit: 20
    ) == 0..<20)
}

@Test func scrolledNarrowRailWindowStillRendersFullPageAroundOffset() {
    let window = HistoryRailRenderWindowPolicy.visibleWindow(
        itemCount: 100,
        visibleRect: CGRect(x: 5400, y: 0, width: 1, height: 300),
        itemStride: 270,
        horizontalContentPadding: 28,
        bufferItemCount: 6,
        renderedItemLimit: 20
    )

    #expect(window.count == 20)
    #expect(window.contains(20))
}

@Test func ordinarySelectionDoesNotOverrideVisibleWindow() {
    #expect(HistoryRailRenderWindowPolicy.focusedID(
        pendingLatestFocusItemID: nil,
        pendingProgrammaticJumpItemID: nil,
        pendingItemScrollID: nil,
        selectedItemID: UUID(),
        visibleRect: CGRect(x: 810, y: 0, width: 1080, height: 300)
    ) == nil)
}

@Test func focusedRailWindowIncludesSelectedNeighborBuffer() {
    #expect(HistoryRailRenderWindowPolicy.focusedWindow(
        focusedIndex: 50,
        itemCount: 100,
        renderedItemLimit: 20,
        edgeBufferItemCount: 3
    ) == 37..<57)
}

@Test func activeSearchSelectsFirstResult() {
    let firstID = UUID()
    let previousID = UUID()

    #expect(HistorySearchResultSelectionPolicy.selectedID(
        currentSelectedID: previousID,
        resultIDs: [firstID, previousID],
        isSearchActive: true
    ) == firstID)
}

@Test func activeSearchClearsSelectionWhenEmpty() {
    #expect(HistorySearchResultSelectionPolicy.selectedID(
        currentSelectedID: UUID(),
        resultIDs: [],
        isSearchActive: true
    ) == nil)
}

@Test func inactiveSearchKeepsExistingSelectionWhenStillPresent() {
    let selectedID = UUID()
    let firstID = UUID()

    #expect(HistorySearchResultSelectionPolicy.selectedID(
        currentSelectedID: selectedID,
        resultIDs: [firstID, selectedID],
        isSearchActive: false
    ) == selectedID)
}
