#!/usr/bin/env python3
from pathlib import Path

root = Path(__file__).resolve().parents[1]
view = root / "Sources/ClipEase/Features/HistoryWindow/HistoryWindowView.swift"
card = root / "Sources/ClipEase/Features/HistoryWindow/HistoryCardView.swift"
input_state = root / "Sources/ClipEase/Features/HistoryWindow/HistoryWindowInputState.swift"
store = root / "Sources/ClipEase/Core/Storage/ClipboardHistoryStore.swift"

view_text = view.read_text(encoding="utf-8")
card_text = card.read_text(encoding="utf-8")
input_text = input_state.read_text(encoding="utf-8")
store_text = store.read_text(encoding="utf-8")

def function_body(text: str, signature: str) -> str:
    if signature not in text:
        return ""
    return text.split(signature, 1)[1].split("\n    private func ", 1)[0]

context_select_body = function_body(
    view_text,
    "private func selectCardForContextMenu(_ item: HistoryPreviewItem)"
)
latest_focus_body = function_body(
    view_text,
    "private func fulfillPendingLatestFocusIfPossible()"
)
latest_transition_body = function_body(
    view_text,
    "private func scheduleLatestProgrammaticTransition("
)
latest_focus_offset_body = function_body(
    view_text,
    "private func latestClipboardFocusTargetOffset(for id: HistoryPreviewItem.ID)"
)
latest_filter_body = function_body(
    view_text,
    "private func resetFiltersForLatestItemFocus()"
)

