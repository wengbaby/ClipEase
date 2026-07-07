# Implementation Plan

- [x] Use CodeGraph to inspect `HistoryWindowView`, source app filter symbols, preview build symbols, and tests before editing.
- [x] Run baseline `swift test --filter HistorySearchCoordinatorTests`.
- [x] Add `HistorySourceAppFilterTests` and verify it fails before production code exists.
- [x] Add `HistorySourceAppFilter.swift` and switch `HistoryWindowView` to use it.
- [x] Run `swift test --filter HistorySourceAppFilterTests`.
- [x] Add `HistoryPreviewBuildCoordinatorTests` and verify it fails before production code exists.
- [x] Add `HistoryPreviewBuildCoordinator.swift` with pure result construction and switch narrow preview build code where safe.
- [x] Run `swift test --filter HistoryPreviewBuildCoordinatorTests`.
- [x] Run `swift test --filter HistorySearchCoordinatorTests`.
