# State Management

> How state is managed in this project.

---

## Overview

<!--
Document your project's state management conventions here.

Questions to answer:
- What state management solution do you use?
- How is local vs global state decided?
- How do you handle server state?
- What are the patterns for derived state?
-->

(To be filled by the team)

---

## State Categories

<!-- Local state, global state, server state, URL state -->

### History Window Search State

`HistoryWindowView` owns SwiftUI state and delegates asynchronous search work to
`HistorySearchCoordinator`. The coordinator is responsible for stale-generation
guards, cancellation, repository pagination, and producing a single
`HistorySearchFilterResult` that is safe to apply on the main actor.

Search flow contract:

- `ClipboardSearchQuery` is a text/limit/offset repository query with optional
  stable filter hints. SQLite FTS may push down deterministic equality filters
  such as item type, source app, pinned state, and group membership, while
  `HistorySearchController.filterItems` remains the final source of truth for
  UI criteria semantics.
- Because repository candidates can be rejected by UI criteria, initial search
  must continue loading repository pages in the background until either
  `targetResultCount` filtered items are available or the repository has no more
  candidates.
- `HistoryWindowView` should pass the rail render target as
  `targetResultCount` when preparing an active search so the first applied result
  can fill the visible rail when enough matching items exist.
- Main-actor state must only be updated after the coordinator confirms the
  current generation still matches the request generation.

Required regression tests:

- `HistorySearchCoordinatorTests.searchCoordinatorFillsInitialFilteredSearchPageBeforeApplying`
  proves filtered first-page misses do not make the visible search result look
  incomplete.
- `HistorySearchCoordinatorTests.searchCoordinatorPushesStableFiltersIntoRepositoryQuery`
  proves stable UI criteria are passed to the repository query so sparse
  filtered searches do not wait on unrelated FTS pages before producing useful
  results.
- Cancellation and stale-generation tests must remain in
  `HistorySearchCoordinatorTests` when changing search task structure.

### History Window Keyboard State

History keyboard routing must treat focused search text, group rename fields,
popover search fields, and actual AppKit `NSTextView` first responders as text
input layers. While a text input layer is active, card-level commands and card
shortcut overlays must stay disabled so `Command` combinations remain owned by
the focused text field.

Required regression tests:

- `HistoryKeyboardShortcutPolicyTests.cardCommandsAreBlockedWhileTextInputIsActive`
  proves card actions such as paste, preview, delete, and visible-card selection
  do not run while text input is active.
- `HistoryKeyboardShortcutPolicyTests.shortcutOverlayIsHiddenWhileTextInputIsActive`
  proves holding `Command` does not reveal card 1-9 shortcut badges while the
  search field or another text input owns focus.
- `HistoryKeyboardShortcutPolicyTests.searchFieldHandoffToFirstResultClearsTextFirstResponder`
  proves Enter/Tab handoff from the search field to the first result clears the
  actual AppKit text first responder immediately, so the next Enter routes to
  card paste instead of being swallowed by the search field command handler.

---

## When to Use Global State

<!-- Criteria for promoting state to global -->

(To be filled by the team)

---

## Server State

<!-- How server data is cached and synchronized -->

(To be filled by the team)

---

## Common Mistakes

<!-- State management mistakes your team has made -->

(To be filled by the team)
