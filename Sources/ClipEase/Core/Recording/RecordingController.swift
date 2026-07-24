import Foundation

enum RecordingPausePreset: String, CaseIterable, Equatable, Sendable {
    case fifteenMinutes
    case thirtyMinutes
    case oneHour
    case threeHours
    case sixHours
    case untilEndOfToday

    var interval: TimeInterval? {
        switch self {
        case .fifteenMinutes: 15 * 60
        case .thirtyMinutes: 30 * 60
        case .oneHour: 60 * 60
        case .threeHours: 3 * 60 * 60
        case .sixHours: 6 * 60 * 60
        case .untilEndOfToday: nil
        }
    }

    var title: String {
        switch self {
        case .fifteenMinutes: L("暂停 15 分钟")
        case .thirtyMinutes: L("暂停 30 分钟")
        case .oneHour: L("暂停 1 小时")
        case .threeHours: L("暂停 3 小时")
        case .sixHours: L("暂停 6 小时")
        case .untilEndOfToday: L("暂停到今日结束")
        }
    }
}

@MainActor
final class RecordingController: ObservableObject {
    @Published private(set) var isPaused: Bool {
        didSet {
            userDefaults.set(isPaused, forKey: Self.isPausedKey)
        }
    }
    @Published private(set) var pauseEndsAt: Date?
    @Published private(set) var activePausePreset: RecordingPausePreset?
    @Published private(set) var pauseCountdownText = ""

    private static let isPausedKey = "recording.isPaused"
    private static let pauseEndsAtKey = "recording.pauseEndsAt"
    private static let activePausePresetKey = "recording.activePausePreset"
    private let userDefaults: UserDefaults
    private var resumeTask: Task<Void, Never>?
    private var countdownTask: Task<Void, Never>?

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.pauseEndsAt = userDefaults.object(forKey: Self.pauseEndsAtKey) as? Date
        self.activePausePreset = userDefaults.string(forKey: Self.activePausePresetKey)
            .flatMap(RecordingPausePreset.init(rawValue:))
        self.isPaused = userDefaults.bool(forKey: Self.isPausedKey)
        restorePauseState()
    }

    func togglePaused() {
        setPaused(!isPaused)
    }

    func setPaused(_ paused: Bool) {
        resumeTask?.cancel()
        resumeTask = nil
        countdownTask?.cancel()
        countdownTask = nil
        pauseEndsAt = nil
        activePausePreset = nil
        pauseCountdownText = ""
        userDefaults.removeObject(forKey: Self.pauseEndsAtKey)
        userDefaults.removeObject(forKey: Self.activePausePresetKey)
        isPaused = paused
    }

    func pause(for interval: TimeInterval, preset: RecordingPausePreset? = nil) {
        let endDate = Date().addingTimeInterval(max(0, interval))
        pause(until: endDate, preset: preset)
    }

    func pauseUntilEndOfToday(now: Date = Date()) {
        let calendar = Calendar.current
        guard let tomorrow = calendar.date(
            byAdding: .day,
            value: 1,
            to: calendar.startOfDay(for: now)
        ) else {
            setPaused(true)
            return
        }

        pause(until: tomorrow, preset: .untilEndOfToday)
    }

    func pauseMenuPrimaryTitle(now: Date = Date()) -> String {
        guard isPaused else {
            return L("暂停")
        }

        guard let pauseEndsAt else {
            return L("恢复")
        }

        return "\(L("恢复记录")) · \(countdownText(until: pauseEndsAt, now: now))"
    }

    private func pause(until endDate: Date, preset: RecordingPausePreset?) {
        resumeTask?.cancel()
        pauseEndsAt = endDate
        activePausePreset = preset
        userDefaults.set(endDate, forKey: Self.pauseEndsAtKey)
        userDefaults.set(preset?.rawValue, forKey: Self.activePausePresetKey)
        isPaused = true
        updateCountdown()
        scheduleResume(at: endDate)
        scheduleCountdownUpdates()
    }

    private func restorePauseState(now: Date = Date()) {
        guard isPaused else {
            pauseEndsAt = nil
            userDefaults.removeObject(forKey: Self.pauseEndsAtKey)
            return
        }

        guard let pauseEndsAt else {
            return
        }

        if pauseEndsAt <= now {
            setPaused(false)
        } else {
            updateCountdown(now: now)
            scheduleResume(at: pauseEndsAt)
            scheduleCountdownUpdates()
        }
    }

    private func scheduleResume(at endDate: Date) {
        resumeTask?.cancel()
        let interval = max(0, endDate.timeIntervalSinceNow)
        let nanoseconds = UInt64(interval * 1_000_000_000)
        resumeTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: nanoseconds)
            if !Task.isCancelled {
                self.setPaused(false)
            }
        }
    }

    private func scheduleCountdownUpdates() {
        countdownTask?.cancel()
        countdownTask = Task { @MainActor [weak self] in
            while let self, self.isPaused, self.pauseEndsAt != nil, !Task.isCancelled {
                self.updateCountdown()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    private func updateCountdown(now: Date = Date()) {
        guard let pauseEndsAt else {
            pauseCountdownText = ""
            return
        }
        pauseCountdownText = countdownText(until: pauseEndsAt, now: now)
    }

    private func countdownText(until endDate: Date, now: Date) -> String {
        let remainingSeconds = max(0, Int(ceil(endDate.timeIntervalSince(now))))
        return String(
            format: "%02d:%02d:%02d",
            remainingSeconds / 3600,
            (remainingSeconds % 3600) / 60,
            remainingSeconds % 60
        )
    }
}
