# A History Window Pure Logic Split

## Goal

Extract pure source-app filter and preview-build logic from `HistoryWindowView` into focused internal helpers without changing behavior.

## Requirements

- Add `HistorySourceAppFilter.swift` for source app option/snapshot construction.
- Add `HistoryPreviewBuildCoordinator.swift` for preview rebuild result types and pure build decisions where extraction is small and safe.
- Keep all SwiftUI hierarchy, layout constants, labels, menus, shortcuts, animation state, and UI event routing unchanged.
- Add focused tests before production extraction.
- Stop and re-plan if extraction requires broad View rewrites.

## Acceptance Criteria

- [x] Source-app snapshot behavior is covered by tests: empty names skipped, duplicate order stable, first available icon file retained in lookup.
- [x] Preview-build coordinator behavior is covered by tests for full and prepend result shape.
- [x] `HistoryWindowView` delegates the extracted pure logic while preserving existing state names and UI behavior.
- [x] `swift test --filter HistorySourceAppFilterTests` passes.
- [x] `swift test --filter HistoryPreviewBuildCoordinatorTests` passes.
