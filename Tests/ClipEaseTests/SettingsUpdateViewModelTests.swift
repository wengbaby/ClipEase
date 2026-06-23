import Foundation
import Testing
@testable import ClipEase

@MainActor
@Test func settingsUpdateViewModelRunsAutomaticCheckWhenNoPreviousCheckExists() async {
    let userDefaults = isolatedUserDefaults()
    let checker = StubUpdateChecker(result: .upToDate(version: "2.3.150"))
    let viewModel = SettingsUpdateViewModel(
        checker: checker,
        currentVersion: "2.3.150",
        userDefaults: userDefaults,
        now: { Date(timeIntervalSince1970: 1_000) }
    )

    await viewModel.checkForUpdates(isAutomatic: true)

    #expect(viewModel.state == .upToDate("2.3.150"))
    #expect(userDefaults.object(forKey: "updateCheck.lastCheckDate") as? Date == Date(timeIntervalSince1970: 1_000))
}

@MainActor
@Test func settingsUpdateViewModelSkipsAutomaticCheckWithinOneDay() async {
    let userDefaults = isolatedUserDefaults()
    userDefaults.set(Date(timeIntervalSince1970: 1_000), forKey: "updateCheck.lastCheckDate")
    let viewModel = SettingsUpdateViewModel(
        checker: StubUpdateChecker(result: .upToDate(version: "2.3.150")),
        currentVersion: "2.3.150",
        userDefaults: userDefaults,
        now: { Date(timeIntervalSince1970: 1_000 + 60 * 60) }
    )

    viewModel.checkAutomaticallyIfNeeded()
    try? await Task.sleep(nanoseconds: 50_000_000)

    #expect(viewModel.state == .idle)
}

@MainActor
@Test func settingsUpdateViewModelRunsAutomaticCheckAfterOneDay() async {
    let userDefaults = isolatedUserDefaults()
    userDefaults.set(Date(timeIntervalSince1970: 1_000), forKey: "updateCheck.lastCheckDate")
    let viewModel = SettingsUpdateViewModel(
        checker: StubUpdateChecker(result: .upToDate(version: "2.3.150")),
        currentVersion: "2.3.150",
        userDefaults: userDefaults,
        now: { Date(timeIntervalSince1970: 1_000 + 24 * 60 * 60) }
    )

    viewModel.checkAutomaticallyIfNeeded()

    await waitUntil {
        viewModel.state == .upToDate("2.3.150")
    }
}

@MainActor
@Test func settingsUpdateViewModelPersistsAutomaticCheckToggle() {
    let userDefaults = isolatedUserDefaults()
    let viewModel = SettingsUpdateViewModel(
        checker: StubUpdateChecker(result: .upToDate(version: "2.3.150")),
        currentVersion: "2.3.150",
        userDefaults: userDefaults
    )

    viewModel.isAutomaticCheckEnabled = false

    #expect(userDefaults.bool(forKey: "updateCheck.automaticEnabled") == false)
}

@MainActor
@Test func settingsUpdateViewModelSurfacesFailedState() async {
    let userDefaults = isolatedUserDefaults()
    let viewModel = SettingsUpdateViewModel(
        checker: StubUpdateChecker(error: AppUpdateCheckError.invalidResponse),
        currentVersion: "2.3.150",
        userDefaults: userDefaults,
        now: { Date(timeIntervalSince1970: 2_000) }
    )

    await viewModel.checkForUpdates(isAutomatic: false)

    #expect(viewModel.state == .failed)
    #expect(userDefaults.object(forKey: "updateCheck.lastCheckDate") as? Date == Date(timeIntervalSince1970: 2_000))
}

private func isolatedUserDefaults() -> UserDefaults {
    let suiteName = "ClipEaseTests.SettingsUpdateViewModel.\(UUID().uuidString)"
    let userDefaults = UserDefaults(suiteName: suiteName)!
    userDefaults.removePersistentDomain(forName: suiteName)
    return userDefaults
}

@MainActor
private func waitUntil(
    timeout: TimeInterval = 1,
    condition: @escaping () -> Bool
) async {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition(), Date() < deadline {
        try? await Task.sleep(nanoseconds: 10_000_000)
    }
}

private struct StubUpdateChecker: AppUpdateChecking {
    let result: AppUpdateCheckResult?
    let error: Error?

    init(result: AppUpdateCheckResult) {
        self.result = result
        self.error = nil
    }

    init(error: Error) {
        self.result = nil
        self.error = error
    }

    func check(currentVersion: String) async throws -> AppUpdateCheckResult {
        if let error {
            throw error
        }

        return result ?? .upToDate(version: currentVersion)
    }
}
