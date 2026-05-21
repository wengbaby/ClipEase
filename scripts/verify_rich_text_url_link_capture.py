#!/usr/bin/env python3
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MONITOR = ROOT / "Sources/ClipEase/Features/ClipboardMonitor/ClipboardMonitor.swift"


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

    depth = 1
    index = match.end()
    while index < len(source) and depth > 0:
        if source[index] == "{":
            depth += 1
        elif source[index] == "}":
            depth -= 1
        index += 1
    return source[match.end():index - 1]


def main() -> None:
    monitor = MONITOR.read_text(encoding="utf-8")
    poll_body = body_of_function(monitor, "poll")
    plain_text_gate = body_of_function(monitor, "shouldCaptureRichTextAsPlainText")

    require("URLParser.url(from: text) != nil" in plain_text_gate,
            "rich text whose plain text is a URL must be captured through addText")
    require("ColorParser.hexColor(from: text) != nil" in plain_text_gate,
            "existing color rich-text plain capture path must be preserved")
    require(poll_body.count("shouldCaptureRichTextAsPlainText(richText.plainText)") >= 2,
            "both RTF and HTML rich-text branches must use the plain-text capture gate")
    require("store.addText(richText.plainText, sourceApp: sourceApp)" in poll_body,
            "plain URL rich text must reach addText so link metadata fetch can run")
    require("store.addRichText(" in poll_body,
            "non-URL rich text must still preserve formatted text")

    print("OK rich text URL link capture checks passed")


if __name__ == "__main__":
    main()
