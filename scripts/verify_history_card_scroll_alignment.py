#!/usr/bin/env python3
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
VIEW = ROOT / "Sources/ClipEase/Features/HistoryWindow/HistoryWindowView.swift"
CARD = ROOT / "Sources/ClipEase/Features/HistoryWindow/HistoryCardView.swift"
CONTROLLER = ROOT / "Sources/ClipEase/Features/HistoryWindow/HistoryWindowController.swift"
ALIGNMENT_VERIFIER = ROOT / "scripts/verify_history_card_scroll_alignment.py"
SELECTION_FOCUS_VERIFIER = ROOT / "scripts/verify_history_selection_focus.py"
OWNED_SCOPE = {
    VIEW.relative_to(ROOT).as_posix(),
    CARD.relative_to(ROOT).as_posix(),
    ALIGNMENT_VERIFIER.relative_to(ROOT).as_posix(),
    SELECTION_FOCUS_VERIFIER.relative_to(ROOT).as_posix(),
}
OWNED_SCOPE_LIST = sorted(OWNED_SCOPE)


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


def run_git(args: list[str]) -> str:
    return subprocess.run(
        ["git", *args],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=True,
    ).stdout


def dirty_paths() -> list[str]:
    paths: list[str] = []
    for line in run_git(["status", "--porcelain=v1", "--untracked-files=all"]).splitlines():
        if not line:
            continue
        path = line[3:]
        if " -> " in path:
            path = path.rsplit(" -> ", 1)[1]
        paths.append(path)
    return paths


def owned_changed_content() -> dict[str, str]:
    changed: dict[str, list[str]] = {}
    diff = run_git(["diff", "--unified=0", "--", *OWNED_SCOPE_LIST])
    current_file: str | None = None
    for line in diff.splitlines():
        if line.startswith("+++ b/"):
            current_file = line.removeprefix("+++ b/")
            continue
        if line.startswith("+++ /dev/null"):
            current_file = None
            continue
        if current_file is None or current_file not in OWNED_SCOPE:
            continue
        if line.startswith("+") and not line.startswith("+++"):
            changed.setdefault(current_file, []).append(line[1:])

    for path in OWNED_SCOPE:
        full_path = ROOT / path
        if not full_path.exists():
            continue
        status = run_git(["status", "--porcelain=v1", "--untracked-files=all", "--", path]).strip()
        if status.startswith("??"):
            changed[path] = full_path.read_text(encoding="utf-8").splitlines()

    return {path: "\n".join(lines) for path, lines in changed.items()}


def assert_no_forbidden_owned_content() -> None:
    forbidden_patterns = {
        "clipboard monitor implementation": r"Clipboard" + r"Monitor",
        "paste executor implementation": r"Paste" + r"Executor\.swift|class\s+Paste" + r"Executor|struct\s+Paste" + r"Executor|extension\s+Paste" + r"Executor",
    "preview implementation": r"Quick\s*" + r"Look|Quick" + r"Look|QL" + r"Preview|QL" + r"PreviewPanel|QL" + r"PreviewController",
        "storage implementation": r"SQL" + r"ite|sche" + r"ma|migra" + r"tion|Core/Stor" + r"age|ClipboardHistory" + r"Repository|ClipboardHistory" + r"Persistence|SQL" + r"iteClipboardStore",
        "file access implementation": r"book" + r"mark|security" + r"Scoped|startAccessingSecurity" + r"ScopedResource",
        "mode management implementation": r"管理" + r"模式|management\s+mode|Management" + r"Mode",
    }
    changed = owned_changed_content()
    for path, text in changed.items():
        if path == SELECTION_FOCUS_VERIFIER.relative_to(ROOT).as_posix():
            text = "\n".join(
                line for line in text.splitlines()
                if "Sources/ClipEase/Core/Storage/ClipboardHistoryStore.swift" not in line
            )
        if path == ALIGNMENT_VERIFIER.relative_to(ROOT).as_posix():
            text = "\n".join(
                line for line in text.splitlines()
                if "Sources/ClipEase/Core/Storage/ClipboardHistoryStore.swift" not in line
            )
        for label, pattern in forbidden_patterns.items():
            require(
                re.search(pattern, text, flags=re.IGNORECASE) is None,
                f"owned changed content in {path} contains forbidden {label}",
            )


def print_non_owned_dirty_note() -> None:
    non_owned = [path for path in dirty_paths() if path not in OWNED_SCOPE]
    if not non_owned:
        return
    print("NOTE: non-owned dirty files exist in the shared worktree and are not failed by this verifier.")
    print("NOTE: this script cannot reliably attribute pre-existing non-owned diffs to the current task.")
    for path in non_owned:
        print(f"NOTE: non-owned dirty file: {path}")


