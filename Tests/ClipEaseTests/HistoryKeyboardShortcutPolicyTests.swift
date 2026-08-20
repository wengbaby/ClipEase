import Foundation
import Testing
@testable import ClipEase

private final class LockedNotificationCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
}

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

@Test func shortcutOverlayIsHiddenWhileTextInputIsActive() {
    #expect(!HistoryShortcutOverlayPolicy.isVisible(
        isCommandKeyPressed: true,
        isInputCommandKeyPressed: false,
        isTextInputActive: true,
        isPreviewContentActive: false
    ))
    #expect(!HistoryShortcutOverlayPolicy.isVisible(
        isCommandKeyPressed: false,
        isInputCommandKeyPressed: true,
        isTextInputActive: true,
        isPreviewContentActive: false
    ))
}

@Test func shortcutOverlayIsVisibleOnlyForCommandOutsideInputLayers() {
    #expect(HistoryShortcutOverlayPolicy.isVisible(
        isCommandKeyPressed: true,
        isInputCommandKeyPressed: false,
        isTextInputActive: false,
        isPreviewContentActive: false
    ))
    #expect(!HistoryShortcutOverlayPolicy.isVisible(
        isCommandKeyPressed: false,
        isInputCommandKeyPressed: false,
        isTextInputActive: false,
        isPreviewContentActive: false
    ))
    #expect(!HistoryShortcutOverlayPolicy.isVisible(
        isCommandKeyPressed: true,
        isInputCommandKeyPressed: false,
        isTextInputActive: false,
        isPreviewContentActive: true
    ))
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

@Test func copyCommandsAreBlockedWhileSearchFieldIsFocused() {
    #expect(!HistoryKeyboardShortcutPolicy.allowsHistoryCommand(
        .copy,
        isTextInputActive: true,
        isPreviewContentActive: false
    ))
    #expect(!HistoryKeyboardShortcutPolicy.allowsHistoryCommand(
        .copyPlainText,
        isTextInputActive: true,
        isPreviewContentActive: false
    ))
}

@Test func searchFieldCommandShortcutsStayInTextField() {
    for keyCode in [KeyCode.a, KeyCode.c, KeyCode.v, KeyCode.x] {
        #expect(HistoryKeyboardInputPolicy.actionForTextInput(
            keyCode: keyCode,
            hasTextEditingModifier: true,
            isShiftPressed: false,
            cursorIsAtEnd: true
        ) == nil)
    }
}

@Test func searchFieldExitKeysCanFocusFirstResult() {
    #expect(HistoryKeyboardInputPolicy.actionForTextInput(
        keyCode: KeyCode.downArrow,
        hasTextEditingModifier: false,
        isShiftPressed: false,
        cursorIsAtEnd: false
    ) == .focusFirstSearchResult)
    #expect(HistoryKeyboardInputPolicy.actionForTextInput(
        keyCode: KeyCode.returnKey,
        hasTextEditingModifier: false,
        isShiftPressed: false,
        cursorIsAtEnd: false
    ) == .enterFirstSearchResult)
    #expect(HistoryKeyboardInputPolicy.actionForTextInput(
        keyCode: KeyCode.tab,
        hasTextEditingModifier: false,
        isShiftPressed: false,
        cursorIsAtEnd: false
    ) == .focusFirstSearchResult)
}

@Test func searchFieldHandoffToFirstResultClearsTextFirstResponder() {
    #expect(HistorySearchTextFirstResponderHandoffPolicy.shouldClearTextFirstResponder(
        isSearchFocused: true,
        isTextInputFocused: true,
        hasSearchResult: true
    ))
    #expect(HistorySearchTextFirstResponderHandoffPolicy.shouldClearTextFirstResponder(
        isSearchFocused: false,
        isTextInputFocused: true,
        hasSearchResult: true
    ))
    #expect(!HistorySearchTextFirstResponderHandoffPolicy.shouldClearTextFirstResponder(
        isSearchFocused: true,
        isTextInputFocused: true,
        hasSearchResult: false
    ))
}

