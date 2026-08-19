import Foundation
import Combine
import Testing
@testable import ClipEase

@Test @MainActor
func historyStoreRoutesPinMetadataLinkAndGroupChangesThroughNarrowMutations() async {
    let group = ClipboardGroup.makeDefault(name: "Work", sortOrder: 0)
    var regular = ClipboardItem.text("regular", sourceApp: .clipease)
    regular.createdAt = Date(timeIntervalSince1970: 100)
    let linkURL = URL(string: "https://example.com/article")!
    let link = ClipboardItem.link(
        linkURL,
        originalText: linkURL.absoluteString,
        sourceApp: .clipease
    )
    let grouped = ClipboardItem.text("group me", sourceApp: .clipease)
    let repository = StoreNarrowMutationRecordingRepository(
        snapshot: ClipboardHistorySnapshot(
            items: [regular, link, grouped],
            groups: [group]
        )
    )
    let persistence = ClipboardHistoryPersistence(repository: repository)
    let writer = ClipboardHistorySaveWriter(
        persistence: persistence,
        batchPolicy: ClipboardHistoryWriteBatchPolicy(
            maximumDelayMilliseconds: 60_000,
            maximumMutationCount: 50
        )
    )
    let defaults = makeStoreNarrowMutationDefaults()
    defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
    let store = ClipboardHistoryStore(
        persistence: persistence,
        userDefaults: defaults,
        saveWriter: writer,
        externalCopyFeedback: { _ in }
    )

    store.markUsed(regular.id)
    store.togglePinned(for: regular.id)
    #expect(store.applyLinkMetadata(
        title: "Updated searchable title",
        storedImage: nil,
        for: link.id,
        url: linkURL
    ))
    store.addItem(grouped.id, toGroup: group.id)

    let result = await store.makeTerminationDrainHandle().drain()

    #expect(result.committedMutationCount == 3)
    let updates = repository.mutations.compactMap { mutation -> ClipboardHistoryItemMutation? in
        guard case .update(let update) = mutation else {
            return nil
        }
        return update
    }
    #expect(updates.count == 3)
    #expect(updates.first(where: { $0.item.id == regular.id })?.fields == [.metadata, .pin])
    #expect(updates.first(where: { $0.item.id == link.id })?.fields == [.metadata])
    #expect(updates.first(where: { $0.item.id == grouped.id })?.fields == [.group])
    #expect(repository.saveSnapshotCount == 0)
}

@Test @MainActor
func historyStoreTerminationHandleSealsProducersAndOnlyDrainsIncrementalWrites() async {
    let repository = StoreNarrowMutationRecordingRepository(
        snapshot: ClipboardHistorySnapshot(items: [], groups: [])
    )
    let persistence = ClipboardHistoryPersistence(repository: repository)
    let writer = ClipboardHistorySaveWriter(
        persistence: persistence,
        batchPolicy: ClipboardHistoryWriteBatchPolicy(
            maximumDelayMilliseconds: 60_000,
            maximumMutationCount: 50
        )
    )
    let defaults = makeStoreNarrowMutationDefaults()
    defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
    let store = ClipboardHistoryStore(
        persistence: persistence,
        userDefaults: defaults,
        saveWriter: writer,
        externalCopyFeedback: { _ in }
    )

    store.addText("before-seal", sourceApp: .clipease)
    _ = store.createGroup()
    let handle = store.makeTerminationDrainHandle()
    store.addText("after-seal", sourceApp: .clipease)

    let result = await Task.detached {
        await handle.drain()
    }.value
    await Task.yield()

    #expect(result.committedMutationCount == 1)
    #expect(repository.mutations.map(\.item.text) == ["before-seal"])
    #expect(repository.saveSnapshotCount == 0)
}

