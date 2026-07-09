import AppKit
import SwiftUI
import Testing
@testable import ClipEase

@MainActor
@Test func historyWindowHostingViewUsesCurrentBoundsAsFittingSize() {
    let view = HistoryWindowHostingView(rootView: Color.clear)
    view.setFrameSize(NSSize(width: 1440, height: 360))

    #expect(view.intrinsicContentSize.width == NSView.noIntrinsicMetric)
    #expect(view.intrinsicContentSize.height == NSView.noIntrinsicMetric)
    #expect(view.fittingSize == NSSize(width: 1440, height: 360))
}

@MainActor
@Test func historyWindowHostingViewRejectsSwiftUIFrameGrowthWhenSizeIsLocked() {
    let view = HistoryWindowHostingView(rootView: Color.clear)
    view.lockContentSize(NSSize(width: 1440, height: 360))

    view.setFrameSize(NSSize(width: 1440, height: 404))

    #expect(view.frame.size == NSSize(width: 1440, height: 360))
    #expect(view.fittingSize == NSSize(width: 1440, height: 360))
}

@MainActor
@Test func historyWindowHostingViewSkipsUnchangedContentSizeLock() {
    let view = HistoryWindowHostingView(rootView: Color.clear)
    let size = NSSize(width: 1440, height: 360)

    #expect(view.lockContentSize(size))
    #expect(!view.lockContentSize(size))
    #expect(view.frame.size == size)
    #expect(view.fittingSize == size)
}
