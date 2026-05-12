import AppKit
import SwiftUI

@MainActor
final class HistoryPreviewWindowController {
    private var panel: NSPanel?
    private var outsideClickMonitor: Any?
    private var localOutsideClickMonitor: Any?
    private var contentLoadTask: Task<Void, Never>?
    private let arrowHeight: CGFloat = 14
    private let horizontalMargin: CGFloat = 12

    var frame: CGRect? {
        panel?.frame
    }

    func show(
        item: ClipboardItem,
        anchorScreenPoint: CGPoint,
        screenFrame: CGRect,
        onCopy: @escaping () -> Void,
        onOpen: @escaping () -> Void,
        onReveal: @escaping () -> Void,
        onCopyURL: @escaping () -> Void,
        onCopyMarkdown: @escaping () -> Void,
        onCopyPath: @escaping () -> Void,
        onCopyRGB: @escaping () -> Void
    ) {
        let size = previewSize(for: item, screenFrame: screenFrame)
        let originY = min(
            max(anchorScreenPoint.y, screenFrame.minY + 8),
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
        self.panel = panel
        contentLoadTask?.cancel()
        setPreviewContent(
            panel: panel,
            item: item,
            arrowX: arrowX,
            size: size,
            isContentReady: false,
            onCopy: onCopy,
            onOpen: onOpen,
            onReveal: onReveal,
            onCopyURL: onCopyURL,
            onCopyMarkdown: onCopyMarkdown,
            onCopyPath: onCopyPath,
            onCopyRGB: onCopyRGB
        )

        if isAlreadyVisible {
            panel.setFrame(frame, display: true)
            scheduleContentLoad(
                panel: panel,
                item: item,
                arrowX: arrowX,
                size: size,
                delay: 30_000_000,
                onCopy: onCopy,
                onOpen: onOpen,
                onReveal: onReveal,
                onCopyURL: onCopyURL,
                onCopyMarkdown: onCopyMarkdown,
                onCopyPath: onCopyPath,
                onCopyRGB: onCopyRGB
            )
        } else {
            let startFrame = frame.offsetBy(dx: 0, dy: -12)
            panel.alphaValue = 0
            panel.setFrame(startFrame, display: false)
            panel.orderFrontRegardless()

            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.22
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)
                panel.animator().alphaValue = 1
                panel.animator().setFrame(frame, display: true)
            } completionHandler: { [weak self, weak panel] in
                guard let self, let panel else {
                    return
                }

                self.scheduleContentLoad(
                    panel: panel,
                    item: item,
                    arrowX: arrowX,
                    size: size,
                    delay: 20_000_000,
                    onCopy: onCopy,
                    onOpen: onOpen,
                    onReveal: onReveal,
                    onCopyURL: onCopyURL,
                    onCopyMarkdown: onCopyMarkdown,
                    onCopyPath: onCopyPath,
                    onCopyRGB: onCopyRGB
                )
            }
        }
    }

    func close() {
        removeOutsideClickMonitor()
        contentLoadTask?.cancel()
        contentLoadTask = nil
        guard let panel, panel.isVisible else {
            panel?.orderOut(nil)
            return
        }

        panel.contentView = NSView()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.7, 0.0, 0.84, 0.0)
            panel.animator().alphaValue = 0
        } completionHandler: { [weak panel] in
            panel?.orderOut(nil)
            panel?.alphaValue = 1
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
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                guard self?.contains(screenPoint: NSEvent.mouseLocation) == false else {
                    return
                }
                onOutsideClick()
            }
        }
        localOutsideClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard self?.contains(screenPoint: NSEvent.mouseLocation) == false else {
                return event
            }
            onOutsideClick()
            return event
        }
    }

    private func makePanel() -> NSPanel {
        let panel = HistoryPreviewPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        return panel
    }

    private func setPreviewContent(
        panel: NSPanel,
        item: ClipboardItem,
        arrowX: CGFloat,
        size: CGSize,
        isContentReady: Bool,
        onCopy: @escaping () -> Void,
        onOpen: @escaping () -> Void,
        onReveal: @escaping () -> Void,
        onCopyURL: @escaping () -> Void,
        onCopyMarkdown: @escaping () -> Void,
        onCopyPath: @escaping () -> Void,
        onCopyRGB: @escaping () -> Void
    ) {
        panel.contentView = NSHostingView(
            rootView: HistoryPreviewPopoverView(
                item: item,
                arrowX: arrowX,
                size: size,
                isContentReady: isContentReady,
                onClose: { [weak self] in
                    self?.close()
                },
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
        arrowX: CGFloat,
        size: CGSize,
        delay: UInt64,
        onCopy: @escaping () -> Void,
        onOpen: @escaping () -> Void,
        onReveal: @escaping () -> Void,
        onCopyURL: @escaping () -> Void,
        onCopyMarkdown: @escaping () -> Void,
        onCopyPath: @escaping () -> Void,
        onCopyRGB: @escaping () -> Void
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
                arrowX: arrowX,
                size: size,
                isContentReady: true,
                onCopy: onCopy,
                onOpen: onOpen,
                onReveal: onReveal,
                onCopyURL: onCopyURL,
                onCopyMarkdown: onCopyMarkdown,
                onCopyPath: onCopyPath,
                onCopyRGB: onCopyRGB
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

    private func previewSize(for item: ClipboardItem, screenFrame: CGRect) -> CGSize {
        let contentLimit = contentSizeLimit(for: screenFrame)
        let chromeHeight: CGFloat = 86
        let maxWindowSize = CGSize(
            width: min(contentLimit.width, screenFrame.width - horizontalMargin * 2),
            height: min(contentLimit.height + chromeHeight, screenFrame.height - 130)
        )

        switch item.type {
        case .image, .link:
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
        }
    }

    private func contentSizeLimit(for screenFrame: CGRect) -> CGSize {
        let width = screenFrame.width * 0.5
        return CGSize(width: width, height: width * 9 / 16)
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
    override var canBecomeKey: Bool {
        false
    }
}