@Test func searchFieldRightArrowOnlyExitsAtEnd() {
    #expect(HistoryKeyboardInputPolicy.actionForTextInput(
        keyCode: KeyCode.rightArrow,
        hasTextEditingModifier: false,
        isShiftPressed: false,
        cursorIsAtEnd: false
    ) == nil)
    #expect(HistoryKeyboardInputPolicy.actionForTextInput(
        keyCode: KeyCode.rightArrow,
        hasTextEditingModifier: false,
        isShiftPressed: false,
        cursorIsAtEnd: true
    ) == .focusFirstSearchResult)
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

@Test func selectedSearchResultIsFocusedAfterSearchFieldHandsOffToCard() {
    #expect(HistoryCardFocusPolicy.isCardFocusActive(
        selectedItemID: UUID(),
        isSearchFieldFocused: true,
        searchHasHandedOffFocusToCard: true
    ))
}

@Test func searchFocusTransitionRefocusesTextFieldAndClearsCardHandoff() {
    #expect(HistorySearchFocusTransitionPolicy.transition(
        event: .searchFieldFocused,
        hasSearchResult: true,
        isSearchVisible: true
    ) == HistorySearchFocusTransition(
        isSearchFocused: true,
        isTextInputFocused: true,
        searchHasHandedOffFocusToCard: false,
        shouldRefocusSearchField: false
    ))
}

@Test func searchFocusTransitionHandsOffToFirstCardWhenResultExists() {
    #expect(HistorySearchFocusTransitionPolicy.transition(
        event: .focusFirstResult,
        hasSearchResult: true,
        isSearchVisible: true
    ) == HistorySearchFocusTransition(
        isSearchFocused: false,
        isTextInputFocused: false,
        searchHasHandedOffFocusToCard: true,
        shouldRefocusSearchField: false
    ))
}

@Test func searchFocusTransitionKeepsSearchFieldFocusedWhenNoResultExists() {
    #expect(HistorySearchFocusTransitionPolicy.transition(
        event: .focusFirstResult,
        hasSearchResult: false,
        isSearchVisible: true
    ) == HistorySearchFocusTransition(
        isSearchFocused: true,
        isTextInputFocused: true,
        searchHasHandedOffFocusToCard: false,
        shouldRefocusSearchField: true
    ))
}

@Test func searchFocusTransitionClearsFocusWhenSearchCloses() {
    #expect(HistorySearchFocusTransitionPolicy.transition(
        event: .searchClosed,
        hasSearchResult: true,
        isSearchVisible: false
    ) == HistorySearchFocusTransition(
        isSearchFocused: false,
        isTextInputFocused: false,
        searchHasHandedOffFocusToCard: false,
        shouldRefocusSearchField: false
    ))
}

@Test func searchTextFieldDoesNotRestoreFocusAfterHandingOffToCard() {
    #expect(!HistorySearchTextFieldFocusPolicy.shouldRestoreFocusOnKeyEvent(
        searchHasHandedOffFocusToCard: true
    ))
    #expect(HistorySearchTextFieldFocusPolicy.shouldRestoreFocusOnKeyEvent(
        searchHasHandedOffFocusToCard: false
    ))
}

@Test func panelSpaceKeyTogglesPreviewAfterSearchHandsOffToCard() {
    #expect(HistoryPanelSpaceKeyPolicy.shouldTogglePreview(
        isHistoryTextInputActive: false,
        isPreviewActive: false
    ))
    #expect(!HistoryPanelSpaceKeyPolicy.shouldTogglePreview(
        isHistoryTextInputActive: true,
        isPreviewActive: false
    ))
    #expect(!HistoryPanelSpaceKeyPolicy.shouldTogglePreview(
        isHistoryTextInputActive: false,
        isPreviewActive: true
    ))
}

