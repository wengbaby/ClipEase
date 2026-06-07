import Foundation
import Testing
@testable import ClipEase

@MainActor
@Test func groupAppearanceCoordinatorBeginsEditingRegularGroup() {
    let coordinator = GroupAppearanceCoordinator()
    let group = ClipboardGroup.makeDefault(name: "Work", sortOrder: 0)

    coordinator.beginEditing(group)

    #expect(coordinator.regularGroupTarget?.id == group.id)
    #expect(coordinator.systemGroupTarget == nil)
    #expect(coordinator.colorHex == group.colorHex)
    #expect(coordinator.originalColorHex == group.colorHex)
    #expect(coordinator.iconName == group.iconName)
    #expect(coordinator.originalIconName == group.iconName)
    #expect(coordinator.iconSearchText.isEmpty)
    #expect(coordinator.isPresented)
}

@MainActor
@Test func groupAppearanceCoordinatorBeginsEditingSystemGroup() {
    let coordinator = GroupAppearanceCoordinator()

    coordinator.beginEditingSystemGroup(
        .pinned,
        colorHex: "#2E8CFF",
        iconName: "pin.fill"
    )

    #expect(coordinator.regularGroupTarget == nil)
    #expect(coordinator.systemGroupTarget == .pinned)
    #expect(coordinator.colorHex == "#2E8CFF")
    #expect(coordinator.iconName == "pin.fill")
    #expect(coordinator.isPresented)
}

@MainActor
@Test func groupAppearanceCoordinatorEscapeClearsSearchBeforeClosing() {
    let coordinator = GroupAppearanceCoordinator()
    coordinator.beginEditing(ClipboardGroup.makeDefault(name: "Work", sortOrder: 0))
    coordinator.iconSearchText = "pin"

    let first = coordinator.handleIconSearchEscape()

    #expect(first == .clearedSearch)
    #expect(coordinator.isPresented)
    #expect(coordinator.iconSearchText.isEmpty)

    let second = coordinator.handleIconSearchEscape()

    #expect(second == .closedPopover)
    #expect(!coordinator.isPresented)
}

@MainActor
@Test func groupAppearanceCoordinatorCloseLayerClearsTargetsAndWindow() {
    let coordinator = GroupAppearanceCoordinator()
    coordinator.beginEditing(ClipboardGroup.makeDefault(name: "Work", sortOrder: 0))
    coordinator.setPopoverWindowPresentForTesting()
    coordinator.iconSearchText = "folder"

    coordinator.closeLayer()

    #expect(coordinator.regularGroupTarget == nil)
    #expect(coordinator.systemGroupTarget == nil)
    #expect(!coordinator.hasPopoverWindow)
    #expect(coordinator.iconSearchText.isEmpty)
    #expect(!coordinator.isPresented)
}
