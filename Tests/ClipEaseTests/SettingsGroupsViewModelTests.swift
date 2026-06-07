import Foundation
import Testing
@testable import ClipEase

@Test func settingsGroupsSubtitleShowsEmptyAndGroupedCounts() {
    #expect(SettingsGroupsViewModel.subtitle(groups: [], itemCount: { _ in 0 }) == "暂无分组")

    let first = ClipboardGroup.fixture(name: "Work", sortOrder: 0)
    let second = ClipboardGroup.fixture(name: "Home", sortOrder: 1)

    let subtitle = SettingsGroupsViewModel.subtitle(groups: [first, second]) { id in
        id == first.id ? 3 : 2
    }

    #expect(subtitle == "2 个分组，5 条内容")
}

@Test func settingsGroupsIconFilterUsesDefaultIconsForEmptyQuery() {
    #expect(SettingsGroupsViewModel.filteredIcons(query: "   ").count == ClipboardGroup.defaultIcons.count)
}

@Test func settingsGroupsIconFilterMatchesLocalizedCaseInsensitively() {
    #expect(SettingsGroupsViewModel.filteredIcons(query: "BOOK").contains("bookmark"))
    #expect(SettingsGroupsViewModel.filteredIcons(query: "folder").allSatisfy {
        $0.localizedCaseInsensitiveContains("folder")
    })
}

@Test func settingsGroupsBulkDeleteRequiresConfirmationOnlyWhenSelectedGroupHasItems() {
    let first = UUID()
    let second = UUID()

    #expect(SettingsGroupsViewModel.bulkDeleteDecision(selectedIDs: [], itemCount: { _ in 0 }) == .none)
    #expect(SettingsGroupsViewModel.bulkDeleteDecision(selectedIDs: [first], itemCount: { _ in 0 }) == .deleteImmediately)
    #expect(SettingsGroupsViewModel.bulkDeleteDecision(selectedIDs: [first, second]) { id in
        id == second ? 1 : 0
    } == .confirm)
}

private extension ClipboardGroup {
    static func fixture(
        name: String,
        sortOrder: Int,
        createdAt: Date = Date(timeIntervalSince1970: 1)
    ) -> ClipboardGroup {
        ClipboardGroup(
            id: UUID(),
            name: name,
            colorHex: "#0A84FF",
            iconName: "tray.full",
            sortOrder: sortOrder,
            createdAt: createdAt,
            updatedAt: createdAt
        )
    }
}
