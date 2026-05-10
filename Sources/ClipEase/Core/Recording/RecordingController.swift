import Foundation

@MainActor
final class RecordingController: ObservableObject {
    @Published private(set) var isPaused: Bool {
        didSet {
            userDefaults.set(isPaused, forKey: Self.isPausedKey)
        }
    }
    @Published private(set) var pauseEndsAt: Date?

    private static let isPausedKey = "recording.isPaused"
    private static let pauseEndsAtKey = "recording.pauseEndsAt"
    private let userDefaults: UserDefaults
    private var resumeTask: Task<Void, Never>?

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.pauseEndsAt = userDefaults.object(forKey: Self.pauseEndsAtKey) as? Date
        self.isPaused = userDefaults.bool(forKey: Self.isPausedKey)
        restorePauseState()
    }

    func togglePaused() {
        setPaused(!isPaused)
    }

    func setPaused(_ paused: Bool) {
        resumeTask?.cancel()
        resumeTask = nil
        pauseEndsAt = nil
        userDefaults.removeObject(forKey: Self.pauseEndsAtKey)
        isPaused = paused
    }

    func pause(for interval: TimeInterval) {
        let endDate = Date().addingTimeInterval(max(0, interval))
        pause(until: endDate)
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

        pause(for: tomorrow.timeIntervalSince(now))
    }

    func pauseMenuPrimaryTitle(now: Date = Date()) -> String {
        guard isPaused else {
            return "暂停"
        }

        guard let pauseEndsAt else {
            return "恢复"
        }

        let remainingSeconds = max(0, Int(pauseEndsAt.timeIntervalSince(now)))
        let hours = remainingSeconds / 3600
        let minutes = max(1, (remainingSeconds % 3600 + 59) / 60)
        return String(format: "%02d:%02d 恢复", hours, minutes)
    }

    private func pause(until endDate: Date) {
        resumeTask?.cancel()
        pauseEndsAt = endDate
        userDefaults.set(endDate, forKey: Self.pauseEndsAtKey)
        isPaused = true
        scheduleResume(at: endDate)
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
            scheduleResume(at: pauseEndsAt)
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
}
