import SwiftUI
import AppKit

struct MoreMenuButton: NSViewRepresentable {
    typealias MenuPresenter = @MainActor (NSMenu, NSButton) -> Void

    let menuProvider: () -> NSMenu

    func makeCoordinator() -> Coordinator {
        Coordinator(menuProvider: menuProvider)
    }

    func makeNSView(context: Context) -> NSButton {
        Self.makeButton(coordinator: context.coordinator)
    }

    static func makeButton(coordinator: Coordinator) -> NSButton {
        let button = NSButton(title: "", target: coordinator, action: #selector(Coordinator.openMenu(_:)))
        configure(button)
        coordinator.button = button
        return button
    }

    static func configure(_ button: NSButton) {
        button.title = ""
        button.image = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: L("更多操作"))
        button.imagePosition = .imageOnly
        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.font = .systemFont(ofSize: 14, weight: .semibold)
        button.alignment = .center
        button.focusRingType = .default
        button.refusesFirstResponder = false
        button.setButtonType(.momentaryChange)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.toolTip = L("更多操作")
        button.setAccessibilityLabel(L("更多操作"))
        button.setAccessibilityRole(.menuButton)
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.menuProvider = menuProvider
        Self.configure(button)
    }

    @MainActor
    final class Coordinator: NSObject {
        var menuProvider: () -> NSMenu
        let menuPresenter: MenuPresenter
        weak var button: NSButton?

        init(
            menuProvider: @escaping () -> NSMenu,
            menuPresenter: @escaping MenuPresenter = { menu, button in
                let point = NSPoint(x: 0, y: button.bounds.minY - 4)
                menu.popUp(positioning: nil, at: point, in: button)
            }
        ) {
            self.menuProvider = menuProvider
            self.menuPresenter = menuPresenter
        }

        @objc func openMenu(_ sender: NSButton) {
            let menu = menuProvider()
            menuPresenter(menu, sender)
        }
    }
}

final class ClosureMenuItemTarget: NSObject {
    private let action: () -> Void

    init(_ action: @escaping () -> Void) {
        self.action = action
    }

    @objc func performAction() {
        action()
    }
}
