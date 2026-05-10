import AppKit
import SwiftUI

@MainActor
final class HistoryWindowController: NSObject, NSWindowDelegate {
    private let panelHeight: CGFloat = 360
    private let store: ClipboardHistoryStore
    private let pasteExecutor: PasteExecutor
    private let recordingController: RecordingController
    private let appMenuController: AppMenuController
    private let previewWindowController = HistoryPreviewWindowController()
    private let previewState = HistoryPreviewState()
    private var panel: HistoryPanel?

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
        let targetFrame = frameForPanel()
        let shouldAnimate = !panel.isVisible

        if shouldAnimate {
            panel.alphaValue = 0
            panel.setFrame(targetFrame.offsetBy(dx: 0, dy: -56), display: false)
        } else {
            panel.setFrame(targetFrame, display: true)
        }

        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        guard shouldAnimate else {
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            panel.animator().setFrame(targetFrame, display: true)
        }
    }

    func close() {
        panel?.orderOut(nil)
        closePreview()
    }

    private func makePanel() -> HistoryPanel {
        let contentView = HistoryWindowView(
            store: store,
            previewState: previewState,
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
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.contentView = NSHostingView(rootView: contentView)
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
            }
        )
        previewWindowController.installOutsideClickMonitor { [weak self] in
            self?.closePreview()
        }
    }

    private func closePreview() {
        previewState.close()
        previewWindowController.close()
    }

    func windowDidResignKey(_ notification: Notification) {
        closePreview()
    }
}
