# History Architecture Stability Performance Optimization

## Goal

Improve maintainability, concurrency confidence, and performance coverage for the history window without changing any user-visible UI/UX behavior.

## Requirements

- Preserve all current visual layout, text, animations, keyboard shortcuts, menu behavior, window positioning, search behavior, grouping behavior, preview behavior, and paste behavior.
- Execute the work in three independently verifiable child tasks:
  - A: extract pure history-window source-app filter and preview-build logic.
  - B: strengthen stale-generation and cancellation coverage for search and preview-build flows.
  - C: extend performance budget coverage to 10k-item scenarios.
- Keep persistence schemas unchanged: no `ClipboardItem` schema changes and no SQLite schema changes.
- Use test-first changes for new extractable logic and regression coverage.
- Run full Swift tests and release build verification before reporting completion.

## Acceptance Criteria

- [x] Child task A is implemented and verified.
- [x] Child task B is implemented and verified.
- [x] Child task C is implemented and verified.
- [x] `swift test` passes.
- [x] `swift build -c release --product ClipEase` passes.
- [x] `scripts/build-app.sh --bump none` passes.
- [x] No intentional UI/UX changes are introduced.
