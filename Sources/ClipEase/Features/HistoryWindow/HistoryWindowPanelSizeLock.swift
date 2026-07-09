import AppKit

enum HistoryWindowPanelSizeLock {
    static let unlockedContentMinSize = NSSize.zero
    static let unlockedContentMaxSize = NSSize(
        width: CGFloat.greatestFiniteMagnitude,
        height: CGFloat.greatestFiniteMagnitude
    )

    @MainActor
    @discardableResult
    static func apply(to panel: NSPanel?, frameSize: NSSize) -> Bool {
        guard let panel else {
            return false
        }

        guard panel.contentMinSize != unlockedContentMinSize ||
            panel.contentMaxSize != unlockedContentMaxSize else {
            return false
        }

        panel.contentMinSize = unlockedContentMinSize
        panel.contentMaxSize = unlockedContentMaxSize
        return true
    }
}
