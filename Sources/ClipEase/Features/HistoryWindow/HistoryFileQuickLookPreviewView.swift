import AppKit
import Quartz
import SwiftUI

struct HistoryFileQuickLookPreviewView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> NSView {
        guard let view = QLPreviewView(frame: .zero, style: .normal) else {
            return HistoryQuickLookFallbackView(url: url)
        }

        view.autostarts = true
        view.previewItem = HistoryQuickLookPreviewItem(url: url)
        return HistoryInteractiveQuickLookContainerView(previewView: view)
    }

    func updateNSView(_ view: NSView, context: Context) {
        guard let previewView = Self.quickLookPreviewView(from: view) else {
            return
        }

        let currentURL = (previewView.previewItem as? HistoryQuickLookPreviewItem)?.previewItemURL
        guard currentURL != url else {
            return
        }

        previewView.previewItem = HistoryQuickLookPreviewItem(url: url)
    }

    static func dismantleNSView(_ view: NSView, coordinator: ()) {
        guard let previewView = Self.quickLookPreviewView(from: view) else {
            return
        }

        previewView.autostarts = false
        previewView.previewItem = nil
    }

    private static func quickLookPreviewView(from view: NSView) -> QLPreviewView? {
        if let previewView = view as? QLPreviewView {
            return previewView
        }

        return (view as? HistoryInteractiveQuickLookContainerView)?.previewView
    }
}

private final class HistoryInteractiveQuickLookContainerView: NSView {
    let previewView: QLPreviewView

    init(previewView: QLPreviewView) {
        self.previewView = previewView
        super.init(frame: .zero)

        wantsLayer = true
        previewView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(previewView)

        NSLayoutConstraint.activate([
            previewView.leadingAnchor.constraint(equalTo: leadingAnchor),
            previewView.trailingAnchor.constraint(equalTo: trailingAnchor),
            previewView.topAnchor.constraint(equalTo: topAnchor),
            previewView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(previewView)
        super.mouseDown(with: event)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }
}

private final class HistoryQuickLookPreviewItem: NSObject, QLPreviewItem {
    let previewItemURL: URL?

    init(url: URL) {
        self.previewItemURL = url
    }
}

private final class HistoryQuickLookFallbackView: NSView {
    init(url: URL) {
        super.init(frame: .zero)

        let imageView = NSImageView(image: ClipEaseAppIcon.roundedImage(NSWorkspace.shared.icon(forFile: url.path), size: NSSize(width: 72, height: 72)))
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.imageScaling = .scaleProportionallyUpOrDown

        let label = NSTextField(labelWithString: url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.alignment = .center
        label.lineBreakMode = .byTruncatingMiddle
        label.maximumNumberOfLines = 2
        label.textColor = .secondaryLabelColor
        label.isSelectable = true

        let pathLabel = NSTextField(labelWithString: url.path)
        pathLabel.translatesAutoresizingMaskIntoConstraints = false
        pathLabel.alignment = .center
        pathLabel.lineBreakMode = .byTruncatingMiddle
        pathLabel.maximumNumberOfLines = 2
        pathLabel.textColor = .tertiaryLabelColor
        pathLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        pathLabel.isSelectable = true

        addSubview(imageView)
        addSubview(label)
        addSubview(pathLabel)

        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -18),
            imageView.widthAnchor.constraint(equalToConstant: 72),
            imageView.heightAnchor.constraint(equalToConstant: 72),
            label.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 12),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            pathLabel.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 6),
            pathLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            pathLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }
}
