#!/usr/bin/env python3
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
HISTORY_WINDOW = ROOT / "Sources/ClipEase/Features/HistoryWindow"
PREVIEW_CONTROLLER = HISTORY_WINDOW / "HistoryPreviewWindowController.swift"
PREVIEW_POPOVER = HISTORY_WINDOW / "HistoryPreviewPopoverView.swift"
QUICKLOOK_BRIDGE = HISTORY_WINDOW / "HistoryFileQuickLookPreviewView.swift"


def fail(message: str) -> None:
    print(f"FAIL: {message}")
    sys.exit(1)


def require(condition: bool, message: str) -> None:
    if not condition:
        fail(message)


def content_switch_source(source: str) -> str:
    marker = "private var content: some View"
    start = source.find(marker)
    if start == -1:
        fail("missing content view switch")
    end = source.find("private var imageContent", start)
    if end == -1:
        fail("missing content switch end marker")
    return source[start:end]


def body_of_case(source: str, case_name: str) -> str:
    match = re.search(
        rf"case\s+\.{re.escape(case_name)}:\s*\n(?P<body>[\s\S]*?)(?=\n\s*case\s+\.|\n\s*\}}\n)",
        source,
    )
    if not match:
        fail(f"missing .{case_name} switch case")
    return match.group("body")


def method_source(source: str, method_name: str) -> str:
    declaration = re.search(rf"\n\s+(?:static\s+)?func\s+{re.escape(method_name)}\b", source)
    if declaration is None:
        fail(f"missing {method_name}")
    start = declaration.start()
    next_method = re.search(r"\n\s+(?:static\s+)?func\s+\w+", source[start + len(method_name):])
    next_type = re.search(r"\n(?:private\s+)?(?:final\s+)?(?:class|struct|enum)\s+", source[start + len(method_name):])
    candidates = [
        start + len(method_name) + match.start()
        for match in [next_method, next_type]
        if match is not None
    ]
    end = min(candidates) if candidates else len(source)
    return source[start:end]


def verify_lifecycle_reuse(controller: str, popover: str) -> None:
    require("private var panel: NSPanel?" in controller, "preview must keep existing NSPanel lifecycle")
    require("parentWindow.addChildWindow(panel, ordered: .above)" in controller,
            "preview panel must remain attached as a child window")
    require("panel.parent?.removeChildWindow(panel)" in controller,
            "preview close must remove the child window")
    require("panel.contentView = NSHostingView" in controller and "HistoryPreviewPopoverView(" in controller,
            "preview content must continue to be hosted by HistoryPreviewPopoverView")
    require("struct HistoryPreviewPopoverView: View" in popover,
            "popover view must remain the preview content surface")


def verify_file_preview_content(popover: str) -> None:
    file_case = body_of_case(content_switch_source(popover), "file")
    require("LazyPreviewTextView" not in file_case,
            ".file preview must not be plain LazyPreviewTextView text")
    require("filePreviewContent" in file_case,
            ".file preview must use the dedicated file preview content")
    for token in [
        "fileFallbackPreview",
        "NSWorkspace.shared.icon(forFile:",
        "fileStatusText",
        "permissionDenied",
        "placeholder",
        "missing",
        "previewableFileReference",
    ]:
        require(token in popover, f"file preview missing fallback/status token {token}")
    require("references.first(where: fileIsPreviewable) ?? references.first" in popover,
            "multi-file preview must choose one primary file instead of instantiating many previews")
    require("ForEach(references)" in popover,
            "multi-file preview must still expose a lightweight file list")


def verify_quicklook_embedding(bridge: str, popover: str, controller: str) -> None:
    combined = "\n".join([bridge, popover, controller])
    require("QLPreviewPanel" not in combined,
            "spike must not use the global QLPreviewPanel")
    require("HistoryFileQuickLookPreviewView" in popover,
            "popover must embed the Quick Look bridge")
    require("QLPreviewView" in bridge and "NSViewRepresentable" in bridge,
            "Quick Look must be embedded as an NSViewRepresentable view")
    require("previewItem" in bridge and "QLPreviewItem" in bridge,
            "embedded Quick Look view must receive a preview item")
    require("dismantleNSView" in bridge,
            "Quick Look bridge must explicitly clean up when SwiftUI dismantles the NSView")
    dismantle_source = method_source(bridge, "dismantleNSView")
    require("static func dismantleNSView" in dismantle_source,
            "Quick Look bridge must implement NSViewRepresentable.dismantleNSView")
    require(re.search(r"\bpreviewItem\s*=\s*nil\b", dismantle_source) is not None,
            "Quick Look dismantleNSView must clear QLPreviewView.previewItem")


def verify_no_scope_creep(*sources: str) -> None:
    combined = "\n".join(sources)
    forbidden_tokens = [
        "PasteExecutor",
        "ClipboardMonitor",
        "SQLiteClipboardStore",
        "ClipboardHistoryStore",
        "ClipboardHistoryRepository",
        "securityScoped",
        "startAccessingSecurityScopedResource",
        "NSPasteboard",
        "writeObjects",
        "copyItem(",
        "moveItem(",
        "removeItem(",
    ]
    for token in forbidden_tokens:
        require(token not in combined, f"preview spike must not cross into forbidden scope: {token}")


def main() -> None:
    controller = PREVIEW_CONTROLLER.read_text(encoding="utf-8")
    popover = PREVIEW_POPOVER.read_text(encoding="utf-8")
    bridge = QUICKLOOK_BRIDGE.read_text(encoding="utf-8")

    verify_lifecycle_reuse(controller, popover)
    verify_file_preview_content(popover)
    verify_quicklook_embedding(bridge, popover, controller)
    verify_no_scope_creep(controller, popover, bridge)
    print("OK Stage 9 Quick Look spike checks passed")


if __name__ == "__main__":
    main()
