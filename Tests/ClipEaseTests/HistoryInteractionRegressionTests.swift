import Foundation
import Testing
@testable import ClipEase

@Test @MainActor func searchFieldEditingSequenceKeepsEditingKeysInsideSearchField() {
    let inputState = HistoryWindowInputState()
    inputState.setTextInputFocused(true)
    inputState.setSearchHasHandedOffFocusToCard(false)

    #expect(inputState.isHistoryTextInputActiveSnapshot)
    #expect(!HistoryKeyboardShortcutPolicy.allowsHistoryCommand(
        .delete,
        isTextInputActive: inputState.isHistoryTextInputActiveSnapshot,
        isPreviewContentActive: false
    ))
    #expect(!HistoryKeyboardShortcutPolicy.allowsHistoryCommand(
        .togglePreview,
        isTextInputActive: inputState.isHistoryTextInputActiveSnapshot,
        isPreviewContentActive: false
    ))
    #expect(HistoryKeyboardInputPolicy.actionForTextInput(
        keyCode: KeyCode.a,
        hasTextEditingModifier: true,
        isShiftPressed: false,
        cursorIsAtEnd: true
    ) == nil)
}

@Test func searchHandoffSequenceAllowsFirstCardPreviewWithoutRefocusingSearchField() {
    let transition = HistorySearchFocusTransitionPolicy.transition(
        event: .focusFirstResult,
        hasSearchResult: true,
        isSearchVisible: true
    )

    #expect(!transition.isSearchFocused)
    #expect(!transition.isTextInputFocused)
    #expect(transition.searchHasHandedOffFocusToCard)
    #expect(!transition.shouldRefocusSearchField)
    #expect(!HistorySearchTextFieldFocusPolicy.shouldRestoreFocusOnKeyEvent(
        searchHasHandedOffFocusToCard: transition.searchHasHandedOffFocusToCard
    ))
    #expect(HistoryPanelSpaceKeyPolicy.shouldTogglePreview(
        isHistoryTextInputActive: transition.isTextInputFocused,
        isPreviewActive: false
    ))
}

@Test @MainActor func searchFieldRefocusAfterCardPreviewRestoresTextInputProtection() {
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
    #expect(!HistoryPanelSpaceKeyPolicy.shouldTogglePreview(
        isHistoryTextInputActive: inputState.isHistoryTextInputActiveSnapshot,
        isPreviewActive: false
    ))
}

@Test func previewFallbackAnchorTracksFocusedCardAcrossHorizontalMovement() {
    let itemStride: CGFloat = 270
    let cardFrame = CGSize(width: 250, height: 270)
    let currentIndex = 7
    let nextIndex = 8

    let currentFrame = HistoryPreviewFramePolicy.fallbackViewportFrame(
        documentFrame: CGRect(
            x: CGFloat(currentIndex) * itemStride,
            y: 0,
            width: cardFrame.width,
            height: cardFrame.height
        ),
        currentOffset: CGFloat(currentIndex) * itemStride,
        cardRailTopInWindow: 68,
        selectedCardTopContentInset: 6
    )
    let nextFrame = HistoryPreviewFramePolicy.fallbackViewportFrame(
        documentFrame: CGRect(
            x: CGFloat(nextIndex) * itemStride,
            y: 0,
            width: cardFrame.width,
            height: cardFrame.height
        ),
        currentOffset: CGFloat(nextIndex) * itemStride,
        cardRailTopInWindow: 68,
        selectedCardTopContentInset: 6
    )

    #expect(currentFrame == CGRect(x: 0, y: 74, width: 250, height: 270))
    #expect(nextFrame == currentFrame)
}

@Test @MainActor func groupAppearanceFirstOpenDefersPopoverUntilAnchorSettles() {
    let coordinator = GroupAppearanceCoordinator()
    let group = ClipboardGroup(
        id: UUID(),
        name: "Work",
        colorHex: "#2E8CFF",
        iconName: "folder",
        sortOrder: 0,
        createdAt: Date(timeIntervalSince1970: 1),
        updatedAt: Date(timeIntervalSince1970: 1)
    )

    coordinator.beginEditing(group)

    #expect(coordinator.isPresented)
    #expect(!coordinator.hasPopoverWindow)
    #expect(PersistentPopoverInitialShowPolicy.shouldScheduleDeferredInitialShow(
        isPresented: coordinator.isPresented,
        isPopoverShown: coordinator.hasPopoverWindow,
        isShowScheduled: false
    ))

    coordinator.setPopoverWindowPresentForTesting()

    #expect(coordinator.hasPopoverWindow)
    #expect(!PersistentPopoverInitialShowPolicy.shouldScheduleDeferredInitialShow(
        isPresented: coordinator.isPresented,
        isPopoverShown: coordinator.hasPopoverWindow,
        isShowScheduled: false
    ))
}
