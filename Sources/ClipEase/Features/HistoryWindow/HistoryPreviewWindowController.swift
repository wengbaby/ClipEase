import AppKit
import SwiftUI

@MainActor
final class HistoryPreviewWindowController {
    private var panel: NSPanel?
    private var outsideClickMonitor: Any?
    private var localOutsideClickMonitor: Any?
    private var escapeKeyMonitor: Any?
    private var contentLoadTask: Task<Void, Never>?
    private var isInteractingInsidePreview = false
    private weak var parentWindow: NSWindow?
    var onKeyStateChange: ((Bool) -> Void)?
    private let arrowHeight: CGFloat = 14
    private let arrowGap: CGFloat = 18
    private let horizontalMargin: CGFloat = 12
    private let defaultPreviewSize = CGSize(width: 620, height: 370)
    // Keeps tiny or 1px-edge images operable without returning to the old 220pt fixed image window.
    private let imagePreviewMinimumContentSize = CGSize(width: 180, height: 140)
    private let deferredContentLoadDelay: UInt64 = 50_000_000

    var frame: CGRect? {
        panel?.frame
    }

    var isVisible: Bool {
        panel?.isVisible == true
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
        onClose: @escaping () -> Void
    ) -> Bool {
        let size = previewSize(for: item, screenFrame: screenFrame)
        let originY = min(
            max(anchorScreenPoint.y + arrowGap, screenFrame.minY + 8),
            screenFrame.maxY - size.height - arrowHeight - 8
        )
        let originX = min(
            max(anchorScreenPoint.x - size.width / 2, screenFrame.minX + horizontalMargin),
            screenFrame.maxX - horizontalMargin - size.width
        )
        let arrowX = min(max(anchorScreenPoint.x - originX, 28), size.width - 28)
        let frame = CGRect(
            x: originX,
            y: originY,
            width: size.width,
            height: size.height + arrowHeight
        )

        let panel = panel ?? makePanel()
        let isAlreadyVisible = panel.isVisible
        let ocrResult = ClipboardOCRMatch(
            text: item.ocrText,
            emails: item.ocrEmails,
            phoneNumbers: item.ocrPhoneNumbers,
            urls: item.ocrURLs,
            textRegions: item.ocrTextRegions
        )
        self.panel = panel
        self.parentWindow = parentWindow
        (panel as? HistoryPreviewPanel)?.onEscape = onClose
        detachPanelFromParent(panel)
        contentLoadTask?.cancel()
        let shouldLoadImmediately = item.type == .text || item.type == .color || item.type == .image
        setPreviewContent(
            panel: panel,
            item: item,
            ocrResult: ocrResult,
            arrowX: arrowX,
            size: size,
            isContentReady: shouldLoadImmediately,
            onCopy: onCopy,
            onOpen: onOpen,
            onReveal: onReveal,
            onCopyURL: onCopyURL,
            onCopyMarkdown: onCopyMarkdown,
            onCopyPath: onCopyPath,
            onCopyRGB: onCopyRGB,
            onClose: onClose
        )

        if isAlreadyVisible {
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
                    delay: deferredContentLoadDelay,
                    onCopy: onCopy,
                    onOpen: onOpen,
                    onReveal: onReveal,
                    onCopyURL: onCopyURL,
                    onCopyMarkdown: onCopyMarkdown,
                    onCopyPath: onCopyPath,
                    onCopyRGB: onCopyRGB,
                    onClose: onClose
                )
            }
        } else {
            panel.alphaValue = 0
            panel.setFrame(frame, display: true)
            panel.orderFrontRegardless()
            animatePanelOpen(panel, targetFrame: frame)
            (panel as? HistoryPreviewPanel)?.onKeyStateChange?(false)
            if !shouldLoadImmediately {
                scheduleContentLoad(
                    panel: panel,
                    item: item,
                    ocrResult: ocrResult,
                    arrowX: arrowX,
                    size: size,
                    delay: deferredContentLoadDelay,
                    onCopy: onCopy,
                    onOpen: onOpen,
                    onReveal: onReveal,
                    onCopyURL: onCopyURL,
                    onCopyMarkdown: onCopyMarkdown,
                    onCopyPath: onCopyPath,
                    onCopyRGB: onCopyRGB,
                    onClose: onClose
                )
            }
        }

        return panel.isVisible
    }

    private func animatePanelOpen(_ panel: NSPanel, targetFrame: CGRect) {
        let startFrame = targetFrame.offsetBy(dx: 0, dy: -6)
        panel.setFrame(startFrame, display: true)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)
            panel.animator().alphaValue = 1
            panel.animator().setFrame(targetFrame, display: true)
        }
    }

    func close() {
        let parentWindow = parentWindow
        removeOutsideClickMonitor()
        removeEscapeKeyMonitor()
        contentLoadTask?.cancel()
        contentLoadTask = nil
        parentWindow?.makeKey()
        (panel as? HistoryPreviewPanel)?.onKeyStateChange?(false)
        guard let panel, panel.isVisible else {
            panel?.orderOut(nil)
            return
        }

        panel.contentView = NSView()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.10
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.7, 0.0, 0.84, 0.0)
            panel.animator().alphaValue = 0
        } completionHandler: { [weak panel] in
            panel?.orderOut(nil)
            panel?.alphaValue = 1
        }
    }

    func move(anchorScreenPoint: CGPoint, screenFrame: CGRect) {
        guard let panel, panel.isVisible else {
            return
        }

        let size = CGSize(width: panel.frame.width, height: max(1, panel.frame.height - arrowHeight))
        let originY = min(
            max(anchorScreenPoint.y + arrowGap, screenFrame.minY + 8),
            screenFrame.maxY - size.height - arrowHeight - 8
        )
        let originX = min(
            max(anchorScreenPoint.x - size.width / 2, screenFrame.minX + horizontalMargin),
            screenFrame.maxX - horizontalMargin - size.width
        )
        let frame = CGRect(
            x: originX,
            y: originY,
            width: panel.frame.width,
            height: panel.frame.height
        )

        guard abs(panel.frame.minX - frame.minX) > 0.5 ||
              abs(panel.frame.minY - frame.minY) > 0.5 else {
            return
        }

        panel.setFrame(frame, display: true, animate: false)
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
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.onKeyStateChange = { [weak self] isKey in
            self?.onKeyStateChange?(isKey)
        }
        return panel
    }

    private func detachPanelFromParent(_ panel: NSPanel) {
        panel.parent?.removeChildWindow(panel)
    }

    private func setPreviewContent(
        panel: NSPanel,
        item: ClipboardItem,
        ocrResult: ClipboardOCRMatch?,
        arrowX: CGFloat,
        size: CGSize,
        isContentReady: Bool,
        onCopy: @escaping () -> Void,
        onOpen: @escaping () -> Void,
        onReveal: @escaping () -> Void,
        onCopyURL: @escaping () -> Void,
        onCopyMarkdown: @escaping () -> Void,
        onCopyPath: @escaping () -> Void,
        onCopyRGB: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        panel.contentView = NSHostingView(
            rootView: HistoryPreviewPopoverView(
                item: item,
                ocrResult: ocrResult,
                arrowX: arrowX,
                size: size,
                isContentReady: isContentReady,
                onClose: onClose,
                onCopy: onCopy,
                onOpen: onOpen,
                onReveal: onReveal,
                onCopyURL: onCopyURL,
                onCopyMarkdown: onCopyMarkdown,
                onCopyPath: onCopyPath,
                onCopyRGB: onCopyRGB
            )
        )
    }

    private func scheduleContentLoad(
        panel: NSPanel,
        item: ClipboardItem,
        ocrResult: ClipboardOCRMatch?,
        arrowX: CGFloat,
        size: CGSize,
        delay: UInt64,
        onCopy: @escaping () -> Void,
        onOpen: @escaping () -> Void,
        onReveal: @escaping () -> Void,
        onCopyURL: @escaping () -> Void,
        onCopyMarkdown: @escaping () -> Void,
        onCopyPath: @escaping () -> Void,
        onCopyRGB: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        contentLoadTask?.cancel()
        contentLoadTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled, panel.isVisible else {
                return
            }

            setPreviewContent(
                panel: panel,
                item: item,
                ocrResult: ocrResult,
                arrowX: arrowX,
                size: size,
                isContentReady: true,
                onCopy: onCopy,
                onOpen: onOpen,
                onReveal: onReveal,
                onCopyURL: onCopyURL,
                onCopyMarkdown: onCopyMarkdown,
                onCopyPath: onCopyPath,
                onCopyRGB: onCopyRGB,
                onClose: onClose
            )
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

private final class HistoryPreviewPanel: NSPanel {
    var onKeyStateChange: ((Bool) -> Void)?
    var onEscape: (() -> Void)?

    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
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