@Test func actualTextFirstResponderKeepsHistoryCommandsInTextInputMode() {
    #expect(HistoryTextInputActivityPolicy.isTextInputActive(
        stateSnapshot: false,
        appTextFirstResponderActive: true
    ))
    #expect(HistoryTextInputActivityPolicy.isTextInputActive(
        stateSnapshot: false,
        appTextFirstResponderActive: true
    ))
    #expect(!HistoryKeyboardShortcutPolicy.allowsHistoryCommand(
        .delete,
        isTextInputActive: HistoryTextInputActivityPolicy.isTextInputActive(
            stateSnapshot: false,
            appTextFirstResponderActive: true
        ),
        isPreviewContentActive: false
    ))
}

@Test @MainActor func searchFieldRefocusClearsCardHandoffForDeleteRouting() {
    let inputState = HistoryWindowInputState()
    inputState.setTextInputFocused(true)
    inputState.setSearchHasHandedOffFocusToCard(true)

    #expect(!inputState.isHistoryTextInputActiveSnapshot)

    inputState.setTextInputFocused(true)

    #expect(inputState.isHistoryTextInputActiveSnapshot)
    #expect(!HistoryKeyboardShortcutPolicy.allowsHistoryCommand(
        .delete,
        isTextInputActive: inputState.isHistoryTextInputActiveSnapshot,
        isPreviewContentActive: false
    ))
}

@Test @MainActor func anyTextInputSnapshotBlocksDeleteFallbackActions() {
    let inputState = HistoryWindowInputState()
    inputState.setAppTextFirstResponderActive(true)

    #expect(inputState.isAnyTextInputActiveSnapshot)

    inputState.setAppTextFirstResponderActive(false)
    inputState.setPresentedInputLayerActive(true)

    #expect(inputState.isAnyTextInputActiveSnapshot)
}

@Test func printableCharactersCanOpenSearchFromPanelFallback() {
    #expect(HistoryKeyboardCharacterPolicy.searchText(from: "a") == "a")
    #expect(HistoryKeyboardCharacterPolicy.searchText(from: "中") == "中")
    #expect(HistoryKeyboardCharacterPolicy.searchText(from: "\t") == nil)
    #expect(HistoryKeyboardCharacterPolicy.searchText(from: " ") == nil)
}

@Test func appleFunctionKeyPrivateCharactersDoNotOpenSearch() {
    #expect(HistoryKeyboardCharacterPolicy.searchText(from: "\u{F700}") == nil)
    #expect(HistoryKeyboardCharacterPolicy.searchText(from: "\u{F701}") == nil)
    #expect(HistoryKeyboardCharacterPolicy.searchText(from: "\u{F702}") == nil)
    #expect(HistoryKeyboardCharacterPolicy.searchText(from: "\u{F703}") == nil)
}

@Test func markedTextInputSourceOpensSearchWithoutAppendingFirstRomanKey() {
    #expect(HistoryKeyboardTextEntryPolicy.action(
        for: "w",
        usesMarkedTextInputSource: true
    ) == .beginComposedSearchInput(HistoryKeyboardPendingTextInputEvent(
        keyCode: 0,
        modifierFlags: 0,
        characters: "w"
    )))
    #expect(HistoryKeyboardTextEntryPolicy.action(
        for: "w",
        usesMarkedTextInputSource: false
    ) == .appendSearchText("w"))
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

@Test func staleUnboundRailWindowRendersFirstPage() {
    #expect(HistoryRailRenderWindowPolicy.visibleWindow(
        itemCount: 100,
        visibleRect: CGRect(x: 5400, y: 0, width: 1080, height: 300),
        hasReliableVisibleRect: false,
        itemStride: 270,
        horizontalContentPadding: 28,
        bufferItemCount: 6,
        renderedItemLimit: 20
    ) == 0..<20)
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

