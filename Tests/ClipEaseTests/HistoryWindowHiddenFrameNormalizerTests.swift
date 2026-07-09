import AppKit
import Testing
@testable import ClipEase

@Test func hiddenFrameNormalizerShrinksHeightOnlyDrift() {
    let frame = NSRect(x: 0, y: -360, width: 3840, height: 404)

    let normalized = HistoryWindowHiddenFrameNormalizer.normalizedFrame(
        currentFrame: frame,
        targetHeight: 360
    )

    #expect(normalized == NSRect(x: 0, y: -360, width: 3840, height: 360))
}

@Test func hiddenFrameNormalizerLeavesMatchingFrameUnchanged() {
    let frame = NSRect(x: 0, y: -360, width: 3840, height: 360)

    let normalized = HistoryWindowHiddenFrameNormalizer.normalizedFrame(
        currentFrame: frame,
        targetHeight: 360
    )

    #expect(normalized == frame)
}
