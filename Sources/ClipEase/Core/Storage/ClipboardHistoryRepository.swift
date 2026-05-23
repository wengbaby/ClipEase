import Foundation

struct ClipboardHistorySnapshot: Sendable {
    var items: [ClipboardItem]
    var groups: [ClipboardGroup]
}

protocol ClipboardHistoryRepository {
    func loadSnapshot() throws -> ClipboardHistorySnapshot
    func loadSnapshot(itemLimit: Int, offset: Int) throws -> ClipboardHistorySnapshot
    func loadItems(limit: Int, offset: Int) throws -> [ClipboardItem]
    func loadItems(contentHash: String, sourceBundleID: String?) throws -> [ClipboardItem]
    func saveSnapshot(_ snapshot: ClipboardHistorySnapshot) throws
    func upsertItem(_ item: ClipboardItem, deleting deletedIDs: Set<ClipboardItem.ID>, groups: [ClipboardGroup]) throws
    func deleteItems(with ids: Set<ClipboardItem.ID>, deletingGroups groupIDs: Set<ClipboardGroup.ID>) throws
    func deleteAllItemsAndGroups() throws
}

extension ClipboardHistoryRepository {
    func loadItems() throws -> [ClipboardItem] {
        try loadSnapshot().items
    }

    func loadSnapshot(itemLimit: Int, offset: Int) throws -> ClipboardHistorySnapshot {
        ClipboardHistorySnapshot(
            items: try loadItems(limit: itemLimit, offset: offset),
            groups: try loadSnapshot().groups
        )
    }

    func loadItems(limit: Int, offset: Int) throws -> [ClipboardItem] {
        let boundedLimit = max(0, limit)
        let boundedOffset = max(0, offset)
        guard boundedLimit > 0 else {
            return []
        }

        return Array(try loadSnapshot().items.dropFirst(boundedOffset).prefix(boundedLimit))
    }

    func loadItems(contentHash: String, sourceBundleID: String?) throws -> [ClipboardItem] {
        try loadSnapshot().items.filter {
            $0.contentHash == contentHash && $0.sourceBundleID == sourceBundleID
        }
    }

    func saveItems(_ items: [ClipboardItem]) throws {
        try saveSnapshot(ClipboardHistorySnapshot(items: items, groups: []))
    }

    func upsertItem(_ item: ClipboardItem, deleting deletedIDs: Set<ClipboardItem.ID>, groups: [ClipboardGroup]) throws {
        var snapshot = try loadSnapshot()
        snapshot.items.removeAll { deletedIDs.contains($0.id) || $0.id == item.id }
        snapshot.items.insert(item, at: 0)
        snapshot.groups = groups
        try saveSnapshot(snapshot)
    }

    func deleteItems(with ids: Set<ClipboardItem.ID>, deletingGroups groupIDs: Set<ClipboardGroup.ID>) throws {
        guard !ids.isEmpty || !groupIDs.isEmpty else {
            return
        }

        var snapshot = try loadSnapshot()
        snapshot.items.removeAll { ids.contains($0.id) }
        snapshot.groups.removeAll { groupIDs.contains($0.id) }
        try saveSnapshot(snapshot)
    }

    func deleteAllItemsAndGroups() throws {
        try saveSnapshot(ClipboardHistorySnapshot(items: [], groups: []))
    }
}
