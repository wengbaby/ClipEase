import AppKit
import SwiftUI

@MainActor
final class HistoryPreviewWindowController {
    private var panel: NSPanel?

    func show(
        item: ClipboardItem,
        anchorScreenPoint: CGPoint,
        screenFrame: CGRect,
        onCopy: @escaping () -> Void
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
        self.panel = panel
        panel.contentView = NSHostingView(
            rootView: HistoryPreviewPopoverView(
                item: item,
                arrowX: arrowX,
                size: size,
                onClose: { [weak self] in
                    self?.close()
                },
                onCopy: onCopy
            )
        )
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
    }

    func close() {
        panel?.orderOut(nil)
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
