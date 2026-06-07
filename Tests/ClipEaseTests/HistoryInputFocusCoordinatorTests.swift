import Testing
@testable import ClipEase

@Test func inputFocusCoordinatorHandsSearchFocusToCardWithoutRefocusRequest() {
    let coordinator = HistoryInputFocusCoordinator()

    let transition = coordinator.focusFirstSearchResult(
        hasSearchResult: true,
        isSearchVisible: true
    )

    #expect(transition == HistorySearchFocusTransition(
        isSearchFocused: false,
        isTextInputFocused: false,
        searchHasHandedOffFocusToCard: true,
        shouldRefocusSearchField: false
    ))
    #expect(!coordinator.shouldRestoreSearchTextFieldFocus(
        searchHasHandedOffFocusToCard: transition.searchHasHandedOffFocusToCard
    ))
}

@Test func inputFocusCoordinatorKeepsSearchFocusedWhenNoCardResultExists() {
    let coordinator = HistoryInputFocusCoordinator()

    let transition = coordinator.focusFirstSearchResult(
        hasSearchResult: false,
        isSearchVisible: true
    )

    #expect(transition == HistorySearchFocusTransition(
        isSearchFocused: true,
        isTextInputFocused: true,
        searchHasHandedOffFocusToCard: false,
        shouldRefocusSearchField: true
    ))
}

@Test func keyboardActionRouterKeepsEditingShortcutsInsideTextInput() {
    let router = HistoryKeyboardActionRouter()

    #expect(router.actionForTextInput(
        keyCode: KeyCode.a,
        hasTextEditingModifier: true,
        isShiftPressed: false,
        cursorIsAtEnd: true
    ) == nil)
    #expect(!router.allowsHistoryCommand(
        .delete,
        isTextInputActive: true,
        isPreviewContentActive: false
    ))
}

@Test func keyboardActionRouterAllowsPreviewAfterSearchCardHandoff() {
    let router = HistoryKeyboardActionRouter()

    #expect(router.shouldTogglePreviewFromPanelSpace(
        isHistoryTextInputActive: false,
        isPreviewActive: false
    ))
    #expect(!router.shouldTogglePreviewFromPanelSpace(
        isHistoryTextInputActive: true,
        isPreviewActive: false
    ))
}
