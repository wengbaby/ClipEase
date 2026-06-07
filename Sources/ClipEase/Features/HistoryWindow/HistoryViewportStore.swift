import Foundation

@MainActor
final class HistoryViewportStore: ObservableObject {
    @Published var visibleRect: CGRect
    @Published var mode: HistoryRailViewportMode

    init(
        visibleRect: CGRect = .zero,
        mode: HistoryRailViewportMode = .automatic
    ) {
        self.visibleRect = visibleRect
        self.mode = mode
    }

    @discardableResult
    func updateVisibleRectIfNeeded(_ nextVisibleRect: CGRect, itemStride: CGFloat) -> Bool {
        guard abs(visibleRect.minX - nextVisibleRect.minX) > itemStride ||
            abs(visibleRect.width - nextVisibleRect.width) > 0.5 ||
            visibleRect == .zero else {
            return false
        }

        visibleRect = nextVisibleRect
        if mode == .visibleArea {
            mode = .automatic
        }
        return true
    }

    func resetForLatestFocus(offsetX: CGFloat, width: CGFloat, height: CGFloat) {
        visibleRect = CGRect(
            x: offsetX,
            y: visibleRect.minY,
            width: max(width, 1),
            height: height
        )
    }
}
