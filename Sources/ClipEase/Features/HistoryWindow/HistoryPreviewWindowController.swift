import AppKit
import SwiftUI

@MainActor
final class HistoryPreviewWindowController {
    private var panel: NSPanel?
    private var outsideClickMonitor: Any?

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
        let arrowHeight: CGFloat = 14
        let horizontalMargin: CGFloat = 12
        let originX = min(
            max(anchorScreenPoint.x - size.width / 2, screenFrame.minX + horizontalMargin),
            screenFrame.maxX - horizontalMargin - size.width
        )
        let arrowX = min(max(anchorScreenPoint.x - originX, 28), size.width - 28)
        let frame = CGRect(
            x: originX,
            y: anchorScreenPoint.y,
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
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { _ in
            Task { @MainActor in
                onOutsideClick()
            }
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
    }

    private func previewSize(for item: ClipboardItem, screenFrame: CGRect) -> CGSize {
        switch item.type {
        case .image:
            guard let width = item.imageWidth,
                  let height = item.imageHeight,
                  width > 0,
                  height > 0 else {
                return CGSize(width: 560, height: 310)
            }

            let maxWidth = min(screenFrame.width - 24, 1000)
            let maxHeight = min(screenFrame.height - 130, 760)
            let chromeHeight: CGFloat = 86
            let ratio = CGFloat(width) / CGFloat(height)
            let imageWidth = min(maxWidth - 8, (maxHeight - chromeHeight) * ratio)
            let imageHeight = imageWidth / ratio
            return CGSize(
                width: max(390, imageWidth + 8),
                height: max(260, min(maxHeight, imageHeight + chromeHeight))
            )
        case .text, .link, .color:
            return CGSize(width: min(620, screenFrame.width - 24), height: 330)
        }
    }
}

private final class HistoryPreviewPanel: NSPanel {
    override var canBecomeKey: Bool {
        false
    }
}
