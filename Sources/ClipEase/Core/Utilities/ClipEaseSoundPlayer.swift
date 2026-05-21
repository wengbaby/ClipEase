import AppKit

@MainActor
final class ClipEaseSoundPlayer {
    static let shared = ClipEaseSoundPlayer()

    private enum FeedbackSound: String {
        case copy = "Copy"
        case paste = "Paste"
    }

    private var copySound: NSSound?
    private var pasteSound: NSSound?

    private init() {}

    func playCopyFeedback() {
        play(.copy)
    }

    func playPasteFeedback() {
        play(.paste)
    }

    private func play(_ feedbackSound: FeedbackSound) {
        let cachedSound = soundCache(for: feedbackSound)
        let sound = cachedSound ?? loadSound(feedbackSound)
        guard let sound else {
            return
        }

        setSoundCache(sound, for: feedbackSound)
        sound.stop()
        sound.currentTime = 0
        sound.play()
    }

    private func soundCache(for feedbackSound: FeedbackSound) -> NSSound? {
        switch feedbackSound {
        case .copy:
            copySound
        case .paste:
            pasteSound
        }
    }

    private func setSoundCache(_ sound: NSSound, for feedbackSound: FeedbackSound) {
        switch feedbackSound {
        case .copy:
            copySound = sound
        case .paste:
            pasteSound = sound
        }
    }

    private func loadSound(_ feedbackSound: FeedbackSound) -> NSSound? {
        guard let url = Bundle.main.url(
            forResource: feedbackSound.rawValue,
            withExtension: "aiff",
            subdirectory: "Sounds"
        ) ?? developmentResourceURL(for: feedbackSound) else {
            return nil
        }

        return NSSound(contentsOf: url, byReference: true)
    }

    private func developmentResourceURL(for feedbackSound: FeedbackSound) -> URL? {
        let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Resources/Sounds")
            .appendingPathComponent("\(feedbackSound.rawValue).aiff")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}
