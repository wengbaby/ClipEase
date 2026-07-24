import Foundation
import Testing
@testable import ClipEase

@Test @MainActor func timedPausePublishesPresetAndCountdown() {
    let defaults = UserDefaults(suiteName: "RecordingControllerTests.timedPause")!
    defaults.removePersistentDomain(forName: "RecordingControllerTests.timedPause")
    defer { defaults.removePersistentDomain(forName: "RecordingControllerTests.timedPause") }

    let controller = RecordingController(userDefaults: defaults)
    controller.pause(for: 15 * 60, preset: .fifteenMinutes)

    #expect(controller.isPaused)
    #expect(controller.activePausePreset == .fifteenMinutes)
    #expect(controller.pauseCountdownText == "00:15:00")
    #expect(controller.pauseMenuPrimaryTitle().hasSuffix(" · 00:15:00"))

    controller.setPaused(false)
}

@Test @MainActor func hourlyPauseUsesHourMinuteSecondCountdown() {
    let defaults = UserDefaults(suiteName: "RecordingControllerTests.hourlyPause")!
    defaults.removePersistentDomain(forName: "RecordingControllerTests.hourlyPause")
    defer { defaults.removePersistentDomain(forName: "RecordingControllerTests.hourlyPause") }

    let controller = RecordingController(userDefaults: defaults)
    controller.pause(for: 60 * 60, preset: .oneHour)

    #expect(controller.activePausePreset == .oneHour)
    #expect(controller.pauseCountdownText == "01:00:00")
    controller.setPaused(false)
}
