# Implementation Plan

- [x] Use CodeGraph before each production-code slice.
- [x] Slice 1: cross-source duplicate coverage.
  - [x] Add failing tests in duplicate resolver, domain store, store-level behavior, and SQLite persisted lookup.
  - [x] Make duplicate content keys source-agnostic for all item types.
  - [x] Make persisted duplicate lookup cross-source when requested with nil source bundle.
  - [x] Run focused tests, release build, bump version, commit.
- [ ] Slice 2: history window lifecycle diagnostics.
  - [ ] Add failing tests for lifecycle event metadata construction and diagnostics display.
  - [ ] Add diagnostics helper/types and wire into controller/view lifecycle points.
  - [ ] Run focused tests, release build, bump version, commit.
- [ ] Final verification: swift test, release build, build app bundle, restart app for manual acceptance.
