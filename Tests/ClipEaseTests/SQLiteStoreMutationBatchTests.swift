import Foundation
import Testing
@testable import ClipEase

@Test func sqliteStoreMutationBatchAppliesUpsertThenNarrowUpdateInOrder() throws {
    let fixture = try SQLiteStoreMutationBatchFixture.make()
    defer { fixture.remove() }

    let inserted = ClipboardItem.debugText(
        "ordered batch",
        createdAt: Date(timeIntervalSince1970: 100),
        sourceApp: .clipease
    )
    var pinned = inserted
    pinned.isPinned = true
    pinned.pinnedAt = Date(timeIntervalSince1970: 200)

    try fixture.store.applyMutations([
        .upsert(
            ClipboardHistoryUpsertMutation(
                item: inserted,
                deletedIDs: [],
                groups: []
            )
        ),
        .update(
            ClipboardHistoryItemMutation(
                item: pinned,
                fields: [.pin]
            )
        )
    ])

    let loaded = try #require(
        fixture.store.loadItems(limit: 10, offset: 0).first
    )
    #expect(loaded.id == inserted.id)
    #expect(loaded.isPinned)
    #expect(loaded.pinnedAt == pinned.pinnedAt)
}

@Test func sqliteStoreMutationBatchRollsBackEveryEarlierMutationOnFailure() throws {
    let fixture = try SQLiteStoreMutationBatchFixture.make()
    defer { fixture.remove() }

    var stored = ClipboardItem.debugText(
        "stored",
        createdAt: Date(timeIntervalSince1970: 100),
        sourceApp: .clipease
    )
    try fixture.store.insertItems([stored])

    stored.isPinned = true
    stored.pinnedAt = Date(timeIntervalSince1970: 200)
    let missing = ClipboardItem.debugText(
        "missing",
        createdAt: Date(timeIntervalSince1970: 300),
        sourceApp: .clipease
    )

    #expect(throws: SQLiteItemMutationError.self) {
        try fixture.store.applyMutations([
            .update(
                ClipboardHistoryItemMutation(
                    item: stored,
                    fields: [.pin]
                )
            ),
            .update(
                ClipboardHistoryItemMutation(
                    item: missing,
                    fields: [.pin]
                )
            )
        ])
    }

    let loaded = try #require(
        fixture.store.loadItems(limit: 10, offset: 0)
            .first(where: { $0.id == stored.id })
    )
    #expect(!loaded.isPinned)
    #expect(loaded.pinnedAt == nil)
}

@Test func sqliteStoreMutationBatchesReuseTheResidentWriterConnection() throws {
    let fixture = try SQLiteStoreMutationBatchFixture.make()
    defer { fixture.remove() }

    let item = ClipboardItem.debugText(
        "resident writer",
        createdAt: Date(timeIntervalSince1970: 100),
        sourceApp: .clipease
    )
    try fixture.store.applyMutations([
        .upsert(
            ClipboardHistoryUpsertMutation(
                item: item,
                deletedIDs: [],
                groups: []
            )
        )
    ])

    var pinned = item
    pinned.isPinned = true
    pinned.pinnedAt = Date(timeIntervalSince1970: 200)
    try fixture.store.applyMutations([
        .update(
            ClipboardHistoryItemMutation(
                item: pinned,
                fields: [.pin]
            )
        )
    ])

    #expect(fixture.store.coordinatedWriterConnectionCount == 1)
}

private struct SQLiteStoreMutationBatchFixture {
    let directory: URL
    let store: SQLiteClipboardStore

    static func make() throws -> SQLiteStoreMutationBatchFixture {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("clipease-store-mutation-batch-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return SQLiteStoreMutationBatchFixture(
            directory: directory,
            store: SQLiteClipboardStore(
                databaseURL: directory.appendingPathComponent("ClipEase.sqlite")
            )
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}
