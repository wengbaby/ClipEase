import Foundation

enum HistoryRailViewportMode: Sendable {
    case automatic
    case firstPage
    case visibleArea
}

struct HistoryRailViewportContext {
    let itemCount: Int
    let visibleRect: CGRect
    let hasReliableVisibleRect: Bool
    let itemStride: CGFloat
    let horizontalContentPadding: CGFloat
    let bufferItemCount: Int
    let renderedItemLimit: Int
    let edgeBufferItemCount: Int
    var mode: HistoryRailViewportMode = .automatic

    func visibleWindow(focusedIndex: Int?) -> Range<Int> {
        if mode == .firstPage {
            return 0..<min(itemCount, renderedItemLimit)
        }

        if mode == .visibleArea {
            return HistoryRailRenderWindowPolicy.visibleWindow(
                itemCount: itemCount,
                visibleRect: visibleRect,
                hasReliableVisibleRect: hasReliableVisibleRect,
                itemStride: itemStride,
                horizontalContentPadding: horizontalContentPadding,
                bufferItemCount: bufferItemCount,
                renderedItemLimit: renderedItemLimit
            )
        }

        let visibleWindow = HistoryRailRenderWindowPolicy.visibleWindow(
            itemCount: itemCount,
            visibleRect: visibleRect,
            hasReliableVisibleRect: hasReliableVisibleRect,
            itemStride: itemStride,
            horizontalContentPadding: horizontalContentPadding,
            bufferItemCount: bufferItemCount,
            renderedItemLimit: renderedItemLimit
        )

        if let focusedIndex,
           !visibleWindow.contains(focusedIndex) {
            return HistoryRailRenderWindowPolicy.focusedWindow(
                focusedIndex: focusedIndex,
                itemCount: itemCount,
                renderedItemLimit: renderedItemLimit,
                edgeBufferItemCount: edgeBufferItemCount
            )
        }

        return visibleWindow
    }
}

enum HistoryRailRenderWindowPolicy {
    static func focusedID(
        pendingLatestFocusItemID: ClipboardItem.ID?,
        pendingProgrammaticJumpItemID: ClipboardItem.ID?,
        pendingItemScrollID: ClipboardItem.ID?,
        selectedItemID: ClipboardItem.ID?,
        visibleRect: CGRect
    ) -> ClipboardItem.ID? {
        if let pendingLatestFocusItemID {
            return pendingLatestFocusItemID
        }
        if let pendingProgrammaticJumpItemID {
            return pendingProgrammaticJumpItemID
        }
        if let pendingItemScrollID {
            return pendingItemScrollID
        }
        return nil
    }

    static func visibleWindow(
        itemCount: Int,
        visibleRect: CGRect,
        hasReliableVisibleRect: Bool = true,
        itemStride: CGFloat,
        horizontalContentPadding: CGFloat,
        bufferItemCount: Int,
        renderedItemLimit: Int
    ) -> Range<Int> {
        guard itemCount > 0 else {
            return 0..<0
        }

        guard hasReliableVisibleRect else {
            return 0..<min(itemCount, renderedItemLimit)
        }

        guard visibleRect.width > 0, itemStride > 0 else {
            return 0..<min(itemCount, renderedItemLimit)
        }

        let visibleMinX = max(visibleRect.minX - horizontalContentPadding, 0)
        guard visibleRect.width >= itemStride else {
            let centerIndex = min(max(Int(floor(visibleMinX / itemStride)), 0), itemCount - 1)
            let start = min(
                max(0, centerIndex - renderedItemLimit / 2),
                max(0, itemCount - renderedItemLimit)
            )
            let end = min(itemCount, start + renderedItemLimit)
            return start..<end
        }

        let visibleMaxX = max(visibleRect.maxX - horizontalContentPadding, visibleMinX)
        let rawStart = Int(floor(visibleMinX / itemStride)) - bufferItemCount
        let rawEnd = Int(ceil(visibleMaxX / itemStride)) + bufferItemCount + 1
        let clampedStart = min(max(0, rawStart), max(itemCount - 1, 0))
        let clampedEnd = min(itemCount, max(clampedStart + 1, rawEnd))
        guard clampedEnd - clampedStart > renderedItemLimit else {
            return clampedStart..<clampedEnd
        }

        let visibleCenter = (visibleMinX + visibleMaxX) / 2
        let centerIndex = min(max(Int(floor(visibleCenter / itemStride)), 0), itemCount - 1)
        let limitedStart = min(
            max(0, centerIndex - renderedItemLimit / 2),
            max(0, itemCount - renderedItemLimit)
        )
        let limitedEnd = min(itemCount, limitedStart + renderedItemLimit)
        return limitedStart..<limitedEnd
    }

    static func focusedWindow(
        focusedIndex: Int,
        itemCount: Int,
        renderedItemLimit: Int,
        edgeBufferItemCount: Int
    ) -> Range<Int> {
        guard itemCount > 0 else {
            return 0..<0
        }

        let clampedIndex = min(max(focusedIndex, 0), itemCount - 1)
        let start = min(
            max(0, clampedIndex - renderedItemLimit / 2 - edgeBufferItemCount),
            max(0, itemCount - renderedItemLimit)
        )
        let end = min(itemCount, start + renderedItemLimit)
        return start..<max(start + 1, end)
    }
}

enum HistoryPreviewFramePolicy {
    static func viewportFrame(
        measuredFrame: CGRect?,
        documentFrame: CGRect?,
        currentOffset: CGFloat,
        cardRailTopInWindow: CGFloat,
        selectedCardTopContentInset: CGFloat
    ) -> CGRect? {
        if let measuredFrame,
           isValidAnchorFrame(measuredFrame) {
            return measuredFrame
        }

        guard let documentFrame,
              isValidAnchorFrame(documentFrame) else {
            return nil
        }

        return fallbackViewportFrame(
            documentFrame: documentFrame,
            currentOffset: currentOffset,
            cardRailTopInWindow: cardRailTopInWindow,
            selectedCardTopContentInset: selectedCardTopContentInset
        )
    }

    static func fallbackViewportFrame(
        documentFrame: CGRect,
        currentOffset: CGFloat,
        cardRailTopInWindow: CGFloat,
        selectedCardTopContentInset: CGFloat
    ) -> CGRect {
        documentFrame.offsetBy(
            dx: -currentOffset,
            dy: cardRailTopInWindow + selectedCardTopContentInset
        )
    }

    private static func isValidAnchorFrame(_ frame: CGRect) -> Bool {
        frame.width > 0 && frame.height > 0 && !frame.isNull && !frame.isInfinite
    }
}

enum HistoryPreviewCacheRetentionPolicy {
    static func retainedWindow(
        itemCount: Int,
        visibleRect: CGRect,
        hasReliableVisibleRect: Bool,
        itemStride: CGFloat,
        horizontalContentPadding: CGFloat,
        retainedItemCount: Int,
        renderedItemLimit: Int
    ) -> Range<Int> {
        guard itemCount > 0 else {
            return 0..<0
        }

        guard visibleRect != .zero else {
            return 0..<min(itemCount, retainedItemCount)
        }

        return HistoryRailViewportContext(
            itemCount: itemCount,
            visibleRect: visibleRect,
            hasReliableVisibleRect: hasReliableVisibleRect,
            itemStride: itemStride,
            horizontalContentPadding: horizontalContentPadding,
            bufferItemCount: retainedItemCount / 2,
            renderedItemLimit: renderedItemLimit,
            edgeBufferItemCount: 3
        ).visibleWindow(focusedIndex: nil)
    }
}
