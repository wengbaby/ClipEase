import AppKit

enum HistoryWindowPanelSizeLock {
    @MainActor
    static func apply(to panel: NSPanel?, frameSize: NSSize) {
        guard let panel else {
            return
        }

        let contentSize = panel.contentRect(
            forFrameRect: NSRect(origin: .zero, size: frameSize)
        ).size
        panel.contentMinSize = contentSize
        panel.contentMaxSize = contentSize
    }
}
