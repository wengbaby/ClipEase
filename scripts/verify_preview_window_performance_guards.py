#!/usr/bin/env python3
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CONTROLLER = ROOT / "Sources/ClipEase/Features/HistoryWindow/HistoryPreviewWindowController.swift"
POPOVER = ROOT / "Sources/ClipEase/Features/HistoryWindow/HistoryPreviewPopoverView.swift"
LINK_WEB = ROOT / "Sources/ClipEase/Features/HistoryWindow/LinkPreviewWebView.swift"


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
    popover = POPOVER.read_text(encoding="utf-8")
    link_web = LINK_WEB.read_text(encoding="utf-8")

    show = body_of_function(controller, "show")
    close = body_of_function(controller, "close")
    schedule_content = body_of_function(controller, "scheduleContentLoad")
    load_preview_image = body_of_function(popover, "loadPreviewImage")

    require("private let deferredContentLoadDelay: UInt64 = 50_000_000" in controller,
            "preview content should keep a small deferred heavy-content delay")
    require("let shouldLoadImmediately = item.type == .text || item.type == .color" in show,
            "image/link/file previews must not load heavy content before open animation starts")
    require("scheduleContentLoad(" in show and "if !shouldLoadImmediately" in show,
            "heavy preview content must be scheduled after the light shell is visible")
    require("contentLoadTask?.cancel()" in close and "panel.contentView = NSView()" in close,
            "closing preview must cancel pending loads and unload heavy content before close animation")
    require("try? await Task.sleep(nanoseconds: delay)" in schedule_content
            and "guard !Task.isCancelled, panel.isVisible else" in schedule_content,
            "deferred preview content load must be cancellable")

    require("previewImage = nil" in popover and "previewImage = await loadImage()" in popover,
            "image preview must clear stale image state and load image asynchronously")
    require("private var previewContentTransitionID: String" in popover
            and ".id(previewContentTransitionID)" in popover
            and ".transition(.opacity.combined(with: .scale(scale: 0.992)))" in popover
            and ".animation(.easeOut(duration: 0.14), value: previewContentTransitionID)" in popover,
            "preview content switches must use a light opacity/scale transition keyed by content identity")
    require("private struct PreviewIconButtonStyle: ButtonStyle" in popover
            and ".scaleEffect(configuration.isPressed ? 0.985 : (isHovered ? 1.01 : 1))" in popover
            and ".animation(.easeOut(duration: 0.08), value: configuration.isPressed)" in popover,
            "preview header/floating buttons must use lightweight hover/press feedback")
    require("Task.detached(priority: .utility)" in load_preview_image
            and "Data(contentsOf: imageURL)" in load_preview_image,
            "image preview disk IO must happen in a utility background task")
    require("context.coordinator.loadDocument(from: url, into: view)" in popover,
            "PDF preview must not synchronously create PDFDocument in makeNSView")
    require("view.document = nil" in popover
            and "context.coordinator.loadDocument(from: url, into: view)" in popover,
            "PDF preview update must unload old documents before background loading the new one")
    require("Task.detached(priority: .utility)" in popover
            and "PDFDocument(url: url)" in popover
            and "deinit {\n            loadTask?.cancel()" in popover,
            "PDF documents must load in a cancellable utility task")
    require("WKNavigationDelegate" in link_web
            and "isLinkPreviewLoading" in popover
            and "linkPreviewOverlay" in popover,
            "link preview must show loading/failure state instead of blank heavy content")

    forbidden_controller = [
        "let shouldLoadImmediately = item.type == .text || item.type == .color || item.type == .image",
    ]
    forbidden_popover = [
        "view.document = PDFDocument(url: url)",
        ".animation(.easeOut(duration: 0.16), value: isContentReady)",
        ".frame(width: isHovered",
        ".frame(height: isHovered",
        ".shadow(\n            color: .black.opacity(isHovered",
    ]
    for snippet in forbidden_controller:
        require(snippet not in controller, f"forbidden preview controller regression: {snippet}")
    for snippet in forbidden_popover:
        require(snippet not in popover, f"forbidden preview popover regression: {snippet}")

    print("OK preview window performance guards present")


if __name__ == "__main__":
    main()
