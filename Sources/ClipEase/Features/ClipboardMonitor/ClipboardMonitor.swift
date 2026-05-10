import AppKit
import Foundation

@MainActor
final class ClipboardMonitor {
    private let pasteboard: NSPasteboard
    private let store: ClipboardHistoryStore
    private let recordingController: RecordingController
    private var timer: Timer?
    private var lastChangeCount: Int

    init(
        store: ClipboardHistoryStore,
        recordingController: RecordingController,
        pasteboard: NSPasteboard = .general
    ) {
        self.store = store
        self.recordingController = recordingController
        self.pasteboard = pasteboard
        self.lastChangeCount = pasteboard.changeCount
    }

    func start() {
        guard timer == nil else {
            return
        }

        timer = Timer.scheduledTimer(
            withTimeInterval: 0.75,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                self?.poll()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        guard pasteboard.changeCount != lastChangeCount else {
            return
        }

        lastChangeCount = pasteboard.changeCount
        guard !recordingController.isPaused else {
            return
        }

        guard let text = pasteboard.string(forType: .string) else {
            return
        }

        store.addText(text, sourceApp: .current)
    }
}
