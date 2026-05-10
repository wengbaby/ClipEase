import AppKit
import Foundation

@MainActor
final class ClipboardMonitor {
    private let pasteboard: NSPasteboard
    private let store: ClipboardHistoryStore
    private let recordingController: RecordingController
    private let ignoredAppSettings: IgnoredAppSettings
    private var timer: Timer?
    private var lastChangeCount: Int

    init(
        store: ClipboardHistoryStore,
        recordingController: RecordingController,
        ignoredAppSettings: IgnoredAppSettings,
        pasteboard: NSPasteboard = .general
    ) {
        self.store = store
        self.recordingController = recordingController
        self.ignoredAppSettings = ignoredAppSettings
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

        let sourceApp = SourceAppInfo.current
        guard !ignoredAppSettings.contains(bundleID: sourceApp.bundleID) else {
            return
        }

        if let image = pasteboard.readObjects(
            forClasses: [NSImage.self],
            options: nil
        )?.first as? NSImage {
            store.addImage(image, sourceApp: sourceApp)
            return
        }

        if let text = pasteboard.string(forType: .string) {
            store.addText(text, sourceApp: sourceApp)
        }
    }
}
