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

    let didApply = HistoryWindowPanelSizeLock.apply(to: panel, frameSize: frameSize)

    #expect(didApply)
    #expect(panel.contentMinSize == expectedContentSize)
    #expect(panel.contentMaxSize == expectedContentSize)
}

@MainActor
@Test func historyWindowPanelSizeLockSkipsUnchangedContentSize() {
    let panel = NSPanel(
        contentRect: NSRect(x: 0, y: 0, width: 1440, height: 360),
        styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
        backing: .buffered,
        defer: false
    )
    let frameSize = NSSize(width: 1440, height: 360)

    #expect(HistoryWindowPanelSizeLock.apply(to: panel, frameSize: frameSize))
    #expect(!HistoryWindowPanelSizeLock.apply(to: panel, frameSize: frameSize))
}