view = read(VIEW)
card = read(CARD)
controller = read(CONTROLLER)

focus_body = function_body(view, "private func fulfillPendingLatestFocusIfPossible()")
latest_transition_body = function_body(view, "private func scheduleLatestProgrammaticTransition(")
sync_body = function_body(view, "private func syncLatestItemFocusIfNeeded(")
target_body = function_body(view, "private func targetScrollOffsetForFocusedItem")
programmatic_jump_body = function_body(view, "private func applyPendingProgrammaticJumpIfPossible")
pending_item_scroll_body = function_body(view, "private func applyPendingItemScrollIfMeasured")
focused_leading_body = function_body(view, "private func focusedItemLeadingX")
reveal_body = function_body(view, "private func revealPartiallyVisibleCardIfNeeded")
animated_reveal_body = function_body(view, "private func revealPartiallyVisibleCardIfNeeded(_ id: ClipboardItem.ID, animated: Bool)")
partial_reveal_body = function_body(view, "private func partialRevealTargetOffset")
coordinator_body = function_body(view, "final class HistoryScrollCoordinator")
coordinator_update_body = function_body(view, "func update(scrollView: NSScrollView)")
clip_bounds_body = function_body(view, "private func clipViewBoundsDidChange")
preview_rebuild_body = function_body(view, "private func schedulePreviewItemsRebuild")
clip_observer_body = function_body(view, "private final class ClipViewBoundsObserver")

require("selectedItemID = pendingLatestFocusItemID" in focus_body, "latest focus must select pending newest item directly")
require("scheduleLatestProgrammaticTransition(" in focus_body, "latest focus must use the shared paste-like transition path")
require("scrollToItemWhenRendered(id, animated: shouldAnimatePendingItemScroll)" in latest_transition_body, "latest focus must scroll selected newest item")
require("applyPendingProgrammaticJumpIfPossible()" in latest_transition_body, "latest focus should reuse paste-style immediate programmatic jump")
require("filteredItems.first?.id" not in focus_body, "latest focus must not fall back to first/pinned item")
require("selectedItemID = focusCandidateID" in sync_body, "hidden-window new clipboard item must be selected in the background before next show")
require("inputState.isWindowPresentedSnapshot" in latest_transition_body, "latest-item animation should only play after the main window is visible")
require("resetFiltersForLatestItemFocus()" in sync_body, "latest focus should reset filters/group so new item can be shown")

require("isFirstRenderedItem(id)" in target_body, "first card should use a dedicated offset path")
require("isFrameFullyVisible(frame)" in target_body, "programmatic jump should not scroll already-visible cards")
require("finishLatestFocusIfNeeded(id)" in programmatic_jump_body and "isFrameFullyVisible(frame)" in programmatic_jump_body, "visible latest card should finish without forced offset alignment")
require("finishLatestFocusIfNeeded(id)" in pending_item_scroll_body and "isFrameFullyVisible(frame)" in pending_item_scroll_body, "measured visible latest card should not jump to edge-peek alignment")
require("return 0" in target_body, "first/latest card with no leading cards should reset offset to zero")
require("focusedItemLeadingX" in target_body and "horizontalContentPadding" in focused_leading_body, "focused item alignment must preserve left content padding")
require("leadingPeekWidth" in focused_leading_body, "focused item with leading cards must expose a leading peek")
require("oneSixthPeekWidth" in view and "/ 6" in view, "peek width should be based on one sixth of a card")
require("horizontalCardSpacing : 0" in focused_leading_body, "leading peek must account for inter-card spacing")

