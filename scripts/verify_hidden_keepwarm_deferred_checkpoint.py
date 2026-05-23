#!/usr/bin/env python3
from pathlib import Path

root = Path(__file__).resolve().parents[1]
source = root / "Sources/ClipEase/Features/HistoryWindow/HistoryWindowView.swift"
text = source.read_text()

required = [
    "@State private var hiddenResourceCheckpointTask: Task<Void, Never>?",
    "hiddenResourceCheckpointTask?.cancel()",
    "try? await Task.sleep(nanoseconds: 750_000_000)",
    "!inputState.isWindowPresentedSnapshot",
    'recordResourceCheckpoint("history.hidden.keepWarm.deferred")',
]

missing = [needle for needle in required if needle not in text]
if missing:
    raise SystemExit("Hidden keep-warm deferred checkpoint guard failed. Missing: " + ", ".join(missing))

note_start = text.index("    private func noteHistoryWindowHidden()")
note_end = text.index("    private func rebuildPreviewItemsIfNeededForVisibleWindow", note_start)
note_body = text[note_start:note_end]

if 'recordResourceCheckpoint("history.hidden.keepWarm")' in note_body:
    raise SystemExit("Hidden keep-warm must not synchronously request an immediate resource checkpoint.")

print("Hidden keep-warm deferred checkpoint guard passed.")