@Test func railViewportContextKeepsVisibleWindowWhenFocusIsAlreadyVisible() {
    let context = HistoryRailViewportContext(
        itemCount: 100,
        visibleRect: CGRect(x: 5400, y: 0, width: 1080, height: 300),
        hasReliableVisibleRect: true,
        itemStride: 270,
        horizontalContentPadding: 28,
        bufferItemCount: 6,
        renderedItemLimit: 20,
        edgeBufferItemCount: 3
    )

    let visibleWindow = context.visibleWindow(focusedIndex: nil)

    #expect(visibleWindow.contains(20))
    #expect(context.visibleWindow(focusedIndex: 20) == visibleWindow)
}

@Test func railViewportContextUsesFocusedWindowWhenFocusLeavesVisibleWindow() {
    let context = HistoryRailViewportContext(
        itemCount: 100,
        visibleRect: CGRect(x: 5400, y: 0, width: 1080, height: 300),
        hasReliableVisibleRect: true,
        itemStride: 270,
        horizontalContentPadding: 28,
        bufferItemCount: 6,
        renderedItemLimit: 20,
        edgeBufferItemCount: 3
    )

    #expect(context.visibleWindow(focusedIndex: 50) == 37..<57)
}

@Test func railViewportContextCanForceFirstPageForSearchReset() {
    let context = HistoryRailViewportContext(
        itemCount: 100,
        visibleRect: CGRect(x: 5400, y: 0, width: 1080, height: 300),
        hasReliableVisibleRect: true,
        itemStride: 270,
        horizontalContentPadding: 28,
        bufferItemCount: 6,
        renderedItemLimit: 20,
        edgeBufferItemCount: 3,
        mode: .firstPage
    )

    #expect(context.visibleWindow(focusedIndex: 50) == 0..<20)
}

@Test func railViewportContextUsesVisibleRectAfterFocusedJumpSettles() {
    let context = HistoryRailViewportContext(
        itemCount: 100,
        visibleRect: CGRect(x: 5400, y: 0, width: 1080, height: 300),
        hasReliableVisibleRect: true,
        itemStride: 270,
        horizontalContentPadding: 28,
        bufferItemCount: 6,
        renderedItemLimit: 20,
        edgeBufferItemCount: 3,
        mode: .visibleArea
    )

    let window = context.visibleWindow(focusedIndex: 50)

    #expect(window.count <= 20)
    #expect(window.contains(20))
}

@Test func previewCacheRetentionUsesFirstPageWhenRailHasNoMeasuredViewport() {
    #expect(HistoryPreviewCacheRetentionPolicy.retainedWindow(
        itemCount: 100,
        visibleRect: .zero,
        hasReliableVisibleRect: false,
        itemStride: 270,
        horizontalContentPadding: 28,
        retainedItemCount: 20,
        renderedItemLimit: 20
    ) == 0..<20)
}

@Test func previewCacheRetentionUsesVisibleViewportWhenRailIsBound() {
    let window = HistoryPreviewCacheRetentionPolicy.retainedWindow(
        itemCount: 100,
        visibleRect: CGRect(x: 5400, y: 0, width: 1080, height: 300),
        hasReliableVisibleRect: true,
        itemStride: 270,
        horizontalContentPadding: 28,
        retainedItemCount: 20,
        renderedItemLimit: 20
    )

    #expect(window.count <= 20)
    #expect(window.contains(20))
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

@Test func ordinarySelectionRestoreWaitsForPendingPastedFocus() {
    #expect(!HistoryOrdinarySelectionRestorePolicy.canRestore(
        hasPendingLatestFocus: false,
        hasPendingDefaultFocus: true,
        hasPendingPastedFocus: true
    ))
    #expect(!HistoryOrdinarySelectionRestorePolicy.canRestore(
        hasPendingLatestFocus: false,
        hasPendingDefaultFocus: false,
        hasPendingPastedFocus: true
    ))
    #expect(HistoryOrdinarySelectionRestorePolicy.canRestore(
        hasPendingLatestFocus: false,
        hasPendingDefaultFocus: false,
        hasPendingPastedFocus: false
    ))
}

