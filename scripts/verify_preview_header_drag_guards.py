#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
POPOVER_VIEW = ROOT / "Sources/ClipEase/Features/HistoryWindow/HistoryPreviewPopoverView.swift"
WINDOW_CONTROLLER = ROOT / "Sources/ClipEase/Features/HistoryWindow/HistoryPreviewWindowController.swift"


def main() -> None:
    popover_view = POPOVER_VIEW.read_text(encoding="utf-8")
    window_controller = WINDOW_CONTROLLER.read_text(encoding="utf-8")

    required = [
        "typealias PreviewHeaderDragCompletion = (_ initialMouseDownEvent: NSEvent, _ dragEvent: NSEvent) -> Void",
        "let onDetachDrag: () -> PreviewHeaderDragCompletion?",
        "dragCompletion?(initialMouseDownEvent, event)",
        "private func dragPanelManually(",
        "private func dragDetachedPreview(_ panel: NSPanel) -> PreviewHeaderDragCompletion",
    ]
    forbidden = [
        "let dragWindow = window\n        let dragCompletion = onDragStarted()\n        dragWindow?.performDrag(with: initialMouseDownEvent)",
        "dragWindow?.performDrag(with: initialMouseDownEvent)",
        "performDrag(with:",
        "dragCompletion?()",
        "onDetachDrag: { nil }",
    ]

    failures: list[str] = []
    combined = "\n".join([popover_view, window_controller])
    for snippet in required:
        if snippet not in combined:
            failures.append(f"Missing preview header drag guard: {snippet}")

    for snippet in forbidden:
        if snippet in combined:
            failures.append(f"Forbidden stale preview header drag path: {snippet}")

    if failures:
        print("Preview header drag guard failed:")
        print("\n".join(failures))
        raise SystemExit(1)

    print("OK preview header drag uses current drag event")


if __name__ == "__main__":
    main()
