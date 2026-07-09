import AppKit
import SwiftUI
import Testing
@testable import ClipEase

@MainActor
@Test func historyWindowPanelSizeLockClearsPanelContentConstraintsForTargetFrameSize() {
    let panel = NSPanel(
        contentRect: NSRect(x: 0, y: 0, width: 1440, height: 360),
        styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
        backing: .buffered,
        defer: false
    )
    panel.contentMinSize = NSSize(width: 1440, height: 360)
    panel.contentMaxSize = NSSize(width: 1440, height: 360)
    let frameSize = NSSize(width: 1440, height: 360)

    let didApply = HistoryWindowPanelSizeLock.apply(to: panel, frameSize: frameSize)

    #expect(didApply)
    #expect(panel.contentMinSize == HistoryWindowPanelSizeLock.unlockedContentMinSize)
    #expect(panel.contentMaxSize == HistoryWindowPanelSizeLock.unlockedContentMaxSize)
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
    panel.contentMinSize = NSSize(width: 1440, height: 360)
    panel.contentMaxSize = NSSize(width: 1440, height: 360)

    #expect(HistoryWindowPanelSizeLock.apply(to: panel, frameSize: frameSize))
    #expect(!HistoryWindowPanelSizeLock.apply(to: panel, frameSize: frameSize))
}

@MainActor
@Test func historyWindowPanelSizeLockDoesNotForcePanelFrameTallerThanTarget() async throws {
    let panel = NSPanel(
        contentRect: NSRect(x: 0, y: 0, width: 1440, height: 360),
        styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
        backing: .buffered,
        defer: false
    )
    let targetFrame = NSRect(x: 0, y: 0, width: 1440, height: 360)
    let hostingView = HistoryWindowHostingView(rootView: Color.clear)
    panel.contentView = hostingView

    _ = HistoryWindowPanelSizeLock.apply(to: panel, frameSize: targetFrame.size)
    hostingView.lockContentSize(targetFrame.size)
    panel.setFrame(targetFrame, display: false)
    panel.layoutIfNeeded()
    panel.orderFrontRegardless()
    defer { panel.orderOut(nil) }
    try await Task.sleep(nanoseconds: 40_000_000)
    panel.orderOut(nil)
    try await Task.sleep(nanoseconds: 40_000_000)
    panel.layoutIfNeeded()

    #expect(panel.frame.size == targetFrame.size)
}
