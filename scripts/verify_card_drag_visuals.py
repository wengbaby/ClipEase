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

required = [
    ("let scale: CGFloat = 0.82", snapshot, "drag snapshot must be scaled to 0.82"),
    ("shadowPadding", snapshot, "drag snapshot must include shadow padding"),
    ("context.setShadow", snapshot, "drag snapshot must use a system-like shadow"),
    ("fraction: 0.82", snapshot, "drag snapshot must be semi-transparent"),
    ("location.x - imageSize.width / 2", frames, "drag image must follow mouse center on x axis"),
    ("location.y - imageSize.height / 2", frames, "drag image must follow mouse center on y axis"),
    ("onClick?()", drag, "drag start must select/focus the dragged card first"),
    ("fraction: 0.82", fallback, "fallback drag image must match snapshot opacity"),
    ("selectCardForPrimaryClick(item)", view, "HistoryWindow must route drag-start focus through primary selection"),
]

missing = [message for snippet, haystack, message in required if snippet not in haystack]
if missing:
    raise SystemExit("Missing card drag visual guard(s):\n" + "\n".join(missing))

print("OK card drag visuals use centered semi-transparent 0.82 snapshots")
