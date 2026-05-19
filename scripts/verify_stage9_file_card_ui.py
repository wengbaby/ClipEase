#!/usr/bin/env python3
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PREVIEW_ITEM = ROOT / "Sources/ClipEase/Features/HistoryWindow/HistoryPreviewItem.swift"
CARD_VIEW = ROOT / "Sources/ClipEase/Features/HistoryWindow/HistoryCardView.swift"
WINDOW_VIEW = ROOT / "Sources/ClipEase/Features/HistoryWindow/HistoryWindowView.swift"
PASTE_EXECUTOR = ROOT / "Sources/ClipEase/Features/PasteExecutor/PasteExecutor.swift"
PREVIEW_CONTROLLER = ROOT / "Sources/ClipEase/Features/HistoryWindow/HistoryPreviewWindowController.swift"
SQLITE_STORE = ROOT / "Sources/ClipEase/Core/Storage/SQLiteClipboardStore.swift"


def fail(message: str) -> None:
    print(f"FAIL: {message}")
    sys.exit(1)


def require(condition: bool, message: str) -> None:
    if not condition:
        fail(message)


def body_of_enum_case_switch(source: str, enum_name: str, case_name: str) -> str:
    pattern = rf"extension\s+{re.escape(enum_name)}[\s\S]*?switch\s+type\s*\{{([\s\S]*?)\n\s*\}}\n\s*\}}"
    match = re.search(pattern, source)
    if not match:
        fail(f"missing {enum_name} type switch")
    switch_body = match.group(1)
    case_match = re.search(rf"case\s+\.{re.escape(case_name)}:\s*\n\s*self\s*=\s*\.(\w+)", switch_body)
    if not case_match:
        fail(f"missing {case_name} mapping")
    return case_match.group(1)


def verify_preview_item() -> None:
    text = PREVIEW_ITEM.read_text(encoding="utf-8")
    require("case file" in text, "HistoryPreviewType must include case file")
    require(body_of_enum_case_switch(text, "HistoryPreviewType", "file") == "file",
            "ClipboardItemType.file must map to HistoryPreviewType.file")
    require("struct HistoryFilePreviewReference" in text,
            "HistoryPreviewItem must expose a lightweight file display DTO")
    require("filePreviewReferences" in text and "item.fileReferences.map" in text,
            "HistoryPreviewItem must carry file preview references from ClipboardItem")
    require("filePreviewReferences.map(\\.displayName)" in text and "filePreviewReferences.map(\\.path)" in text,
            "normalized search text must include file names and full paths")
    require("ClipboardFileReference" not in text,
            "HistoryPreviewItem should not expose storage file references directly")


def verify_card_view() -> None:
    text = CARD_VIEW.read_text(encoding="utf-8")
    require("case .file:" in text and "filePreview" in text,
            "HistoryCardView must render file cards with a dedicated preview")
    for token in ["doc.fill", "folder.fill", "primaryFileTitle", "fileCountText", "filePathSummaries"]:
        require(token in text, f"file card missing UI token {token}")
    for label in ["缺失", "无权限", "占位", "未确认"]:
        require(label in text, f"file card missing conservative status label {label}")
    require(".frame(width: 250, height: 270)" in text,
            "file card change must keep stable card dimensions")
    require(".lineLimit(1)" in text and ".lineLimit(2)" in text and ".truncationMode(.middle)" in text,
            "file card must constrain long names and paths")


def verify_search_type_filter() -> None:
    text = WINDOW_VIEW.read_text(encoding="utf-8")
    require("case file" in text, "search type filter must include file token")
    require('case .file:\n            "文件"' in text, "file search token must have title")
    require('case .file:\n            "doc"' in text, "file search token must have icon")
    require("case .file:\n            .file" in text, "file search token must map to HistoryPreviewType.file")


def verify_no_scope_creep() -> None:
    preview_controller_text = PREVIEW_CONTROLLER.read_text(encoding="utf-8")
    paste_executor_text = PASTE_EXECUTOR.read_text(encoding="utf-8")
    sqlite_text = SQLITE_STORE.read_text(encoding="utf-8")

    require("QuickLook" not in preview_controller_text and "QLPreview" not in preview_controller_text,
            "Stage 9 file card UI must not add Quick Look")
    file_indexes = [
        line.strip()
        for line in sqlite_text.splitlines()
        if "CREATE INDEX" in line and ("file_path" in line or "file_name" in line)
    ]
    require(not file_indexes, "Stage 9 file card UI must not add SQLite file path/name search indexes")


def main() -> None:
    verify_preview_item()
    verify_card_view()
    verify_search_type_filter()
    verify_no_scope_creep()
    print("OK Stage 9 file card UI checks passed")


if __name__ == "__main__":
    main()
