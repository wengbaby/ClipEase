import Foundation

struct HistoryInputFocusCoordinator {
    func searchFieldFocused(hasSearchResult: Bool, isSearchVisible: Bool) -> HistorySearchFocusTransition {
        HistorySearchFocusTransitionPolicy.transition(
            event: .searchFieldFocused,
            hasSearchResult: hasSearchResult,
            isSearchVisible: isSearchVisible
        )
    }

    func focusFirstSearchResult(hasSearchResult: Bool, isSearchVisible: Bool) -> HistorySearchFocusTransition {
        HistorySearchFocusTransitionPolicy.transition(
            event: .focusFirstResult,
            hasSearchResult: hasSearchResult,
            isSearchVisible: isSearchVisible
        )
    }

    func searchClosed(hasSearchResult: Bool, isSearchVisible: Bool) -> HistorySearchFocusTransition {
        HistorySearchFocusTransitionPolicy.transition(
            event: .searchClosed,
            hasSearchResult: hasSearchResult,
            isSearchVisible: isSearchVisible
        )
    }

    func shouldRestoreSearchTextFieldFocus(searchHasHandedOffFocusToCard: Bool) -> Bool {
        HistorySearchTextFieldFocusPolicy.shouldRestoreFocusOnKeyEvent(
            searchHasHandedOffFocusToCard: searchHasHandedOffFocusToCard
        )
    }
}

