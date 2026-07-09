import Foundation

enum HistoryWindowHiddenFrameNormalizer {
    static func normalizedFrame(currentFrame: CGRect, targetHeight: CGFloat) -> CGRect {
        guard currentFrame.height > targetHeight else {
            return currentFrame
        }

        return CGRect(
            x: currentFrame.minX,
            y: currentFrame.minY,
            width: currentFrame.width,
            height: targetHeight
        )
    }
}
