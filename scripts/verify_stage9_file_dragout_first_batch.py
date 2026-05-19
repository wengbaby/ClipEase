#!/usr/bin/env python3
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CARD_VIEW = ROOT / "Sources/ClipEase/Features/HistoryWindow/HistoryCardView.swift"
WINDOW_VIEW = ROOT / "Sources/ClipEase/Features/HistoryWindow/HistoryWindowView.swift"
PREVIEW_ITEM = ROOT / "Sources/ClipEase/Features/HistoryWindow/HistoryPreviewItem.swift"


def fail(message: str) -> None:
    print(f"FAIL: {message}")
    sys.exit(1)


def require(condition: bool, message: str) -> None:
    if not condition:
        fail(message)


def body_of_function(source: str, name: str) -> str:
    match = re.search(rf"\bfunc\s+{re.escape(name)}\b[^\{{]*\{{", source)
    if not match:
        fail(f"missing function {name}")

    return balanced_body(source, match.end(), match.end())


def body_of_type(source: str, declaration: str) -> str:
    match = re.search(rf"\b{re.escape(declaration)}\b[^\{{]*\{{", source)
    if not match:
        fail(f"missing {declaration}")

    return balanced_body(source, match.end(), match.end())


def balanced_body(source: str, start: int, index: int) -> str:
    depth = 1
    while index < len(source) and depth > 0:
        if source[index] == "{":
            depth += 1
        elif source[index] == "}":
            depth -= 1
        index += 1
    return source[start:index - 1]


def verify_file_drag_source(card_view: str, window_view: str) -> None:
    require("FileCardDragSourceView" in card_view, "HistoryCardView must mount a file drag source bridge")
    require("NSViewRepresentable" in card_view and "NSDraggingSource" in card_view,
            "file drag-out must use an AppKit drag source bridge")
    require("onFileDragStatus: showStatus" in window_view,
            "HistoryWindowView must wire drag source status into the existing status path")

    bridge = body_of_type(card_view, "private final class FileCardDragSourceNSView")
    representable = body_of_type(card_view, "private struct FileCardDragSourceView")
    combined = "\n".join([bridge, representable])

    require("item?.type == .file" in bridge and "item.type == .file" in bridge,
            "drag source must only activate for .file cards")
    require("FileManager.default.fileExists(atPath: url.path)" in bridge,
            "drag source must check file existence immediately before dragging")
    require("URL(fileURLWithPath: reference.path).standardizedFileURL" in bridge,
            "drag source must use standardized local file URLs")
    require("NSDraggingItem(pasteboardWriter: url as NSURL)" in bridge,
            "drag source must write NSURL file URL pasteboard writers")
    require(".string" not in bridge and "setString" not in bridge and "NSItemProvider" not in bridge,
            "drag source must not write text paths or SwiftUI item providers")
    require(".onDrag" not in card_view and ".draggable" not in card_view,
            "file drag-out must not use SwiftUI .onDrag/.draggable")

    validator = body_of_function(bridge, "validFileDragURLs")
    require("compactMap" in validator and "return nil" in validator,
            "validator must drop invalid references")
    require("hasInvalidReferences = true" in validator,
            "validator must track partial/all invalid references")

    drag_start = body_of_function(bridge, "startFileDrag")
    require("guard !result.urls.isEmpty else" in drag_start and "onInvalid?()" in drag_start,
            "all-invalid drag must not start a valid dragging session and must show status")
    require("if result.hasInvalidReferences" in drag_start and "onPartial?()" in drag_start,
            "partial invalid drag must expose a partial status path")
    require("beginDraggingSession(with: draggingItems" in drag_start,
            "valid file URLs must start an AppKit dragging session")

    require('"未找到可拖出的文件"' in card_view, "all-invalid status text must be present")
    require('"已拖出可用文件"' in card_view, "partial-invalid status text must be present")

    forbidden = [
        "copyItem(",
        "moveItem(",
        "removeItem(",
        "startAccessingSecurityScopedResource",
        "securityScoped",
        "bookmark",
        "temporaryDirectory",
        "NSTemporaryDirectory",
        "NSWorkspace.shared.open",
        "CREATE TABLE",
        "CREATE INDEX",
        "Repository",
        "ClipboardItem(",
        "favorite",
        "management",
        "JSON",
    ]
    for token in forbidden:
        require(token not in combined, f"drag source must not introduce forbidden token {token}")


def verify_preview_helper_scope(preview_item: str) -> None:
    require("HistoryFilePreviewReference" in preview_item and "filePreviewReferences" in preview_item,
            "drag-out should use the lightweight preview file references")
    require("ClipboardFileReference" not in preview_item,
            "HistoryPreviewItem must not expose storage file references directly")


def main() -> None:
    card_view = CARD_VIEW.read_text(encoding="utf-8")
    window_view = WINDOW_VIEW.read_text(encoding="utf-8")
    preview_item = PREVIEW_ITEM.read_text(encoding="utf-8")
    verify_file_drag_source(card_view, window_view)
    verify_preview_helper_scope(preview_item)
    print("OK Stage 9 file drag-out first batch checks passed")


if __name__ == "__main__":
    main()