@Test func selectionRecoveryPrefersPastedItemAfterMarkUsedReordersHistory() {
    let firstID = UUID()
    let pastedID = UUID()
    let rememberedID = UUID()
    let existingIDs: Set<UUID> = [pastedID, rememberedID, firstID]

    #expect(HistorySelectionRecoveryPolicy.selectedID(
        pendingPastedID: pastedID,
        preferredID: rememberedID,
        rememberedID: rememberedID,
        firstID: firstID,
        containsID: { existingIDs.contains($0) }
    ) == pastedID)
}

@Test func selectionRecoveryFallsBackWhenPastedItemNoLongerExists() {
    let firstID = UUID()
    let pastedID = UUID()
    let rememberedID = UUID()
    let existingIDs: Set<UUID> = [rememberedID, firstID]

    #expect(HistorySelectionRecoveryPolicy.selectedID(
        pendingPastedID: pastedID,
        preferredID: rememberedID,
        rememberedID: rememberedID,
        firstID: firstID,
        containsID: { existingIDs.contains($0) }
    ) == rememberedID)
}

@Test func rememberedViewportRestoreWaitsForPastedFocusRequest() {
    #expect(!HistoryRememberedViewportRestorePolicy.canRestore(
        didRestoreRememberedViewport: false,
        hasPendingLatestFocus: false,
        hasPendingDefaultFocus: false,
        hasPendingPastedFocus: true,
        hasRememberedSelection: true
    ))
}

@Test func rememberedViewportRestoreDoesNotOverrideExplicitDefaultFocus() {
    #expect(!HistoryRememberedViewportRestorePolicy.canRestore(
        didRestoreRememberedViewport: true,
        hasPendingLatestFocus: false,
        hasPendingDefaultFocus: false,
        hasPendingPastedFocus: false,
        hasRememberedSelection: true
    ))
}

@Test func rememberedViewportRestoreRequiresRememberedSelectionAndNoPendingFocus() {
    #expect(HistoryRememberedViewportRestorePolicy.canRestore(
        didRestoreRememberedViewport: false,
        hasPendingLatestFocus: false,
        hasPendingDefaultFocus: false,
        hasPendingPastedFocus: false,
        hasRememberedSelection: true
    ))
    #expect(!HistoryRememberedViewportRestorePolicy.canRestore(
        didRestoreRememberedViewport: false,
        hasPendingLatestFocus: false,
        hasPendingDefaultFocus: false,
        hasPendingPastedFocus: false,
        hasRememberedSelection: false
    ))
}

@Test func previewFollowRetriesAcrossMultipleLayoutPasses() {
    #expect(HistoryPreviewFollowPolicy.retryDelaysNanoseconds.count >= 3)
    #expect(HistoryPreviewFollowPolicy.retryDelaysNanoseconds.allSatisfy { $0 > 0 })
}

@Test func defaultSelectionPrefersFirstPinnedItemWithoutReordering() {
    let first = UUID()
    let pinned = UUID()
    let last = UUID()

    #expect(HistoryDefaultSelectionPolicy.selectedID(
        pinnedIDs: [pinned],
        orderedIDs: [first, pinned, last]
    ) == pinned)
    #expect(HistoryDefaultSelectionPolicy.selectedID(
        pinnedIDs: [],
        orderedIDs: [first, pinned, last]
    ) == first)
}

@Test func previewPlacementUpdatesArrowWhenWindowIsPinnedByScreenEdge() {
    let screenFrame = CGRect(x: 0, y: 0, width: 900, height: 700)
    let size = CGSize(width: 390, height: 260)
    let first = HistoryPreviewPlacementPolicy.placement(
        anchorScreenPoint: CGPoint(x: 760, y: 250),
        screenFrame: screenFrame,
        size: size
    )
    let second = HistoryPreviewPlacementPolicy.placement(
        anchorScreenPoint: CGPoint(x: 820, y: 250),
        screenFrame: screenFrame,
        size: size
    )

    #expect(first.frame.minX == second.frame.minX)
    #expect(first.arrowX != second.arrowX)
    #expect(second.arrowX > first.arrowX)
}

