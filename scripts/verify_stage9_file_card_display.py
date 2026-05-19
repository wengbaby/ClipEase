#!/usr/bin/env python3
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CARD_VIEW = ROOT / "Sources/ClipEase/Features/HistoryWindow/HistoryCardView.swift"
PREVIEW_ITEM = ROOT / "Sources/ClipEase/Features/HistoryWindow/HistoryPreviewItem.swift"


def fail(message: str) -> None:
    print(f"FAIL: {message}")
    sys.exit(1)


def require(condition: bool, message: str) -> None:
    if not condition:
        fail(message)


def block_after(source: str, marker: str, next_marker: str) -> str:
    start = source.find(marker)
    require(start != -1, f"missing block marker: {marker}")
    end = source.find(next_marker, start + len(marker))
    require(end != -1, f"missing next block marker after: {marker}")
    return source[start:end]


def verify_file_preview_body(text: str) -> None:
    body = block_after(text, "private var filePreview: some View", "private var multiFileIconStack")
    require("ZStack" in body, "file preview content should be icon-only and centered")
    require("multiFileIconStack" in body, "multi-file preview must use stacked icons")
    require('fileIcon(name: primaryFileIconName, size: 78)' in body,
            "single-file preview must use one centered file icon")
    require('.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)' in body,
            "file preview must be centered in the content area")

    forbidden = [
        "primaryFileTitle",
        "fileCountText",
        "fileFooterText",
        "filePathSummaries",
        "highlightedText",
        "Text(",
        "ForEach("
    ]
    for token in forbidden:
        require(token not in body, f"file preview content area must not render {token}")


def verify_multi_file_icon_stack(text: str) -> None:
    body = block_after(text, "private var multiFileIconStack: some View", "private func fileIcon")
    require(body.count("fileIcon(") >= 3, "multi-file preview must show stacked file icons")
    require(".offset(" in body and ".opacity(" in body,
            "multi-file icons should visibly stack instead of collapsing into one icon")
    require("Text(" not in body and "highlightedText" not in body,
            "multi-file content area must not render labels or paths")


def verify_footer_rules(text: str) -> None:
    footer_view = block_after(text, "private var footerView: some View", "private var fileFooter")
    require("if item.type == .file" in footer_view and "fileFooter" in footer_view,
            "file cards must use a dedicated footer")

    file_footer = block_after(text, "private var fileFooter: some View", "private var primaryFile")
    require("Text(fileFooterText)" in file_footer, "file footer must render controlled file footer text")
    require("if isMultiFilePreview" in file_footer,
            "multi-file and single-file footers must be rendered by separate branches")
    require(".lineLimit(1)" in file_footer and ".lineLimit(2)" in file_footer,
            "single-file footer must allow up to 2 lines while multi-file footer stays compact")
    require(".truncationMode(.middle)" in file_footer,
            "long single-file paths must truncate with ellipsis")

    footer_text = block_after(text, "private var fileFooterText: String", "private var filePathSummaries")
    require("guard !isMultiFilePreview else" in footer_text,
            "multi-file footer must take a separate path from single-file footer")
    require("fileCountText" in footer_text,
            "multi-file footer should keep the item count")
    require("primaryFile.path" in footer_text,
            "single-file footer should use the single file path")
    require("item.footer" in footer_text,
            "single-file footer should retain fallback footer text")

    multi_branch = footer_text.split("guard !isMultiFilePreview else", 1)[1].split("}", 1)[0]
    require("primaryFile.path" not in multi_branch and "item.footer" not in multi_branch,
            "multi-file footer must not display paths")


def verify_preview_item_still_searches_paths(text: str) -> None:
    require("filePreviewReferences.map(\\.displayName)" in text,
            "file display names must remain searchable")
    require("filePreviewReferences.map(\\.path)" in text,
            "file paths must remain searchable even when hidden from multi-file cards")


def main() -> None:
    card_text = CARD_VIEW.read_text(encoding="utf-8")
    preview_text = PREVIEW_ITEM.read_text(encoding="utf-8")

    verify_file_preview_body(card_text)
    verify_multi_file_icon_stack(card_text)
    verify_footer_rules(card_text)
    verify_preview_item_still_searches_paths(preview_text)

    print("OK Stage 9 file card display checks passed")


if __name__ == "__main__":
    main()
