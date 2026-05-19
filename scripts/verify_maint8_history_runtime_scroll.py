#!/usr/bin/env python3
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
VIEW = ROOT / "Sources/ClipEase/Features/HistoryWindow/HistoryWindowView.swift"
CONTROLLER = ROOT / "Sources/ClipEase/Features/HistoryWindow/HistoryWindowController.swift"


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        print(f"FAIL: {message}")
        sys.exit(1)


def function_body(text: str, signature: str) -> str:
    start = text.find(signature)
    require(start >= 0, f"missing function: {signature}")
    brace = text.find("{", start)
    require(brace >= 0, f"missing function body: {signature}")
    depth = 0
    for index in range(brace, len(text)):
        char = text[index]
        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return text[brace + 1:index]
    require(False, f"unterminated function body: {signature}")


view = read(VIEW)
controller = read(CONTROLLER)

coordinator_body = function_body(view, "final class HistoryScrollCoordinator")
update_body = function_body(view, "func update(scrollView: NSScrollView)")
restore_body = function_body(view, "func restoreSavedOffset()")
scroll_to_offset_body = function_body(view, "func scrollToOffset(_ offsetX: CGFloat, animated: Bool, suppressUserOffsetSave: Bool = false)")
perform_scroll_body = function_body(view, "private func performScrollToOffset(_ offsetX: CGFloat, animated: Bool, suppressUserOffsetSave: Bool = false)")
observe_body = function_body(view, "private func observeClipViewIfNeeded")
clip_change_body = function_body(view, "private func clipViewBoundsDidChange")
clip_observer_body = function_body(view, "private final class ClipViewBoundsObserver")
preview_rebuild_body = function_body(view, "private func schedulePreviewItemsRebuild")
sync_latest_body = function_body(view, "private func syncLatestItemFocusIfNeeded(")
apply_pending_body = function_body(view, "private func applyPendingItemScrollIfMeasured")
partial_reveal_body = function_body(view, "private func partialRevealTargetOffset")

require(
    "restoreSavedOffset()" not in update_body,
    "coordinator binding must not restore an old saved offset during SwiftUI/AppKit update churn",
)
require(
    "observeClipViewIfNeeded(scrollView.contentView)" in update_body,
    "coordinator must bind the real NSScrollView clip view",
)
require(
    "applyPendingBindingScrollIfNeeded()" in update_body,
    "pending scroll/restore requests made before AppKit binding must be replayed exactly once",
)
require(
    "needsRestoreOnNextBinding = true" in restore_body,
    "restore requests made before scroll view binding must be remembered",
)
require(
    "guard pendingOffsetForNextBinding == nil" in restore_body,
    "saved viewport restore must not override an explicit pending latest-item offset",
)
require(
    "pendingOffsetForNextBinding = offsetX" in perform_scroll_body,
    "absolute scroll requests made before scroll view binding must be remembered",
)
require(
    "if !suppressUserOffsetSave" in perform_scroll_body,
    "suppressed latest-item offsets must queue without persisting stale user viewport state",
)
require(
    "private var coalescedScrollRequest" in coordinator_body
    and "private func coalesceScrollToOffset" in coordinator_body
    and "performScrollToOffset(" in scroll_to_offset_body,
    "animated scroll requests should coalesce so repeated latest-item jumps do not start competing animations",
)
require(
    "boundsObserver" in coordinator_body
    and "ClipViewBoundsObserver" in observe_body
    and "NSView.boundsDidChangeNotification" in clip_observer_body
    and "clipView.postsBoundsChangedNotifications = true" in clip_observer_body,
    "coordinator must observe actual NSClipView bounds changes",
)
require(
    "guard !isProgrammaticScroll" in clip_change_body
    and "saveOffset(clipView.bounds.minX)" in clip_change_body,
    "user/runtime viewport changes must save the real document offset without echoing programmatic scrolls",
)
require(
    "isProgrammaticScroll = true" in coordinator_body
    and "isProgrammaticScroll = false" in coordinator_body,
    "programmatic scrolls must suppress bounds-change feedback while still saving the final target",
)
require(
    "if pendingLatestFocusItemID == nil" in preview_rebuild_body
    and "restoreSelectionAfterPreviewRebuild" in preview_rebuild_body,
    "preview rebuild must not restore an old selection while newest-item focus is pending",
)
require(
    "pendingLatestFocusItemID = focusCandidateID" in sync_latest_body
    and "HistoryScrollCoordinator.shared.discardSavedOffset(for: HistoryGroupSelection.all.storageValue)" in sync_latest_body
    and "fulfillPendingLatestFocusIfPossible()" in sync_latest_body,
    "new clipboard items must select the new item and force an absolute viewport reset",
)
require(
    "scheduleOffsetChangeNotification" in coordinator_body
    and "pendingOffsetNotificationTask" in coordinator_body
    and "try? await Task.sleep(nanoseconds: 33_000_000)" in coordinator_body,
    "scroll offset notifications must be throttled so preview following does not flood the main thread",
)
require(
    "previewItemsSourceSignature" in view
    and "HistoryPreviewSourceSignature" in view
    and "guard sourceSignature != previewItemsSourceSignature" in preview_rebuild_body,
    "preview item rebuilds should skip unchanged source snapshots",
)
require(
    "previewItemCache" in view
    and "CachedHistoryPreviewItem" in view
    and "cachedItem.signature == signature" in preview_rebuild_body
    and "previewItem = cachedItem.item" in preview_rebuild_body,
    "preview item rebuilds should reuse unchanged HistoryPreviewItem values",
)
require(
    "fileReferences: [ClipboardFileReference]" in view
    and "sourceAppName" in function_body(view, "private struct HistoryPreviewSourceSignature"),
    "preview item cache signature must include fields that affect display and search",
)
require(
    "HistoryScrollCoordinator.shared.scrollToOffset(\n            targetOffset" in apply_pending_body,
    "pending item alignment must use absolute AppKit coordinator offsets",
)
require(
    "HistoryScrollCoordinator.shared.visibleDocumentRect" in partial_reveal_body
    and "frame.minX < leftVisibleEdge" in partial_reveal_body
    and "frame.maxX > rightVisibleEdge" in partial_reveal_body,
    "partial-card reveal must use the runtime document viewport for both directions",
)
require(
    "HistoryScrollCoordinator.shared.restoreSavedOffset()" in controller,
    "window show should remain the explicit saved-offset restore point",
)

print("PASS: maint8 history runtime scroll architecture checks")
