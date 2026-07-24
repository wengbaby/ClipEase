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
        var panelOpeningHandler: ((ColorButtonView) -> Void)?

        init(
            color: NSColor,
            onChange: @escaping (NSColor) -> Void,
            panelOpeningHandler: ((ColorButtonView) -> Void)? = nil
        ) {
            self.color = color
            self.onChange = onChange
            self.panelOpeningHandler = panelOpeningHandler
        }

        func openColorPanel(from view: ColorButtonView) {
            if let panelOpeningHandler {
                panelOpeningHandler(view)
                return
            }

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

        override func isAccessibilityElement() -> Bool {
            true
        }

        override func accessibilityRole() -> NSAccessibility.Role? {
            .button
        }

        override func accessibilityLabel() -> String? {
            L("分组颜色")
        }

        override func accessibilityValue() -> Any? {
            Self.sRGBHexValue(for: color)
        }

        override func accessibilityChildren() -> [Any]? {
            []
        }

        override func accessibilityPerformPress() -> Bool {
            guard let coordinator else {
                return false
            }

            coordinator.openColorPanel(from: self)
            return true
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

        override func keyDown(with event: NSEvent) {
            switch event.keyCode {
            case KeyCode.space, KeyCode.returnKey, KeyCode.enter:
                coordinator?.openColorPanel(from: self)
            default:
                super.keyDown(with: event)
            }
        }

        override var focusRingMaskBounds: NSRect {
            bounds
        }

        override func drawFocusRingMask() {
            NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill()
        }

        private static func sRGBHexValue(for color: NSColor) -> String {
            guard let sRGBColor = color.usingColorSpace(.sRGB) else {
                return "#000000"
            }

            let components = [sRGBColor.redComponent, sRGBColor.greenComponent, sRGBColor.blueComponent]
            let hexadecimalComponents = components.map { component in
                String(format: "%02X", min(255, max(0, Int((component * 255).rounded()))))
            }
            return "#\(hexadecimalComponents.joined())"
        }
    }
}
