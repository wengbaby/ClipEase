# History Window Smoothness Optimization Plan

## Summary

Optimize main history window smoothness by moving non-critical work out of the open/close animation path. This is a behavioral scheduling change only: no UI hierarchy, layout, style, animation duration, shortcuts, search semantics, paste result, or SQLite schema changes.

The current code path shows that `HistoryWindowController.show()` runs a 0.14s window animation, while `HistoryWindowView.onAppear` schedules deferred startup work that can begin preview rebuild/search/accessibility refresh shortly after the first frame. That can compete with the animation and SwiftUI layout. The fix is to make startup work wait for a presentation-safe delay, centralize the timing policy in a pure type, and cancel/coalesce work when the window closes or the source changes.

## Entry Files And Call Chain

- Entry files:
  - `Sources/ClipEase/Features/HistoryWindow/HistoryWindowController.swift`
  - `Sources/ClipEase/Features/HistoryWindow/HistoryWindowView.swift`
  - `Sources/ClipEase/Features/HistoryWindow/HistoryWindowLifecycleDiagnostics.swift`
- Key call chain:
  - `HistoryWindowController.show()` -> panel order/key/presented -> open animation -> `finishShowingWindow()`
  - `HistoryWindowView.onAppear` -> `scheduleDeferredStartupWork()` -> `schedulePreviewItemsRebuild()` -> `scheduleSearchUpdate()`
  - `HistoryWindowController.close()` / `HistoryWindowView.onDisappear` -> cancel tasks -> close cleanup
- Impact scope:
  - History window startup/teardown scheduling, diagnostics, and tests.
  - No storage, search result sorting, card rendering, keyboard policy, or visual styling changes.

## Implementation Slices

### Slice 1: Startup Scheduling Policy

Add a pure `HistoryWindowLifecycleScheduler` policy that computes when deferred startup work can run:

- animated open: wait until after the 0.14s open animation plus a small settle buffer.
- already-visible/no-animation open: keep work immediate or near-immediate.
- hidden/closing window: do not run startup work.

Tests:

- Animated open defers preview/search/accessibility past animation budget.
- Non-animated visible show does not add the full delay.
- Hidden window disallows startup work.

Implementation:

- Replace hard-coded double sleep in `scheduleDeferredStartupWork(delayNanoseconds:)` with the scheduler policy.
- Record a new diagnostic event for deferred startup beginning, using existing metadata shape.
- Keep `schedulePreviewItemsRebuild(from:)` and `scheduleSearchUpdate` semantics unchanged once the work starts.

### Slice 2: Close-Time Cancellation And Coalescing

Make close/hidden transitions cancel presentation work before it can apply stale results:

- cancel `deferredStartupTask` and preview rebuild task when hide cleanup is requested.
- increment preview generation when canceling for hide so late detached results cannot apply.
- avoid scheduling visible-window rebuild while `inputState.isWindowPresentedSnapshot` is false.

Tests:

- Hide cleanup policy cancels pending startup and invalidates preview generation.
- Canceled preview result still cannot apply after generation changes.
- Existing search/focus keyboard regression tests remain green.

Implementation:

- Add a small helper in `HistoryWindowView` for canceling startup presentation work.
- Call it from `onDisappear` and `windowHideRequestID` handling.
- Keep close animation and cleanup ordering intact.

### Slice 3: Verification And Manual Acceptance

After code slices:

- Run focused tests for lifecycle scheduler, lifecycle diagnostics, preview build coordinator, search coordinator, keyboard shortcut policy.
- Run `swift test`.
- Run `swift build -c release --product ClipEase`.
- Run `scripts/build-app.sh --bump none`.
- If build script changes build number, rerun focused tests/release build and commit build number.
- Stop old ClipEase process and launch `.build/ClipEase.app`.

## Commit Protocol

Each code slice must:

- Start with CodeGraph context.
- Add failing tests first.
- Implement minimal code.
- Run focused tests and release build.
- Bump patch version with `python3 scripts/bump_version.py --bump patch`.
- Rerun focused tests and release build.
- Audit diff for UI/UX and schema safety.
- Commit locally.

The plan/documentation change is committed separately before code changes.

## Progress

- [x] Plan document committed.
- [x] Slice 1 startup scheduling policy implemented, verified, and committed.
- [x] Slice 2 close-time cancellation and coalescing implemented, verified, and committed.
- [x] Slice 3 final verification and app restart.
