import Foundation
import ServiceManagement

@MainActor
final class LoginItemController: ObservableObject {
    private var status: SMAppService.Status

    var statusText: String {
        Self.title(for: status)
    }

    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    init() {
        status = SMAppService.mainApp.status
    }

    func refresh() {
        status = SMAppService.mainApp.status
        objectWillChange.send()
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
            L("已启用")
        case .requiresApproval:
            L("需要在系统设置中批准")
        case .notRegistered:
            L("未启用")
        case .notFound:
            L("当前构建暂不可用")
        @unknown default:
            L("未知状态")
        }
    }
}