@Test @MainActor
func historyStoreImmediateTerminationDrainsGroupsImportsAndEditableContentInOrder() async throws {
    var editable = ClipboardItem.richText(
        plainText: "before edit",
        fileName: "before-edit.rtf",
        sourceApp: .clipease
    )
    editable.createdAt = Date(timeIntervalSince1970: 100)
    let repository = StoreNarrowMutationRecordingRepository(
        snapshot: ClipboardHistorySnapshot(items: [editable], groups: [])
    )
    let persistence = ClipboardHistoryPersistence(repository: repository)
    let writer = ClipboardHistorySaveWriter(
        persistence: persistence,
        batchPolicy: ClipboardHistoryWriteBatchPolicy(
            maximumDelayMilliseconds: 60_000,
            maximumMutationCount: 50
        )
    )
    let defaults = makeStoreNarrowMutationDefaults()
    defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
    let store = ClipboardHistoryStore(
        persistence: persistence,
        userDefaults: defaults,
        saveWriter: writer,
        externalCopyFeedback: { _ in }
    )

    let plainImport = ClipboardItem.text("plain import", sourceApp: .clipease)
    #expect(store.importItems([plainImport]) == 1)

    let backupGroup = ClipboardGroup.makeDefault(name: "Backup", sortOrder: 0)
    var groupedImport = ClipboardItem.text("grouped import", sourceApp: .clipease)
    groupedImport.groupID = backupGroup.id
    groupedImport.groupedAt = groupedImport.createdAt
    #expect(store.importBackupItems([groupedImport], groups: [backupGroup]) == 1)

    let createdGroup = store.createGroup()
    #expect(store.renameGroup(createdGroup.id, name: "Renamed") == .renamed)
    store.updateGroupAppearance(
        createdGroup.id,
        colorHex: "#FF375F",
        iconName: "heart.fill"
    )
    store.moveGroup(fromOffsets: IndexSet(integer: 1), toOffset: 0)
    let edited = try #require(
        store.updateEditableContent(for: editable.id, text: "after edit")
    )

    let result = await store.makeTerminationDrainHandle().drain()
    let persisted = repository.persistedSnapshot
    let events = repository.events

    #expect(!result.requiresFullResync)
    #expect(repository.saveSnapshotCount == 0)
    #expect(persisted.groups == store.groups)
    #expect(persisted.items.contains { $0.id == plainImport.id })
    #expect(persisted.items.contains { $0.id == groupedImport.id && $0.groupID == backupGroup.id })
    #expect(persisted.items.first(where: { $0.id == editable.id })?.text == "after edit")
    #expect(
        repository.mutations.compactMap { mutation -> ClipboardHistoryItemMutation? in
            guard case .update(let update) = mutation,
                  update.item.id == edited.id else {
                return nil
            }
            return update
        }.last?.fields == [.content, .metadata]
    )

    let groupBarrierIndex = try #require(events.firstIndex { event in
        guard case .groups(let ids) = event else { return false }
        return ids.contains(backupGroup.id)
    })
    let groupedInsertIndex = try #require(events.firstIndex { event in
        guard case .insert(let ids) = event else { return false }
        return ids.contains(groupedImport.id)
    })
    #expect(groupBarrierIndex < groupedInsertIndex)
}

private final class StoreNarrowMutationRecordingRepository: ClipboardHistoryRepository, @unchecked Sendable {
    enum Event: Equatable {
        case groups([ClipboardGroup.ID])
        case insert([ClipboardItem.ID])
        case mutations([ClipboardItem.ID])
    }

    private let lock = NSLock()
    private var snapshot: ClipboardHistorySnapshot
    private var storedMutations: [ClipboardHistoryRepositoryMutation] = []
    private var storedEvents: [Event] = []
    private var storedSaveSnapshotCount = 0

    init(snapshot: ClipboardHistorySnapshot) {
        self.snapshot = snapshot
    }

    var mutations: [ClipboardHistoryRepositoryMutation] {
        lock.withLock { storedMutations }
    }

    var saveSnapshotCount: Int {
        lock.withLock { storedSaveSnapshotCount }
    }

    var persistedSnapshot: ClipboardHistorySnapshot {
        lock.withLock { snapshot }
    }

    var events: [Event] {
        lock.withLock { storedEvents }
    }

    func loadSnapshot() throws -> ClipboardHistorySnapshot {
        lock.withLock { snapshot }
    }

