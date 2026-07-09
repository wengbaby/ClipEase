# History window smoothness optimization

## Goal

Reduce history main-window open/close stutter and frame drops while preserving the current UI/UX, animation timing, window placement, keyboard semantics, search ordering, paste behavior, and storage schema.

## Requirements

- Keep the visible window behavior unchanged: no layout, text, style, shortcut, animation duration, placement, search result ordering, or paste behavior changes.
- Prevent heavy startup work from competing with the open animation. Preview rebuild, search update, remembered viewport restoration, focus restoration, accessibility refresh, and cache/resource checkpoints must run after the presentation-critical window phase.
- Prevent hidden/closing windows from applying stale preview/search work after close.
- Keep all existing generation and cancellation guards. New scheduling must be explicit and testable.
- Record enough diagnostics to compare before/after: open request, ordered, presented, first frame, preview ready, close request, animation complete, cleanup complete, and deferred startup work.
- Build and launch the new app bundle for manual acceptance after all changes.

## Acceptance Criteria

- [ ] Opening the history window does not start preview rebuild/search/accessibility refresh until after the open animation budget has passed.
- [ ] Closing the history window cancels pending deferred startup and preview/search work before cleanup applies visible state.
- [ ] Existing keyboard, focus handoff, search, paste, and preview behaviors remain covered by regression tests.
- [ ] Diagnostics show the deferred startup phase separately from first frame and preview ready.
- [ ] `swift test`, `swift build -c release --product ClipEase`, and `scripts/build-app.sh --bump none` pass.
- [ ] Old ClipEase process is stopped and the new `.build/ClipEase.app` is launched for manual acceptance.