@Test func detachedPreviewFrameRemovesArrowHeightAndKeepsTopEdge() {
    let attachedFrame = CGRect(x: 120, y: 180, width: 390, height: 274)
    let detachedFrame = HistoryPreviewDetachedFramePolicy.frame(
        for: CGSize(width: 390, height: 260),
        keepingTopEdgeFrom: attachedFrame
    )

    #expect(detachedFrame.height == 260)
    #expect(detachedFrame.maxY == attachedFrame.maxY)
}

@Test func previewFallbackFrameTracksDocumentPositionAndScrollOffset() {
    let frame = HistoryPreviewFramePolicy.fallbackViewportFrame(
        documentFrame: CGRect(x: 540, y: 0, width: 250, height: 270),
        currentOffset: 270,
        cardRailTopInWindow: 68,
        selectedCardTopContentInset: 6
    )

    #expect(frame == CGRect(x: 270, y: 74, width: 250, height: 270))
}

@Test func previewViewportFramePrefersMeasuredFrameWhenValid() {
    let measuredFrame = CGRect(x: 120, y: 74, width: 250, height: 270)
    let frame = HistoryPreviewFramePolicy.viewportFrame(
        measuredFrame: measuredFrame,
        documentFrame: CGRect(x: 540, y: 0, width: 250, height: 270),
        currentOffset: 270,
        cardRailTopInWindow: 68,
        selectedCardTopContentInset: 6
    )

    #expect(frame == measuredFrame)
}

@Test func previewViewportFrameFallsBackWhenMeasuredFrameIsEmpty() {
    let frame = HistoryPreviewFramePolicy.viewportFrame(
        measuredFrame: CGRect(x: 120, y: 74, width: 0, height: 0),
        documentFrame: CGRect(x: 540, y: 0, width: 250, height: 270),
        currentOffset: 270,
        cardRailTopInWindow: 68,
        selectedCardTopContentInset: 6
    )

    #expect(frame == CGRect(x: 270, y: 74, width: 250, height: 270))
}

@Test func previewViewportFrameReturnsNilWhenNoValidAnchorExists() {
    let frame = HistoryPreviewFramePolicy.viewportFrame(
        measuredFrame: CGRect(x: 120, y: 74, width: 0, height: 0),
        documentFrame: nil,
        currentOffset: 270,
        cardRailTopInWindow: 68,
        selectedCardTopContentInset: 6
    )

    #expect(frame == nil)
}

@Test func groupRenameKeyPolicySubmitsOnReturnOrEnter() {
    #expect(HistoryGroupRenameKeyPolicy.action(for: KeyCode.returnKey) == .submit)
    #expect(HistoryGroupRenameKeyPolicy.action(for: KeyCode.enter) == .submit)
    #expect(HistoryGroupRenameKeyPolicy.action(for: KeyCode.escape) == .cancel)
    #expect(HistoryGroupRenameKeyPolicy.action(for: KeyCode.a) == nil)
}

@Test func groupRenameActionPolicySubmitsWhenGlobalEnterActionArrives() {
    #expect(HistoryGroupRenameActionPolicy.action(for: .enterFirstSearchResult) == .submit)
    #expect(HistoryGroupRenameActionPolicy.action(for: .close) == .cancel)
    #expect(HistoryGroupRenameActionPolicy.action(for: .delete) == .consume)
}

