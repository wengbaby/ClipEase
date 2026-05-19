#!/usr/bin/env python3
from pathlib import Path

root = Path(__file__).resolve().parents[1]
view = root / "Sources/ClipEase/Features/HistoryWindow/HistoryWindowView.swift"
text = view.read_text()

required = [
    "latestClipboardFocusGeneration",
    "pendingLatestFocusTimestamp",
    "pendingLatestFocusReason",
    "pendingLatestFocusLockID",
    "pendingLatestFocusReason = newlyInsertedItemID == focusCandidateID ? .inserted : .refreshed",
    "pendingLatestFocusLockID = focusCandidateID",
    "selectedItemID = focusCandidateID",
    "private func focusRecentlyAddedItemOnShowIfNeeded(sourceItems: [ClipboardItem])",
    "focusRecentlyAddedItemOnShowIfNeeded(sourceItems: store.items)",
    "newestChangedItem.createdAt > latestPresentedItemTimestamp.addingTimeInterval(0.001)",
    "private func convergeLatestClipboardFocusIfNeeded()",
    "private func latestChangedFocusItemCandidate()",
    "private func latestChangedItemSort(_ left: ClipboardItem, _ right: ClipboardItem) -> Bool",
    "store.items.max",
    "newestByTimestamp.createdAt > pendingLatestFocusTimestamp.addingTimeInterval(0.001)",
    "pendingLatestFocusItemID != newestChangedItem.id",
    "pendingLatestFocusReason = .refreshed",
    "pendingLatestFocusLockID = newestChangedItem.id",
    "private func finishLatestFocusIfNeeded",
    "convergeLatestClipboardFocusIfNeeded()",
    "currentLatestClipboardFocusGeneration == latestClipboardFocusGeneration",
]

missing = [snippet for snippet in required if snippet not in text]
if missing:
    raise SystemExit("Missing latest clipboard focus convergence guard(s):\n" + "\n".join(missing))

print("OK latest clipboard focus convergence guards present")
