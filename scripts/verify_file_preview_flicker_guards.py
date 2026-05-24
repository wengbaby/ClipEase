#!/usr/bin/env python3
from pathlib import Path

root = Path(__file__).resolve().parents[1]
controller = (root / "Sources/ClipEase/Features/HistoryWindow/HistoryPreviewWindowController.swift").read_text()
popover = (root / "Sources/ClipEase/Features/HistoryWindow/HistoryPreviewPopoverView.swift").read_text()

required_controller = [
    "let shouldLoadImmediately = item.type == .text || item.type == .color || item.type == .file",
]

required_popover = [
    "private var previewContentTransitionID: String {",
    "if item.type == .file {",
    "return [",
    "item.id.uuidString,",
    "item.type.rawValue",
    "].joined(separator: \":\")",
]

missing = [snippet for snippet in required_controller if snippet not in controller]
missing += [snippet for snippet in required_popover if snippet not in popover]
if missing:
    raise SystemExit("Missing file preview flicker guard snippets:\n" + "\n".join(missing))

preview_id_start = popover.index("private var previewContentTransitionID: String {")
preview_id_end = popover.index("@ViewBuilder\n    private var linkPreviewOverlay", preview_id_start)
preview_id_body = popover[preview_id_start:preview_id_end]

file_branch_start = preview_id_body.index("if item.type == .file {")
file_branch_end = preview_id_body.index("\n        }\n\n        return [", file_branch_start) + len("\n        }")
file_branch = preview_id_body[file_branch_start:file_branch_end]

for forbidden in [
    "selectedFileReferenceID",
    "isContentReady",
]:
    if forbidden in file_branch:
        raise SystemExit(f"File preview transition identity must not depend on {forbidden}")

print("OK file preview avoids repeated open-time content transitions")
