import AppKit
import SwiftUI
import Testing
@testable import ClipEase

@MainActor
@Test func historyWindowPanelSizeLockPinsContentSizeForTargetFrameSize() {
    let panel = NSPanel(
        contentRect: NSRect(x: 0, y: 0, width: 1440, height: 360),
        styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
        backing: .buffered,
        defer: false
    )
    let frameSize = NSSize(width: 1440, height: 360)
    let expectedContentSize = panel.contentRect(
        forFrameRect: NSRect(origin: .zero, size: frameSize)
    ).size

    HistoryWindowPanelSizeLock.apply(to: panel, frameSize: frameSize)

    #expect(panel.contentMinSize == expectedContentSize)
    #expect(panel.contentMaxSize == expectedContentSize)
}

@MainActor
@Test func historyWindowPanelSizeLockDoesNotGrowPanelFrameHeight() {
    let panel = NSPanel(
        contentRect: .zero,
        styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
        backing: .buffered,
        defer: false
    )
    let frame = NSRect(x: 0, y: 0, width: 1440, height: 360)
    panel.contentView = HistoryWindowHostingView(rootView: Color.clear)

    HistoryWindowPanelSizeLock.apply(to: panel, frameSize: frame.size)
    (panel.contentView as? HistoryWindowHostingView<Color>)?.lockContentSize(frame.size)
    panel.setFrame(frame, display: false)
    panel.orderFrontRegardless()
    panel.layoutIfNeeded()
    panel.orderOut(nil)

    #expect(panel.frame.size == frame.size)
}
