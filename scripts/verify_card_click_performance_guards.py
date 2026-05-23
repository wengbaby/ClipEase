#!/usr/bin/env python3
from pathlib import Path

root = Path(__file__).resolve().parents[1]
view = root / "Sources/ClipEase/Features/HistoryWindow/HistoryWindowView.swift"
card = root / "Sources/ClipEase/Features/HistoryWindow/HistoryCardView.swift"
controller = root / "Sources/ClipEase/Features/HistoryWindow/HistoryWindowController.swift"
preview_controller = root / "Sources/ClipEase/Features/HistoryWindow/HistoryPreviewWindowController.swift"
preview_text_view = root / "Sources/ClipEase/Features/HistoryWindow/LazyPreviewTextView.swift"
link_preview_view = root / "Sources/ClipEase/Features/HistoryWindow/LinkPreviewWebView.swift"
input_state = root / "Sources/ClipEase/Features/HistoryWindow/HistoryWindowInputState.swift"
keyboard_tap = root / "Sources/ClipEase/Features/HistoryWindow/HistoryKeyboardEventTap.swift"
store = root / "Sources/ClipEase/Core/Storage/ClipboardHistoryStore.swift"
view_text = view.read_text(encoding="utf-8")
card_text = card.read_text(encoding="utf-8")
controller_text = controller.read_text(encoding="utf-8")
preview_controller_text = preview_controller.read_text(encoding="utf-8")
preview_text_view_text = preview_text_view.read_text(encoding="utf-8")
link_preview_view_text = link_preview_view.read_text(encoding="utf-8")
input_state_text = input_state.read_text(encoding="utf-8")
keyboard_tap_text = keyboard_tap.read_text(encoding="utf-8")
store_text = store.read_text(encoding="utf-8")
text = "\n".join([
    view_text,
    card_text,
    controller_text,
    preview_controller_text,
    preview_text_view_text,
    link_preview_view_text,
    input_state_text,
    keyboard_tap_text,
    store_text,
])

required = [
    "private final class FileCardDragSourceNSView: NSView, NSDraggingSource",
    "override func mouseDown(with event: NSEvent)",
    "override func mouseDragged(with event: NSEvent)",
    "override func mouseUp(with event: NSEvent)",
    "override func rightMouseDown(with event: NSEvent)",
    "guard hypot(deltaX, deltaY) <= clickMoveTolerance",
    "draggableText(for: item) != nil",
    "rememberSelectedItemTask",
    "latestFocusRetryTask",
    "latestFocusRetryTask?.cancel()",
    "var attemptsRemaining = remainingAttempts",
    "while attemptsRemaining > 0",
    "try? await Task.sleep(nanoseconds: 150_000_000)",
    "persistSelectedItem()",
    "private func blurSearchFieldForCardInteraction()",
    "hostWindow?.makeFirstResponder(nil)",
    "blurSearchFieldForCardInteraction()",
    "struct HistoryCardView: View, Equatable",
    "nonisolated static func ==",
    ".equatable()",
    "private func historyCard(_ item: HistoryPreviewItem)",
    "let isSelected = selectedItemID == item.id",
    "@State private var isHovered = false",
    "@State private var isPressed = false",
    ".fill(Color.white.opacity(isPressed ? 0.16 : (isHovered ? 0.08 : 0)))",
    ".scaleEffect(isPressed ? 0.996 : (isHovered ? 1.004 : 1))",
    ".animation(.easeOut(duration: 0.12), value: isHovered)",
    ".animation(.easeOut(duration: 0.08), value: isPressed)",
    "onHoverChanged",
    "onPressChanged",
    "override func updateTrackingAreas()",
    "override func mouseEntered(with event: NSEvent)",
    "override func mouseExited(with event: NSEvent)",
    "radius: isSelected ? 12 : 0",
    "final class HistoryCardAssetLoadGate",
    "DispatchSemaphore(value: 3)",
    "HistoryCardAssetLoadGate.shared.load",
    "private struct RichTextCardPreview: View",
    "Text(attributedText ?? fallbackAttributedText)",
    "swiftUIAttributedString",
    "AttributedString(highlightedText, including: \\.appKit)",
    "private let panelAnimationDistance: CGFloat = 360",
    "private let panelAnimationDuration: TimeInterval = 0.14",
    "panel.setFrame(hiddenFrame(for: targetFrame), display: false)",
    "context.duration = panelAnimationDuration",
    "panel.animator().setFrame(targetFrame, display: false)",
    "panel.alphaValue = 1",
    "context.timingFunction = CAMediaTimingFunction(name: .linear)",
    "private func finishShowingWindow()",
    "self?.finishShowingWindow()",
    "styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView]",
    "panel.level = .screenSaver",
    "let frame = screen?.frame ?? NSScreen.main?.frame ?? .zero",
    "hostingView.focusRingType = .none",
    "hostingView.layer?.borderWidth = 0",
    "hostingView.layer?.shadowOpacity = 0",
    "private var previewActive = false",
    "private var previewKeyWindowActive = false",
    "var isPreviewActiveSnapshot: Bool",
    "return previewActive && previewKeyWindowActive",
    "@Published private(set) var isPreviewContentActive = false",
    "isTextInputActiveForEditShortcut || inputState.isPreviewContentActive",
    "latestItemFocusRequest",
    "items.removeAll { duplicateIDs.contains($0.id) }",
    "insertItemMaintainingSort(insertedItem)",
    "private var itemIDsByHash",
    "let duplicateIDs = itemIDsByHash[hash] ?? []",
    "latestItemFocusRequest = ClipboardItemFocusRequest(itemID: insertedItem.id, reason: .inserted)",
    "store.latestItemFocusRequest",
    "func setPreviewActive(_ isActive: Bool)",
    "func setPreviewKeyWindowActive(_ isActive: Bool)",
    "if inputState?.isPreviewActiveSnapshot == true",
    "shouldHandleWhilePreviewContentFocused",
    "if previewState.isVisible {\n            closePreview()\n        }\n\n        if !isSearchVisible",
    "if !inputState.isPreviewContentActive {\n                shortcutButtons\n            }",
    "private var shortcutButtons: some View",
    "NumberShortcutHandler(inputState: inputState)",
    "weak var inputState: HistoryWindowInputState?",
    "private func isPreviewContentActive() -> Bool",
    "!self.isPreviewContentActive()",
    "let shouldShowCommandOverlay = isCommandPressed && inputState?.isPreviewActiveSnapshot != true",
    "@discardableResult\n    func show(",
    ") -> Bool",
    "let didShowPreview = previewWindowController.show(",
    "guard didShowPreview else",
    "inputState.setPreviewActive(true)",
    "inputState.setPreviewActive(false)",
    "inputState.setPreviewKeyWindowActive(isKey)",
    "previewWindowController.onKeyStateChange",
    "private func closePreview()",
    "override var canBecomeKey: Bool",
    "override func becomeKey()",
    "override func resignKey()",
    "panel.makeKey()",
    "panel.orderFrontRegardless()",
    "panel.alphaValue = 1",
    "override func performKeyEquivalent(with event: NSEvent) -> Bool",
    "sendStandardEditAction(#selector(NSResponder.selectAll(_:)))",
    "sendStandardEditAction(#selector(NSText.copy(_:)))",
    "sendStandardEditAction(#selector(NSText.paste(_:)))",
    "private func sendStandardEditAction(_ selector: Selector) -> Bool",
    "private var escapeKeyMonitor: Any?",
    "func installEscapeKeyMonitor(onEscape: @escaping @MainActor () -> Void)",
    "event.keyCode == KeyCode.escape",
    "self.panel?.isKeyWindow == true",
    "previewWindowController.installEscapeKeyMonitor",
    "private final class InteractivePreviewTextView: NSTextView",
    "window?.makeFirstResponder(self)",
    "private final class InteractivePreviewWebView: WKWebView",
    "private weak var parentWindow: NSWindow?",
    "detachPanelFromParent(panel)",
    "private func retryPendingLatestFocusJumpIfNeeded",
    "private func scheduleLatestProgrammaticTransition(",
    "retryPendingLatestFocusJumpIfNeeded(id, remainingAttempts: 4)",
    "private var coalescedScrollRequest",
    "private func coalesceScrollToOffset",
    "performScrollToOffset(",
    "func forceLayout()",
    "HistoryScrollCoordinator.shared.forceLayout()",
    "if previewWindowController.isAttachedVisible",
    "fulfillPendingLatestFocusIfPossible()",
]

