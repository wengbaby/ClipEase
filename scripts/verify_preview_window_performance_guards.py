#!/usr/bin/env python3
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CONTROLLER = ROOT / "Sources/ClipEase/Features/HistoryWindow/HistoryPreviewWindowController.swift"
HISTORY_CONTROLLER = ROOT / "Sources/ClipEase/Features/HistoryWindow/HistoryWindowController.swift"
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


def body_of_function_matching(source: str, pattern: str, description: str) -> str:
    match = re.search(pattern, source)
    if not match:
        fail(f"missing function {description}")

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
    history_controller = HISTORY_CONTROLLER.read_text(encoding="utf-8")
    popover = POPOVER.read_text(encoding="utf-8")
    link_web = LINK_WEB.read_text(encoding="utf-8")

    show = body_of_function(controller, "show")
    close = body_of_function_matching(controller, r"\bfunc\s+close\s*\(\s*allowDetached:\s*Bool\s*\)\s*\{", "close(allowDetached:)")
    schedule_content = body_of_function(controller, "scheduleContentLoad")
    load_preview_image = body_of_function(popover, "loadPreviewImage")
    detach_current = body_of_function(controller, "detachCurrentPreview")
    close_detached = body_of_function(controller, "closeDetachedPreview")
    configure_attached = body_of_function(controller, "configureAttachedPanel")
    configure_detached = body_of_function(controller, "configureDetachedPanel")
    detached_frame = body_of_function(controller, "detachedFrame")
    clamped_window_frame = body_of_function(controller, "clampedWindowFrame")
    install_detached_escape = body_of_function(controller, "installDetachedEscapeKeyMonitorIfNeeded")
    detached_panel_for_event = body_of_function(controller, "detachedPanel")
    show_preview = body_of_function(history_controller, "showPreview")
    header = re.search(r"private var header: some View \{(?P<body>.*?)\n    private var actionMenu", popover, re.S)
    require(header is not None, "preview header block missing")
    header_body = header.group("body")

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
    require("private var detachedPanels: [ObjectIdentifier: NSPanel] = [:]" in controller,
            "detached previews must be retained independently from the attached preview slot")
    require("self.panel = nil" in detach_current
            and "detachedPanels[panelID] = panel" in detach_current,
            "detaching must release the attached preview slot so the next preview opens at the card position")
    require("private func closeDetachedPreview(_ detachedPanel: NSPanel)" in controller
            and "detachedPanels.removeValue(forKey: panelID)" in controller
            and "detachedPanel.contentView = NSView()" in controller,
            "each detached preview must close independently and clean up its own content")
    require("private var detachedEscapeKeyMonitor: Any?" in controller
            and "installDetachedEscapeKeyMonitorIfNeeded()" in detach_current
            and "removeDetachedEscapeKeyMonitorIfNeeded()" in close_detached,
            "detached previews need their own Esc monitor lifecycle")
    require("NSEvent.addLocalMonitorForEvents(matching: .keyDown)" in install_detached_escape
            and "event.keyCode == KeyCode.escape" in install_detached_escape
            and "self.closeDetachedPreview(detachedPanel)" in install_detached_escape
            and "return nil" in install_detached_escape,
            "Esc in a focused detached preview must close that detached window")
    require("event.window as? NSPanel" in detached_panel_for_event
            and "NSApp.keyWindow as? NSPanel" in detached_panel_for_event
            and "detachedPanels[ObjectIdentifier" in detached_panel_for_event,
            "detached Esc handling must be scoped to the event or key detached preview")
    require("var isAttachedVisible: Bool" in controller
            and "panel?.isVisible == true" in controller
            and "var isRecordingSuppressionActive: Bool" in controller,
            "controller must distinguish attached previews from detached windows")
    require("configureDetachedPanel(panel)" in detach_current
            and "panel.level = .normal" in controller
            and "panel.hasShadow = true" in controller
            and "panel.makeKeyAndOrderFront(nil)" in detach_current,
            "detached preview must become a normal switchable App window")
    require("private let detachedPreviewMinimumSize = CGSize(width: 390, height: 260)" in controller
            and "panel.minSize = .zero" in configure_attached
            and "panel.minSize = detachedPreviewMinimumSize" in configure_detached,
            "detached previews must have a usable minimum size while attached popovers keep flexible sizing")
    require("bestScreen(for: proposedFrame)?.visibleFrame" in detached_frame
            and "clampedWindowFrame(proposedFrame, to: visibleFrame)" in detached_frame
            and "min(max(frame.minX, visibleFrame.minX), visibleFrame.maxX - width)" in clamped_window_frame
            and "min(max(frame.minY, visibleFrame.minY), visibleFrame.maxY - height)" in clamped_window_frame,
            "detached preview initial frame must stay within the current visible screen area")
    require("private func bestScreen(for frame: CGRect) -> NSScreen?" in controller
            and "visibleFrame.intersection(frame).area" in controller
            and "private extension CGRect" in controller
            and "var area: CGFloat" in controller,
            "detached preview screen selection must use visible-frame intersection area")
    require("removeOutsideClickMonitor()" in detach_current
            and "removeEscapeKeyMonitor()" in detach_current
            and "configuration.onDetach()" in detach_current,
            "detaching must stop attached-popover monitors and clear history preview state")
    require(detach_current.count("configuration.onDetach()") == 1,
            "detached preview close/escape must not re-run the main-window detach callback")
    require("onDetach:" in show_preview
            and "self.inputState.setPreviewActive(false)" in show_preview
            and "self.previewState.close()" in show_preview
            and "self.close()" in show_preview,
            "detaching a preview must immediately close the main history window")
    require("showsArrow: true" in controller
            and "showsArrow: false" in detach_current
            and "let showsArrow: Bool" in popover
            and "if showsArrow" in popover
            and "height: size.height + (showsArrow ? 14 : 0)" in popover,
            "detached preview must hide the attached-popover arrow and shrink its window frame")
    require("PreviewHeaderDragRegion(onDragStarted: onDetachDrag)" in popover
            and "private struct PreviewHeaderDragRegion: NSViewRepresentable" in popover
            and "private let dragActivationDistance: CGFloat = 4" in popover
            and "override func mouseDragged(with event: NSEvent)" in popover
            and "dragWindow?.performDrag(with: initialMouseDownEvent)" in popover
            and "minHeight: 22, maxHeight: 22" in header_body
            and header_body.count(".padding(.vertical, 10)") == 1
            and ".allowsHitTesting(false)" in popover,
            "only the preview header title area should start window detach drag")

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
    require(".buttonStyle(PreviewBadgeButtonStyle())" in popover
            and "private struct PreviewBadgeButtonStyle: ButtonStyle" in popover
            and "Capsule()" in popover,
            "OCR/contact badges must use lightweight hover/press feedback")
    require(".buttonStyle(PreviewFileReferenceButtonStyle())" in popover
            and "private struct PreviewFileReferenceButtonStyle: ButtonStyle" in popover
            and ".animation(.easeOut(duration: 0.10), value: isSelected)" in popover,
            "file reference rows must use lightweight feedback and selection transition")
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
