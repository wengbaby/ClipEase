import AppKit
import SwiftUI

@MainActor
final class HistoryWindowController: NSObject, NSWindowDelegate {
    private let panelHeight: CGFloat = 360
    private let panelAnimationDistance: CGFloat = 360
    private let panelAnimationDuration: TimeInterval = 0.14
    private let panelBackgroundColor = NSColor(red: 0.78, green: 0.82, blue: 0.92, alpha: 1.0)
    private let store: ClipboardHistoryStore
    private let pasteExecutor: PasteExecutor
    private let accessibilityPermissionState: AccessibilityPermissionState
    private let recordingController: RecordingController
    private let appMenuController: AppMenuController
    private let previewWindowController = HistoryPreviewWindowController()
    private let previewState = HistoryPreviewState()
    private let renderState = HistoryWindowRenderState()
    private let inputState = HistoryWindowInputState()
    private lazy var keyboardEventTap = HistoryKeyboardEventTap(inputState: inputState)
    private var panel: HistoryPanel?
    private var outsideClickMonitor: Any?
    private var localOutsideClickMonitor: Any?
    private var isClosing = false
    private weak var previousFrontmostApplication: NSRunningApplication?
    private var lastKnownPanelFrame: NSRect?

    init(
        store: ClipboardHistoryStore,
        pasteExecutor: PasteExecutor,
        accessibilityPermissionState: AccessibilityPermissionState,
        recordingController: RecordingController,
        appMenuController: AppMenuController
    ) {
        self.store = store
        self.pasteExecutor = pasteExecutor
        self.accessibilityPermissionState = accessibilityPermissionState
        self.recordingController = recordingController
        self.appMenuController = appMenuController
        super.init()
    }

    func preloadHistoryDataAfterLaunch() {
        let panel = panel ?? makePanel()
        self.panel = panel
        let targetFrame = frameForPanel()
        panel.setFrame(hiddenFrame(for: targetFrame), display: false)
        renderState.prepareForPreload(itemCount: store.items.count)
        inputState.setWindowVisible(true)
        inputState.setWindowPresented(false)
        PerformanceDiagnosticsService.shared.record(
            "history.preload.start",
            category: "history",
            durationMS: 0,
            itemCount: store.items.count,
            metadata: ["reason": "app.launch"]
        )
        renderState.mark("prepared")
        renderState.finishTrace()
    }

    func toggle() {
        if let panel, panel.isVisible {
            close()
            return
        }

        show()
    }

    func show() {
        captureFrontmostApplicationIfNeeded()
        let panel = panel ?? makePanel()
        self.panel = panel
        isClosing = false
        let targetFrame = frameForPanel()
        lastKnownPanelFrame = targetFrame
        GlobalStatusToastController.shared.updateHistoryWindowFrame(targetFrame, screen: panel.screen ?? NSScreen.clipeaseScreenContainingMouse ?? NSScreen.main)
        appMenuController.setStatusToastAnchorWindow(panel)
        let shouldAnimate = !panel.isVisible

        panel.hasShadow = false
        panel.alphaValue = 1
        if shouldAnimate {
            renderState.prepareForShow(itemCount: store.items.count)
            panel.setFrame(hiddenFrame(for: targetFrame), display: false)
        } else {
            panel.disableScreenUpdatesUntilFlush()
            panel.setFrame(targetFrame, display: true)
        }

        panel.orderFrontRegardless()
        panel.makeKey()
        renderState.mark("panel-ordered")
        if let latestFocusRequest = store.latestItemFocusRequest {
            inputState.requestItemFocus(latestFocusRequest.itemID, resetToAll: true)
        } else if !HistoryScrollCoordinator.shared.hasPendingExplicitOffset {
            HistoryScrollCoordinator.shared.restoreSavedOffset()
        }
        inputState.setWindowVisible(true)
        inputState.setWindowPresented(true)
        store.setOCRInteractiveThrottleActive(true)

        guard shouldAnimate else {
            finishShowingWindow()
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = panelAnimationDuration
            context.timingFunction = CAMediaTimingFunction(name: .linear)
            panel.animator().setFrame(targetFrame, display: false)
        } completionHandler: { [weak self, weak panel] in
            Task { @MainActor in
                guard panel?.isVisible == true else {
                    return
                }
                panel?.hasShadow = false
                self?.finishShowingWindow()
            }
        }
    }

