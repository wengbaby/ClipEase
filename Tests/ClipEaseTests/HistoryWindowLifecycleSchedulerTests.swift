import CoreGraphics
import Testing
@testable import ClipEase

@Test func lifecycleSchedulerSchedulesLaunchPreloadOnNextMainActorTurn() {
    #expect(HistoryWindowLifecycleScheduler.launchPreloadDelayNanoseconds == 0)
}

@Test func lifecycleSchedulerKeepsAccessibilityPromptDelayedAfterLaunch() {
    #expect(HistoryWindowLifecycleScheduler.launchAccessibilityPromptDelayNanoseconds == 700_000_000)
}

@Test func lifecycleSchedulerDefersPresentedStartupWorkOffPresentationCallback() {
    #expect(HistoryWindowLifecycleScheduler.presentedStartupDelayNanoseconds == 48_000_000)
}

@Test func lifecycleSchedulerRunsPresentedStartupAfterPresentationRecoveryBuffer() {
    #expect(
        HistoryWindowLifecycleScheduler.presentedStartupDelayNanoseconds >=
            HistoryWindowLifecycleScheduler.animatedOpenPresentationRecoveryDelayNanoseconds + 32_000_000
    )
}

@Test func lifecycleSchedulerDefersStartupPastAnimatedOpenBudget() {
    let delay = HistoryWindowLifecycleScheduler.startupDelayNanoseconds(
        requestedDelayNanoseconds: 0,
        isWindowVisible: true,
        isWindowPresented: true,
        isOpenAnimationActive: true
    )

    #expect(delay == 180_000_000)
}

@Test func lifecycleSchedulerKeepsRequestedDelayWhenAlreadyPresentedWithoutAnimation() {
    let delay = HistoryWindowLifecycleScheduler.startupDelayNanoseconds(
        requestedDelayNanoseconds: 32_000_000,
        isWindowVisible: true,
        isWindowPresented: true,
        isOpenAnimationActive: false
    )

    #expect(delay == 32_000_000)
}

@Test func lifecycleSchedulerDefersWhenAnimationStartedBeforePresentedSnapshotUpdates() {
    let delay = HistoryWindowLifecycleScheduler.startupDelayNanoseconds(
        requestedDelayNanoseconds: 0,
        isWindowVisible: true,
        isWindowPresented: false,
        isOpenAnimationActive: true
    )

    #expect(delay == 180_000_000)
}

@Test func lifecycleSchedulerSkipsStartupWhenWindowIsHiddenOrOnlyPreloaded() {
    #expect(HistoryWindowLifecycleScheduler.startupDelayNanoseconds(
        requestedDelayNanoseconds: 0,
        isWindowVisible: false,
        isWindowPresented: false,
        isOpenAnimationActive: false
    ) == nil)
    #expect(HistoryWindowLifecycleScheduler.startupDelayNanoseconds(
        requestedDelayNanoseconds: 0,
        isWindowVisible: true,
        isWindowPresented: false,
        isOpenAnimationActive: false
    ) == nil)
}

@Test func lifecycleSchedulerAllowsVisibleRebuildOnlyWhenPresentedOrAnimating() {
    #expect(HistoryWindowLifecycleScheduler.shouldScheduleVisibleRebuild(
        isWindowVisible: true,
        isWindowPresented: true,
        isOpenAnimationActive: false
    ))
    #expect(HistoryWindowLifecycleScheduler.shouldScheduleVisibleRebuild(
        isWindowVisible: true,
        isWindowPresented: false,
        isOpenAnimationActive: true
    ))
    #expect(!HistoryWindowLifecycleScheduler.shouldScheduleVisibleRebuild(
        isWindowVisible: true,
        isWindowPresented: false,
        isOpenAnimationActive: false
    ))
    #expect(!HistoryWindowLifecycleScheduler.shouldScheduleVisibleRebuild(
        isWindowVisible: false,
        isWindowPresented: false,
        isOpenAnimationActive: false
    ))
}

