import AppKit
import ApplicationServices

@MainActor
final class AccessibilityPermissionState: ObservableObject {
    @Published private(set) var isTrusted = false

    var currentAppURL: URL {
        Bundle.main.bundleURL
    }

    var currentAppPath: String {
        currentAppURL.path
    }

    init() {
        refresh()
    }

    @discardableResult
    func refresh(promptIfNeeded: Bool = false) -> Bool {
        if promptIfNeeded {
            let options = [
                "AXTrustedCheckOptionPrompt": true
            ] as CFDictionary
            isTrusted = AXIsProcessTrustedWithOptions(options)
        } else {
            isTrusted = AXIsProcessTrustedWithOptions(nil)
        }

        return isTrusted
    }

    func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    func revealCurrentAppInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([currentAppURL])
    }

    func copyCurrentAppPath() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(currentAppPath, forType: .string)
    }
}
