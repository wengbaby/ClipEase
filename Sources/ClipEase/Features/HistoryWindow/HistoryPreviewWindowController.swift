import AppKit
import SwiftUI

@MainActor
final class HistoryPreviewWindowController {
    private var panel: NSPanel?
    private var outsideClickMonitor: Any?
    private var localOutsideClickMonitor: Any?
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
        let hostingView = NSHostingView(
            rootView: HistoryPreviewPopoverView(
                item: item,
                arrowX: arrowX,
                size: size,
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
        panel.contentView = hostingView

        if isAlreadyVisible {
            panel.setFrame(frame, display: true)
        } else {
            let startFrame = frame.offsetBy(dx: 0, dy: -12)
            panel.alphaValue = 0
            panel.setFrame(startFrame, display: false)
            panel.orderFrontRegardless()

            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.13
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
                panel.animator().setFrame(frame, display: true)
            }
        }
    }

    func close() {
        removeOutsideClickMonitor()
        panel?.orderOut(nil)
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
            let measuredTextSize = measuredSize(for: item.text, wrappingWidth: maxWindowSize.width - 32)
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

    private func measuredSize(for text: String, wrappingWidth: CGFloat) -> CGSize {
        let font = NSFont.systemFont(ofSize: 15, weight: .regular)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byWordWrapping
        let attributedText = NSAttributedString(
            string: text.isEmpty ? " " : text,
            attributes: [
                .font: font,
                .paragraphStyle: paragraphStyle
            ]
        )
        let boundingRect = attributedText.boundingRect(
            with: CGSize(width: wrappingWidth, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        let singleLineWidth = (text.isEmpty ? " " : text).size(withAttributes: [.font: font]).width

        return CGSize(
            width: ceil(min(max(singleLineWidth, 390 - 32), wrappingWidth)),
            height: ceil(boundingRect.height + 32)
        )
    }
}

private final class HistoryPreviewPanel: NSPanel {
    override var canBecomeKey: Bool {
        false
    }
}