@Test func lifecycleSchedulerDefersPreviewApplyDuringAnimatedOpen() {
    #expect(HistoryWindowLifecycleScheduler.previewApplyDelayNanoseconds(
        isOpenAnimationActive: true
    ) == HistoryWindowLifecycleScheduler.animatedOpenStartupDelayNanoseconds)
}

@Test func lifecycleSchedulerAppliesPreviewImmediatelyOutsideAnimatedOpen() {
    #expect(HistoryWindowLifecycleScheduler.previewApplyDelayNanoseconds(
        isOpenAnimationActive: false
    ) == 0)
}

@Test func lifecycleSchedulerDefersPresentationStateUntilAnimatedOpenCompletes() {
    #expect(!HistoryWindowLifecycleScheduler.shouldApplyPresentationStateBeforeAnimation(
        shouldAnimate: true
    ))
    #expect(HistoryWindowLifecycleScheduler.shouldApplyPresentationStateBeforeAnimation(
        shouldAnimate: false
    ))
}

@Test func lifecycleSchedulerDefersPresentationRecoveryAfterAnimatedOpenCompletion() {
    #expect(HistoryWindowLifecycleScheduler.presentationRecoveryDelayNanoseconds(
        shouldAnimate: true
    ) == 16_000_000)
    #expect(HistoryWindowLifecycleScheduler.presentationRecoveryDelayNanoseconds(
        shouldAnimate: false
    ) == 0)
}

@Test func lifecycleSchedulerSkipsLaunchPreloadWhenPanelAlreadyExistsOrOpening() {
    #expect(HistoryWindowLifecycleScheduler.shouldRunLaunchPreload(
        hasPanel: false,
        isWindowVisible: false,
        isOpenAnimationActive: false
    ))
    #expect(!HistoryWindowLifecycleScheduler.shouldRunLaunchPreload(
        hasPanel: true,
        isWindowVisible: false,
        isOpenAnimationActive: false
    ))
    #expect(!HistoryWindowLifecycleScheduler.shouldRunLaunchPreload(
        hasPanel: false,
        isWindowVisible: true,
        isOpenAnimationActive: false
    ))
    #expect(!HistoryWindowLifecycleScheduler.shouldRunLaunchPreload(
        hasPanel: false,
        isWindowVisible: false,
        isOpenAnimationActive: true
    ))
}

@Test func lifecycleSchedulerKeepsLaunchPreloadShellOnly() {
    #expect(!HistoryWindowLifecycleScheduler.shouldPublishVisibleStateForLaunchPreload())
}

@Test func lifecycleSchedulerDefersMakeKeyUntilAnimatedOpenCompletes() {
    #expect(!HistoryWindowLifecycleScheduler.shouldMakeKeyBeforeAnimation(
        shouldAnimate: true
    ))
    #expect(HistoryWindowLifecycleScheduler.shouldMakeKeyBeforeAnimation(
        shouldAnimate: false
    ))
}

@Test func lifecycleSchedulerAvoidsRasterizingContentDuringWindowAnimation() {
    #expect(!HistoryWindowLifecycleScheduler.shouldRasterizeContentDuringWindowAnimation(
        shouldAnimate: true
    ))
    #expect(!HistoryWindowLifecycleScheduler.shouldRasterizeContentDuringWindowAnimation(
        shouldAnimate: false
    ))
}

@Test func lifecycleSchedulerSkipsUnchangedContentRasterizationUpdates() {
    #expect(!HistoryWindowLifecycleScheduler.shouldUpdateContentRasterization(
        currentIsRasterized: false,
        targetIsRasterized: false,
        currentScale: 2,
        targetScale: 2
    ))
    #expect(HistoryWindowLifecycleScheduler.shouldUpdateContentRasterization(
        currentIsRasterized: false,
        targetIsRasterized: true,
        currentScale: 2,
        targetScale: 2
    ))
    #expect(HistoryWindowLifecycleScheduler.shouldUpdateContentRasterization(
        currentIsRasterized: true,
        targetIsRasterized: true,
        currentScale: 1,
        targetScale: 2
    ))
}

