import AppKit
import QuartzCore
import SwiftUI

@MainActor
final class HistoryPreviewWindowController {
    private let clipboardWriter: ClipboardWriteCoordinator
    private var panel: NSPanel?
    private var outsideClickMonitor: Any?
    private var localOutsideClickMonitor: Any?
    private var escapeKeyMonitor: Any?
    private var detachedEscapeKeyMonitor: Any?
    private var contentLoadTask: Task<Void, Never>?
    private var contentConfiguration: PreviewContentConfiguration?
    private var isContentReady = false
    private var attachedAnimationGeneration: UInt64 = 0
    private var isAttachedClosing = false
    private var detachedPanels: [ObjectIdentifier: NSPanel] = [:]
    private var isInteractingInsidePreview = false
    private weak var parentWindow: NSWindow?
    var onKeyStateChange: ((Bool) -> Void)?
    private let arrowHeight: CGFloat = 14
    private let arrowGap: CGFloat = 18
    private let horizontalMargin: CGFloat = 12
    private let defaultPreviewSize = CGSize(width: 620, height: 370)
    private let detachedPreviewMinimumSize = CGSize(width: 390, height: 260)
    // Keeps tiny or 1px-edge images operable without returning to the old 220pt fixed image window.
    private let imagePreviewMinimumContentSize = CGSize(width: 180, height: 140)
    private let deferredContentLoadDelay: UInt64 = 50_000_000
    private let bloomOpenDuration: TimeInterval = 0.34
    private let bloomCloseDuration: TimeInterval = 0.22

    init(clipboardWriter: ClipboardWriteCoordinator) {
        self.clipboardWriter = clipboardWriter
    }

    var frame: CGRect? {
        panel?.frame
    }

    var isVisible: Bool {
        isAttachedVisible || detachedPanels.values.contains { $0.isVisible }
    }

    var isAttachedVisible: Bool {
        panel?.isVisible == true
    }

    func applyAppearance(_ appearance: NSAppearance?) {
        panel?.appearance = appearance
        detachedPanels.values.forEach { $0.appearance = appearance }
    }

    var isRecordingSuppressionActive: Bool {
        if panel?.isVisible == true {
            return true
        }

        return detachedPanels.values.contains { $0.isVisible && $0.isKeyWindow }
    }

    @discardableResult
    func show(
        item: ClipboardItem,
        parentWindow: NSWindow,
        anchorScreenPoint: CGPoint,
        screenFrame: CGRect,
        onCopy: @escaping () -> Void,
        onOpen: @escaping () -> Void,
        onReveal: @escaping () -> Void,
        onCopyURL: @escaping () -> Void,
        onCopyMarkdown: @escaping () -> Void,
        onCopyPath: @escaping () -> Void,
        onCopyRGB: @escaping () -> Void,
        onClose: @escaping () -> Void,
        onDetach: @escaping () -> Void
    ) -> Bool {
        let size = previewSize(for: item, screenFrame: screenFrame)
        let placement = HistoryPreviewPlacementPolicy.placement(
            anchorScreenPoint: anchorScreenPoint,
            screenFrame: screenFrame,
            size: size
        )
        let attachedFrame = placement.frame
        let arrowX = placement.arrowX

        let panel = panel ?? makePanel()
        let isAlreadyVisible = panel.isVisible
        let frame = attachedFrame
        let ocrResult = ClipboardOCRMatch(
            text: item.ocrText,
            emails: item.ocrEmails,
            phoneNumbers: item.ocrPhoneNumbers,
            urls: item.ocrURLs,
            textRegions: item.ocrTextRegions
        )
        self.panel = panel
        self.parentWindow = parentWindow
        contentLoadTask?.cancel()
        let shouldLoadImmediately = item.type == .text || item.type == .color || item.type == .file
        isContentReady = shouldLoadImmediately
        contentConfiguration = PreviewContentConfiguration(
            item: item,
            ocrResult: ocrResult,
            arrowX: arrowX,
            size: size,
            onCopy: onCopy,
            onOpen: onOpen,
            onReveal: onReveal,
            onCopyURL: onCopyURL,
            onCopyMarkdown: onCopyMarkdown,
            onCopyPath: onCopyPath,
            onCopyRGB: onCopyRGB,
            onClose: onClose,
            onDetach: onDetach
        )
        configureAttachedPanel(panel)
        detachPanelFromParent(panel)
        renderPreviewContent(panel: panel)
        (panel as? HistoryPreviewPanel)?.onEscape = { [weak self] in
            guard self?.panel === panel else {
                return
            }

            onClose()
        }

        attachedAnimationGeneration &+= 1
        let animationGeneration = attachedAnimationGeneration
        let shouldAnimateOpen = !isAlreadyVisible || isAttachedClosing
        isAttachedClosing = false

        if !shouldAnimateOpen {
            panel.setFrame(frame, display: true, animate: false)
            panel.orderFrontRegardless()
            (panel as? HistoryPreviewPanel)?.onKeyStateChange?(false)
            if !shouldLoadImmediately {
                scheduleContentLoad(
                    panel: panel,
                    item: item,
                    ocrResult: ocrResult,
                    arrowX: arrowX,
                    size: size,
                    delay: deferredContentLoadDelay
                )
            }
        } else {
            panel.setFrame(frame, display: true)
            prepareContentBloomLayer(panel, anchorX: arrowX, isOpening: true)
            panel.orderFrontRegardless()
            animatePanelOpen(panel, animationGeneration: animationGeneration)
            (panel as? HistoryPreviewPanel)?.onKeyStateChange?(false)
            if !shouldLoadImmediately {
                scheduleContentLoad(
                    panel: panel,
                    item: item,
                    ocrResult: ocrResult,
                    arrowX: arrowX,
                    size: size,
                    delay: deferredContentLoadDelay
                )
            }
        }

        return panel.isVisible
    }

