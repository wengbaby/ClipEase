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

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.isPaused = userDefaults.bool(forKey: Self.isPausedKey)
    }

    func togglePaused() {
        isPaused.toggle()
    }
}

