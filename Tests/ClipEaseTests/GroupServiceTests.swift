import Foundation
import Testing
@testable import ClipEase

@Test func groupServiceSortsGroupsAndRebuildsIndex() {
    let early = ClipboardGroup.fixture(name: "Early", sortOrder: 1, createdAt: Date(timeIntervalSince1970: 10))
    let late = ClipboardGroup.fixture(name: "Late", sortOrder: 1, createdAt: Date(timeIntervalSince1970: 20))
    let first = ClipboardGroup.fixture(name: "First", sortOrder: 0, createdAt: Date(timeIntervalSince1970: 30))

    var groups = [late, first, early]
    let index = GroupService.sortGroupsAndBuildIndex(&groups)

    #expect(groups.map(\.id) == [first.id, early.id, late.id])
    #expect(groups.map(\.sortOrder) == [0, 1, 2])
    #expect(index == [first.id: 0, early.id: 1, late.id: 2])
}

@Test func groupServiceResolvesGroupIndexAndRepairsStaleIndex() {
    let first = ClipboardGroup.fixture(name: "First", sortOrder: 0)
    let second = ClipboardGroup.fixture(name: "Second", sortOrder: 1)
    var index = [second.id: 0]

    let resolved = GroupService.groupIndex(
        for: second.id,
        groups: [first, second],
        indexByID: &index
    )

    #expect(resolved == 1)
    #expect(index == [first.id: 0, second.id: 1])
}

@Test func groupServiceRenameRejectsEmptyDuplicateAndUnchangedNames() {
    var groups = [
        ClipboardGroup.fixture(name: "Work", sortOrder: 0),
        ClipboardGroup.fixture(name: "Home", sortOrder: 1)
    ]
    var index = GroupService.rebuildGroupIndex(groups)

    #expect(GroupService.renameGroup(groups[0].id, name: "   ", groups: &groups, indexByID: &index) == .empty)
    #expect(GroupService.renameGroup(groups[0].id, name: " work ", groups: &groups, indexByID: &index) == .unchanged)
    #expect(GroupService.renameGroup(groups[0].id, name: "HOME", groups: &groups, indexByID: &index) == .duplicate)

    let result = GroupService.renameGroup(groups[0].id, name: "Projects", groups: &groups, indexByID: &index)

    #expect(result == .renamed)
    #expect(groups[0].name == "Projects")
}

@Test func groupServiceBuildsUniqueGroupName() {
    let groups = [
        ClipboardGroup.fixture(name: "新分组", sortOrder: 0),
        ClipboardGroup.fixture(name: "新分组 2", sortOrder: 1)
    ]

    #expect(GroupService.uniqueGroupName(baseName: "新分组", groups: groups) == "新分组 3")
    #expect(GroupService.uniqueGroupName(baseName: "   ", groups: groups) == "新分组 3")
}

@Test func groupServiceUpdatesGroupCountOnMove() {
    let oldID = UUID()
    let newID = UUID()
    var counts = [oldID: 1]

    GroupService.updateGroupCountOnMove(from: oldID, to: newID, countByGroupID: &counts)

    #expect(counts[oldID] == nil)
    #expect(counts[newID] == 1)
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
