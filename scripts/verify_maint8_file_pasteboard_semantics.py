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


def body_of_var(source: str, name: str) -> str:
    match = re.search(rf"\bvar\s+{re.escape(name)}\b[^\{{]*\{{", source)
    if not match:
        fail(f"missing var {name}")

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
    poll = body_of_function(monitor, "poll")
    reader = body_of_function(monitor, "localFileURLsFromPasteboard")
    item_reader = body_of_function(monitor, "fileURLs")
    path_reader = body_of_function(monitor, "fileURLs")
    file_url_types = body_of_var(monitor, "fileURLTypes")
    file_semantics = body_of_var(monitor, "fileSemanticTypes")
    path_semantics = body_of_var(monitor, "pathBackedFileSemanticTypes")

    require("localFileURLsFromPasteboard()" in poll, "poll must keep file capture before text capture")
    require(poll.find("localFileURLsFromPasteboard()") < poll.find("pasteboard.string(forType: .string)"),
            "file capture must run before final text capture")

    require("guard pasteboardHasFileSemanticTypes else" in reader,
            "file capture must require pasteboard-level file semantics")
    require("fileURLsFromReadObjects(options: [.urlReadingFileURLsOnly: true])" in reader,
            "file capture must still read explicit file URL objects")
    require("fileURLsFromFilenamesPropertyList()" in reader,
            "file capture must still read Finder NSFilenamesPboardType data")
    require("fileURLs(fromPasteboardString: pasteboard.string(forType: .fileURL))" in reader,
            "file capture must still read explicit fileURL pasteboard strings")

    require("fileURLsFromPasteboardString" not in monitor,
            "plain string path capture helper must not exist")
    require("pasteboard.string(forType: .string)" not in reader,
            "top-level plain string content must not be parsed as file paths")

    require("itemHasPathBackedFileSemanticTypes(item)" in item_reader,
            "item string path fallback must be guarded by path-backed file semantics")
    require("item.string(forType: .string)" in item_reader,
            "item-level string fallback should remain for Finder/file semantic pasteboards")
    require(".URL" not in path_semantics,
            "generic URL pasteboard type must not enable plain string path fallback")
    for token in [
        "Self.filenamesPasteboardType",
        "Self.filePromiseContentPasteboardType",
        "Self.filePromiseMetadataPasteboardType",
    ]:
        require(token in path_semantics, f"path-backed file semantic fallback missing {token}")

    for token in [".fileURL", "Self.publicFileURLPasteboardType"]:
        require(token in file_url_types, f"explicit file URL type set missing {token}")
    require("fileURLTypes +" in file_semantics,
            "pasteboard-level file semantics must include explicit file URL types")
    require("Self.filenamesPasteboardType" in file_semantics,
            "pasteboard-level file semantics missing Finder filename type")

    require("urls.count == paths.count" in monitor,
            "file semantic path fallback must reject mixed path/text payloads")
    require("fileExists" in monitor,
            "path fallback must only convert existing local paths")
    require("store.addText(text, sourceApp: sourceApp)" in poll,
            "ordinary text capture must remain available after file checks")

    print("OK Maint8 file pasteboard semantic checks passed")


if __name__ == "__main__":
    main()
