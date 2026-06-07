# ClipEase Maintenance Roadmap

Date: 2026-06-07

## Goal

Turn the recent bug fixes and project-wide review into an ordered maintenance backlog, then execute it step by step without changing the current UI, interaction model, or user-visible features unless a listed bug explicitly requires it.

## Constraints

- Preserve current UI layout, styling, shortcuts, and workflows.
- Make one maintenance slice verifiable before starting the next one.
- Prefer policy/controller extraction with tests over broad rewrites.
- Do not move unrelated code while fixing one slice.
- After each code slice: bump version, build, run, test, then commit.

## Execution Order

### 1. Main Window Search, Focus, And Render Window

Purpose:
- Stop search, keyboard focus, virtual card rendering, and preview follow-up from depending on scattered `@State` transitions in `HistoryWindowView`.

Files:
- `Sources/ClipEase/Features/HistoryWindow/HistoryWindowView.swift`
- `Sources/ClipEase/Features/HistoryWindow/HistoryWindowInputState.swift`
- `Sources/ClipEase/Features/HistoryWindow/HistorySearchController.swift`
- `Sources/ClipEase/Features/HistoryWindow/HistoryRailViewportController.swift`
- `Tests/ClipEaseTests/HistoryKeyboardShortcutPolicyTests.swift`

Work:
- Extract more search selection and render-window decisions into small pure policies.
- Add tests for the current user rules before moving production logic.
- Keep rendered item limit at 20 and search page size at 50.
- Keep search field keyboard behavior unchanged:
  - When the search field is focused, all keys stay in the search field except Down, Right-at-end, Enter, Tab, and Esc.
  - Esc clears search content first, then closes the search field when empty.
  - Tab/Down/Right-at-end/Enter hand focus to the first card.
  - Search typing selects the first result visually but does not focus the card until the user hands off focus.

Verification:
- `swift test`
- Build the app.
- Run the app and manually smoke-test opening the main window, typing search text, deleting search text, Tab handoff, Space preview, and horizontal card navigation.

### 2. Clipboard Write Coordinator

Purpose:
- Make every app-originated clipboard write go through one path so ClipEase never records its own copy/paste action as a new card.

Files:
- `Sources/ClipEase/Features/PasteExecutor/PasteExecutor.swift`
- `Sources/ClipEase/Features/PasteExecutor/PasteboardWriter.swift`
- `Sources/ClipEase/Core/Storage/ClipboardHistoryStore.swift`
- Search all direct `NSPasteboard.general`, `clearContents`, `setString`, and `writeObjects` calls.

Work:
- Introduce one write coordinator API for text, rich text, image, and file URLs.
- Move self-write skip registration into that coordinator.
- Replace direct pasteboard writes from UI and helper code where they affect user copy/paste behavior.

Verification:
- Unit tests for text, rich text/plain-text paste, image, and file self-write skip.
- Manual smoke-test double-click paste, Enter paste, plain-text paste, right-click copy, preview copy.

### 3. Swift Concurrency Warning Cleanup

Purpose:
- Remove known Sendable/concurrency risks instead of carrying warnings through releases.

Files:
- `Sources/ClipEase/Core/Services/ClipboardOCRService.swift`
- `Sources/ClipEase/Features/HistoryWindow/HistoryPreviewPopoverView.swift`
- Other files found by `rg "@unchecked Sendable|Task.detached|DispatchQueue.global" Sources`.

Work:
- Avoid sending Vision/PDFKit non-Sendable objects across concurrency boundaries.
- Replace unsafe detached work with actor/service boundaries or main-actor object creation where required by framework behavior.
- Keep `@unchecked Sendable` only where there is a documented lock or actor boundary.

Verification:
- `swift test`
- Release build with no newly introduced Swift concurrency warnings.

### 4. Store And SQLite Boundary Split

Purpose:
- Reduce the size and responsibility of `ClipboardHistoryStore` and `SQLiteClipboardStore`.

Files:
- `Sources/ClipEase/Core/Storage/ClipboardHistoryStore.swift`
- `Sources/ClipEase/Core/Storage/SQLiteClipboardStore.swift`
- New focused storage files as needed.

Work:
- Split schema/migration from SQLite query code.
- Split item/group/search-index DAO functions.
- Move retention, compaction, and save scheduling into dedicated small types.
- Keep public store behavior unchanged.

Verification:
- Existing storage tests.
- Add search-index, compaction, and pagination tests where behavior is extracted.

### 5. Settings View Split

Purpose:
- Stop settings page bugs from coming from one large view owning unrelated operations.

Files:
- `Sources/ClipEase/Features/Settings/SettingsView.swift`
- New focused settings section files as needed.

Work:
- Split history data, performance/logs, groups, shortcut, permissions, and about sections into focused views.
- Move async operations into small helpers or view models.
- Keep the visual result unchanged.

Verification:
- `swift test`
- Build and manually open each settings category.

### 6. Preview Positioning Follow-Up

Purpose:
- Make preview positioning independent from stale card frames when virtual rendering is active.

Files:
- `Sources/ClipEase/Features/HistoryWindow/HistoryWindowView.swift`
- `Sources/ClipEase/Features/HistoryWindow/HistoryPreviewWindowController.swift`
- `Sources/ClipEase/Features/HistoryWindow/HistoryRailViewportController.swift`

Work:
- Define one preview anchor policy.
- Add tests for focused-card frame fallback behavior.
- Keep arrow alignment on keyboard left/right at both rail edges.

Verification:
- Unit tests for preview anchor policy.
- Manual smoke-test Space preview, left/right navigation, edge cards, and scrolling while preview is open.

### 7. Performance Benchmarks

Purpose:
- Make large data performance measurable instead of relying on visual feel only.

Files:
- `Tests/ClipEaseTests`
- `Sources/ClipEase/Core/Utilities/PerformanceDiagnosticsService.swift`
- Optional benchmark script under `scripts/`.

Work:
- Add repeatable datasets:
  - 1000 text items.
  - 3000 mixed text/link/color/file items.
  - 1000 rich text/image/file-heavy items.
- Track main-window preview item build, search apply, render-window calculation, and storage search timing.

Verification:
- Benchmark command produces stable timing output.
- No benchmark stores data in the user history database.

### 8. Release Script Hardening

Purpose:
- Make release publication safe when remote `main` changes during local work.

Files:
- `scripts/release.sh`
- `docs/releases/release-checklist.md`

Work:
- Fetch and verify remote branch state before tagging.
- Push branch before creating tag.
- Clean up local tag if publication fails.
- Keep release note format unchanged.

Verification:
- Dry-run local release path.
- Publish path only when user explicitly asks for release.

## Progress

- Slice 1 completed in `de1c4b3`: search focus and render-window policies were isolated with tests.
- Slice 2 completed in `35a0c7b`: clipboard writes were centralized through `ClipboardWriteCoordinator`.
- Slice 3 completed in `2532166`: non-Sendable OCR/PDF preview work was contained.
- Slice 4 completed in `9d61ee4`: database compaction scheduling was isolated.
- Slice 5 completed in `db98074`: the about settings section was split from `SettingsView`.
- Slice 6 completed in `34eed7e`: preview anchor frame selection was isolated and tested.
- Slice 7 completed in `19239ab`: repeatable performance benchmarks and a benchmark script were added.
- Slice 8 completed in `ea71b9c`: release publication guardrails were added.

## Current Slice

All planned maintenance slices in this roadmap are complete.

Success for the current slice means:
- Any future maintenance starts from a new, focused slice.
- Release publication still requires explicit user approval.
