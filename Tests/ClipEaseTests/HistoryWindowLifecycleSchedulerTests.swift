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
