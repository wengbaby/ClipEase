import AppKit
import SwiftUI

@MainActor
final class GroupColorPanelController: NSObject {
    static let shared = GroupColorPanelController()

    private var onChange: ((NSColor) -> Void)?
    private weak var activeSource: NSView?

    private override init() {}

    var isVisible: Bool {
        NSColorPanel.shared.isVisible
    }

    func open(source: NSView?, color: Color, onChange: @escaping (NSColor) -> Void) {
        self.onChange = onChange

        let panel = NSColorPanel.shared
        panel.setTarget(self)
        panel.setAction(#selector(colorPanelChanged(_:)))
        panel.showsAlpha = false
        panel.isContinuous = true
        panel.color = NSColor(color).usingColorSpace(.sRGB) ?? .systemBlue
        panel.hidesOnDeactivate = false
        panel.worksWhenModal = true
        position(panel, near: source)
        panel.orderFrontRegardless()
        panel.makeKeyAndOrderFront(nil)
    }

    func toggle(source: NSView, color: Color, onChange: @escaping (NSColor) -> Void) {
        if activeSource === source,
           NSColorPanel.shared.isVisible {
            close()
        } else {
            activeSource = source
            open(source: source, color: color, onChange: onChange)
        }
    }

    func close(source: NSView) {
        guard activeSource === source else {
            return
        }

        close()
    }

    func close() {
        activeSource = nil
        onChange = nil
        let panel = NSColorPanel.shared
        panel.setTarget(nil)
        panel.setAction(nil)
        panel.close()
    }

    func closeIfVisible() {
        guard isVisible else {
            return
        }

        close()
    }

    static func closeSharedColorPanel() {
        NSColorPanel.shared.close()
    }

    @objc private func colorPanelChanged(_ sender: NSColorPanel) {
        let color = sender.color.usingColorSpace(.sRGB) ?? sender.color
        onChange?(color)
    }

    private func position(_ panel: NSColorPanel, near source: NSView?) {
        guard let source,
              let sourceWindow = source.window else {
            panel.level = .floating
            return
        }

        NSApp.activate(ignoringOtherApps: true)
        sourceWindow.makeKey()

        let sourceFrame = sourceWindow.convertToScreen(source.convert(source.bounds, to: nil))
        let visibleFrame = bestScreen(for: sourceFrame)?.visibleFrame ?? NSScreen.main?.visibleFrame ?? sourceFrame
        let panelFrame = panel.frame
        let panelWidth = max(panelFrame.width, 320)
        let panelHeight = max(panelFrame.height, 360)
        let spacing: CGFloat = 12

        let preferredX = sourceFrame.maxX + spacing
        let fallbackX = sourceFrame.minX - panelWidth - spacing
        let unclampedX = preferredX + panelWidth <= visibleFrame.maxX ? preferredX : fallbackX
        let x = min(max(unclampedX, visibleFrame.minX), visibleFrame.maxX - panelWidth)

        let preferredTopY = sourceFrame.maxY
        let topY = min(
            max(preferredTopY, visibleFrame.minY + panelHeight),
            visibleFrame.maxY
        )

        let sourceLevel = sourceWindow.level.rawValue
        let minimumLevel = NSWindow.Level.floating.rawValue
        panel.level = NSWindow.Level(rawValue: max(sourceLevel + 1, minimumLevel))
        panel.setFrameTopLeftPoint(NSPoint(x: x, y: topY))
    }

    private func bestScreen(for frame: NSRect) -> NSScreen? {
        NSScreen.screens.max { lhs, rhs in
            lhs.visibleFrame.intersection(frame).area < rhs.visibleFrame.intersection(frame).area
        }
    }
}

private extension NSRect {
    var area: CGFloat {
        guard !isNull, !isEmpty else {
            return 0
        }

        return width * height
    }
}