require("HistoryScrollCoordinator.shared.visibleDocumentRect" in partial_reveal_body, "edge reveal should use the NSScrollView document viewport")
require("revealPartiallyVisibleCardIfNeeded(id, animated: true)" in reveal_body, "edge reveal should animate by default")
require("HistoryScrollCoordinator.shared.scrollToOffset(targetOffset, animated: animated)" in animated_reveal_body, "edge reveal should animate to a target offset")
require("frame.minX < leftVisibleEdge" in partial_reveal_body and "frame.maxX > rightVisibleEdge" in partial_reveal_body, "edge reveal should handle both left and right clipped cards")
require("edgeRevealTrailingX" in partial_reveal_body and "edgeRevealLeadingX" in partial_reveal_body, "edge reveal should leave about one sixth of the adjacent card visible")
require("frame.minX - edgeRevealLeadingX" in partial_reveal_body, "left-edge reveal should expose the previous card")
require("frame.maxX + edgeRevealTrailingX" in partial_reveal_body, "right-edge reveal should expose the next card")
require("cardDocumentFrame(for: id)" in partial_reveal_body, "edge reveal should align cards in document coordinates")
require("renderedItemIndex(for id: HistoryPreviewItem.ID)" in view, "card frames should be derived from the rendered item index")
require("cardDocumentFrame(forRenderedIndex itemIndex: Int)" in view, "card frames should use stable document-space math")
require("historyCardWidth + horizontalCardSpacing" in view, "card document frames must account for spacing")
require("applyPendingItemScrollIfMeasured(pendingItemScrollID)" in view, "pending scroll alignment must retry when requested")
card_mouse_body = function_body(card, "private final class FileCardDragSourceNSView")
require("clickMoveTolerance" in card_mouse_body, "card click handling must ignore drag movement")
require("override func mouseDown" in card_mouse_body and "override func mouseUp" in card_mouse_body, "card click handling must use AppKit mouse events")
require("guard hypot(deltaX, deltaY) <= clickMoveTolerance" in card_mouse_body, "drag movement must not trigger card selection")
require("addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp])" not in card, "card clicks must not install one local monitor per card")

require("HorizontalScrollWheelRedirector(scope: .cardRail)" in view, "main card rail must be the only coordinator-bound redirector")
require(view.count("HorizontalScrollWheelRedirector(scope: .cardRail)") == 1, "only one card rail redirector should bind HistoryScrollCoordinator")
require(view.count("HorizontalScrollWheelRedirector(scope: .auxiliaryRail)") >= 2, "group/search rails should keep auxiliary horizontal wheel redirects")
require("guard scope == .cardRail else" in view, "auxiliary rails must not update or save HistoryScrollCoordinator offsets")

update_card_rail_body = function_body(view, "private func updateCardRailCoordinatorIfNeeded")
save_card_rail_body = function_body(view, "private func saveCardRailOffsetIfNeeded")
require(
    "guard scope == .cardRail else" in update_card_rail_body
    and "HistoryScrollCoordinator.shared.update(scrollView: scrollView)" in update_card_rail_body,
    "auxiliary rail redirectors must return before updating HistoryScrollCoordinator",
)
require(
    "guard scope == .cardRail else" in save_card_rail_body
    and "HistoryScrollCoordinator.shared.saveOffset(nextX)" in save_card_rail_body,
    "auxiliary rail redirectors must return before saving HistoryScrollCoordinator offsets",
)

require("func scrollToOffset(_ offsetX: CGFloat, animated: Bool, suppressUserOffsetSave: Bool = false)" in coordinator_body, "coordinator must expose absolute offset scrolling")
require("var currentOffset: CGFloat" in coordinator_body, "coordinator must expose current offset for alignment math")
require("var visibleDocumentRect: CGRect?" in coordinator_body, "coordinator must expose the contentView document viewport")
require("saveOffset(preserveSavedOffset ?? nextX)" in coordinator_body, "coordinator should save clamped offsets after programmatic scrolling")
require("scrollToClampedOffset" in coordinator_body, "absolute and relative scrolling should share clamping logic")
require("restoreSavedOffset()" not in coordinator_update_body, "coordinator binding must not replay old offsets during SwiftUI updates")
require("applyPendingBindingScrollIfNeeded()" in coordinator_update_body, "coordinator should replay only explicit pending scroll requests after binding")
require("ClipViewBoundsObserver" in coordinator_body and "NSView.boundsDidChangeNotification" in clip_observer_body, "coordinator must observe real clip-view bounds changes")
require("guard !isProgrammaticScroll" in clip_bounds_body and "saveOffset(clipView.bounds.minX)" in clip_bounds_body, "user viewport changes must save the real AppKit offset")

require("@State private var pendingItemScrollRetryCount" in view, "pending item scroll must track finite retries")
require("pendingItemScrollMaxRetryCount" in view, "pending item scroll must have a retry limit")
require("pendingItemScrollRetryCount < pendingItemScrollMaxRetryCount" in view, "pending item scroll must stop retrying")
require("FileCardDragSourceNSView" in card and "selectCardForPrimaryClick(item)" in view, "card clicks should be handled by the AppKit interaction layer")
require("if pendingLatestFocusItemID == nil" in preview_rebuild_body and "restoreSelectionAfterPreviewRebuild" in preview_rebuild_body, "preview rebuild must not restore an old selection over pending newest-item focus")

assert_no_forbidden_owned_content()
print_non_owned_dirty_note()

require("HistoryScrollCoordinator.shared.restoreSavedOffset()" in controller, "controller should keep restoring saved offsets on show")

print("PASS: history card scroll alignment static checks")
