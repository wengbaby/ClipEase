import Foundation
import CoreGraphics

enum HistoryWindowLifecycleScheduler {
    static let animatedOpenStartupDelayNanoseconds: UInt64 = 180_000_000

    static func startupDelayNanoseconds(
        requestedDelayNanoseconds: UInt64,
        isWindowVisible: Bool,
        isWindowPresented: Bool,
        isOpenAnimationActive: Bool
    ) -> UInt64? {
        guard isWindowVisible else {
            return nil
        }

        guard isWindowPresented || isOpenAnimationActive else {
            return nil
        }

        guard isOpenAnimationActive else {
            return requestedDelayNanoseconds
        }

        return max(requestedDelayNanoseconds, animatedOpenStartupDelayNanoseconds)
    }

    static func shouldScheduleVisibleRebuild(
        isWindowVisible: Bool,
        isWindowPresented: Bool,
        isOpenAnimationActive: Bool
    ) -> Bool {
        isWindowVisible && (isWindowPresented || isOpenAnimationActive)
    }

    static func shouldApplyPresentationStateBeforeAnimation(shouldAnimate: Bool) -> Bool {
        !shouldAnimate
    }

    static func shouldRunLaunchPreload(
        hasPanel: Bool,
        isWindowVisible: Bool,
        isOpenAnimationActive: Bool
    ) -> Bool {
        !hasPanel && !isWindowVisible && !isOpenAnimationActive
    }

    static func shouldMakeKeyBeforeAnimation(shouldAnimate: Bool) -> Bool {
        !shouldAnimate
    }

    static func shouldApplyHiddenFrame(
        currentFrame: CGRect,
        targetFrame: CGRect,
        tolerance: CGFloat = 0.5
    ) -> Bool {
        let hasMatchingHorizontalFrame = abs(currentFrame.minX - targetFrame.minX) <= tolerance &&
            abs(currentFrame.width - targetFrame.width) <= tolerance
        let isTopAlignedOffscreenFrame = hasMatchingHorizontalFrame &&
            abs(currentFrame.maxY - targetFrame.maxY) <= tolerance &&
            currentFrame.height >= targetFrame.height
        if isTopAlignedOffscreenFrame {
            return false
        }

        return abs(currentFrame.minX - targetFrame.minX) > tolerance ||
            abs(currentFrame.minY - targetFrame.minY) > tolerance ||
            abs(currentFrame.width - targetFrame.width) > tolerance ||
            abs(currentFrame.height - targetFrame.height) > tolerance
    }

    static func previewGenerationAfterHideCleanup(currentGeneration: UInt64) -> UInt64 {
        currentGeneration &+ 1
    }
}
