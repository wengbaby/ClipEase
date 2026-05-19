import SwiftUI
import AppKit

struct GroupColorWell: NSViewRepresentable {
    var color: NSColor
    var onChange: (NSColor) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(color: color, onChange: onChange)
    }

    func makeNSView(context: Context) -> ColorButtonView {
        let view = ColorButtonView()
        view.coordinator = context.coordinator
        view.color = color.usingColorSpace(.sRGB) ?? color
        return view
    }

    func updateNSView(_ view: ColorButtonView, context: Context) {
        context.coordinator.color = color
        context.coordinator.onChange = onChange
        let normalizedColor = color.usingColorSpace(.sRGB) ?? color
        view.coordinator = context.coordinator
        view.color = normalizedColor
    }

    @MainActor
    static func dismantleNSView(_ view: ColorButtonView, coordinator: Coordinator) {
        // SwiftUI may rebuild the popover content while the system color panel is open.
        // The popover/window close paths own actually closing the shared color panel.
    }

    @MainActor
    final class Coordinator: NSObject {
        var color: NSColor
        var onChange: (NSColor) -> Void

        init(color: NSColor, onChange: @escaping (NSColor) -> Void) {
            self.color = color
            self.onChange = onChange
        }

        func openColorPanel(from view: ColorButtonView) {
            GroupColorPanelController.shared.toggle(
                source: view,
                color: Color(color.usingColorSpace(.sRGB) ?? color),
                onChange: { [weak self, weak view] color in
                    self?.color = color
                    view?.color = color
                    self?.onChange(color)
                }
            )
        }
    }

    @MainActor
    final class ColorButtonView: NSView {
        weak var coordinator: Coordinator?
        var color: NSColor = .systemBlue {
            didSet {
                needsDisplay = true
            }
        }

        override var acceptsFirstResponder: Bool {
            true
        }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
            true
        }

        override func draw(_ dirtyRect: NSRect) {
            super.draw(dirtyRect)

            let backgroundPath = NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8)
            color.setFill()
            backgroundPath.fill()

            NSColor.white.withAlphaComponent(0.35).setStroke()
            backgroundPath.lineWidth = 1
            backgroundPath.stroke()
        }

        override func mouseDown(with event: NSEvent) {
            window?.makeFirstResponder(self)
            coordinator?.openColorPanel(from: self)
        }
    }
}
