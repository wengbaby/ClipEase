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
animation path. The global keyboard event tap must not be created during hidden
preload because a pre-created session event tap can interfere with global hotkey
delivery in some automation and permission states. Do not start the tap before
`orderFrontRegardless()` for animated opens; `keyboardEventTap.start()` has been
observed to take more than a frame budget and should run from
`finishShowingWindow()` after the panel animation completes. The tap must pass
events through until `HistoryWindowInputState` reports the window is presented.
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
single-frame presentation-recovery buffer. Preview rebuild, search refresh, and
accessibility refresh must start after that recovery buffer so they do not
compete with the final visible frame; the presented startup delay should remain
at least 32ms longer than the presentation-recovery buffer. Animated opens also
defer keyboard event tap startup until presentation recovery completes. For
non-animated opens, keyboard event tap startup may still run while finishing
show.

Window open/close slide animations should prefer a fixed panel frame with a
temporary content-layer transform over animating the whole `NSPanel` frame.
Do not rasterize the hosting content layer during this transform unless new
diagnostics prove it is cheaper: enabling rasterization has been observed to add
more than a frame of main-thread preparation before the panel is ordered. This
keeps the visible UI identical while avoiding repeated WindowServer work during
panel movement.

Do not synchronously force SwiftUI/AppKit layout or display while preparing the
content layer before ordering the panel. `layoutSubtreeIfNeeded()` and
`displayIfNeeded()` in that path have been observed to add more than a frame of
main-thread work before the window appears; the animated path should only pin
the final panel/content size and apply the temporary layer transform/clipping.

Content-layer transform preparation may be the animated path only when the
panel frame is pinned to the final target frame before ordering, the hosting
view size is locked to that target frame, and completion always resets layer
translation, clipping, rasterization, panel opacity, and background color. This
path exists to avoid repeatedly animating the whole `NSPanel` frame. If the
translated path changes perceived top/bottom spacing, cards appear flush with
the screen edge, or the top gap grows, revert to frame animation and add a
layout regression before re-enabling it. Clipping/transparent-background
preparation must remain gated behind
`shouldApplyContentLayerTransformPreparation(initialTranslationY:)`.
Repeated panel/content size locks for the same size must be idempotent no-ops;
do not call through to AppKit/SwiftUI frame setters when the locked size already
matches the current frame.
When using content-layer animation, hidden/preloaded panels should remain at the
target visible frame while ordered out. The open path should skip `setFrame`
when the current frame already matches the target frame; do not reintroduce an
offscreen panel frame for this animation path.

Launch hidden preload should prepare the reusable window shell and may warm
preview state only while the window is still hidden, not presented, not
animating, and the preview cache is stale. Preview warming from a hidden window
is also allowed after a real hide when the cache is stale. Visible presentation
must still defer preview rebuild/search/accessibility work until the animation
and presentation-recovery buffer have passed, so hidden warm work must never be
moved back into the open animation path.

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
