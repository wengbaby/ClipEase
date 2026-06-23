import Foundation

enum SettingsUpdateState: Equatable {
    case idle
    case checking
    case upToDate(String)
    case updateAvailable(AppUpdateInfo)
    case failed

    var isChecking: Bool {
        if case .checking = self {
            return true
        }
        return false
    }
}

@MainActor
final class SettingsUpdateViewModel: ObservableObject {
    @Published private(set) var state: SettingsUpdateState = .idle
    @Published var isAutomaticCheckEnabled: Bool {
        didSet {
            userDefaults.set(isAutomaticCheckEnabled, forKey: Self.automaticCheckKey)
        }
    }

    private static let automaticCheckKey = "updateCheck.automaticEnabled"
    private static let lastCheckDateKey = "updateCheck.lastCheckDate"
    private static let automaticCheckInterval: TimeInterval = 24 * 60 * 60

    private let checker: AppUpdateChecking
    private let currentVersion: String
    private let userDefaults: UserDefaults
    private let now: () -> Date

    init(
        checker: AppUpdateChecking = GitHubReleaseUpdateChecker(),
        currentVersion: String = AppVersionInfo.shortVersion,
        userDefaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init
    ) {
        self.checker = checker
        self.currentVersion = currentVersion
        self.userDefaults = userDefaults
        self.now = now
        self.isAutomaticCheckEnabled = userDefaults.object(forKey: Self.automaticCheckKey) as? Bool ?? true
    }

    func checkAutomaticallyIfNeeded() {
        guard isAutomaticCheckEnabled,
              shouldRunAutomaticCheck(at: now()) else {
            return
        }

        Task {
            await checkForUpdates(isAutomatic: true)
        }
    }

    func checkManually() {
        Task {
            await checkForUpdates(isAutomatic: false)
        }
    }

    func checkForUpdates(isAutomatic: Bool) async {
        guard !state.isChecking else {
            return
        }

        state = .checking

        do {
            let result = try await checker.check(currentVersion: currentVersion)
            userDefaults.set(now(), forKey: Self.lastCheckDateKey)

            switch result {
            case .upToDate(let version):
                state = .upToDate(version)
            case .updateAvailable(let info):
                state = .updateAvailable(info)
            }
        } catch {
            userDefaults.set(now(), forKey: Self.lastCheckDateKey)
            state = .failed
        }
    }

    private func shouldRunAutomaticCheck(at date: Date) -> Bool {
        guard let lastCheckDate = userDefaults.object(forKey: Self.lastCheckDateKey) as? Date else {
            return true
        }

        return date.timeIntervalSince(lastCheckDate) >= Self.automaticCheckInterval
    }
}
