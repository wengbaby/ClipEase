import AppKit
import SwiftUI

final class HistoryWindowHostingView<Content: View>: NSHostingView<Content> {
    private var lockedContentSize: NSSize?

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    override var fittingSize: NSSize {
        if let lockedContentSize {
            return lockedContentSize
        }

        return bounds.size
    }

    func lockContentSize(_ size: NSSize) {
        lockedContentSize = size
        super.setFrameSize(size)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(lockedContentSize ?? newSize)
    }
}