@Test func lifecycleSchedulerSkipsForcedContentLayerPreparationBeforeFrameAnimation() {
    #expect(!HistoryWindowLifecycleScheduler.shouldPrepareContentLayerBeforeOrdering(
        shouldAnimate: true
    ))
    #expect(!HistoryWindowLifecycleScheduler.shouldPrepareContentLayerBeforeOrdering(
        shouldAnimate: false
    ))
}

@Test func lifecycleSchedulerKeepsWindowFrameAnimationForLayoutStability() {
    #expect(!HistoryWindowLifecycleScheduler.shouldUseContentLayerAnimation(
        shouldAnimate: true
    ))
    #expect(!HistoryWindowLifecycleScheduler.shouldUseContentLayerAnimation(
        shouldAnimate: false
    ))
}

@Test func lifecycleSchedulerAppliesContentLayerClippingOnlyForTranslatedAnimation() {
    #expect(HistoryWindowLifecycleScheduler.shouldApplyContentLayerTransformPreparation(
        initialTranslationY: -360
    ))
    #expect(!HistoryWindowLifecycleScheduler.shouldApplyContentLayerTransformPreparation(
        initialTranslationY: 0
    ))
}

@Test func lifecycleSchedulerSkipsRedundantAccessibilityRefreshForVerifiedOrClosingToggle() {
    #expect(!HistoryWindowLifecycleScheduler.shouldRefreshAccessibilityBeforeToggle(
        isWindowVisible: true
    ))
    #expect(HistoryWindowLifecycleScheduler.shouldRefreshAccessibilityBeforeToggle(
        isWindowVisible: false
    ))
    #expect(!HistoryWindowLifecycleScheduler.shouldRefreshAccessibilityBeforeShow(
        alreadyVerified: true
    ))
    #expect(HistoryWindowLifecycleScheduler.shouldRefreshAccessibilityBeforeShow(
        alreadyVerified: false
    ))
}

@Test func lifecycleSchedulerDefersKeyboardTapStartUntilFinishShowing() {
    #expect(!HistoryWindowLifecycleScheduler.shouldStartKeyboardEventTapBeforeOrdering(
        shouldAnimate: true
    ))
    #expect(!HistoryWindowLifecycleScheduler.shouldStartKeyboardEventTapBeforeOrdering(
        shouldAnimate: false
    ))
}

@Test func lifecycleSchedulerMovesAnimatedKeyboardTapStartToPresentationRecovery() {
    #expect(!HistoryWindowLifecycleScheduler.shouldStartKeyboardEventTapWhenFinishingShow(
        shouldAnimate: true
    ))
    #expect(HistoryWindowLifecycleScheduler.shouldStartKeyboardEventTapWhenFinishingShow(
        shouldAnimate: false
    ))
    #expect(HistoryWindowLifecycleScheduler.shouldStartKeyboardEventTapDuringPresentationRecovery(
        shouldAnimate: true
    ))
    #expect(!HistoryWindowLifecycleScheduler.shouldStartKeyboardEventTapDuringPresentationRecovery(
        shouldAnimate: false
    ))
}

@Test func lifecycleSchedulerSkipsRedundantHiddenFrameApplication() {
    let frame = CGRect(x: 0, y: -360, width: 1440, height: 360)

    #expect(!HistoryWindowLifecycleScheduler.shouldApplyHiddenFrame(
        currentFrame: frame,
        targetFrame: frame
    ))
    #expect(HistoryWindowLifecycleScheduler.shouldApplyHiddenFrame(
        currentFrame: CGRect(x: 0, y: 0, width: 1440, height: 360),
        targetFrame: frame
    ))
}

