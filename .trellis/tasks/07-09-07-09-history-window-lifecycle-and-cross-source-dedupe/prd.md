# History window lifecycle diagnostics and cross-source dedupe

## Goal

Add non-UI lifecycle diagnostics for history window open/close frame drops and make same-content clipboard items cover older entries across source apps.

## Requirements

- Add non-UI diagnostics for history window open/close without changing UI/UX, animation timing, window placement, shortcuts, search ordering, paste behavior, or SQLite schema.
- Record lifecycle events for open request, ordered, presented, first frame, preview ready, close request, close animation complete, and close cleanup complete.
- Include stable metadata where available: item count, whether the panel was already visible, whether animation is used, pending focus state, visible item count, and preview item count.
- Change duplicate detection to be source-agnostic for text, links, colors, images, and files.
- When a new item covers an older same-content item, keep the new item's content/source/icon/time but inherit the older item's pinned and group state.
- Ensure persisted duplicate lookup also works across sources after cold start.

## Acceptance Criteria

- [ ] Same text copied from different apps results in one history item with the latest source metadata.
- [ ] Same image hash copied from different apps dedupes across source apps.
- [ ] Same ordered file path set copied from different apps dedupes across source apps.
- [ ] Existing pinned/group state is inherited by the replacement item.
- [ ] SQLite persisted duplicate lookup with nil source bundle returns all matching source apps.
- [ ] Window lifecycle diagnostics are recorded with stable event names and metadata.
- [ ] Full test suite and release build pass.
