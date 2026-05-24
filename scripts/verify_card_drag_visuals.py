#!/usr/bin/env python3
import re
from pathlib import Path

root = Path(__file__).resolve().parents[1]
card_path = root / "Sources/ClipEase/Features/HistoryWindow/HistoryCardView.swift"
view_path = root / "Sources/ClipEase/Features/HistoryWindow/HistoryWindowView.swift"
card = card_path.read_text(encoding="utf-8")
view = view_path.read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(message)


def body_of_function(source: str, name: str) -> str:
    match = re.search(rf"\bfunc\s+{re.escape(name)}\b[^\{{]*\{{", source)
    require(match is not None, f"missing function {name}")
    index = match.end()
    depth = 1
    while index < len(source) and depth > 0:
        if source[index] == "{":
            depth += 1
        elif source[index] == "}":
            depth -= 1
        index += 1
    return source[match.end():index - 1]


snapshot = body_of_function(card, "snapshotDragImage")
frames = body_of_function(card, "setDragFrames")
drag = body_of_function(card, "handleDrag")
fallback = body_of_function(card, "fallbackDragImage")
bridge = card[card.find("private final class FileCardDragSourceNSView"):]

required = [
    ("private final class CardDragPreviewWindowController", card, "drag preview must use a dedicated floating window"),
    ("dragPreviewController.show(", bridge, "drag source must show the floating preview before starting AppKit drag"),
    ("dragPreviewController.update(mouseScreenLocation:", bridge, "drag source must update floating preview during dragging"),
    ("dragPreviewController.finish()", bridge, "drag source must close floating preview when dragging ends"),
    ("func draggingSession(_ session: NSDraggingSession, movedTo screenPoint: NSPoint)", bridge, "drag source must track AppKit drag movement"),
    ("func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation)", bridge, "drag source must clean up after AppKit drag session"),
    ("onMouseExitedWindow?()", bridge, "drag source must close the history window once the cursor exits the window"),
    ("let onMouseExitedWindow: () -> Void", card, "HistoryCardView must accept a window-close callback for out-of-window drags"),
    ("onMouseExitedWindow: onMouseExitedWindow", card, "drag source bridge must receive the window-close callback"),
    ("onMouseExitedWindow: closeWindowForCardDrag", view, "HistoryWindowView must close the main window for out-of-window card drags"),
    ("private func closeWindowForCardDrag()", view, "HistoryWindowView must expose a dedicated drag-close helper"),
    ("return NSImage(size: NSSize(width: 1, height: 1))", card, "system drag image must be transparent because the floating preview owns visuals"),
    ("let scale: CGFloat = isInsideSourceCard ? 1.06 : 0.48", card, "floating preview must grow inside card bounds and shrink outside card bounds"),
    ("guard lastInsideSourceCard != isInsideSourceCard else", card, "floating preview must move immediately while size state is unchanged"),
    ("panel.setFrame(nextFrame, display: false)", card, "floating preview must track the mouse without animating every move"),
    ("context.duration = 0.08", card, "floating preview frame changes must be fast enough to follow the cursor"),
    ("panel.level = .screenSaver", card, "floating preview must render above the history window"),
    ("panel.ignoresMouseEvents = true", card, "floating preview must not steal drag events"),
    ("fraction: 0.86", snapshot, "floating preview snapshot must be semi-transparent"),
    ("shadowPadding", snapshot, "drag snapshot must include shadow padding"),
    ("context.setShadow", snapshot, "drag snapshot must use a system-like shadow"),
    ("location.x - imageSize.width / 2", frames, "drag image must follow mouse center on x axis"),
    ("location.y - imageSize.height / 2", frames, "drag image must follow mouse center on y axis"),
    ("onClick?()", drag, "drag start must select/focus the dragged card first"),
    ("fraction: 0.82", fallback, "fallback drag image must match snapshot opacity"),
    ("selectCardForPrimaryClick(item)", view, "HistoryWindow must route drag-start focus through primary selection"),
]

missing = [message for snippet, haystack, message in required if snippet not in haystack]
if missing:
    raise SystemExit("Missing card drag visual guard(s):\n" + "\n".join(missing))

forbidden = [
    ("let scale: CGFloat = 0.82", snapshot, "floating preview snapshot must not be pre-shrunk before state scaling"),
    ("dragImage: cardDragImage", card, "AppKit drag image must not render the visible card snapshot directly"),
]
present_forbidden = [message for snippet, haystack, message in forbidden if snippet in haystack]
if present_forbidden:
    raise SystemExit("Forbidden card drag visual pattern(s):\n" + "\n".join(present_forbidden))

print("OK card drag visuals use a floating preview window with transparent AppKit drag images")
