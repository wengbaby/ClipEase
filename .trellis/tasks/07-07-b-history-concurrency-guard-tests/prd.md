# B History Concurrency Guard Tests

## Goal

Strengthen confidence that stale or canceled asynchronous history search and preview-build work cannot overwrite newer state.

## Requirements

- Add regression tests for stale search generation behavior.
- Add regression tests for load-more cancellation/staleness behavior where feasible through existing coordinator APIs.
- Add preview-build coordinator tests for stale-result application decisions.
- Do not change the thread model, SQLite writer queue, save timing, or business results.

## Acceptance Criteria

- [x] Stale generation search results are ignored by tests.
- [x] Canceled or stale load-more paths are covered by tests or documented if already structurally unreachable.
- [x] Preview-build stale-result application decision is covered by tests.
- [x] `swift test --filter HistorySearchCoordinatorTests` passes.
- [x] `swift test --filter HistoryPreviewBuildCoordinatorTests` passes.