    func saveSnapshot(_ snapshot: ClipboardHistorySnapshot) throws {
        lock.withLock {
            self.snapshot = snapshot
            storedSaveSnapshotCount += 1
        }
    }

    func upsertItem(
        _ item: ClipboardItem,
        deleting deletedIDs: Set<ClipboardItem.ID>,
        groups: [ClipboardGroup]
    ) throws {
        lock.withLock {
            snapshot.items.removeAll { deletedIDs.contains($0.id) || $0.id == item.id }
            snapshot.items.insert(item, at: 0)
            snapshot.groups = groups
        }
    }

    func upsertGroups(_ groups: [ClipboardGroup]) throws {
        lock.withLock {
            snapshot.groups = groups
            storedEvents.append(.groups(groups.map(\.id)))
        }
    }

    func insertItems(_ items: [ClipboardItem]) throws {
        lock.withLock {
            let insertedIDs = Set(items.map(\.id))
            snapshot.items.removeAll { insertedIDs.contains($0.id) }
            snapshot.items.insert(contentsOf: items, at: 0)
            storedEvents.append(.insert(items.map(\.id)))
        }
    }

    func applyMutations(_ mutations: [ClipboardHistoryRepositoryMutation]) throws {
        lock.withLock {
            storedMutations.append(contentsOf: mutations)
            storedEvents.append(.mutations(mutations.map(\.itemID)))
            for mutation in mutations {
                switch mutation {
                case .upsert(let upsert):
                    snapshot.items.removeAll {
                        upsert.deletedIDs.contains($0.id) || $0.id == upsert.item.id
                    }
                    snapshot.items.insert(upsert.item, at: 0)
                    snapshot.groups = upsert.groups
                case .update(let update):
                    guard let index = snapshot.items.firstIndex(where: { $0.id == update.item.id }) else {
                        continue
                    }
                    snapshot.items[index] = update.item
                }
            }
        }
    }
}

private func makeStoreNarrowMutationDefaults() -> UserDefaults {
    let suiteName = "store-narrow-mutation-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.set(suiteName, forKey: "tests.suiteName")
    defaults.set(HistoryRetentionPolicy.forever.rawValue, forKey: "history.retentionPolicy")
    return defaults
}

private func defaultsSuiteName(_ defaults: UserDefaults) -> String {
    defaults.string(forKey: "tests.suiteName")!
}

@Test @MainActor
func storeRemoveItemFromGroupUpdatesInMemoryItemsAndNotifies() async {
    let group = ClipboardGroup.makeDefault(name: "Work", sortOrder: 0)
    var grouped = ClipboardItem.text("group me", sourceApp: .clipease)
    grouped.createdAt = Date(timeIntervalSince1970: 100)
    grouped.groupID = group.id
    grouped.groupedAt = Date()
    let regular = ClipboardItem.text("regular", sourceApp: .clipease)

    let repository = StoreNarrowMutationRecordingRepository(
        snapshot: ClipboardHistorySnapshot(items: [grouped, regular], groups: [group])
    )
    let persistence = ClipboardHistoryPersistence(repository: repository)
    let writer = ClipboardHistorySaveWriter(
        persistence: persistence,
        batchPolicy: ClipboardHistoryWriteBatchPolicy(
            maximumDelayMilliseconds: 60_000,
            maximumMutationCount: 50
        )
    )
    let defaults = makeStoreNarrowMutationDefaults()
    defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
    let store = ClipboardHistoryStore(
        persistence: persistence,
        userDefaults: defaults,
        saveWriter: writer,
        externalCopyFeedback: { _ in }
    )

    var receivedItems: [[ClipboardItem]] = []
    let cancellable = store.$items.sink { items in
        receivedItems.append(items)
    }

    #expect(store.item(with: grouped.id)?.groupID == group.id)

    store.removeItemFromGroup(grouped.id)

    #expect(store.item(with: grouped.id)?.groupID == nil)
    #expect(store.item(with: grouped.id)?.groupedAt == nil)

    let lastReceived = receivedItems.last
    #expect(lastReceived?.first(where: { $0.id == grouped.id })?.groupID == nil)

    cancellable.cancel()
    _ = await store.makeTerminationDrainHandle().drain()
}
