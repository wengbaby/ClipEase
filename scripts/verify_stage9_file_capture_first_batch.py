#!/usr/bin/env python3
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MONITOR = ROOT / "Sources/ClipEase/Features/ClipboardMonitor/ClipboardMonitor.swift"
STORE = ROOT / "Sources/ClipEase/Core/Storage/ClipboardHistoryStore.swift"
MODEL = ROOT / "Sources/ClipEase/Core/Models/ClipboardItem.swift"
PASTE_EXECUTOR = ROOT / "Sources/ClipEase/Features/PasteExecutor/PasteExecutor.swift"
PREVIEW_CONTROLLER = ROOT / "Sources/ClipEase/Features/HistoryWindow/HistoryPreviewWindowController.swift"


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


def verify_monitor() -> None:
    monitor = MONITOR.read_text(encoding="utf-8")
    poll = body_of_function(monitor, "poll")

    file_capture = poll.find("localFileURLsFromPasteboard()")
    image_capture = poll.find("readObjects(\n            forClasses: [NSImage.self]")
    text_capture = poll.find("pasteboard.string(forType: .string)")

    require(file_capture != -1, "ClipboardMonitor must read file URLs")
    require(image_capture != -1, "ClipboardMonitor image capture guard missing")
    require(text_capture != -1, "ClipboardMonitor text capture guard missing")
    require(file_capture < image_capture < text_capture, "file URL capture must run before image and text capture")
    require("store.addFiles(fileURLs, sourceApp: sourceApp)" in poll, "ClipboardMonitor must call store.addFiles")

    file_reader = body_of_function(monitor, "localFileURLsFromPasteboard")
    require(".urlReadingFileURLsOnly" in file_reader, "pasteboard URL read must be restricted to file URLs")
    require("url.isFileURL" in file_reader, "pasteboard file reader must filter non-file URLs")
    require(".fileURL" in file_reader, "pasteboard file reader must handle Finder file URL items")
    require("guard pasteboardHasFileSemanticTypes else" in file_reader,
            "pasteboard file reader must require file semantic pasteboard types")
    require("fileURLsFromPasteboardString()" not in file_reader,
            "pasteboard file reader must not convert top-level plain string paths into file cards")
    require("pasteboard.string(forType: .string)" not in file_reader,
            "top-level plain string content must stay eligible for text capture")
    require("security" not in file_reader.lower() and "bookmark" not in file_reader.lower(),
            "ClipboardMonitor must not create security-scoped bookmarks")

    require("urls.count == paths.count" in monitor,
            "path text fallback must not swallow mixed text that only partly looks like files")
    require("itemHasPathBackedFileSemanticTypes(item)" in monitor,
            "path text fallback must only run for path-backed file semantic pasteboard items")


def verify_store() -> None:
    store = STORE.read_text(encoding="utf-8")

    add_files = body_of_function(store, "addFiles")
    require("func addFiles(_ urls: [URL], sourceApp: SourceAppInfo)" in store,
            "ClipboardHistoryStore must expose addFiles(_ urls:sourceApp:)")
    require("ClipboardItem.file(" in add_files, "addFiles must construct ClipboardItem.file")
    require("sortItems()" in add_files and "pruneExpiredItems()" in add_files and "scheduleSave()" in add_files,
            "addFiles must sort, apply retention, and save")
    require("recentHashes" in add_files and "fileHash(" in add_files,
            "addFiles must dedupe repeated same-app file groups")

    reference_builder = body_of_function(store, "fileReference")
    for token in [
        ".contentTypeKey",
        ".fileSizeKey",
        ".contentModificationDateKey",
        ".isDirectoryKey",
        ".isAliasFileKey",
        "pathStatus:",
        "lastCheckedAt:",
    ]:
        require(token in reference_builder, f"fileReference missing metadata token {token}")
    require("resolvingAlias" not in store and "bookmark" not in store.lower(),
            "Store must not resolve aliases or create bookmarks")
    require("copyItem" not in add_files and "moveItem" not in add_files and "removeItem" not in add_files,
            "addFiles must not copy, move, or delete source files")

    path_status = body_of_function(store, "pathStatus")
    require(".notDownloaded" in path_status and ".placeholder" in path_status,
            "pathStatus must conservatively mark not-downloaded iCloud placeholders")
    require(".missing" in path_status and ".permissionDenied" in path_status and ".available" in path_status,
            "pathStatus must cover missing, permission denied, and available")

    text_hash = body_of_function(store, "textHash")
    require("case .file:" in text_hash and "fileHash(for: item.fileReferences" in text_hash,
            "file dedupe must use file references")
    require("case .text, .link, .color:" in text_hash,
            "text/link/color dedupe must remain separate from file dedupe")


def verify_no_scope_creep() -> None:
    changed_texts = {
        "ClipboardItem": MODEL.read_text(encoding="utf-8"),
        "PasteExecutor": PASTE_EXECUTOR.read_text(encoding="utf-8"),
        "HistoryPreviewWindowController": PREVIEW_CONTROLLER.read_text(encoding="utf-8"),
    }

    require("securityScoped" not in "\n".join(changed_texts.values()),
            "Stage 9 first batch must not add security-scoped bookmark handling")
    require("QLPreview" not in changed_texts["HistoryPreviewWindowController"]
            and "QuickLook" not in changed_texts["HistoryPreviewWindowController"],
            "Stage 9 first batch must not add Quick Look")


def main() -> None:
    verify_monitor()
    verify_store()
    verify_no_scope_creep()
    print("OK Stage 9 file capture first batch checks passed")


if __name__ == "__main__":
    main()
