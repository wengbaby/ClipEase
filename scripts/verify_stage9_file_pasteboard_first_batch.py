#!/usr/bin/env python3
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PASTE_EXECUTOR = ROOT / "Sources/ClipEase/Features/PasteExecutor/PasteExecutor.swift"
WINDOW_VIEW = ROOT / "Sources/ClipEase/Features/HistoryWindow/HistoryWindowView.swift"
STORE = ROOT / "Sources/ClipEase/Core/Storage/ClipboardHistoryStore.swift"
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


def switch_case_body(source: str, case_label: str) -> str:
    case_match = re.search(rf"\n\s*case\s+{re.escape(case_label)}:\s*\n", source)
    if not case_match:
        fail(f"missing switch case {case_label}")

    start = case_match.end()
    next_case = re.search(r"\n\s*case\s+\.", source[start:])
    end = start + next_case.start() if next_case else len(source)
    return source[start:end]


def verify_file_copy_execution() -> None:
    text = PASTE_EXECUTOR.read_text(encoding="utf-8")
    copy_to_pasteboard = body_of_function(text, "copyToPasteboard")
    file_case = switch_case_body(copy_to_pasteboard, ".file")

    require("case .text, .link, .color:" in copy_to_pasteboard,
            "text/link/color copy path should stay separate from file copy")
    require("case .file:" in copy_to_pasteboard, "copyToPasteboard must have a dedicated .file branch")
    require("validLocalFileURLs(for: item)" in file_case, "file branch must collect valid local file URLs")
    require("pasteboard.writeObjects" in file_case and "NSURL" in file_case,
            "file branch must write NSURL file references with NSPasteboard.writeObjects")
    require("fileFallbackText(for: item)" in file_case and "pasteboard.setString(fallbackText, forType: .string)" in file_case,
            "file branch must fall back to path text when no local file exists")
    require("store.addFiles(fileURLs, sourceApp: .clipease)" in file_case,
            "file branch must add self-copied file references as ClipEase cards")
    require("skipNextClipboardFiles" not in file_case,
            "file branch must not skip self-copied file references")

    validator = body_of_function(text, "validLocalFileURLs")
    require("item.fileReferences" in validator, "file URL validator must be based on item.fileReferences")
    require("URL(fileURLWithPath:" in validator and "standardizedFileURL" in validator,
            "file URL validator must create local standardized file URLs")
    require("FileManager.default.fileExists" in validator,
            "file URL validator must check that paths still exist before writing pasteboard")
    require("isDirectory" not in validator, "file URL validator must allow directories as file references")

    plain_text = body_of_function(text, "copyPlainTextToPasteboard")
    pasteboard_string = body_of_function(text, "pasteboardString")
    require("pasteboard.setString(pasteboardString(for: item), forType: .string)" in plain_text,
            "copyPlainTextToPasteboard must continue writing string content")
    require("item.fileReferences" in pasteboard_string and "reference.path.trimmingCharacters" in pasteboard_string,
            "file plain text copy must continue writing path strings")
    require("store.addText(pasteboardString(for: item), sourceApp: .clipease)" in plain_text,
            "file plain text copy must add the actual path string as a ClipEase card")


def verify_status_copy() -> None:
    text = WINDOW_VIEW.read_text(encoding="utf-8")
    for function_name, expected in [
        ("copyStatus", "已复制文件引用"),
        ("copiedOnlyStatus", "已复制文件引用，需授权后自动粘贴"),
        ("pastedStatus", "已粘贴文件引用到当前 App"),
    ]:
        body = body_of_function(text, function_name)
        file_case = switch_case_body(body, ".file")
        require(expected in file_case, f"{function_name} must use 文件引用 for file cards")
        require("文件路径" not in file_case, f"{function_name} must not call normal file copy 文件路径")


def verify_clip_ease_self_copy_capture() -> None:
    store = STORE.read_text(encoding="utf-8")
    monitor = MONITOR.read_text(encoding="utf-8")
    paste_executor = PASTE_EXECUTOR.read_text(encoding="utf-8")
    poll = body_of_function(monitor, "poll")
    copy_to_pasteboard = body_of_function(paste_executor, "copyToPasteboard")

    require("func skipNextClipboardFiles(_ urls: [URL])" in store,
            "ClipboardHistoryStore should keep skipNextClipboardFiles(_:) for external/programmatic guards")
    require("func consumeSkippedClipboardFiles(_ urls: [URL]) -> Bool" in store,
            "ClipboardHistoryStore must expose consumeSkippedClipboardFiles(_:) for monitor")
    require("clipboardFilePathSetKey(for: urls)" in store and "standardizedFileURL.path" in store,
            "file self-copy guard must compare standardized file paths")
    require("store.consumeSkippedClipboardFiles(fileURLs)" in poll,
            "ClipboardMonitor must still consume explicit skipped file guards")
    require("let sourceApp = monitoredSourceApp" in poll,
            "ClipboardMonitor must normalize ClipEase-origin clipboard writes")
    require("current.isClipEase ? .clipease : current" in monitor,
            "ClipboardMonitor must tag ClipEase-origin clipboard writes as ClipEase")
    require("store.addText(pasteboardString(for: item), sourceApp: .clipease)" in copy_to_pasteboard,
            "PasteExecutor text copy must add a ClipEase card")
    require("store.addFiles(fileURLs, sourceApp: .clipease)" in copy_to_pasteboard,
            "PasteExecutor file copy must add a ClipEase card")
    require("store.addImage(image, sourceApp: .clipease)" in copy_to_pasteboard,
            "PasteExecutor image copy must add a ClipEase card")


def verify_no_scope_creep() -> None:
    paste_executor = PASTE_EXECUTOR.read_text(encoding="utf-8")
    copy_to_pasteboard = body_of_function(paste_executor, "copyToPasteboard")
    validator = body_of_function(paste_executor, "validLocalFileURLs")
    relevant_text = "\n".join([
        copy_to_pasteboard,
        validator,
        body_of_function(STORE.read_text(encoding="utf-8"), "skipNextClipboardFiles"),
        body_of_function(STORE.read_text(encoding="utf-8"), "consumeSkippedClipboardFiles"),
        body_of_function(MONITOR.read_text(encoding="utf-8"), "poll"),
    ])

    forbidden_tokens = [
        "copyItem(",
        "moveItem(",
        "removeItem(",
        "securityScoped",
        "bookmark",
        "Finder",
        "QLPreviewPanel",
        "schema",
        "index",
        "CREATE INDEX",
        "favorite",
        "management",
    ]
    for token in forbidden_tokens:
        require(token not in relevant_text,
                f"file pasteboard first batch must not introduce forbidden token {token}")


def main() -> None:
    verify_file_copy_execution()
    verify_status_copy()
    verify_clip_ease_self_copy_capture()
    verify_no_scope_creep()
    print("OK Stage 9 file pasteboard first batch checks passed")


if __name__ == "__main__":
    main()
