#!/usr/bin/env python3
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
HISTORY_WINDOW = ROOT / "Sources/ClipEase/Features/HistoryWindow"
PREVIEW_POPOVER = HISTORY_WINDOW / "HistoryPreviewPopoverView.swift"
QUICKLOOK_BRIDGE = HISTORY_WINDOW / "HistoryFileQuickLookPreviewView.swift"


def fail(message: str) -> None:
    print(f"FAIL: {message}")
    sys.exit(1)


def require(condition: bool, message: str) -> None:
    if not condition:
        fail(message)


def method_source(source: str, method_name: str) -> str:
    declaration = re.search(rf"\n\s+(?:static\s+)?(?:private\s+)?func\s+{re.escape(method_name)}\b", source)
    if declaration is None:
        fail(f"missing {method_name}")
    start = declaration.start()
    next_method = re.search(r"\n\s+(?:static\s+)?(?:private\s+)?func\s+\w+", source[start + len(method_name):])
    next_type = re.search(r"\n(?:private\s+)?(?:final\s+)?(?:class|struct|enum)\s+", source[start + len(method_name):])
    candidates = [
        start + len(method_name) + match.start()
        for match in [next_method, next_type]
        if match is not None
    ]
    end = min(candidates) if candidates else len(source)
    return source[start:end]


def property_source(source: str, property_name: str) -> str:
    declaration = re.search(rf"\n\s+(?:static\s+)?(?:private\s+)?var\s+{re.escape(property_name)}\b", source)
    if declaration is None:
        fail(f"missing {property_name}")
    start = declaration.start()
    next_member = re.search(
        r"\n\s+(?:static\s+)?(?:private\s+)?(?:func|var)\s+\w+",
        source[start + len(property_name):],
    )
    next_type = re.search(r"\n(?:private\s+)?(?:final\s+)?(?:class|struct|enum)\s+", source[start + len(property_name):])
    candidates = [
        start + len(property_name) + match.start()
        for match in [next_member, next_type]
        if match is not None
    ]
    end = min(candidates) if candidates else len(source)
    return source[start:end]


def verify_clickable_file_list(popover: str) -> None:
    require("@State private var selectedFileReferenceID" in popover,
            "popover must keep selected file reference state")
    require("selectedFileReference(from: references)" in popover,
            "preview pane must derive its file from current selection")
    require("synchronizeSelectedFileReference(with: references)" in popover,
            "selection must be initialized and kept valid as references change")
    require("ForEach(references)" in popover and "Button {" in popover,
            "right-side file rows must be clickable buttons")
    require("selectedFileReferenceID = reference.id" in popover,
            "clicking a row must update selectedFileReferenceID")
    require("isSelected: selectedFileReferenceID == reference.id" in popover,
            "file rows must receive selected state")
    require(".fill(isSelected ? Color(red:" in popover,
            "selected row must have a visible background fill")


def verify_truncation_and_layout(popover: str) -> None:
    list_source = method_source(popover, "fileReferenceRow")
    require(list_source.count(".truncationMode(.middle)") >= 3,
            "file list title/path/status should use middle truncation")
    require(list_source.count(".lineLimit(") >= 3,
            "file list text must have line limits")
    require(".frame(maxWidth: .infinity, alignment: .leading)" in list_source,
            "file list row content must be constrained to avoid overflow")
    require(".contentShape(" in list_source,
            "file row hit target should cover the row")


def verify_no_duplicate_quicklook_caption(popover: str) -> None:
    require("filePreviewCaption" not in popover,
            "Quick Look content area must not include duplicate bottom caption")
    pane_source = method_source(popover, "filePreviewPane")
    require(".overlay(alignment: .bottomLeading)" not in pane_source,
            "Quick Look pane must not overlay file name/path caption")
    require("HistoryFileQuickLookPreviewView(url:" in pane_source,
            "preview pane must continue embedding HistoryFileQuickLookPreviewView")
    footer_source = property_source(popover, "footer")
    require("if item.type != .file" in footer_source,
            "file popover footer must not show item.footer path text")
    require("Text(item.footer)" in footer_source,
            "non-file popover footer should keep item.footer")
    require("Text(item.relativeTime)" in footer_source,
            "file popover footer should retain non-duplicative relative time")


def verify_interactive_preview_and_selectable_fallback(popover: str, bridge: str) -> None:
    require("HistoryInteractiveQuickLookContainerView" in bridge,
            "QLPreviewView must be wrapped in an interactive container")
    require("override var acceptsFirstResponder: Bool" in bridge,
            "Quick Look container must accept first responder")
    require("window?.makeFirstResponder(previewView)" in bridge,
            "Quick Look container must forward clicks toward the preview view")
    require("return HistoryInteractiveQuickLookContainerView(previewView: view)" in bridge,
            "makeNSView must return the interactive Quick Look container")
    require("Self.quickLookPreviewView(from: view)" in bridge,
            "update/dismantle must resolve the embedded QLPreviewView")
    require(bridge.count("isSelectable = true") >= 2,
            "AppKit fallback file name and path labels must be selectable")
    fallback_source = method_source(popover, "fileFallbackPreview")
    require(fallback_source.count(".textSelection(.enabled)") >= 3,
            "SwiftUI fallback file name/path text must be selectable")


def verify_scope_guard(popover: str, bridge: str) -> None:
    combined = "\n".join([popover, bridge])
    forbidden_tokens = [
        "QLPreviewPanel",
        "NSPasteboard",
        "writeObjects",
        "copyItem(",
        "moveItem(",
        "removeItem(",
        "startAccessingSecurityScopedResource",
        "bookmark",
    ]
    for token in forbidden_tokens:
        require(token not in combined, f"quicklook interaction fix must not add forbidden scope: {token}")


def main() -> None:
    popover = PREVIEW_POPOVER.read_text(encoding="utf-8")
    bridge = QUICKLOOK_BRIDGE.read_text(encoding="utf-8")

    verify_clickable_file_list(popover)
    verify_truncation_and_layout(popover)
    verify_no_duplicate_quicklook_caption(popover)
    verify_interactive_preview_and_selectable_fallback(popover, bridge)
    verify_scope_guard(popover, bridge)
    print("OK Stage 9 Quick Look interaction checks passed")


if __name__ == "__main__":
    main()
