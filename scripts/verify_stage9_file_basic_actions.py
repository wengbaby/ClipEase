#!/usr/bin/env python3
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
WINDOW_VIEW = ROOT / "Sources/ClipEase/Features/HistoryWindow/HistoryWindowView.swift"
PREVIEW_POPOVER = ROOT / "Sources/ClipEase/Features/HistoryWindow/HistoryPreviewPopoverView.swift"
WINDOW_CONTROLLER = ROOT / "Sources/ClipEase/Features/HistoryWindow/HistoryWindowController.swift"


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


def body_of_property(source: str, name: str) -> str:
    match = re.search(rf"\bvar\s+{re.escape(name)}\b[^\{{]*\{{", source)
    if not match:
        fail(f"missing property {name}")

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


def verify_window_context_menu(window_view: str) -> None:
    menu_body = body_of_function(window_view, "typeSpecificContextMenu")
    file_case = switch_case_body(menu_body, ".file")

    require('Button("复制路径")' in file_case and "copyFilePaths(item.id)" in file_case,
            'file context menu must include "复制路径" wired to copyFilePaths')
    require('Button("在 Finder 中显示")' in file_case and "revealFilesInFinder(item.id)" in file_case,
            'file context menu must include "在 Finder 中显示" wired to revealFilesInFinder')
    require("Divider()" in file_case, "file context menu must end with a divider")
    require("openImage" not in file_case and "openLink" not in file_case,
            "file context menu must not add an open-file action")


def verify_file_helpers(window_view: str) -> None:
    copy_body = body_of_function(window_view, "copyFilePaths")
    reveal_body = body_of_function(window_view, "revealFilesInFinder")
    existing_urls_body = body_of_function(window_view, "existingFileURLs")
    helper_text = "\n".join([copy_body, reveal_body, existing_urls_body])

    require("item.type == .file" in copy_body and "item.fileReferences" in copy_body,
            "copyFilePaths must only operate on file references")
    require('.joined(separator: "\\n")' in copy_body,
            "copyFilePaths must copy multiple paths as newline-separated text")
    require("NSPasteboard.general.setString(pathsText, forType: .string)" in copy_body,
            "copyFilePaths must write path text to the pasteboard")
    require("addClipEaseTextCard(pathsText)" in copy_body,
            "copyFilePaths must add the copied path text as a ClipEase card")
    require("未找到文件" in copy_body and "未找到文件" in reveal_body,
            "empty or invalid file references must only show a status")

    require("existingFileURLs(for: item)" in reveal_body,
            "revealFilesInFinder must resolve existing file URLs before revealing")
    require("NSWorkspace.shared.activateFileViewerSelecting(urls)" in reveal_body,
            "Finder reveal must use activateFileViewerSelecting")
    require("URL(fileURLWithPath: reference.path).standardizedFileURL" in existing_urls_body,
            "Finder reveal must use standardized local file URLs")
    require("FileManager.default.fileExists(atPath: url.path)" in existing_urls_body,
            "Finder reveal must prefer paths that still exist")

    forbidden_tokens = [
        "copyItem(",
        "moveItem(",
        "removeItem(",
        "startAccessingSecurityScopedResource",
        "securityScoped",
        "bookmark",
        ".onDrag",
        "NSItemProvider",
        ".draggable",
        "NSWorkspace.shared.open",
        "favorite",
        "management",
    ]
    for token in forbidden_tokens:
        require(token not in helper_text,
                f"file basic action helpers must not introduce forbidden token {token}")


def verify_popover_file_menu(popover: str) -> None:
    action_menu = body_of_property(popover, "actionMenu")
    file_case = switch_case_body(action_menu, ".file")

    require('Button("在 Finder 中显示", action: onReveal)' in file_case,
            'file preview action menu must include "在 Finder 中显示" using onReveal')
    require('Button("复制路径", action: onCopyPath)' in file_case,
            'file preview action menu must include "复制路径" using onCopyPath')
    require("action: onCopy)" not in file_case and "action: onCopy\n" not in file_case,
            "file preview action menu must not bind file path copy to ordinary onCopy")
    require("复制文件路径" not in file_case,
            'file preview action menu must not keep the old "复制文件路径" label')

    forbidden_tokens = [
        "copyItem(",
        "moveItem(",
        "removeItem(",
        "startAccessingSecurityScopedResource",
        "securityScoped",
        "bookmark",
        ".onDrag",
        "NSItemProvider",
        ".draggable",
        "NSWorkspace.shared.open",
        "favorite",
        "management",
    ]
    for token in forbidden_tokens:
        require(token not in file_case,
                f"file preview action menu must not introduce forbidden token {token}")


