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