    private func animatePanelOpen(_ panel: NSPanel, animationGeneration: UInt64) {
        guard let layer = panel.contentView?.layer else {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = bloomOpenDuration
                panel.contentView?.animator().alphaValue = 1
            }
            return
        }

        let scaleAnimation = CAKeyframeAnimation(keyPath: "transform")
        scaleAnimation.duration = bloomOpenDuration
        scaleAnimation.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)
        scaleAnimation.values = [
            NSValue(caTransform3D: CATransform3DMakeScale(0.12, 0.04, 1)),
            NSValue(caTransform3D: CATransform3DMakeScale(0.5, 0.5, 1)),
            NSValue(caTransform3D: CATransform3DIdentity)
        ]
        scaleAnimation.keyTimes = [0, 0.55, 1]
        scaleAnimation.fillMode = .forwards
        scaleAnimation.isRemovedOnCompletion = false

        NSAnimationContext.runAnimationGroup { context in
            context.duration = bloomOpenDuration
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)
            panel.contentView?.animator().alphaValue = 1
            layer.opacity = 1
            layer.add(scaleAnimation, forKey: "bloomOpen")
            layer.transform = CATransform3DIdentity
        } completionHandler: { [weak self, weak panel] in
            MainActor.assumeIsolated {
                guard let self,
                      self.attachedAnimationGeneration == animationGeneration else {
                    return
                }
                self.resetContentBloomLayer(panel)
            }
        }
    }

    private func prepareContentBloomLayer(_ panel: NSPanel, anchorX: CGFloat, isOpening: Bool) {
        guard let contentView = panel.contentView else {
            return
        }

        contentView.wantsLayer = true
        guard let layer = contentView.layer else {
            return
        }

        let width = max(contentView.bounds.width, panel.frame.width, 1)
        let normalizedAnchorX = min(max(anchorX / width, 0.08), 0.92)
        updateLayerAnchorPoint(layer, anchorPoint: CGPoint(x: normalizedAnchorX, y: 0))
        contentView.alphaValue = isOpening ? 0 : 1
        layer.opacity = isOpening ? 0 : 1
        layer.transform = isOpening ? previewBloomCollapsedTransform : CATransform3DIdentity
    }

    private var previewBloomCollapsedTransform: CATransform3D {
        CATransform3DMakeScale(0.12, 0.04, 1)
    }

    private func updateLayerAnchorPoint(_ layer: CALayer, anchorPoint: CGPoint) {
        guard layer.anchorPoint != anchorPoint else {
            return
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let oldOrigin = layer.frame.origin
        layer.anchorPoint = anchorPoint
        let newOrigin = layer.frame.origin
        layer.position = CGPoint(
            x: layer.position.x - newOrigin.x + oldOrigin.x,
            y: layer.position.y - newOrigin.y + oldOrigin.y
        )
        CATransaction.commit()
    }

    private func resetContentBloomLayer(_ panel: NSPanel?) {
        guard let contentView = panel?.contentView,
              let layer = contentView.layer else {
            return
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        contentView.alphaValue = 1
        layer.opacity = 1
        layer.transform = CATransform3DIdentity
        updateLayerAnchorPoint(layer, anchorPoint: CGPoint(x: 0.5, y: 0.5))
        CATransaction.commit()
    }

    func close() {
        close(allowDetached: false)
    }

    static func releaseHostedContent(from panel: NSPanel?) {
        guard let panel else {
            return
        }
        panel.contentView = NSView()
        panel.contentView?.alphaValue = 1
    }

    func close(allowDetached: Bool) {
        let parentWindow = parentWindow
        removeOutsideClickMonitor()
        removeEscapeKeyMonitor()
        contentLoadTask?.cancel()
        contentLoadTask = nil
        contentConfiguration = nil
        isContentReady = false
        (panel as? HistoryPreviewPanel)?.onKeyStateChange?(false)
        (panel as? HistoryPreviewPanel)?.onEscape = nil
        guard let panel, panel.isVisible else {
            isAttachedClosing = false
            panel?.orderOut(nil)
            Self.releaseHostedContent(from: panel)
            parentWindow?.makeKey()
            return
        }

        attachedAnimationGeneration &+= 1
        let animationGeneration = attachedAnimationGeneration
        isAttachedClosing = true

        let scaleAnimation = CAKeyframeAnimation(keyPath: "transform")
        scaleAnimation.duration = bloomCloseDuration
        scaleAnimation.timingFunction = CAMediaTimingFunction(controlPoints: 0.7, 0.0, 0.84, 0.0)
        scaleAnimation.values = [
            NSValue(caTransform3D: CATransform3DIdentity),
            NSValue(caTransform3D: CATransform3DMakeScale(0.85, 0.85, 1)),
            NSValue(caTransform3D: CATransform3DMakeScale(0.12, 0.04, 1))
        ]
        scaleAnimation.keyTimes = [0, 0.5, 1]
        scaleAnimation.fillMode = .forwards
        scaleAnimation.isRemovedOnCompletion = false

        if let layer = panel.contentView?.layer {
            layer.add(scaleAnimation, forKey: "bloomClose")
            layer.transform = CATransform3DMakeScale(0.12, 0.04, 1)
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = bloomCloseDuration
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.7, 0.0, 0.84, 0.0)
            panel.contentView?.animator().alphaValue = 0
            panel.contentView?.layer?.opacity = 0
        } completionHandler: { [weak self, weak panel] in
            MainActor.assumeIsolated {
                guard self?.attachedAnimationGeneration == animationGeneration else {
                    return
                }
                self?.isAttachedClosing = false
                panel?.contentView?.alphaValue = 0
                panel?.contentView?.layer?.opacity = 0
                panel?.contentView?.layer?.transform = CATransform3DIdentity
                panel?.orderOut(nil)
                parentWindow?.makeKey()
                Self.releaseHostedContent(from: panel)
            }
        }
    }

    func move(anchorScreenPoint: CGPoint, screenFrame: CGRect) {
        guard let panel, panel.isVisible else {
            return
        }

        let size = CGSize(width: panel.frame.width, height: max(1, panel.frame.height - arrowHeight))
        let placement = HistoryPreviewPlacementPolicy.placement(
            anchorScreenPoint: anchorScreenPoint,
            screenFrame: screenFrame,
            size: size
        )
        let frame = placement.frame
        let shouldUpdateArrow = updateAttachedArrowXIfNeeded(placement.arrowX)

        guard shouldUpdateArrow ||
              abs(panel.frame.minX - frame.minX) > 0.5 ||
              abs(panel.frame.minY - frame.minY) > 0.5 else {
            return
        }

        panel.setFrame(frame, display: true, animate: false)
        if shouldUpdateArrow {
            renderPreviewContent(panel: panel)
        }
    }

    func contains(screenPoint: CGPoint) -> Bool {
        guard let panel, panel.isVisible else {
            return false
        }

        return panel.frame.contains(screenPoint)
    }

    func installOutsideClickMonitor(onOutsideClick: @escaping @MainActor () -> Void) {
        removeOutsideClickMonitor()
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .leftMouseUp, .rightMouseUp]) { [weak self] event in
            Task { @MainActor in
                guard let self else {
                    return
                }

                if self.isInteractingInsidePreview {
                    if event.type == .leftMouseUp || event.type == .rightMouseUp {
                        self.isInteractingInsidePreview = false
                    }
                    return
                }

                guard self.contains(screenPoint: NSEvent.mouseLocation) == false else {
                    self.isInteractingInsidePreview = true
                    return
                }
                onOutsideClick()
            }
        }
        localOutsideClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .leftMouseUp, .rightMouseUp]) { [weak self] event in
            if self?.contains(screenPoint: NSEvent.mouseLocation) == true {
                if (event.type == .leftMouseDown || event.type == .rightMouseDown),
                   let panel = self?.panel {
                    self?.isInteractingInsidePreview = true
                    panel.makeKeyAndOrderFront(nil)
                    (panel as? HistoryPreviewPanel)?.onKeyStateChange?(true)
                } else if event.type == .leftMouseUp || event.type == .rightMouseUp {
                    self?.isInteractingInsidePreview = false
                }
                return event
            }
            if self?.isInteractingInsidePreview == true {
                if event.type == .leftMouseUp || event.type == .rightMouseUp {
                    self?.isInteractingInsidePreview = false
                }
                return event
            }
            onOutsideClick()
            return event
        }
    }

    func installEscapeKeyMonitor(onEscape: @escaping @MainActor () -> Void) {
        removeEscapeKeyMonitor()
        escapeKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self,
                  event.keyCode == KeyCode.escape,
                  self.panel?.isKeyWindow == true,
                  self.panel?.isVisible == true else {
                return event
            }

            onEscape()
            return nil
        }
    }

    private func makePanel() -> NSPanel {
        let panel = HistoryPreviewPanel(
            contentRect: .zero,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.appearance = AppearanceSettings.shared.windowAppearance
        panel.hidesOnDeactivate = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.onKeyStateChange = { [weak self] isKey in
            self?.onKeyStateChange?(isKey)
        }
        configureAttachedPanel(panel)
        return panel
    }

    private func configureAttachedPanel(_ panel: NSPanel) {
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.hasShadow = false
        panel.isMovable = false
        panel.minSize = .zero
        panel.animationBehavior = .none
        (panel as? HistoryPreviewPanel)?.isDetachedPreview = false
    }

    private func configureDetachedPanel(_ panel: NSPanel) {
        detachPanelFromParent(panel)
        parentWindow = nil
        panel.level = .normal
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hasShadow = true
        panel.isMovable = true
        panel.minSize = detachedPreviewMinimumSize
        panel.animationBehavior = .default
        (panel as? HistoryPreviewPanel)?.isDetachedPreview = true
    }

    private func detachPanelFromParent(_ panel: NSPanel) {
        panel.parent?.removeChildWindow(panel)
    }

    private func renderPreviewContent(panel: NSPanel) {
        guard let configuration = contentConfiguration else {
            return
        }

        renderPreviewContent(
            panel: panel,
            configuration: configuration,
            isContentReady: isContentReady,
            showsArrow: true,
            onClose: { configuration.onClose() },
            onDetachDrag: { [weak self] in
                guard let self else {
                    return nil
                }
                if self.detachedPanels[ObjectIdentifier(panel)] === panel {
                    return self.dragDetachedPreview(panel)
                }
                return self.detachCurrentPreview()
            }
        )
    }

    private func updateAttachedArrowXIfNeeded(_ arrowX: CGFloat) -> Bool {
        guard let configuration = contentConfiguration,
              abs(configuration.arrowX - arrowX) > 0.5 else {
            return false
        }

        contentConfiguration = configuration.withArrowX(arrowX)
        return true
    }

    private func renderPreviewContent(
        panel: NSPanel,
        configuration: PreviewContentConfiguration,
        isContentReady: Bool,
        showsArrow: Bool,
        onClose: @escaping () -> Void,
        onDetachDrag: @escaping () -> PreviewHeaderDragCompletion?
    ) {
        panel.contentView = NSHostingView(
            rootView: HistoryPreviewPopoverView(
                item: configuration.item,
                ocrResult: configuration.ocrResult,
                arrowX: configuration.arrowX,
                size: configuration.size,
                showsArrow: showsArrow,
                isContentReady: isContentReady,
                onClose: onClose,
                onCopy: configuration.onCopy,
                onOpen: configuration.onOpen,
                onReveal: configuration.onReveal,
                onCopyURL: configuration.onCopyURL,
                onCopyMarkdown: configuration.onCopyMarkdown,
                onCopyPath: configuration.onCopyPath,
                onCopyRGB: configuration.onCopyRGB,
                onDetachDrag: onDetachDrag,
                clipboardWriter: clipboardWriter
            )
            .preferredColorScheme(AppearanceSettings.shared.preferredColorScheme)
        )
    }

    private func scheduleContentLoad(
        panel: NSPanel,
        item: ClipboardItem,
        ocrResult: ClipboardOCRMatch?,
        arrowX: CGFloat,
        size: CGSize,
        delay: UInt64
    ) {
        contentLoadTask?.cancel()
        contentLoadTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled, panel.isVisible else {
                return
            }
            guard self.panel === panel,
                  self.contentConfiguration?.item.id == item.id,
                  self.contentConfiguration?.arrowX == arrowX,
                  self.contentConfiguration?.size == size,
                  self.contentConfiguration?.ocrResult?.text == ocrResult?.text else {
                return
            }

            self.isContentReady = true
            self.renderPreviewContent(panel: panel)
        }
    }

    private func detachCurrentPreview() -> PreviewHeaderDragCompletion? {
        guard let panel,
              panel.isVisible,
              let configuration = contentConfiguration else {
            return nil
        }

        removeOutsideClickMonitor()
        removeEscapeKeyMonitor()
        contentLoadTask?.cancel()
        contentLoadTask = nil
        contentConfiguration = nil
        isContentReady = false
        parentWindow = nil
        return { [weak self, weak panel] initialMouseDownEvent, firstDragEvent in
            guard let panel else {
                return
            }
            self?.prepareDetachedPreviewContent(panel: panel, configuration: configuration)
            self?.dragPanelManually(
                panel,
                initialMouseDownEvent: initialMouseDownEvent,
                firstDragEvent: firstDragEvent
            )
            self?.completeInitialDetachedPreviewDrag(panel: panel, configuration: configuration)
        }
    }

    private func prepareDetachedPreviewContent(panel: NSPanel, configuration: PreviewContentConfiguration) {
        renderPreviewContent(
            panel: panel,
            configuration: configuration,
            isContentReady: true,
            showsArrow: false,
            onClose: { [weak self, weak panel] in
                guard let panel else {
                    return
                }
                self?.closeDetachedPreview(panel)
            },
            onDetachDrag: { [weak self, weak panel] in
                guard let panel else {
                    return nil
                }
                return self?.dragDetachedPreview(panel)
            }
        )
        panel.setFrame(
            HistoryPreviewDetachedFramePolicy.frame(
                for: configuration.size,
                keepingTopEdgeFrom: panel.frame
            ),
            display: true,
            animate: false
        )
    }

    private func completeInitialDetachedPreviewDrag(panel: NSPanel, configuration: PreviewContentConfiguration) {
        guard panel.isVisible else {
            return
        }

        self.panel = nil
        configureDetachedPanel(panel)
        let panelID = ObjectIdentifier(panel)
        detachedPanels[panelID] = panel
        installDetachedEscapeKeyMonitorIfNeeded()
        (panel as? HistoryPreviewPanel)?.onEscape = { [weak self, weak panel] in
            guard let panel else {
                return
            }
            self?.closeDetachedPreview(panel)
        }
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        configuration.onDetach()
        finishDetachedPreviewDrag(panel: panel, configuration: configuration)
    }

    private func dragDetachedPreview(_ panel: NSPanel) -> PreviewHeaderDragCompletion {
        { [weak self, weak panel] initialMouseDownEvent, firstDragEvent in
            guard let panel = panel as? HistoryPreviewPanel,
                  panel.isVisible else {
                return
            }

            self?.dragPanelManually(
                panel,
                initialMouseDownEvent: initialMouseDownEvent,
                firstDragEvent: firstDragEvent
            )
        }
    }

    private func dragPanelManually(
        _ panel: NSPanel,
        initialMouseDownEvent: NSEvent,
        firstDragEvent: NSEvent
    ) {
        let initialMouseScreenPoint = panel.convertPoint(toScreen: initialMouseDownEvent.locationInWindow)
        let initialFrameOrigin = panel.frame.origin

        func movePanelToCurrentMouse() {
            let currentMousePoint = NSEvent.mouseLocation
            let nextOrigin = NSPoint(
                x: initialFrameOrigin.x + currentMousePoint.x - initialMouseScreenPoint.x,
                y: initialFrameOrigin.y + currentMousePoint.y - initialMouseScreenPoint.y
            )
            panel.setFrameOrigin(nextOrigin)
        }

        movePanelToCurrentMouse()
        while true {
            guard let event = NSApp.nextEvent(
                matching: [.leftMouseDragged, .leftMouseUp],
                until: .distantFuture,
                inMode: .eventTracking,
                dequeue: true
            ) else {
                continue
            }

            if event.type == .leftMouseUp {
                break
            }

            if event.type == .leftMouseDragged {
                movePanelToCurrentMouse()
            }
        }
    }

    private func finishDetachedPreviewDrag(panel: NSPanel, configuration: PreviewContentConfiguration) {
        let panelID = ObjectIdentifier(panel)
        guard let retainedPanel = self.detachedPanels[panelID],
              retainedPanel === panel,
              panel.isVisible else {
            return
        }
    }

    private func closeDetachedPreview(_ detachedPanel: NSPanel) {
        let panelID = ObjectIdentifier(detachedPanel)
        detachedPanels.removeValue(forKey: panelID)
        removeDetachedEscapeKeyMonitorIfNeeded()
        (detachedPanel as? HistoryPreviewPanel)?.onKeyStateChange?(false)
        (detachedPanel as? HistoryPreviewPanel)?.onEscape = nil
        detachedPanel.contentView = NSView()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.10
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.7, 0.0, 0.84, 0.0)
            detachedPanel.animator().alphaValue = 0
        } completionHandler: { [weak detachedPanel] in
            MainActor.assumeIsolated {
                detachedPanel?.orderOut(nil)
                detachedPanel?.alphaValue = 1
            }
        }
    }

    private func detachedFrame(for size: CGSize, keepingTopEdgeFrom frame: CGRect) -> CGRect {
        let proposedFrame = CGRect(
            x: frame.minX,
            y: frame.maxY - size.height,
            width: size.width,
            height: size.height
        )
        let visibleFrame = bestScreen(for: proposedFrame)?.visibleFrame ?? NSScreen.main?.visibleFrame ?? proposedFrame
        return clampedWindowFrame(proposedFrame, to: visibleFrame)
    }

    private func clampedWindowFrame(_ frame: CGRect, to visibleFrame: CGRect) -> CGRect {
        let width = min(frame.width, visibleFrame.width)
        let height = min(frame.height, visibleFrame.height)
        let x = min(max(frame.minX, visibleFrame.minX), visibleFrame.maxX - width)
        let y = min(max(frame.minY, visibleFrame.minY), visibleFrame.maxY - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    private func bestScreen(for frame: CGRect) -> NSScreen? {
        NSScreen.screens.max { lhs, rhs in
            lhs.visibleFrame.intersection(frame).area < rhs.visibleFrame.intersection(frame).area
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

    private func removeEscapeKeyMonitor() {
        if let escapeKeyMonitor {
            NSEvent.removeMonitor(escapeKeyMonitor)
            self.escapeKeyMonitor = nil
        }
    }

    private func installDetachedEscapeKeyMonitorIfNeeded() {
        guard detachedEscapeKeyMonitor == nil else {
            return
        }

        detachedEscapeKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self,
                  event.keyCode == KeyCode.escape,
                  let detachedPanel = self.detachedPanel(for: event) else {
                return event
            }

            self.closeDetachedPreview(detachedPanel)
            return nil
        }
    }

    private func removeDetachedEscapeKeyMonitorIfNeeded() {
        guard detachedPanels.isEmpty,
              let detachedEscapeKeyMonitor else {
            return
        }

        NSEvent.removeMonitor(detachedEscapeKeyMonitor)
        self.detachedEscapeKeyMonitor = nil
    }

    private func detachedPanel(for event: NSEvent) -> NSPanel? {
        if let eventPanel = event.window as? NSPanel,
           detachedPanels[ObjectIdentifier(eventPanel)] != nil {
            return eventPanel
        }

        if let keyPanel = NSApp.keyWindow as? NSPanel,
           detachedPanels[ObjectIdentifier(keyPanel)] != nil {
            return keyPanel
        }

        return nil
    }

    private func previewSize(for item: ClipboardItem, screenFrame: CGRect) -> CGSize {
        let contentLimit = contentSizeLimit(for: screenFrame)
        let chromeHeight: CGFloat = 86
        let maxWindowSize = CGSize(
            width: min(contentLimit.width, screenFrame.width - horizontalMargin * 2),
            height: min(contentLimit.height + chromeHeight, screenFrame.height - 130)
        )

        switch item.type {
        case .image:
            return imagePreviewSize(for: item, maxWindowSize: maxWindowSize, chromeHeight: chromeHeight)
        case .link:
            return CGSize(
                width: max(390, maxWindowSize.width),
                height: max(260, maxWindowSize.height)
            )
        case .text:
            let measuredTextSize = estimatedTextSize(for: item.text, wrappingWidth: maxWindowSize.width - 32)
            return CGSize(
                width: min(maxWindowSize.width, max(390, measuredTextSize.width + 32)),
                height: min(maxWindowSize.height, max(260, measuredTextSize.height + chromeHeight))
            )
        case .color:
            return CGSize(
                width: min(620, maxWindowSize.width),
                height: min(330, maxWindowSize.height)
            )
        case .file:
            return CGSize(
                width: max(720, maxWindowSize.width),
                height: max(520, maxWindowSize.height)
            )
        }
    }

    private func stablePreviewSize(for screenFrame: CGRect) -> CGSize {
        let maxWidth = max(390, screenFrame.width - horizontalMargin * 2)
        let maxHeight = max(260, screenFrame.height - 130)
        return CGSize(
            width: min(defaultPreviewSize.width, maxWidth),
            height: min(defaultPreviewSize.height, maxHeight)
        )
    }

    private func contentSizeLimit(for screenFrame: CGRect) -> CGSize {
        let visibleWidthLimit = max(390, screenFrame.width - horizontalMargin * 2)
        let visibleHeightLimit = max(260, screenFrame.height - 130)
        return CGSize(
            width: min(1_920, visibleWidthLimit),
            height: min(1_080, visibleHeightLimit)
        )
    }

    private func imagePreviewSize(
        for item: ClipboardItem,
        maxWindowSize: CGSize,
        chromeHeight: CGFloat
    ) -> CGSize {
        guard let imageWidth = item.imageWidth,
              let imageHeight = item.imageHeight,
              imageWidth > 0,
              imageHeight > 0 else {
            return stablePreviewSize(forScreenLimitedWindowSize: maxWindowSize)
        }

        let maxContentWidth = max(1, maxWindowSize.width)
        let maxContentHeight = max(1, maxWindowSize.height - chromeHeight)
        let ratio = CGFloat(imageWidth) / CGFloat(imageHeight)
        let scale = min(maxContentWidth / CGFloat(imageWidth), maxContentHeight / CGFloat(imageHeight), 1)
        var contentWidth = CGFloat(imageWidth) * scale
        var contentHeight = CGFloat(imageHeight) * scale

        if contentWidth > maxContentWidth {
            contentWidth = maxContentWidth
            contentHeight = contentWidth / ratio
        }
        if contentHeight > maxContentHeight {
            contentHeight = maxContentHeight
            contentWidth = contentHeight * ratio
        }

        let minimumContentWidth = min(imagePreviewMinimumContentSize.width, maxContentWidth)
        let minimumContentHeight = min(imagePreviewMinimumContentSize.height, maxContentHeight)
        let usableContentWidth = min(maxContentWidth, max(minimumContentWidth, ceil(contentWidth)))
        let usableContentHeight = min(maxContentHeight, max(minimumContentHeight, ceil(contentHeight)))

        return CGSize(
            width: usableContentWidth,
            height: min(maxWindowSize.height, usableContentHeight + chromeHeight)
        )
    }

    private func stablePreviewSize(forScreenLimitedWindowSize maxWindowSize: CGSize) -> CGSize {
        CGSize(
            width: min(defaultPreviewSize.width, maxWindowSize.width),
            height: min(defaultPreviewSize.height, maxWindowSize.height)
        )
    }

    private func estimatedTextSize(for text: String, wrappingWidth: CGFloat) -> CGSize {
        let averageCharacterWidth: CGFloat = 8
        let lineHeight: CGFloat = 22
        let charactersPerLine = max(1, Int(wrappingWidth / averageCharacterWidth))
        let sourceLines = text.isEmpty ? [" "] : text.components(separatedBy: .newlines)
        var visualLineCount = 0
        var widestCharacterCount = 0

        for line in sourceLines {
            let count = max(1, line.count)
            visualLineCount += max(1, Int(ceil(Double(count) / Double(charactersPerLine))))
            widestCharacterCount = max(widestCharacterCount, min(count, charactersPerLine))
        }

        return CGSize(
            width: ceil(min(max(CGFloat(widestCharacterCount) * averageCharacterWidth, 390 - 32), wrappingWidth)),
            height: ceil(CGFloat(max(1, visualLineCount)) * lineHeight + 32)
        )
    }

}

enum HistoryPreviewDetachedFramePolicy {
    static func frame(for size: CGSize, keepingTopEdgeFrom frame: CGRect) -> CGRect {
        CGRect(
            x: frame.minX,
            y: frame.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }
}

private struct PreviewContentConfiguration {
    let item: ClipboardItem
    let ocrResult: ClipboardOCRMatch?
    let arrowX: CGFloat
    let size: CGSize
    let onCopy: () -> Void
    let onOpen: () -> Void
    let onReveal: () -> Void
    let onCopyURL: () -> Void
    let onCopyMarkdown: () -> Void
    let onCopyPath: () -> Void
    let onCopyRGB: () -> Void
    let onClose: () -> Void
    let onDetach: () -> Void

    func withArrowX(_ arrowX: CGFloat) -> PreviewContentConfiguration {
        PreviewContentConfiguration(
            item: item,
            ocrResult: ocrResult,
            arrowX: arrowX,
            size: size,
            onCopy: onCopy,
            onOpen: onOpen,
            onReveal: onReveal,
            onCopyURL: onCopyURL,
            onCopyMarkdown: onCopyMarkdown,
            onCopyPath: onCopyPath,
            onCopyRGB: onCopyRGB,
            onClose: onClose,
            onDetach: onDetach
        )
    }
}

struct HistoryPreviewPlacementPolicy {
    struct Placement: Equatable {
        let frame: CGRect
        let arrowX: CGFloat
    }

    static func placement(
        anchorScreenPoint: CGPoint,
        screenFrame: CGRect,
        size: CGSize,
        arrowHeight: CGFloat = 14,
        arrowGap: CGFloat = 18,
        horizontalMargin: CGFloat = 12
    ) -> Placement {
        let originY = min(
            max(anchorScreenPoint.y + arrowGap, screenFrame.minY + 8),
            screenFrame.maxY - size.height - arrowHeight - 8
        )
        let originX = min(
            max(anchorScreenPoint.x - size.width / 2, screenFrame.minX + horizontalMargin),
            screenFrame.maxX - horizontalMargin - size.width
        )
        let arrowX = min(max(anchorScreenPoint.x - originX, 28), size.width - 28)
        return Placement(
            frame: CGRect(
                x: originX,
                y: originY,
                width: size.width,
                height: size.height + arrowHeight
            ),
            arrowX: arrowX
        )
    }
}

final class HistoryPreviewPanel: NSPanel {
    var onKeyStateChange: ((Bool) -> Void)?
    var onEscape: (() -> Void)?
    var isDetachedPreview = false

    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        isDetachedPreview
    }

    override func becomeKey() {
        super.becomeKey()
        onKeyStateChange?(true)
    }

    override func resignKey() {
        super.resignKey()
        onKeyStateChange?(false)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command),
              let characters = event.charactersIgnoringModifiers?.lowercased(),
              characters.count == 1 else {
            return super.performKeyEquivalent(with: event)
        }

        switch characters {
        case "w" where isDetachedPreview:
            onEscape?()
            return true
        case "a":
            return sendStandardEditAction(#selector(NSResponder.selectAll(_:)))
        case "c":
            return sendStandardEditAction(#selector(NSText.copy(_:)))
        case "x":
            return sendStandardEditAction(#selector(NSText.cut(_:)))
        case "v":
            return sendStandardEditAction(#selector(NSText.paste(_:)))
        case "z":
            return event.modifierFlags.contains(.shift)
                ? sendStandardEditAction(Selector(("redo:")))
                : sendStandardEditAction(Selector(("undo:")))
        default:
            return super.performKeyEquivalent(with: event)
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == KeyCode.escape {
            onEscape?()
            return
        }

        super.keyDown(with: event)
    }

    private func sendStandardEditAction(_ selector: Selector) -> Bool {
        guard let target = firstResponder ?? contentView else {
            return false
        }

        return NSApp.sendAction(selector, to: target, from: self)
    }
}

private extension CGRect {
    var area: CGFloat {
        guard !isNull, !isEmpty else {
            return 0
        }

        return width * height
    }
}
