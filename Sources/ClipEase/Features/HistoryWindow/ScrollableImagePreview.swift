import AppKit
import SwiftUI

struct ScrollableImagePreview: NSViewRepresentable {
    let image: NSImage?

    func makeNSView(context: Context) -> NSScrollView {
        let imageView = NSImageView()
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = imageView
        context.coordinator.imageView = imageView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let imageView = context.coordinator.imageView else {
            return
        }

        imageView.image = image
        let imageSize = image?.size ?? scrollView.contentSize
        imageView.frame = NSRect(
            origin: .zero,
            size: NSSize(
                width: max(imageSize.width, scrollView.contentSize.width),
                height: max(imageSize.height, scrollView.contentSize.height)
            )
        )
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        weak var imageView: NSImageView?
    }
}
