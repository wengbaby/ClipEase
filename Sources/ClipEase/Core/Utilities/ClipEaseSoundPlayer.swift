import AVFoundation
import Foundation

@MainActor
final class ClipEaseSoundPlayer {
    static let shared = ClipEaseSoundPlayer()

    private enum FeedbackSound: String {
        case copy = "Copy"
        case paste = "Paste"
    }

    private var copyPlayer: AVAudioPlayer?
    private var pastePlayer: AVAudioPlayer?

    private init() {}

    func playCopyFeedback() {
        play(.copy)
    }

    func playPasteFeedback() {
        play(.paste)
    }

    private func play(_ feedbackSound: FeedbackSound) {
        let cachedPlayer = playerCache(for: feedbackSound)
        let player = cachedPlayer ?? loadPlayer(feedbackSound)
        guard let player else {
            return
        }

        setPlayerCache(player, for: feedbackSound)
        player.stop()
        player.currentTime = 0
        player.play()
    }

    private func playerCache(for feedbackSound: FeedbackSound) -> AVAudioPlayer? {
        switch feedbackSound {
        case .copy:
            copyPlayer
        case .paste:
            pastePlayer
        }
    }

    private func setPlayerCache(_ player: AVAudioPlayer, for feedbackSound: FeedbackSound) {
        switch feedbackSound {
        case .copy:
            copyPlayer = player
        case .paste:
            pastePlayer = player
        }
    }

    private func loadPlayer(_ feedbackSound: FeedbackSound) -> AVAudioPlayer? {
        guard let url = Bundle.main.url(
            forResource: feedbackSound.rawValue,
            withExtension: "aiff",
            subdirectory: "Sounds"
        ) ?? developmentResourceURL(for: feedbackSound) else {
            return nil
        }

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.volume = 1
            player.prepareToPlay()
            return player
        } catch {
            return nil
        }
    }

    private func developmentResourceURL(for feedbackSound: FeedbackSound) -> URL? {
        let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Resources/Sounds")
            .appendingPathComponent("\(feedbackSound.rawValue).aiff")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}
