#!/usr/bin/env python3
from pathlib import Path

root = Path(__file__).resolve().parents[1]
files = [
    root / "Sources/ClipEase/Features/HistoryWindow/HistoryWindowView.swift",
    root / "Sources/ClipEase/Features/HistoryWindow/HistoryWindowController.swift",
    root / "Sources/ClipEase/Features/HistoryWindow/HistoryWindowRenderState.swift",
]
text = "\n".join(path.read_text() for path in files)

required = [
    'private var renderedItems: [HistoryPreviewItem]',
    'filteredItems',
    'schedulePersistSavedOffsets()',
    'try? await Task.sleep(nanoseconds: 500_000_000)',
    'scheduleOffsetChangeNotification',
    'pendingOffsetNotificationTask',
    'savedOffset > maxX + 0.5',
    'clipView.bounds.minX < savedOffset',
    'UserDefaults.standard.set(selectedItemID.uuidString, forKey: "history.lastSelectedItemID")',
    'HistoryScrollCoordinator.shared.restoreSavedOffset()',
]

missing = [snippet for snippet in required if snippet not in text]
if missing:
    raise SystemExit("Missing viewport restore guard(s):\n" + "\n".join(missing))

print("OK viewport restore persistence guards present")
