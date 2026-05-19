#!/usr/bin/env python3
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CARD_VIEW = ROOT / "Sources/ClipEase/Features/HistoryWindow/HistoryCardView.swift"


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
    text = CARD_VIEW.read_text(encoding="utf-8")
    preview_body = property_body(text, "preview")
    text_body = property_body(text, "textPreview")
    link_body = property_body(text, "linkPreview")
    image_body = property_body(text, "imagePreview")

    require("case .text:\n            textPreview" in preview_body,
            "text cards must use the dedicated text preview layout")
    require(".frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)" in text_body,
            "text preview must fill the available card content area")
    require("textPreviewLineLimit" in text_body and ".truncationMode(.tail)" in text_body,
            "text preview must constrain overflow with tail truncation")
    require(".mask(alignment: .bottom)" in text_body and "LinearGradient(" in text_body,
            "text preview must keep a bottom fade mask")

    require("Text(item.linkTitle ?? item.preview)" not in link_body and "Text(item.preview)" not in link_body,
            "link preview content area must not duplicate title or URL text")
    require("private var linkFooter: some View" in text and "Text(linkFooterTitle)" in text and "Text(linkFooterURL)" in text,
            "link footer must render title above URL")
    require(".frame(maxWidth: .infinity, maxHeight: .infinity)" not in link_body,
            "link preview must not stretch an empty middle area between icon and title")

    require(".scaledToFit()" in image_body,
            "image cards must preserve image aspect ratio")
    require(".padding(10)" not in image_body,
            "image cards must not add forced padding around fitted images")
    require(".frame(width: 250, height: 270)" in text,
            "card layout must keep stable card dimensions")

    print("OK Maint7 card visual layout checks passed")


if __name__ == "__main__":
    main()