def verify_controller_preview_file_callbacks(controller: str) -> None:
    show_preview_body = body_of_function(controller, "showPreview")
    reveal_body = body_of_function(controller, "revealPreviewItem")
    copy_dispatch_body = body_of_function(controller, "copyPreviewPath")
    copy_file_body = body_of_function(controller, "copyPreviewFilePaths")
    existing_urls_body = body_of_function(controller, "existingPreviewFileURLs")

    require("onReveal:" in show_preview_body and "revealPreviewItem(item)" in show_preview_body,
            "preview onReveal must call the controller reveal dispatcher")
    require("onCopyPath:" in show_preview_body and "copyPreviewPath(for: item)" in show_preview_body,
            "preview onCopyPath must call the controller path-copy dispatcher")
    require("imagePath(for: item)" not in show_preview_body,
            "preview onCopyPath must not be wired directly to imagePath")

    reveal_image_case = switch_case_body(reveal_body, ".image")
    reveal_file_case = switch_case_body(reveal_body, ".file")
    copy_image_case = switch_case_body(copy_dispatch_body, ".image")
    copy_file_case = switch_case_body(copy_dispatch_body, ".file")

    require("imageURL(for: item)" in reveal_image_case,
            "preview image reveal must keep using imageURL")
    require("existingPreviewFileURLs(for: item)" in reveal_file_case,
            "preview file reveal must resolve existing file URLs")
    require("未找到文件" in reveal_file_case,
            "preview file reveal must show a missing-file status when no URL is valid")
    require("NSWorkspace.shared.activateFileViewerSelecting(urls)" in reveal_file_case,
            "preview file reveal must use activateFileViewerSelecting")
    require("NSWorkspace.shared.open" not in reveal_file_case,
            "preview file reveal must not open files")

    require("copyPlainPreviewText(imagePath(for: item))" in copy_image_case,
            "preview image copy path must keep using imagePath")
    require("copyPreviewFilePaths(for: item)" in copy_file_case,
            "preview file copy path must call the file path helper")
    require("item.type == .file" in copy_file_body and "item.fileReferences" in copy_file_body,
            "preview file copy path must only operate on file references")
    require('.joined(separator: "\\n")' in copy_file_body,
            "preview file copy path must copy multiple paths as newline-separated text")
    require("NSPasteboard.general.setString(pathsText, forType: .string)" in copy_file_body,
            "preview file copy path must write path text to the pasteboard")
    require("store.addText(pathsText, sourceApp: .clipease)" in copy_file_body,
            "preview file copy path must add the copied path text as a ClipEase card")
    require("未找到文件" in copy_file_body,
            "preview file copy path must show a missing-file status when paths are unavailable")

    require("URL(fileURLWithPath: reference.path).standardizedFileURL" in existing_urls_body,
            "preview file reveal must use standardized local file URLs")
    require("FileManager.default.fileExists(atPath: url.path)" in existing_urls_body,
            "preview file reveal must only select paths that still exist")

    controller_file_text = "\n".join([reveal_file_case, copy_file_body, existing_urls_body])
    forbidden_tokens = [
        "copyItem(",
        "moveItem(",
        "removeItem(",
        "startAccessingSecurityScopedResource",
        "securityScoped",
        "bookmark",
        ".onDrag",
        "NSItemProvider",
        ".draggable",
        "NSWorkspace.shared.open",
    ]
    for token in forbidden_tokens:
        require(token not in controller_file_text,
                f"preview file callbacks must not introduce forbidden token {token}")


def main() -> None:
    window_view = WINDOW_VIEW.read_text(encoding="utf-8")
    popover = PREVIEW_POPOVER.read_text(encoding="utf-8")
    controller = WINDOW_CONTROLLER.read_text(encoding="utf-8")

    verify_window_context_menu(window_view)
    verify_file_helpers(window_view)
    verify_popover_file_menu(popover)
    verify_controller_preview_file_callbacks(controller)
    print("OK Stage 9 file basic action checks passed")


if __name__ == "__main__":
    main()