forbidden = [
    "CardMouseInteractionLayer",
    "NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp])",
    "private var localMonitor: Any?",
    ".scaleEffect(isShortcutOverlayVisible",
    ".scaleEffect(isHovered ?",
    ".scaleEffect(isPressed ? 0.95",
    "panel.animator().alphaValue",
    "private func animateContentLayer",
    "panel.contentView?.layer?.transform = CATransform3DMakeTranslation",
    "panel?.hasShadow = true",
    "panel.hasShadow = true",
    ".focusable()",
    "override var canBecomeKey: Bool {\n        false",
    "isTextInputActiveForEditShortcut || previewState.isVisible",
    "parentWindow.addChildWindow(panel, ordered: .above)",
    "panel.animator().alphaValue = 1",
    "func windowDidResignKey(_ notification: Notification) {\n        closePreview()",
    "panel.makeKey()\n            (panel as? HistoryPreviewPanel)?.onKeyStateChange?(true)\n            if !shouldLoadImmediately",
    "NumberShortcutHandler(isEnabled:",
    "private struct RichTextCardPreview: NSViewRepresentable",
    "func makeNSView(context: Context) -> NSTextView",
    "textView.layoutManager?.ensureLayout",
    "lhs.isSelected == rhs.isSelected",
]

missing = [snippet for snippet in required if snippet not in text]
present_forbidden = []
for snippet in forbidden:
    if snippet in {
        "CardMouseInteractionLayer",
        ".scaleEffect(isShortcutOverlayVisible",
    }:
        search_text = text
    elif snippet in {
        "panel.animator().alphaValue",
        "private func animateContentLayer",
        "panel.contentView?.layer?.transform = CATransform3DMakeTranslation",
        "panel?.hasShadow = true",
        "panel.hasShadow = true",
    }:
        search_text = controller_text
    elif snippet == ".focusable()":
        search_text = view_text
    else:
        search_text = card_text
    if snippet in search_text:
        present_forbidden.append(snippet)

if missing or present_forbidden:
    if missing:
        print("Missing card click performance guard(s):")
        print("\n".join(missing))
    if present_forbidden:
        print("Forbidden high-frequency click path present:")
        print("\n".join(present_forbidden))
    raise SystemExit(1)

print("OK card click performance guards present")
