# Implementation Plan

- [x] Use CodeGraph to inspect `HistorySearchCoordinator`, `HistoryPreviewBuildCoordinator`, and related tests before editing.
- [x] Add a stale search generation test.
- [x] Add a stale/canceled load-more test if the existing API can exercise it deterministically.
- [x] Add preview-build stale application decision tests.
- [x] Make minimal production guard changes only if a failing test exposes a gap.
- [x] Run `swift test --filter HistorySearchCoordinatorTests`.
- [x] Run `swift test --filter HistoryPreviewBuildCoordinatorTests`.
