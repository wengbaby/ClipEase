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

### History Window Presentation State

Opening the history window must keep presentation-critical work out of the
animation completion path. The global keyboard event tap must not be created
during hidden preload because a pre-created session event tap can interfere with
global hotkey delivery in some automation and permission states. Start the tap
immediately before the history panel is ordered instead, then rely on its
existing idempotent `start()` guard during finish. The tap must pass events
through until `HistoryWindowInputState` reports the window is presented.
Hidden/closing transitions should reset transient keyboard state without
tearing down reusable resources that are expensive to recreate on the next open.

Preview rebuilds may run off the main actor while an open animation is active,
but applying the rebuild result to SwiftUI state must wait until the animation
budget has passed. Presented-state notifications should enqueue deferred
startup work instead of synchronously rebuilding preview/search state inside the
notification callback.

Animated opens must separate presentation recovery from deferred startup work.
After the panel animation completes, window-visible/window-presented state may be
published, but remembered viewport restoration and focus handoff run after a
short presentation-recovery buffer. Preview rebuild, search refresh, and
accessibility refresh must start after that recovery buffer so they do not
compete with the final visible frame.

Window open/close frame animations should temporarily rasterize the history
hosting content layer and reset rasterization immediately after the animation or
hide cleanup. This keeps the visible UI identical while avoiding repeated
SwiftUI/layer recomposition during panel movement.

Launch hidden preload should only prepare the reusable window shell and must not
start preview warming. Preview warming from a hidden window is allowed after a
real hide when the cache is stale, but launch-time hidden rebuilds can overlap a
near-immediate user open and compete with first-frame presentation.

### Settings Update Check State

`SettingsUpdateViewModel` owns the settings UI state for update checks and
delegates network lookups to `GitHubReleaseUpdateChecker`.

Update check contract:

- The primary lookup uses the GitHub Releases API so update-available states can
  include a direct DMG download URL when GitHub returns release asset metadata.
- If the anonymous API request fails, including GitHub rate limiting, the
  checker must fall back to the public `/releases/latest` page redirect and parse
  the final tag URL. This fallback may not include a direct DMG URL, but it must
  still report update availability and provide the release page URL.

Required regression tests:

- `GitHubReleaseUpdateCheckerTests.githubReleaseUpdateCheckerFallsBackToLatestPageWhenAPIIsRateLimited`
  proves ordinary users are not blocked from update detection when the
  unauthenticated GitHub API quota is exhausted.

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
