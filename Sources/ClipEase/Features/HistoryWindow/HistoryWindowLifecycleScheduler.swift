import Foundation
import CoreGraphics

enum HistoryWindowLifecycleScheduler {
    static let launchPreloadDelayNanoseconds: UInt64 = 0
    static let launchAccessibilityPromptDelayNanoseconds: UInt64 = 700_000_000
    static let presentedStartupDelayNanoseconds: UInt64 = 48_000_000
    static let animatedOpenStartupDelayNanoseconds: UInt64 = 180_000_000
    static let animatedOpenPresentationRecoveryDelayNanoseconds: UInt64 = 0

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

    static func previewApplyDelayNanoseconds(isOpenAnimationActive: Bool) -> UInt64 {
        isOpenAnimationActive ? animatedOpenStartupDelayNanoseconds : 0
    }

    static func shouldApplyPresentationStateBeforeAnimation(shouldAnimate: Bool) -> Bool {
        !shouldAnimate
    }

    static func presentationRecoveryDelayNanoseconds(shouldAnimate: Bool) -> UInt64 {
        shouldAnimate ? animatedOpenPresentationRecoveryDelayNanoseconds : 0
    }

    static func shouldRunLaunchPreload(
        hasPanel: Bool,
        isWindowVisible: Bool,
        isOpenAnimationActive: Bool
    ) -> Bool {
        !hasPanel && !isWindowVisible && !isOpenAnimationActive
    }

    static func shouldPublishVisibleStateForLaunchPreload() -> Bool {
        false
    }

    static func shouldMakeKeyBeforeAnimation(shouldAnimate: Bool) -> Bool {
        !shouldAnimate
    }

    static func shouldRasterizeContentDuringWindowAnimation(shouldAnimate: Bool) -> Bool {
        false
    }

    static func shouldUpdateContentRasterization(
        currentIsRasterized: Bool,
        targetIsRasterized: Bool,
        currentScale: CGFloat,
        targetScale: CGFloat,
        scaleTolerance: CGFloat = 0.01
    ) -> Bool {
        currentIsRasterized != targetIsRasterized || abs(currentScale - targetScale) > scaleTolerance
    }

    static func shouldPrepareContentLayerBeforeOrdering(shouldAnimate: Bool) -> Bool {
        false
    }

    static func shouldUseContentLayerAnimation(shouldAnimate: Bool) -> Bool {
        shouldAnimate
    }

    static func shouldKeepHiddenPanelAtTargetFrame(
        usesContentLayerAnimation: Bool
    ) -> Bool {
        usesContentLayerAnimation
    }

    static func shouldOrderHiddenPanelDuringLaunchPreload(
        usesContentLayerAnimation: Bool
    ) -> Bool {
        false
    }

    static func shouldRepairHiddenPanelTargetFrameAfterClose(
        usesContentLayerAnimation: Bool
    ) -> Bool {
        usesContentLayerAnimation
    }

    static func shouldKeepPanelOrderedAfterClose(
        usesContentLayerAnimation: Bool
    ) -> Bool {
        false
    }

    static func shouldCloseOnToggle(
        isPanelOrdered: Bool,
        isWindowVisible: Bool
    ) -> Bool {
        isPanelOrdered || isWindowVisible
    }

    static func shouldOrderPanelBeforeOpen(
        isPanelOrdered: Bool,
        isWindowVisible: Bool
    ) -> Bool {
        !isPanelOrdered
    }

    static func shouldApplyTargetFrame(
        currentFrame: CGRect,
        targetFrame: CGRect,
        tolerance: CGFloat = 0.5
    ) -> Bool {
        abs(currentFrame.minX - targetFrame.minX) > tolerance ||
            abs(currentFrame.minY - targetFrame.minY) > tolerance ||
            abs(currentFrame.width - targetFrame.width) > tolerance ||
            abs(currentFrame.height - targetFrame.height) > tolerance
    }

    static func shouldApplyContentLayerTransformPreparation(
        initialTranslationY: CGFloat,
        tolerance: CGFloat = 0.5
    ) -> Bool {
        abs(initialTranslationY) > tolerance
    }

    static func shouldSynchronouslyFlushContentLayerBeforeOrdering(
        usesContentLayerAnimation: Bool
    ) -> Bool {
        false
    }

    static func shouldRefreshAccessibilityBeforeToggle(isWindowVisible: Bool) -> Bool {
        !isWindowVisible
    }

    static func shouldRefreshAccessibilityBeforeShow(alreadyVerified: Bool) -> Bool {
        !alreadyVerified
    }

    static func shouldStartKeyboardEventTapBeforeOrdering(shouldAnimate: Bool) -> Bool {
        false
    }

    static func shouldStartKeyboardEventTapWhenFinishingShow(shouldAnimate: Bool) -> Bool {
        !shouldAnimate
    }

    static func shouldStartKeyboardEventTapDuringPresentationRecovery(shouldAnimate: Bool) -> Bool {
        shouldAnimate
    }

    static func shouldApplyHiddenFrame(
        currentFrame: CGRect,
        targetFrame: CGRect,
        tolerance: CGFloat = 0.5
    ) -> Bool {
        let hasMatchingHorizontalFrame = abs(currentFrame.minX - targetFrame.minX) <= tolerance &&
            abs(currentFrame.width - targetFrame.width) <= tolerance
        let hasMatchingHeight = abs(currentFrame.height - targetFrame.height) <= tolerance
        let isTopAlignedOffscreenFrame = hasMatchingHorizontalFrame &&
            hasMatchingHeight &&
            abs(currentFrame.maxY - targetFrame.maxY) <= tolerance
        if isTopAlignedOffscreenFrame {
            return false
        }

        let isOriginAlignedOffscreenFrame = hasMatchingHorizontalFrame &&
            hasMatchingHeight &&
            abs(currentFrame.minY - targetFrame.minY) <= tolerance
        if isOriginAlignedOffscreenFrame {
            return false
        }

        return abs(currentFrame.minX - targetFrame.minX) > tolerance ||
            abs(currentFrame.minY - targetFrame.minY) > tolerance ||
            abs(currentFrame.width - targetFrame.width) > tolerance ||
            abs(currentFrame.height - targetFrame.height) > tolerance
    }

    static func shouldCancelPreviewBuildForHide(hasPendingPreviewBuild: Bool) -> Bool {
        false
    }

    static func shouldWarmPreviewAfterHide(
        hasSourceItems: Bool,
        canSkipPreviewRebuild: Bool
    ) -> Bool {
        hasSourceItems && !canSkipPreviewRebuild
    }

    static func shouldWarmPreviewForPreloadedHiddenWindow(
        isWindowVisible: Bool,
        isWindowPresented: Bool,
        isOpenAnimationActive: Bool,
        hasSourceItems: Bool,
        canSkipPreviewRebuild: Bool
    ) -> Bool {
        !isWindowVisible &&
            !isWindowPresented &&
            !isOpenAnimationActive &&
            hasSourceItems &&
            !canSkipPreviewRebuild
    }

    static func previewGenerationAfterHideCleanup(
        currentGeneration: UInt64,
        hasPendingPreviewBuild: Bool = false
    ) -> UInt64 {
        guard shouldCancelPreviewBuildForHide(hasPendingPreviewBuild: hasPendingPreviewBuild) else {
            return currentGeneration
        }

        return currentGeneration &+ 1
    }
}
