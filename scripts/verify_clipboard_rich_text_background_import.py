#!/usr/bin/env python3
from pathlib import Path

root = Path(__file__).resolve().parents[1]
source = root / "Sources/ClipEase/Features/ClipboardMonitor/ClipboardMonitor.swift"
text = source.read_text()

required = [
    "private enum RichTextPasteboardPayload: Sendable",
    "private var richTextImportTask: Task<Void, Never>?",
    "scheduleRichTextImport(",
    "Task.detached(priority: .utility)",
    "clipboard.richText.import",
    "capturedType: \"html.scheduled\"",
    "capturedType: \"rtf.scheduled\"",
    "nonisolated private static func richTextFromHTMLData",
    "nonisolated private static func richTextFromRTFData",
]

missing = [needle for needle in required if needle not in text]
if missing:
    raise SystemExit("Clipboard rich text background import guard failed. Missing: " + ", ".join(missing))

poll_start = text.index("    private func poll()")
poll_end = text.index("    private func recordPollDuration", poll_start)
poll_body = text[poll_start:poll_end]

for forbidden in [
    "htmlRichTextFromPasteboard()",
    "rtfRichTextFromPasteboard()",
    "attributedString(",
    "NSAttributedString(",
]:
    if forbidden in poll_body:
        raise SystemExit(f"Clipboard poll must not synchronously parse rich text: {forbidden}")

print("Clipboard rich text background import guard passed.")