@Test func persistentPopoverInitialShowIsDeferredUntilAnchorSettles() {
    #expect(PersistentPopoverInitialShowPolicy.shouldScheduleDeferredInitialShow(
        isPresented: true,
        isPopoverShown: false,
        isShowScheduled: false
    ))
    #expect(!PersistentPopoverInitialShowPolicy.shouldScheduleDeferredInitialShow(
        isPresented: false,
        isPopoverShown: false,
        isShowScheduled: false
    ))
    #expect(!PersistentPopoverInitialShowPolicy.shouldScheduleDeferredInitialShow(
        isPresented: true,
        isPopoverShown: true,
        isShowScheduled: false
    ))
    #expect(!PersistentPopoverInitialShowPolicy.shouldScheduleDeferredInitialShow(
        isPresented: true,
        isPopoverShown: false,
        isShowScheduled: true
    ))
}

@Test func persistentPopoverAppliesOnlyValidMeasuredContentSizes() {
    #expect(PersistentPopoverContentSizePolicy.shouldApply(
        CGSize(width: 304, height: 382)
    ))
    #expect(!PersistentPopoverContentSizePolicy.shouldApply(.zero))
    #expect(!PersistentPopoverContentSizePolicy.shouldApply(
        CGSize(width: 304, height: 0)
    ))
}

@Test func groupAppearanceOutsideClickPolicyClosesOnlyOutsideOwnedPanels() {
    #expect(HistoryGroupAppearanceOutsideClickPolicy.shouldClose(
        isEnabled: true,
        eventWindowRole: .hostWindow
    ))
    #expect(HistoryGroupAppearanceOutsideClickPolicy.shouldClose(
        isEnabled: true,
        eventWindowRole: .outsideApp
    ))
    #expect(!HistoryGroupAppearanceOutsideClickPolicy.shouldClose(
        isEnabled: true,
        eventWindowRole: .popover
    ))
    #expect(!HistoryGroupAppearanceOutsideClickPolicy.shouldClose(
        isEnabled: true,
        eventWindowRole: .colorPanel
    ))
    #expect(!HistoryGroupAppearanceOutsideClickPolicy.shouldClose(
        isEnabled: false,
        eventWindowRole: .hostWindow
    ))
}

@Test @MainActor func windowHideCleanupCanBeRequestedBeforeWindowVisibilityChanges() {
    let inputState = HistoryWindowInputState()
    inputState.setWindowVisible(true)
    inputState.setWindowPresented(true)
    let originalRequestID = inputState.windowHideRequestID

    inputState.requestWindowHideCleanup()

    #expect(inputState.isWindowVisible)
    #expect(!inputState.isWindowPresented)
    #expect(!inputState.isWindowPresentedSnapshot)
    #expect(inputState.windowHideRequestID != originalRequestID)
}

@Test @MainActor func windowPresentedChangePostsTargetedNotificationOnlyWhenValueChanges() {
    let inputState = HistoryWindowInputState()
    let notificationCount = LockedNotificationCounter()
    let observer = NotificationCenter.default.addObserver(
        forName: HistoryWindowInputState.windowPresentedDidChangeNotification,
        object: inputState,
        queue: nil
    ) { _ in
        notificationCount.increment()
    }
    defer {
        NotificationCenter.default.removeObserver(observer)
    }

    inputState.setWindowPresented(true)
    inputState.setWindowPresented(true)
    inputState.setWindowPresented(false)

    #expect(notificationCount.value == 2)
}

@Test func keyboardEventTapHandlesEventsOnlyAfterWindowIsPresented() {
    #expect(!HistoryKeyboardEventTap.shouldHandleEvent(isWindowPresented: false))
    #expect(HistoryKeyboardEventTap.shouldHandleEvent(isWindowPresented: true))
}

@Test @MainActor func openAnimationSnapshotIsClearedByWindowHide() {
    let inputState = HistoryWindowInputState()

    inputState.setOpenAnimationActive(true)

    #expect(inputState.isOpenAnimationActiveSnapshot)

    inputState.notifyWindowWillHide()

    #expect(!inputState.isOpenAnimationActiveSnapshot)
}