    func close() {
        guard let panel,
              panel.isVisible,
              !isClosing else {
            inputState.notifyWindowWillHide()
            keyboardEventTap.stop()
            removeOutsideClickMonitor()
            closePreview()
            panel?.orderOut(nil)
            panel?.hasShadow = false
            return
        }

        isClosing = true
        panel.hasShadow = false
        let targetFrame = hiddenFrame(for: panel.frame)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = panelAnimationDuration
            context.timingFunction = CAMediaTimingFunction(name: .linear)
            panel.animator().setFrame(targetFrame, display: false)
        } completionHandler: { [weak self, weak panel] in
            Task { @MainActor in
                self?.inputState.notifyWindowWillHide()
                self?.keyboardEventTap.stop()
                self?.removeOutsideClickMonitor()
                self?.closePreview()
                panel?.orderOut(nil)
                panel?.alphaValue = 1
                panel?.hasShadow = false
                self?.store.setOCRInteractiveThrottleActive(false)
                self?.isClosing = false
            }
        }
    }

    func hideImmediatelyForAutoPaste() {
        inputState.notifyWindowWillHide()
        keyboardEventTap.stop()
        removeOutsideClickMonitor()
        closePreview()
        panel?.orderOut(nil)
        panel?.hasShadow = false
        store.setOCRInteractiveThrottleActive(false)
        isClosing = false
    }

    private func finishShowingWindow() {
        keyboardEventTap.start()
        installOutsideClickMonitor()
    }

    private func makePanel() -> HistoryPanel {
        let contentView = HistoryWindowView(
            store: store,
            previewState: previewState,
            renderState: renderState,
            inputState: inputState,
            recordingController: recordingController,
            accessibilityPermissionState: accessibilityPermissionState,
            appMenuController: appMenuController,
            pasteExecutor: pasteExecutor,
            onClose: { [weak self] in
                self?.close()
            },
            onPreview: { [weak self] item, cardFrame in
                self?.showPreview(item, cardFrame: cardFrame)
            },
            onMovePreview: { [weak self] cardFrame in
                self?.movePreview(cardFrame: cardFrame)
            },
            onClosePreview: { [weak self] in
                self?.closePreview()
            },
            onCreateText: { [weak self] defaultGroupID in
                self?.createTextFromHistoryWindow(defaultGroupID: defaultGroupID)
            }
        )

        let panel = HistoryPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        panel.delegate = self
        panel.onEscape = { [weak self] in
            self?.inputState.dispatch(.close)
        }
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovable = false
        panel.animationBehavior = .none
        panel.backgroundColor = panelBackgroundColor
        panel.isOpaque = true
        panel.hasShadow = false
        previewWindowController.onKeyStateChange = { [weak self] isKey in
            self?.inputState.setPreviewKeyWindowActive(isKey)
        }

        let hostingView = NSHostingView(rootView: contentView)
        hostingView.focusRingType = .none
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = panelBackgroundColor.cgColor
        hostingView.layer?.borderWidth = 0
        hostingView.layer?.shadowOpacity = 0
        hostingView.layer?.masksToBounds = false
        panel.contentView = hostingView
        return panel
    }

    private func frameForPanel() -> NSRect {
        let screen = NSScreen.clipeaseScreenContainingMouse ?? NSScreen.main
        let frame = screen?.frame ?? NSScreen.main?.frame ?? .zero
        return NSRect(
            x: frame.minX,
            y: frame.minY,
            width: frame.width,
            height: panelHeight
        )
    }

    private func hiddenFrame(for frame: NSRect) -> NSRect {
        frame.offsetBy(dx: 0, dy: -panelAnimationDistance)
    }

    func pasteTargetApplication() -> NSRunningApplication? {
        previousFrontmostApplication
    }

    var isPreviewInteractionActive: Bool {
        previewWindowController.isRecordingSuppressionActive
    }

    private func captureFrontmostApplicationIfNeeded() {
        guard let frontmostApplication = NSWorkspace.shared.frontmostApplication,
              frontmostApplication.bundleIdentifier != Bundle.main.bundleIdentifier else {
            return
        }

        previousFrontmostApplication = frontmostApplication
    }

    private func installOutsideClickMonitor() {
        removeOutsideClickMonitor()
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .leftMouseUp, .rightMouseUp]) { [weak self] event in
            Task { @MainActor in
                self?.closeIfClickIsOutsideHistory(event)
            }
        }
        localOutsideClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .leftMouseUp, .rightMouseUp]) { [weak self] event in
            self?.closeIfClickIsOutsideHistory(event)
            return event
        }
    }

    private func removeOutsideClickMonitor() {
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
            self.outsideClickMonitor = nil
        }
        if let localOutsideClickMonitor {
            NSEvent.removeMonitor(localOutsideClickMonitor)
            self.localOutsideClickMonitor = nil
        }
    }

    private func closeIfClickIsOutsideHistory(_ event: NSEvent) {
        guard let panel, panel.isVisible else {
            return
        }
        guard !inputState.isWindowPinnedOpenSnapshot else {
            return
        }
        guard !inputState.isPreviewContentActive else {
            return
        }

        if event.window === panel {
            return
        }

        if let eventWindow = event.window,
           NSApp.windows.contains(eventWindow) {
            return
        }

        let screenPoint = NSEvent.mouseLocation
        if panel.frame.contains(screenPoint) || previewWindowController.contains(screenPoint: screenPoint) {
            return
        }

        close()
    }

    private func showPreview(_ item: ClipboardItem, cardFrame: CGRect) {
        guard let panel else {
            inputState.setPreviewActive(false)
            previewState.close()
            return
        }

        let anchorScreenPoint = CGPoint(
            x: panel.frame.minX + cardFrame.midX,
            y: panel.frame.maxY - cardFrame.minY
        )
        let screenFrame = panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? panel.frame
        let didShowPreview = previewWindowController.show(
            item: item,
            parentWindow: panel,
            anchorScreenPoint: anchorScreenPoint,
            screenFrame: screenFrame,
            onCopy: { [weak self, pasteExecutor] in
                guard let self else {
                    return
                }
                switch pasteExecutor.copyToPasteboard(item) {
                case .copied:
                    ClipEaseSoundPlayer.shared.playCopyFeedback()
                    self.showStatus(self.copyStatus(for: item))
                case .copiedFallbackText:
                    ClipEaseSoundPlayer.shared.playCopyFeedback()
                    self.showStatus(self.copyFallbackTextStatus(for: item))
                case .failed(let reason):
                    self.showStatus(reason)
                }
            },
            onOpen: { [weak self] in
                self?.openPreviewItem(item)
            },
            onReveal: { [weak self] in
                self?.revealPreviewItem(item)
            },
            onCopyURL: { [weak self] in
                self?.copyPlainPreviewText(item.text)
            },
            onCopyMarkdown: { [weak self] in
                self?.copyPlainPreviewText(self?.markdownLink(for: item))
            },
            onCopyPath: { [weak self] in
                self?.copyPreviewPath(for: item)
            },
            onCopyRGB: { [weak self] in
                self?.copyPlainPreviewText(self?.rgbString(from: item.text))
            },
            onClose: { [weak self] in
                self?.closePreview()
            },
            onDetach: { [weak self] in
                guard let self else {
                    return
                }
                self.inputState.setPreviewActive(false)
                self.previewState.close()
                self.close()
            }
        )
        guard didShowPreview else {
            inputState.setPreviewActive(false)
            previewState.close()
            return
        }

        guard previewWindowController.isAttachedVisible else {
            inputState.setPreviewActive(false)
            previewState.close()
            return
        }

        previewState.open(item.id)
        inputState.setPreviewActive(true)
        previewWindowController.installOutsideClickMonitor { [weak self] in
            self?.closePreview()
        }
        previewWindowController.installEscapeKeyMonitor { [weak self] in
            self?.closePreview()
        }
    }

    private func movePreview(cardFrame: CGRect) {
        guard let panel else {
            return
        }

        let anchorScreenPoint = CGPoint(
            x: panel.frame.minX + cardFrame.midX,
            y: panel.frame.maxY - cardFrame.minY
        )
        let screenFrame = panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? panel.frame
        previewWindowController.move(anchorScreenPoint: anchorScreenPoint, screenFrame: screenFrame)
    }

    private func openPreviewItem(_ item: ClipboardItem) {
        switch item.type {
        case .link:
            if let url = item.url {
                NSWorkspace.shared.open(url)
            }
        case .image:
            if let url = imageURL(for: item) {
                NSWorkspace.shared.open(url)
            }
        case .text, .color, .file:
            break
        }
    }

    private func revealPreviewItem(_ item: ClipboardItem) {
        switch item.type {
        case .image:
            guard let url = imageURL(for: item) else {
                return
            }

            NSWorkspace.shared.activateFileViewerSelecting([url])
        case .file:
            let urls = existingPreviewFileURLs(for: item)
            guard !urls.isEmpty else {
                showStatus("未找到文件")
                return
            }

            NSWorkspace.shared.activateFileViewerSelecting(urls)
        case .text, .link, .color:
            break
        }
    }

    private func copyPlainPreviewText(_ text: String?) {
        guard let text,
              !text.isEmpty else {
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        store.skipNextClipboardText(text)
        store.addText(text, sourceApp: .clipease)
        ClipEaseSoundPlayer.shared.playCopyFeedback()
    }

    private func copyPreviewPath(for item: ClipboardItem) {
        switch item.type {
        case .image:
            copyPlainPreviewText(imagePath(for: item))
        case .file:
            copyPreviewFilePaths(for: item)
        case .text, .link, .color:
            break
        }
    }

    private func copyPreviewFilePaths(for item: ClipboardItem) {
        guard item.type == .file else {
            showStatus("未找到文件")
            return
        }

        let paths = item.fileReferences
            .map(\.path)
            .filter { !$0.isEmpty }

        guard !paths.isEmpty else {
            showStatus("未找到文件")
            return
        }

        let pathsText = paths.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(pathsText, forType: .string)
        store.skipNextClipboardText(pathsText)
        store.addText(pathsText, sourceApp: .clipease)
        ClipEaseSoundPlayer.shared.playCopyFeedback()
        showStatus(paths.count > 1 ? "已复制 \(paths.count) 个文件路径" : "已复制文件路径")
    }

    private func markdownLink(for item: ClipboardItem) -> String? {
        guard item.type == .link else {
            return nil
        }

        let title = (item.linkTitle?.isEmpty == false ? item.linkTitle : nil)
            ?? item.url?.host(percentEncoded: false)
            ?? item.text
        return "[\(title)](\(item.text))"
    }

    private func imagePath(for item: ClipboardItem) -> String? {
        imageURL(for: item)?.path
    }

    private func imageURL(for item: ClipboardItem) -> URL? {
        guard item.type == .image,
              let fileName = item.imageFileName else {
            return nil
        }

        return try? ClipEaseStoragePaths.imageFileURL(fileName: fileName)
    }

    private func existingPreviewFileURLs(for item: ClipboardItem) -> [URL] {
        guard item.type == .file else {
            return []
        }

        return item.fileReferences.compactMap { reference in
            guard !reference.path.isEmpty else {
                return nil
            }

            let url = URL(fileURLWithPath: reference.path).standardizedFileURL
            guard FileManager.default.fileExists(atPath: url.path) else {
                return nil
            }

            return url
        }
    }

    private func showStatus(_ text: String) {
        if let frame = lastKnownPanelFrame {
            GlobalStatusToastController.shared.updateHistoryWindowFrame(frame, screen: panel?.screen ?? NSScreen.clipeaseScreenContainingMouse ?? NSScreen.main)
        }
        appMenuController.setStatusToastAnchorWindow(panel)
        GlobalStatusToastController.shared.show(text, relativeTo: panel)
    }

    private func copyStatus(for item: ClipboardItem) -> String {
        switch item.type {
        case .text:
            item.richTextFileName == nil ? "已复制文本" : "已复制富文本"
        case .link:
            "已复制链接"
        case .image:
            "已复制图片"
        case .color:
            "已复制颜色"
        case .file:
            "已复制文件引用"
        }
    }

    private func copyFallbackTextStatus(for item: ClipboardItem) -> String {
        switch item.type {
        case .file:
            "文件不可用，已复制文件路径"
        default:
            copyStatus(for: item)
        }
    }

    private func rgbString(from hex: String) -> String? {
        guard let components = ClipEaseColorComponents(hex: hex) else {
            return nil
        }

        let red = Int(round(components.red * 255))
        let green = Int(round(components.green * 255))
        let blue = Int(round(components.blue * 255))
        return "rgb(\(red), \(green), \(blue))"
    }

    private func closePreview() {
        inputState.setPreviewActive(false)
        previewState.close()
        previewWindowController.close()
    }

    private func showAndFocusCreatedItem(_ item: ClipboardItem) {
        show()
        inputState.requestItemFocus(item.id, resetToAll: item.groupID == nil)
    }

    func createTextFromHistoryWindow(defaultGroupID: ClipboardGroup.ID?) {
        close()
        appMenuController.createTextItem(defaultGroupID: defaultGroupID) { [weak self] item in
            self?.showAndFocusCreatedItem(item)
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        if previewWindowController.isAttachedVisible {
            return
        }

        closePreview()
    }
}