@Test func lifecycleSchedulerTreatsOffscreenTopAlignedHiddenFrameAsReusable() {
    #expect(!HistoryWindowLifecycleScheduler.shouldApplyHiddenFrame(
        currentFrame: CGRect(x: 0, y: -404, width: 1440, height: 404),
        targetFrame: CGRect(x: 0, y: -360, width: 1440, height: 360)
    ))
}

@Test func lifecycleSchedulerTreatsOffscreenOriginAlignedTallerHiddenFrameAsReusable() {
    #expect(!HistoryWindowLifecycleScheduler.shouldApplyHiddenFrame(
        currentFrame: CGRect(x: 0, y: -360, width: 1440, height: 404),
        targetFrame: CGRect(x: 0, y: -360, width: 1440, height: 360)
    ))
}

@Test func lifecycleSchedulerKeepsPreviewBuildRunningDuringHideCleanup() {
    #expect(!HistoryWindowLifecycleScheduler.shouldCancelPreviewBuildForHide(
        hasPendingPreviewBuild: true
    ))
    #expect(HistoryWindowLifecycleScheduler.previewGenerationAfterHideCleanup(
        currentGeneration: 9,
        hasPendingPreviewBuild: true
    ) == 9)
}

@Test func lifecycleSchedulerWarmsPreviewAfterHideWhenPreviewStateIsStale() {
    #expect(HistoryWindowLifecycleScheduler.shouldWarmPreviewAfterHide(
        hasSourceItems: true,
        canSkipPreviewRebuild: false
    ))
    #expect(!HistoryWindowLifecycleScheduler.shouldWarmPreviewAfterHide(
        hasSourceItems: true,
        canSkipPreviewRebuild: true
    ))
    #expect(!HistoryWindowLifecycleScheduler.shouldWarmPreviewAfterHide(
        hasSourceItems: false,
        canSkipPreviewRebuild: false
    ))
}

@Test func lifecycleSchedulerWarmsPreviewForPreloadedHiddenWindowOnlyWhenHiddenAndStale() {
    #expect(HistoryWindowLifecycleScheduler.shouldWarmPreviewForPreloadedHiddenWindow(
        isWindowVisible: false,
        isWindowPresented: false,
        isOpenAnimationActive: false,
        hasSourceItems: true,
        canSkipPreviewRebuild: false
    ))
    #expect(!HistoryWindowLifecycleScheduler.shouldWarmPreviewForPreloadedHiddenWindow(
        isWindowVisible: true,
        isWindowPresented: true,
        isOpenAnimationActive: false,
        hasSourceItems: true,
        canSkipPreviewRebuild: false
    ))
    #expect(!HistoryWindowLifecycleScheduler.shouldWarmPreviewForPreloadedHiddenWindow(
        isWindowVisible: true,
        isWindowPresented: false,
        isOpenAnimationActive: true,
        hasSourceItems: true,
        canSkipPreviewRebuild: false
    ))
    #expect(!HistoryWindowLifecycleScheduler.shouldWarmPreviewForPreloadedHiddenWindow(
        isWindowVisible: true,
        isWindowPresented: false,
        isOpenAnimationActive: false,
        hasSourceItems: true,
        canSkipPreviewRebuild: true
    ))
}

@Test func lifecycleSchedulerSkipsLaunchHiddenPreviewWarmWhenThereAreNoItems() {
    #expect(!HistoryWindowLifecycleScheduler.shouldWarmPreviewForPreloadedHiddenWindow(
        isWindowVisible: false,
        isWindowPresented: false,
        isOpenAnimationActive: false,
        hasSourceItems: false,
        canSkipPreviewRebuild: false
    ))
}

@Test func previewBuildCoordinatorRejectsExplicitlyCanceledTask() {
    #expect(!HistoryPreviewBuildCoordinator.shouldApplyResult(
        isTaskCancelled: true,
        generation: 9,
        currentGeneration: 9
    ))
}
