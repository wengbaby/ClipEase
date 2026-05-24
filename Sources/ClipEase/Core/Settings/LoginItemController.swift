import Foundation
import ServiceManagement

@MainActor
final class LoginItemController: ObservableObject {
    @Published private(set) var statusText: String = ""

    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    init() {
        refresh()
    }

    func refresh() {
        statusText = Self.title(for: SMAppService.mainApp.status)
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("ClipEase failed to update login item: \(error.localizedDescription)")
        }

        refresh()
    }

    private static func title(for status: SMAppService.Status) -> String {
        switch status {
        case .enabled:
            "已启用"
        case .requiresApproval:
            "需要在系统设置中批准"
        case .notRegistered:
            "未启用"
        case .notFound:
            "当前构建暂不可用"
        @unknown default:
            "未知状态"
        }
    }
}
