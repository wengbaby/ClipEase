#!/usr/bin/env python3
import sys
import re
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


def property_body(source: str, property_name: str) -> str:
    pattern = rf"private var {re.escape(property_name)}: some View \{{([\s\S]*?)\n    \}}"
    match = re.search(pattern, source)
    if not match:
        fail(f"missing {property_name}")
    return match.group(1)


def main() -> None:
    card_text = CARD_VIEW.read_text(encoding="utf-8")
    preview_text = PREVIEW_ITEM.read_text(encoding="utf-8")
    text_body = property_body(card_text, "textPreview")
    link_body = property_body(card_text, "linkPreview")

    require("let richTextFileName: String?" in preview_text,
            "HistoryPreviewItem must carry richTextFileName")
    require("self.richTextFileName = item.richTextFileName" in preview_text,
            "HistoryPreviewItem must preserve rich text attachment references")

    require("RichTextCardPreview(" in card_text and "ClipEaseStoragePaths.richTextFileURL" in card_text,
            "text cards with richTextFileName must read existing RichTexts attachments")
    require("NSAttributedString(" in card_text and "documentType: NSAttributedString.DocumentType.rtf" in card_text,
            "rich text cards must parse RTF as attributed text")
    require("previewTextPreservingRichAttributes" in card_text,
            "rich text preview must preserve source attributes")
    require("maxPreviewCharacters" in card_text and "attributedSubstring(from:" in card_text,
            "rich text card preview must limit expensive RTF rendering")
    require("RichTextCardPreview(" in text_body and ".frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)" in text_body,
            "rich text cards must fill the text preview area")
    require("textPreviewLineLimit" in card_text and ".padding(.bottom, 2)" in card_text,
            "plain text cards must extend content toward the bottom")
    require(".mask(alignment: .bottom)" in card_text and ".frame(height: 34)" in card_text,
            "text cards must keep bottom fade")

    require("Text(item.linkTitle ?? item.preview)" not in link_body,
            "link content area must not render URL title")
    require("Text(item.preview)" not in link_body,
            "link content area must not render URL address")
    require("Text(linkFooterTitle)" in card_text and ".font(.system(size: 13, weight: .bold))" in card_text,
            "link footer must show bold URL title above URL")
    require("Text(linkFooterURL)" in card_text and ".truncationMode(.middle)" in card_text,
            "link footer must show truncated URL below title")

    print("OK Maint8 rich text and link/text layout checks passed")


if __name__ == "__main__":
    main()
