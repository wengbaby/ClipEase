import AppKit

enum HistoryWindowPanelSizeLock {
    @MainActor
    @discardableResult
    static func apply(to panel: NSPanel?, frameSize: NSSize) -> Bool {
        guard let panel else {
            return false
        }

        let contentSize = panel.contentRect(
            forFrameRect: NSRect(origin: .zero, size: frameSize)
        ).size
        guard panel.contentMinSize != contentSize ||
            panel.contentMaxSize != contentSize else {
            return false
        }

        panel.contentMinSize = contentSize
        panel.contentMaxSize = contentSize
        return true
    }
}
