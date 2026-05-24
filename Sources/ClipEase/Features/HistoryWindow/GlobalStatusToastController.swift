import AppKit
import SwiftUI

@MainActor
final class GlobalStatusToastController {
    static let shared = GlobalStatusToastController()

    private let toastDurationNanoseconds: UInt64 = 1_200_000_000
    private let fadeInDuration: TimeInterval = 0.12
    private let fadeOutDuration: TimeInterval = 0.28
    private let toastSize = NSSize(width: 200, height: 200)
    private let fallbackHistoryPanelHeight: CGFloat = 360
    private var panel: NSPanel?
    private var generation: UInt64 = 0
    private var lastHistoryWindowFrame: NSRect?
    private weak var lastHistoryWindowScreen: NSScreen?

    private init() {}

    func updateHistoryWindowFrame(_ frame: NSRect, screen: NSScreen?) {
        lastHistoryWindowFrame = frame
        lastHistoryWindowScreen = screen
    }

    func show(_ text: String, relativeTo parentWindow: NSWindow?) {
        generation &+= 1
        let currentGeneration = generation
        let panel = panel ?? makePanel()
        self.panel = panel

        if let parentWindow,
           isHistoryWindow(parentWindow),
           parentWindow.isVisible {
            updateHistoryWindowFrame(parentWindow.frame, screen: parentWindow.screen)
        }

        panel.contentView = NSHostingView(rootView: GlobalStatusToastView(text: text))
        panel.setFrame(frame(relativeTo: parentWindow), display: true)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = fadeInDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: toastDurationNanoseconds)
            guard generation == currentGeneration else {
                return
            }

            NSAnimationContext.runAnimationGroup { context in
                context.duration = fadeOutDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().alphaValue = 0
            } completionHandler: {
                Task { @MainActor in
                    guard self.generation == currentGeneration else {
                        return
                    }

                    panel.orderOut(nil)
                    panel.alphaValue = 1
                }
            }
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: toastSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.hasShadow = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.ignoresMouseEvents = true
        return panel
    }

    private func frame(relativeTo parentWindow: NSWindow?) -> NSRect {
        if let parentWindow,
           isHistoryWindow(parentWindow),
           parentWindow.isVisible {
            updateHistoryWindowFrame(parentWindow.frame, screen: parentWindow.screen)
        }

        if let parentFrame = lastHistoryWindowFrame {
            return frame(overHistoryFrame: parentFrame, screen: lastHistoryWindowScreen ?? parentWindow?.screen)
        }

        let fallbackScreen = parentWindow?.screen ?? NSScreen.clipeaseScreenContainingMouse ?? NSScreen.main
        return frame(overHistoryFrame: fallbackHistoryFrame(for: fallbackScreen), screen: fallbackScreen)
    }

    private func frame(overHistoryFrame historyFrame: NSRect, screen: NSScreen?) -> NSRect {
        let visibleFrame = screenVisibleFrame(for: screen)
        let origin = NSPoint(
            x: historyFrame.midX - toastSize.width / 2,
            y: min(historyFrame.maxY + 14, visibleFrame.maxY - toastSize.height - 8)
        )
        return NSRect(origin: origin, size: toastSize)
    }

    private func fallbackHistoryFrame(for screen: NSScreen?) -> NSRect {
        let screenFrame = screen?.frame ?? NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        return NSRect(
            x: screenFrame.minX,
            y: screenFrame.minY,
            width: screenFrame.width,
            height: fallbackHistoryPanelHeight
        )
    }

    private func screenVisibleFrame(for screen: NSScreen?) -> NSRect {
        screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
    }

    private func isHistoryWindow(_ window: NSWindow) -> Bool {
        window is HistoryPanel
    }
}

private struct GlobalStatusToastView: View {
    let text: String
    private let hudForeground = Color(red: 106 / 255, green: 107 / 255, blue: 109 / 255)

    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: statusIconName)
                .font(.system(size: 70, weight: .regular))
                .foregroundStyle(hudForeground)
                .frame(height: 82)

            Text(text)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(hudForeground)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.72)
                .frame(width: 160, height: 36)
        }
        .padding(.top, 34)
        .frame(width: 200, height: 200, alignment: .top)
        .background(
            SystemHUDVisualEffect()
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var statusIconName: String {
        if text.contains("失败") || text.contains("无法") || text.contains("未找到") || text.contains("请授权") {
            return "exclamationmark.circle.fill"
        }

        if text.contains("暂停") {
            return "pause.circle.fill"
        }

        return "checkmark.circle.fill"
    }
}

private struct SystemHUDVisualEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.isEmphasized = false
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.isEmphasized = false
    }
}
