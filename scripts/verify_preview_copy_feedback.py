#!/usr/bin/env python3
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CONTROLLER = ROOT / "Sources/ClipEase/Features/HistoryWindow/HistoryWindowController.swift"
BACKLOG = ROOT / "docs/V2_OPTIMIZATION_BACKLOG.md"


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
    controller = CONTROLLER.read_text(encoding="utf-8")
    backlog = BACKLOG.read_text(encoding="utf-8")
    show_preview = body_of_function(controller, "showPreview")
    copy_status = body_of_function(controller, "copyStatus")
    fallback_status = body_of_function(controller, "copyFallbackTextStatus")

    require("标题：Stage 9 预览窗口复制按钮统一 toast / fallback 状态" in backlog,
            "backlog item for preview copy feedback should remain documented")
    require("onCopy: { [weak self, pasteExecutor] in" in show_preview,
            "preview copy action must be handled by HistoryWindowController so it can show toast feedback")
    require("switch pasteExecutor.copyToPasteboard(item)" in show_preview,
            "preview copy action must inspect PasteboardCopyResult")
    require("case .copied:" in show_preview and "self.showStatus(self.copyStatus(for: item))" in show_preview,
            "preview copy success must show the same status as main-window copy")
    require("case .copiedFallbackText:" in show_preview
            and "self.showStatus(self.copyFallbackTextStatus(for: item))" in show_preview,
            "preview copy fallback must show file-path fallback status")
    require("case .failed(let reason):" in show_preview and "self.showStatus(reason)" in show_preview,
            "preview copy failure must show the failure reason")
    require("ClipEaseSoundPlayer.shared.playCopyFeedback()" in show_preview,
            "preview copy success and fallback must keep copy sound feedback")
    require("case .file:" in copy_status and "已复制文件引用" in copy_status,
            "preview normal file copy must report 文件引用")
    require("case .file:" in fallback_status and "文件不可用，已复制文件路径" in fallback_status,
            "preview fallback file copy must report 文件路径")

    print("OK preview copy feedback guards passed")


if __name__ == "__main__":
    main()
