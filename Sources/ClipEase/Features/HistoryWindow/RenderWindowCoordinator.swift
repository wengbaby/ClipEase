import Foundation

enum RenderWindowCoordinator {
    static func contentWidth(
        itemCount: Int,
        cardWidth: CGFloat,
        cardSpacing: CGFloat,
        horizontalPadding: CGFloat
    ) -> CGFloat {
        guard itemCount > 0 else {
            return horizontalPadding * 2
        }

        return horizontalPadding * 2 +
            CGFloat(itemCount) * cardWidth +
            CGFloat(max(itemCount - 1, 0)) * cardSpacing
    }

    static func viewportContext(
        itemCount: Int,
        visibleRect: CGRect,
        hasReliableVisibleRect: Bool,
        itemStride: CGFloat,
        horizontalContentPadding: CGFloat,
        bufferItemCount: Int,
        renderedItemLimit: Int,
        edgeBufferItemCount: Int,
        mode: HistoryRailViewportMode
    ) -> HistoryRailViewportContext {
        HistoryRailViewportContext(
            itemCount: itemCount,
            visibleRect: visibleRect,
            hasReliableVisibleRect: hasReliableVisibleRect,
            itemStride: itemStride,
            horizontalContentPadding: horizontalContentPadding,
            bufferItemCount: bufferItemCount,
            renderedItemLimit: renderedItemLimit,
            edgeBufferItemCount: edgeBufferItemCount,
            mode: mode
        )
    }

    static func renderedWindowItems(
        items: [HistoryPreviewItem],
        visibleWindow: Range<Int>
    ) -> ArraySlice<HistoryPreviewItem> {
        guard !visibleWindow.isEmpty else {
            return items[0..<0]
        }

        return items[visibleWindow]
    }

    static func documentFrame(
        itemIndex: Int,
        horizontalPadding: CGFloat,
        itemStride: CGFloat,
        cardWidth: CGFloat
    ) -> CGRect {
        CGRect(
            x: horizontalPadding + CGFloat(itemIndex) * itemStride,
            y: 0,
            width: cardWidth,
            height: 270
        )
    }
}
