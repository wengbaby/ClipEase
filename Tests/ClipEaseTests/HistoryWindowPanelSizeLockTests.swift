import AppKit
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
