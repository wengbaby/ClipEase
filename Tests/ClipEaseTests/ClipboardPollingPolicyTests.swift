import Foundation
import Testing
@testable import ClipEase

@Test func clipboardPollingPolicyUsesActiveIntervalBeforeIdleThreshold() {
    let policy = ClipboardPollingPolicy(
        activeInterval: 0.25,
        idleInterval: 0.75,
        idleThreshold: 12
    )

    #expect(policy.interval(afterUnchangedPollCount: 0) == 0.25)
    #expect(policy.interval(afterUnchangedPollCount: 11) == 0.25)
}

@Test func clipboardPollingPolicyUsesIdleIntervalAtThreshold() {
    let policy = ClipboardPollingPolicy(
        activeInterval: 0.25,
        idleInterval: 0.75,
        idleThreshold: 12
    )

    #expect(policy.interval(afterUnchangedPollCount: 12) == 0.25)
    #expect(policy.interval(afterUnchangedPollCount: 30) == 0.25)
}

@Test func defaultClipboardPollingPolicyBalancesResponsivenessAndIdleCost() {
    #expect(ClipboardPollingPolicy.default.activeInterval == 0.25)
    #expect(ClipboardPollingPolicy.default.idleInterval == 0.25)
    #expect(ClipboardPollingPolicy.default.idleThreshold == 12)
    #expect(ClipboardPollingPolicy.maximumScheduledInterval == 0.25)
    #expect(ClipboardPollingPolicy.timerTolerance == 0.025)
}
