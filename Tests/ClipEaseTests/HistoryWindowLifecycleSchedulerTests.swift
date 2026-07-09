import CoreGraphics
import Testing
@testable import ClipEase

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

@Test func lifecycleSchedulerDefersPresentationStateUntilAnimatedOpenCompletes() {
    #expect(!HistoryWindowLifecycleScheduler.shouldApplyPresentationStateBeforeAnimation(
        shouldAnimate: true
    ))
    #expect(HistoryWindowLifecycleScheduler.shouldApplyPresentationStateBeforeAnimation(
        shouldAnimate: false
    ))
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

@Test func lifecycleSchedulerDefersMakeKeyUntilAnimatedOpenCompletes() {
    #expect(!HistoryWindowLifecycleScheduler.shouldMakeKeyBeforeAnimation(
        shouldAnimate: true
    ))
    #expect(HistoryWindowLifecycleScheduler.shouldMakeKeyBeforeAnimation(
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

@Test func lifecycleSchedulerInvalidatesPreviewGenerationForHideCleanup() {
    let nextGeneration = HistoryWindowLifecycleScheduler.previewGenerationAfterHideCleanup(
        currentGeneration: 9
    )

    #expect(nextGeneration == 10)
    #expect(!HistoryPreviewBuildCoordinator.shouldApplyResult(
        isTaskCancelled: false,
        generation: 9,
        currentGeneration: nextGeneration
    ))
}
