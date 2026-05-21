#!/usr/bin/env python3
from pathlib import Path


root = Path(__file__).resolve().parents[1]
controller = root / "Sources/ClipEase/Features/HistoryWindow/HistoryWindowController.swift"
view = root / "Sources/ClipEase/Features/HistoryWindow/HistoryWindowView.swift"
input_state = root / "Sources/ClipEase/Features/HistoryWindow/HistoryWindowInputState.swift"

controller_text = controller.read_text(encoding="utf-8")
view_text = view.read_text(encoding="utf-8")
input_state_text = input_state.read_text(encoding="utf-8")

required_controller = [
    "private let panelAnimationDistance: CGFloat = 360",
    "private let panelAnimationDuration: TimeInterval = 0.14",
    "panel.animationBehavior = .none",
    "panel.isOpaque = true",
    "panel.hasShadow = false",
    "hostingView.layer?.shadowOpacity = 0",
    "renderState.prepareForShow(itemCount: store.items.count)",
    "panel.setFrame(hiddenFrame(for: targetFrame), display: true)",
    "panel.orderFrontRegardless()",
    "panel.makeKey()",
    "renderState.mark(\"panel-ordered\")",
    "context.timingFunction = CAMediaTimingFunction(name: .linear)",
    "panel.animator().setFrame(targetFrame, display: false)",
    "panel.animator().setFrame(targetFrame, display: false)",
    "self?.finishShowingWindow()",
    "panel.animator().setFrame(targetFrame, display: false)",
    "panel?.orderOut(nil)",
    "guard !inputState.isPreviewContentActive else",
    "if panel.frame.contains(screenPoint) || previewWindowController.contains(screenPoint: screenPoint)",
    "private func finishShowingWindow()",
    "keyboardEventTap.start()",
    "installOutsideClickMonitor()",
]

required_view = [
    ".transaction { transaction in",
    "transaction.animation = nil",
    "previewBuildTask?.cancel()",
    "preheatTask?.cancel()",
    "previewFollowTask?.cancel()",
    "rememberSelectedItemTask?.cancel()",
    "deferredStartupTask?.cancel()",
    "private func scheduleDeferredStartupWork()",
    "try? await Task.sleep(nanoseconds: 32_000_000)",
    "schedulePreviewItemsRebuild(from: sourceItems)",
    "try? await Task.sleep(nanoseconds: 260_000_000)",
    "scheduleSearchUpdate(debounceNanoseconds:",
    "isTextInputActiveForEditShortcut || inputState.isPreviewContentActive",
    "if !inputState.isPreviewContentActive {\n                shortcutButtons\n            }",
]

required_input_state = [
    "@Published private(set) var isPreviewContentActive = false",
    "func setWindowVisible(_ isVisible: Bool)",
    "func setWindowPresented(_ isPresented: Bool)",
    "func notifyWindowWillHide()",
]

forbidden_controller = [
    "panel.animator().alphaValue",
    "panel.animator().setAlphaValue",
    "panel?.animator().alphaValue",
    "panel.contentView?.layer?.transform",
    "CATransform3DMakeTranslation",
    "private func animateContentLayer",
    "panel.hasShadow = true",
    "panel?.hasShadow = true",
    "context.allowsImplicitAnimation = true",
    "installOutsideClickMonitor()\n        panel.orderFrontRegardless()",
]

forbidden_view = [
    ".focusable()",
    ".scaleEffect(isShortcutOverlayVisible",
    "NumberShortcutHandler(isEnabled:",
    "isTextInputActiveForEditShortcut || previewState.isVisible",
    ".onAppear {\n            renderState.mark(\"swiftui-appear\")\n            HistoryWindowInputState.currentForTextEditing = inputState\n            restoreRememberedGroupSelection()\n            HistoryScrollCoordinator.shared.loadSavedOffsets(from: rememberedScrollOffsetsByScopeData)\n            HistoryScrollCoordinator.shared.setScope(selectedGroup.storageValue)\n            HistoryScrollCoordinator.shared.onOffsetChange = { [weak inputState] _ in\n                guard inputState?.isWindowPresentedSnapshot == true else {\n                    return\n                }\n\n                Task { @MainActor in\n                    followPreviewForCurrentScroll()\n                }\n            }\n            refreshMoveToGroupMenuSnapshot()\n            primeLatestItemPresentationGuard(sourceItems: store.items)\n            if let request = store.latestItemFocusRequest {\n                focusRequestedLatestItem(request)\n            }\n            focusRecentlyAddedItemOnShowIfNeeded(sourceItems: store.items)\n            schedulePreviewItemsRebuild(from: store.items)",
]

checks = [
    ("controller required", required_controller, controller_text, True),
    ("view required", required_view, view_text, True),
    ("input state required", required_input_state, input_state_text, True),
    ("controller forbidden", forbidden_controller, controller_text, False),
    ("view forbidden", forbidden_view, view_text, False),
]

failures = []
for label, snippets, text, should_exist in checks:
    for snippet in snippets:
        present = snippet in text
        if should_exist and not present:
            failures.append(f"Missing {label}: {snippet}")
        if not should_exist and present:
            failures.append(f"Forbidden {label}: {snippet}")

if "func close() {" not in controller_text or "completionHandler:" not in controller_text:
    failures.append("Missing close animation completion handler")

if failures:
    print("History window animation/performance guard failed:")
    print("\n".join(failures))
    raise SystemExit(1)

print("OK history window animation/performance guards present")
