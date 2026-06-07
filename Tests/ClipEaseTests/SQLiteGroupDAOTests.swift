import Foundation
import Testing
@testable import ClipEase

@Test func sqliteGroupDAOLoadsGroupsBySortOrderThenCreatedAt() throws {
    let fixture = try SQLiteGroupDAOFixture.make()
    defer { fixture.remove() }

    let database = try SQLiteDatabase(url: fixture.databaseURL)
    defer { database.close() }
    try fixture.store.initialize()
    try database.execute("PRAGMA foreign_keys = ON")

    let later = SQLiteGroupDAOFixture.group(
        name: "later",
        sortOrder: 1,
        createdAt: Date(timeIntervalSince1970: 200)
    )
    let earlier = SQLiteGroupDAOFixture.group(
        name: "earlier",
        sortOrder: 1,
        createdAt: Date(timeIntervalSince1970: 100)
    )
    let first = SQLiteGroupDAOFixture.group(
        name: "first",
        sortOrder: 0,
        createdAt: Date(timeIntervalSince1970: 300)
    )

    try SQLiteGroupDAO.insert(later, in: database)
    try SQLiteGroupDAO.insert(earlier, in: database)
    try SQLiteGroupDAO.insert(first, in: database)

    let groups = try SQLiteGroupDAO.loadGroups(in: database)

    #expect(groups.map(\.name) == ["first", "earlier", "later"])
}

@Test func sqliteGroupDAOUpsertsAndDeletesGroups() throws {
    let fixture = try SQLiteGroupDAOFixture.make()
    defer { fixture.remove() }

    let database = try SQLiteDatabase(url: fixture.databaseURL)
    defer { database.close() }
    try fixture.store.initialize()
    try database.execute("PRAGMA foreign_keys = ON")

    let groupID = UUID()
    let original = SQLiteGroupDAOFixture.group(id: groupID, name: "old", sortOrder: 0)
    let updated = SQLiteGroupDAOFixture.group(id: groupID, name: "new", sortOrder: 2)

    try SQLiteGroupDAO.upsert([original], in: database)
    try SQLiteGroupDAO.upsert([updated], in: database)

    let groups = try SQLiteGroupDAO.loadGroups(in: database)
    #expect(groups.map(\.name) == ["new"])
    #expect(groups.first?.sortOrder == 2)

    try SQLiteGroupDAO.deleteGroups(with: [groupID], in: database)
    #expect(try SQLiteGroupDAO.loadGroups(in: database).isEmpty)
}

@Test func sqliteGroupDAOInsertsGroupItemAndDeleteCascadesJoinRows() throws {
    let fixture = try SQLiteGroupDAOFixture.make()
    defer { fixture.remove() }

    let database = try SQLiteDatabase(url: fixture.databaseURL)
    defer { database.close() }
    try fixture.store.initialize()
    try database.execute("PRAGMA foreign_keys = ON")

    let group = SQLiteGroupDAOFixture.group(name: "group", sortOrder: 0)
    var item = ClipboardItem.debugText(
        "grouped",
        createdAt: Date(timeIntervalSince1970: 100),
        sourceApp: .clipease
    )
    item.groupID = group.id
    item.groupedAt = Date(timeIntervalSince1970: 200)

    try SQLiteGroupDAO.insert(group, in: database)
    try SQLiteItemDAO.insert(item, in: database)
    try SQLiteGroupDAO.insertGroupItem(for: item, in: database)

    #expect(try database.queryInt("SELECT COUNT(*) FROM group_items WHERE group_id = ?", values: [.text(group.id.uuidString)]) == 1)
    let row = try #require(database.query("SELECT created_at, sort_order FROM group_items").first)
    #expect(row.requiredDouble("created_at") == 200)
    #expect(row.requiredInt("sort_order") == 0)

    try SQLiteGroupDAO.deleteGroups(with: [group.id], in: database)
    #expect(try database.queryInt("SELECT COUNT(*) FROM group_items WHERE group_id = ?", values: [.text(group.id.uuidString)]) == 0)
}

private struct SQLiteGroupDAOFixture {
    let directory: URL
    let databaseURL: URL
    let store: SQLiteClipboardStore

    static func make() throws -> SQLiteGroupDAOFixture {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("clipease-group-dao-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let databaseURL = directory.appendingPathComponent("ClipEase.sqlite")
        return SQLiteGroupDAOFixture(
            directory: directory,
            databaseURL: databaseURL,
            store: SQLiteClipboardStore(databaseURL: databaseURL)
        )
    }

    static func group(
        id: UUID = UUID(),
        name: String,
        sortOrder: Int,
        createdAt: Date = Date(timeIntervalSince1970: 100),
        updatedAt: Date = Date(timeIntervalSince1970: 200)
    ) -> ClipboardGroup {
        ClipboardGroup(
            id: id,
            name: name,
            colorHex: "#0A84FF",
            iconName: "tray.full",
            sortOrder: sortOrder,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}
