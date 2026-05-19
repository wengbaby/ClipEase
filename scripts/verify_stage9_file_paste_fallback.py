#!/usr/bin/env python3
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PASTE_EXECUTOR = ROOT / "Sources/ClipEase/Features/PasteExecutor/PasteExecutor.swift"
WINDOW_VIEW = ROOT / "Sources/ClipEase/Features/HistoryWindow/HistoryWindowView.swift"


def fail(message: str) -> None:
    print(f"FAIL: {message}")
    sys.exit(1)


def require(condition: bool, message: str) -> None:
    if not condition:
        fail(message)


def balanced_body(source: str, start: int) -> str:
    depth = 1
    index = start
    while index < len(source) and depth > 0:
        if source[index] == "{":
            depth += 1
        elif source[index] == "}":
            depth -= 1
        index += 1
    return source[start:index - 1]


def body_of_function(source: str, name: str) -> str:
    match = re.search(rf"\bfunc\s+{re.escape(name)}\b[^\{{]*\{{", source)
    if not match:
        fail(f"missing function {name}")
    return balanced_body(source, match.end())


def switch_case_body(source: str, case_label: str) -> str:
    case_match = re.search(rf"\n\s*case\s+{re.escape(case_label)}:\s*\n", source)
    if not case_match:
        fail(f"missing switch case {case_label}")

    start = case_match.end()
    next_case = re.search(r"\n\s*case\s+\.", source[start:])
    end = start + next_case.start() if next_case else len(source)
    return source[start:end]


def require_ordered(source: str, first: str, second: str, message: str) -> None:
    first_index = source.find(first)
    second_index = source.find(second)
    require(first_index >= 0 and second_index >= 0 and first_index < second_index, message)


def verify_paste_executor() -> None:
    text = PASTE_EXECUTOR.read_text(encoding="utf-8")
    copy_to_pasteboard = body_of_function(text, "copyToPasteboard")
    file_case = switch_case_body(copy_to_pasteboard, ".file")
    fallback = body_of_function(text, "fileFallbackText")
    paste_to_frontmost = body_of_function(text, "pasteToFrontmostApp")

    require("validLocalFileURLs(for: item)" in file_case,
            ".file copy must validate local file URLs before writing")
    require("pasteboard.writeObjects(fileURLs.map { $0 as NSURL })" in file_case,
            ".file copy must still write NSURL file references when any URL is valid")
    require_ordered(file_case, "pasteboard.writeObjects(fileURLs.map { $0 as NSURL })", "fileFallbackText(for: item)",
                    ".file copy must prefer file URL pasteboard references before fallback text")
    require("guard !fileURLs.isEmpty else" not in file_case,
            ".file copy must not directly fail before fallback when there are no valid URLs")
    require("guard let fallbackText = fileFallbackText(for: item)" in file_case,
            ".file copy must compute fallback text when all URLs are invalid")
    require("pasteboard.setString(fallbackText, forType: .string)" in file_case,
            "fallback must write text to the pasteboard")
    require("store.addText(fallbackText, sourceApp: .clipease)" in file_case,
            "fallback text writes must create a ClipEase-sourced history card")
    require("return .copiedFallbackText" in file_case,
            "fallback success must return a distinct non-failed result")
    require_ordered(file_case, "guard let fallbackText = fileFallbackText(for: item)", 'return .failed("未找到文件")',
                    "missing-file failure may only happen after fallback text is unavailable")

    require("reference.path.trimmingCharacters" in fallback and "reference.displayName.trimmingCharacters" in fallback,
            "fallback text must come from file path first and displayName second")
    require('joined(separator: "\\n")' in fallback,
            "fallback text must join multiple file references with newlines")
    require("item.text.trimmingCharacters" in fallback,
            "fallback text must fall back to item.text when file references have no usable text")

    require("case .copiedFallbackText" in paste_to_frontmost,
            "auto paste must preserve fallback result semantics")
    require(".copiedFallbackTextOnly" in paste_to_frontmost and ".pastedFallbackText" in paste_to_frontmost,
            "auto paste must expose copied-only and pasted fallback states")


def verify_history_window_status() -> None:
    text = WINDOW_VIEW.read_text(encoding="utf-8")
    copy_item = body_of_function(text, "copyItem")
    paste_item = body_of_function(text, "pasteItem")

    require("case .copiedFallbackText:" in copy_item and "copyFallbackTextStatus(for: item)" in copy_item,
            "copy action must dispatch fallback text status separately")
    require("case .copiedFallbackTextOnly:" in paste_item and "copiedOnlyFallbackTextStatus(for: item)" in paste_item,
            "copied-only paste fallback must dispatch fallback text status separately")
    require("case .pastedFallbackText:" in paste_item and "pastedFallbackTextStatus(for: item)" in paste_item,
            "pasted fallback must dispatch fallback text status separately")

    for function_name in [
        "copyFallbackTextStatus",
        "copiedOnlyFallbackTextStatus",
        "pastedFallbackTextStatus",
    ]:
        body = body_of_function(text, function_name)
        file_case = switch_case_body(body, ".file")
        require("文件路径" in file_case,
                f"{function_name} must describe fallback as 文件路径")
        require("文件引用" not in file_case,
                f"{function_name} must not misreport fallback as 文件引用")


def verify_no_scope_creep() -> None:
    paste_executor = PASTE_EXECUTOR.read_text(encoding="utf-8")
    window_view = WINDOW_VIEW.read_text(encoding="utf-8")
    combined = "\n".join([
        body_of_function(paste_executor, "copyToPasteboard"),
        body_of_function(paste_executor, "fileFallbackText"),
        body_of_function(paste_executor, "validLocalFileURLs"),
        body_of_function(paste_executor, "pasteToFrontmostApp"),
        body_of_function(window_view, "copyItem"),
        body_of_function(window_view, "pasteItem"),
        body_of_function(window_view, "copyFallbackTextStatus"),
        body_of_function(window_view, "copiedOnlyFallbackTextStatus"),
        body_of_function(window_view, "pastedFallbackTextStatus"),
    ])

    forbidden_tokens = [
        "copyItem(",
        "moveItem(",
        "removeItem(",
        "securityScoped",
        "bookmark",
        "temporaryDirectory",
        "NSTemporaryDirectory",
        "temporary copy",
        "NSWorkspace.shared.open",
        ".onDrag",
        ".draggable",
        "schema",
        "Repository",
        "ClipboardItem(",
        "favorite",
        "management",
        "JSON",
    ]
    for token in forbidden_tokens:
        require(token not in combined,
                f"fallback paste change must not introduce forbidden token {token}")


def main() -> None:
    verify_paste_executor()
    verify_history_window_status()
    verify_no_scope_creep()
    print("OK Stage 9 file paste fallback checks passed")


if __name__ == "__main__":
    main()
