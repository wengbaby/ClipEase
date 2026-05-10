import Foundation

@MainActor
final class RecordingController: ObservableObject {
    @Published private(set) var isPaused: Bool {
        didSet {
            userDefaults.set(isPaused, forKey: Self.isPausedKey)
        }
    }

    private static let isPausedKey = "recording.isPaused"
    private let userDefaults: UserDefaults
    private var resumeTask: Task<Void, Never>?

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.isPaused = userDefaults.bool(forKey: Self.isPausedKey)
    }

    func togglePaused() {
        setPaused(!isPaused)
    }

    func setPaused(_ paused: Bool) {
        resumeTask?.cancel()
        resumeTask = nil
        isPaused = paused
    }

    func pause(for interval: TimeInterval) {
        setPaused(true)
        let nanoseconds = UInt64(max(0, interval) * 1_000_000_000)
        resumeTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: nanoseconds)
            if !Task.isCancelled {
                self.isPaused = false
                self.resumeTask = nil
            }
        }
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
}
