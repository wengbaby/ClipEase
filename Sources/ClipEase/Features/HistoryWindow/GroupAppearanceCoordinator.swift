import AppKit
import Foundation

@MainActor
final class GroupAppearanceCoordinator: ObservableObject {
    enum EscapeAction: Equatable {
        case clearedSearch
        case closedPopover
        case none
    }

    @Published var regularGroupTarget: ClipboardGroup?
    @Published var systemGroupTarget: SystemHistoryGroup?
    @Published var colorHex = "#2E8CFF"
    @Published var originalColorHex = "#2E8CFF"
    @Published var iconName = "tray.full"
    @Published var originalIconName = "tray.full"
    @Published var iconSearchText = ""
    @Published private(set) var popoverWindow: NSWindow?

    var isPresented: Bool {
        regularGroupTarget != nil || systemGroupTarget != nil
    }

    var hasPopoverWindow: Bool {
        popoverWindow != nil
    }

    func beginEditing(_ group: ClipboardGroup) {
        systemGroupTarget = nil
        colorHex = group.colorHex
        originalColorHex = group.colorHex
        iconName = group.iconName
        originalIconName = group.iconName
        iconSearchText = ""
        regularGroupTarget = group
    }

    func beginEditingSystemGroup(
        _ group: SystemHistoryGroup,
        colorHex: String,
        iconName: String
    ) {
        regularGroupTarget = nil
        self.colorHex = colorHex
        originalColorHex = colorHex
        self.iconName = iconName
        originalIconName = iconName
        iconSearchText = ""
        systemGroupTarget = group
    }

    func setPopoverWindow(_ window: NSWindow?) {
        popoverWindow = window
    }

    func setPopoverWindowPresentForTesting() {
        popoverWindow = NSWindow()
    }

    func closeRegularPopover() {
        regularGroupTarget = nil
        clearSharedPresentationState()
    }

    func closeSystemPopover() {
        systemGroupTarget = nil
        clearSharedPresentationState()
    }

    func closeLayer() {
        regularGroupTarget = nil
        systemGroupTarget = nil
        clearSharedPresentationState()
    }

    func handleIconSearchEscape() -> EscapeAction {
        if !iconSearchText.isEmpty {
            iconSearchText = ""
            return .clearedSearch
        }

        guard isPresented else {
            return .none
        }

        closeLayer()
        return .closedPopover
    }

    private func clearSharedPresentationState() {
        popoverWindow = nil
        iconSearchText = ""
    }
}
