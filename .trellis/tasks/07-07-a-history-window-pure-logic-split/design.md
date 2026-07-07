# Design

## Boundaries

- `HistoryWindowView` remains the owner of SwiftUI state and view rendering.
- `HistorySourceAppFilter` owns pure derivation of source-app filter options and icon lookup.
- `HistoryPreviewBuildCoordinator` owns only pure preview-build result structures and deterministic result construction that can be tested outside SwiftUI.

## Compatibility

- No model, storage, or UI schema changes.
- Extracted types use internal access so tests can validate behavior without making public API.

## Risk Controls

- Tests are added before extraction.
- Extraction is limited to moving existing logic or introducing direct wrapper helpers with equivalent inputs and outputs.
