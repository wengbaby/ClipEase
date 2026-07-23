import AppKit
import ApplicationServices

@MainActor
final class AccessibilityPermissionState: ObservableObject {
    @Published private(set) var isTrusted = false
    private let isProcessTrusted: (Bool) -> Bool

    var currentAppURL: URL {
        Bundle.main.bundleURL
    }

    var currentAppPath: String {
        currentAppURL.path
    }

    init(isProcessTrusted: ((Bool) -> Bool)? = nil) {
        self.isProcessTrusted = isProcessTrusted ?? { promptIfNeeded in
            if promptIfNeeded {
                let options = [
                    "AXTrustedCheckOptionPrompt": true
                ] as CFDictionary
                return AXIsProcessTrustedWithOptions(options)
            }
            return AXIsProcessTrustedWithOptions(nil)
        }
        refresh()
    }

    @discardableResult
    func refresh(promptIfNeeded: Bool = false) -> Bool {
        isTrusted = isProcessTrusted(promptIfNeeded)

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

    @discardableResult
    func copyCurrentAppPath(using clipboardWriter: ClipboardWriteCoordinator) -> Bool {
        clipboardWriter.writeText(currentAppPath)
    }
}