checks = {
    "window visibility is observable by HistoryWindowView": (
        "@Published private(set) var isWindowVisible" in input_text
        and "@Published private(set) var isWindowPresented" in input_text
        and "@Published private(set) var isWindowPinnedOpen" in input_text
        and "func toggleWindowPinnedOpen()" in input_text
        and ".onChange(of: inputState.isWindowVisible)" in view_text
        and "syncLatestItemFocusIfNeeded(sourceItems: store.items)" in view_text
        and "inputState.setWindowPresented(true)" in (root / "Sources/ClipEase/Features/HistoryWindow/HistoryWindowController.swift").read_text(encoding="utf-8").split("guard shouldAnimate else", 1)[0]
        and "if !HistoryScrollCoordinator.shared.hasPendingExplicitOffset" in (root / "Sources/ClipEase/Features/HistoryWindow/HistoryWindowController.swift").read_text(encoding="utf-8")
    ),
    "pinned window debug mode keeps history open": (
        "Image(systemName: inputState.isWindowPinnedOpen ? \"pin.fill\" : \"pin\")" in view_text
        and "private func toggleWindowPinnedOpen()" in view_text
        and "private func closeAfterPasteIfNeeded()" in view_text
        and "guard !inputState.isWindowPinnedOpenSnapshot else" in (root / "Sources/ClipEase/Features/HistoryWindow/HistoryWindowController.swift").read_text(encoding="utf-8")
        and "shouldPassThroughWhileWindowPinned" in (root / "Sources/ClipEase/Features/HistoryWindow/HistoryKeyboardEventTap.swift").read_text(encoding="utf-8")
        and "case .copy, .copyPlainText" in (root / "Sources/ClipEase/Features/HistoryWindow/HistoryKeyboardEventTap.swift").read_text(encoding="utf-8")
    ),
    "new latest item is focused after rebuild and search": (
        "pendingLatestFocusItemID" in view_text
        and "latestPresentedItemID" in view_text
        and "fulfillPendingLatestFocusIfPossible()" in view_text
        and "scheduleLatestProgrammaticTransition(" in latest_focus_body
        and "resetFiltersForLatestItemFocus()" in view_text
        and "selectedItemID = pendingLatestFocusItemID" in latest_focus_body
        and "scrollToItemWhenRendered(id, animated: shouldAnimatePendingItemScroll)" in latest_transition_body
        and "currentLatestClipboardFocusGeneration == latestClipboardFocusGeneration" in view_text
        and "convergeLatestClipboardFocusIfNeeded()" in view_text
    ),
    "latest focus distinguishes new and refreshed card motion": (
        "enum Reason: Equatable" in store_text
        and "items.removeAll { duplicateIDs.contains($0.id) }" in store_text
        and "latestItemFocusRequest = ClipboardItemFocusRequest(itemID: insertedItem.id, reason: .inserted)" in store_text
        and "reason: .inserted" in store_text
        and "private var itemIDsByHash" in store_text
        and "let duplicateIDs = itemIDsByHash[hash] ?? []" in store_text
        and "@State private var pendingLatestFocusReason" in view_text
        and "@State private var pendingLatestFocusLockID" in view_text
        and "selectedItemID = itemID" in view_text
        and "animateWhenPresented: inputState.isWindowPresentedSnapshot" in latest_focus_body
        and ".easeOut(duration: pendingLatestFocusReason == .refreshed ? 0.34 : 0.30)" in view_text
        and "inputState.isWindowPresentedSnapshot" in latest_transition_body
    ),
    "latest focus scroll is single-pass and suppresses offset rollback": (
        "private func finishLatestFocusIfNeeded" in view_text
        and "suppressUserOffsetSave: pendingLatestFocusLockID == id" in view_text
        and "func scrollToOffset(_ offsetX: CGFloat, animated: Bool, suppressUserOffsetSave: Bool = false)" in view_text
        and "scheduleProgrammaticJump(to id: ClipboardItem.ID)" in view_text
        and "scheduleLatestProgrammaticTransition(\n            to: id," in view_text
        and "applyPendingProgrammaticJumpIfPossible()" in latest_transition_body
        and "scrollToItemWhenRendered(id, animated: false)" in view_text
    ),
    "latest clipboard updates always align target as first visible card": (
        "pendingLatestFocusLockID == id" in view_text
        and "latestClipboardFocusTargetOffset(for: id)" in view_text
        and "store.items.firstIndex(where: { $0.id == id })" in latest_focus_offset_body
        and "historyCardWidth + horizontalCardSpacing" in latest_focus_offset_body
        and "frame.minX - horizontalContentPadding" not in latest_focus_offset_body
        and "cardDocumentFrame(for: id)" not in latest_focus_offset_body
        and "suppressUserOffsetSave: true" in view_text
        and "finishLatestFocusIfSettled(id, targetOffset: targetOffset)" in view_text
        and "pendingProgrammaticJumpItemID = id" in view_text
    ),
    "latest item focus clears filters that could hide the new card": (
        "selectedGroup = .all" in latest_filter_body
        and "searchText = \"\"" in latest_filter_body
        and "searchCriteria = HistorySearchCriteria()" in latest_filter_body
        and "isSearchVisible = false" in latest_filter_body
        and "inputState.setSearchVisible(false)" in latest_filter_body
    ),
    "latest item scroll uses measured offset hook": (
        "@State private var pendingItemScrollID" in view_text
        and "@State private var itemScrollRequestID" in view_text
        and ".onChange(of: itemScrollRequestID)" in view_text
        and "applyPendingItemScrollIfMeasured(pendingItemScrollID)" in view_text
        and "targetScrollOffsetForFocusedItem" in view_text
        and "HistoryScrollCoordinator.shared.scrollToOffset(\n            targetOffset," in view_text
    ),
    "right click updates selected card before context menu actions": (
        "FileCardDragSourceNSView" in card_text
        and "selectCardForContextMenu(item)" in view_text
        and "override func rightMouseDown(with event: NSEvent)" in card_text
        and "selectedItemID = item.id" in context_select_body
    ),
    "selected border has top clearance and draw priority": (
        "selectedCardTopContentInset" in view_text
        and ".padding(.top, selectedCardTopContentInset)" in view_text
        and "private func historyCard(_ item: HistoryPreviewItem)" in view_text
        and "let isSelected = selectedItemID == item.id" in view_text
        and ".zIndex(isSelected ? 1 : 0)" in view_text
    ),
}

failed = [name for name, passed in checks.items() if not passed]
if failed:
    for name in failed:
        print(f"FAIL: {name}")
    raise SystemExit(1)

for name in checks:
    print(f"PASS: {name}")
