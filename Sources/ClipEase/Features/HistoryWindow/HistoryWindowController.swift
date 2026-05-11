import AppKit
import SwiftUI

@MainActor
final class HistoryWindowController: NSObject, NSWindowDelegate {
    private let panelHeight: CGFloat = 360
    private let panelAnimationDistance: CGFloat = 360
    private let panelBackgroundColor = NSColor(red: 0.78, green: 0.82, blue: 0.92, alpha: 1.0)
    private let store: ClipboardHistoryStore
    private let pasteExecutor: PasteExecutor
    private let recordingController: RecordingController
    private let appMenuController: AppMenuController
    private let previewWindowController = HistoryPreviewWindowController()
    private let previewState = HistoryPreviewState()
    private let renderState = HistoryWindowRenderState()
    private var panel: HistoryPanel?
    private var isClosing = false

    init(
        store: ClipboardHistoryStore,
        pasteExecutor: PasteExecutor,
        recordingController: RecordingController,
        appMenuController: AppMenuController
    ) {
        self.store = store
        self.pasteExecutor = pasteExecutor
        self.recordingController = recordingController
        self.appMenuController = appMenuController
        super.init()
    }

    func toggle() {
        if let panel, panel.isVisible {
            close()
            return
        }

        show()
    }

    func show() {
        let panel = panel ?? makePanel()
        self.panel = panel
        isClosing = false
        let targetFrame = frameForPanel()
        let shouldAnimate = !panel.isVisible

        if shouldAnimate {
            renderState.prepareForShow()
            panel.hasShadow = false
            panel.alphaValue = 1
            panel.setFrame(hiddenFrame(for: targetFrame), display: false)
        } else {
            panel.setFrame(targetFrame, display: true)
        }

        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        panel.displayIfNeeded()

        guard shouldAnimate else {
            return
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 16_000_000)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)
                panel.animator().setFrame(targetFrame, display: false)
            } completionHandler: { [weak panel] in
                Task { @MainActor in
                    panel?.displayIfNeeded()
                    panel?.hasShadow = true
                    self.renderState.revealAllItems()
                }
            }
        }
    }

    func close() {
        closePreview()
        guard let panel,
              panel.isVisible,
              !isClosing else {
            panel?.orderOut(nil)
            return
        }

        isClosing = true
        panel.hasShadow = false
        let targetFrame = hiddenFrame(for: panel.frame)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.7, 0.0, 0.84, 0.0)
            panel.animator().setFrame(targetFrame, display: false)
        } completionHandler: { [weak self, weak panel] in
            Task { @MainActor in
                panel?.orderOut(nil)
                panel?.hasShadow = true
                self?.isClosing = false
            }
        }
    }

    private func makePanel() -> HistoryPanel {
        let contentView = HistoryWindowView(
            store: store,
            previewState: previewState,
            renderState: renderState,
            recordingController: recordingController,
            appMenuController: appMenuController,
            pasteExecutor: pasteExecutor,
            onClose: { [weak self] in
                self?.close()
            },
            onPreview: { [weak self] item, cardFrame in
                self?.showPreview(item, cardFrame: cardFrame)
            },
            onClosePreview: { [weak self] in
                self?.closePreview()
            }
        )

        let panel = HistoryPanel(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        panel.delegate = self
        panel.onEscape = { [weak self] in
            self?.close()
        }
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovable = false
        panel.animationBehavior = .none
        panel.backgroundColor = panelBackgroundColor
        panel.isOpaque = true
        panel.hasShadow = true

        let hostingView = NSHostingView(rootView: contentView)
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = panelBackgroundColor.cgColor
        panel.contentView = hostingView
        return panel
    }

    private func frameForPanel() -> NSRect {
        let screen = NSScreen.clipeaseScreenContainingMouse ?? NSScreen.main
        let frame = screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
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

    private func showPreview(_ item: ClipboardItem, cardFrame: CGRect) {
        guard let panel else {
            return
        }

        let anchorScreenPoint = CGPoint(
            x: panel.frame.minX + cardFrame.midX,
            y: panel.frame.maxY - cardFrame.minY
        )
        let screenFrame = panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? panel.frame
        previewWindowController.show(
            item: item,
            anchorScreenPoint: anchorScreenPoint,
            screenFrame: screenFrame,
            onCopy: { [pasteExecutor] in
                pasteExecutor.copyToPasteboard(item)
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
                self?.copyPlainPreviewText(self?.imagePath(for: item))
            },
            onCopyRGB: { [weak self] in
                self?.copyPlainPreviewText(self?.rgbString(from: item.text))
            }
        )
        previewWindowController.installOutsideClickMonitor { [weak self] in
            self?.closePreview()
        }
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
        case .text, .color:
            break
        }
    }

    private func revealPreviewItem(_ item: ClipboardItem) {
        guard let url = imageURL(for: item) else {
            return
        }

        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func copyPlainPreviewText(_ text: String?) {
        guard let text,
              !text.isEmpty else {
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        store.skipNextClipboardText(text)
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
        previewState.close()
        previewWindowController.close()
    }

    func windowDidResignKey(_ notification: Notification) {
        closePreview()
    }
}
