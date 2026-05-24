import AppKit
import SwiftUI

@MainActor
final class AccessibilityPermissionGuideWindowController: NSObject, NSWindowDelegate {
    private let permissionState: AccessibilityPermissionState
    private var window: AccessibilityPermissionGuideWindow?

    init(permissionState: AccessibilityPermissionState) {
        self.permissionState = permissionState
        super.init()
    }

    func show() {
        permissionState.refresh(promptIfNeeded: true)

        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let guideView = AccessibilityPermissionGuideView(permissionState: permissionState) { [weak self] in
            self?.closeIfTrusted()
        }
        let window = AccessibilityPermissionGuideWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 360),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "开启辅助功能权限"
        window.contentView = NSHostingView(rootView: guideView)
        window.center()
        window.delegate = self
        window.onCommandW = { [weak window] in
            window?.orderOut(nil)
        }
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func closeIfTrusted() {
        permissionState.refresh()
        if permissionState.isTrusted {
            window?.orderOut(nil)
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }
}

private final class AccessibilityPermissionGuideWindow: NSWindow {
    var onCommandW: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers?.lowercased() == "w" {
            onCommandW?()
            return
        }

        super.keyDown(with: event)
    }
}

private struct AccessibilityPermissionGuideView: View {
    @ObservedObject var permissionState: AccessibilityPermissionState
    let onAuthorized: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: permissionState.isTrusted ? "checkmark.shield.fill" : "lock.shield.fill")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(permissionState.isTrusted ? Color.green : Color.accentColor)

                VStack(alignment: .leading, spacing: 4) {
                    Text(permissionState.isTrusted ? "辅助功能权限已开启" : "轻贴需要辅助功能权限")
                        .font(.system(size: 22, weight: .semibold))
                    Text(permissionState.isTrusted ? "现在可以使用快捷键打开历史窗口并自动粘贴。" : "开启后才可以使用全局快捷键、自动粘贴和稳定的主窗口交互。")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                permissionStep("1", "点击“打开系统设置”。")
                permissionStep("2", "在“辅助功能”列表中找到 ClipEase 或轻贴。")
                permissionStep("3", "打开开关后回到轻贴，点击“我已开启”。")
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            Text(permissionState.currentAppPath)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .textSelection(.enabled)

            Spacer()

            HStack(spacing: 10) {
                Button("打开系统设置") {
                    permissionState.openSystemSettings()
                    permissionState.refresh(promptIfNeeded: true)
                }
                .buttonStyle(.borderedProminent)

                Button("显示当前 App") {
                    permissionState.revealCurrentAppInFinder()
                }
                .buttonStyle(.bordered)

                Spacer()

                Button(permissionState.isTrusted ? "完成" : "我已开启") {
                    permissionState.refresh()
                    onAuthorized()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(24)
        .frame(width: 520, height: 360)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            permissionState.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            permissionState.refresh()
            onAuthorized()
        }
    }

    private func permissionStep(_ index: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Text(index)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.white)
                .frame(width: 19, height: 19)
                .background(Circle().fill(Color.accentColor))

            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
        }
    }
}
