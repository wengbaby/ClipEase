import Foundation

struct ClipboardHistorySnapshot: Sendable {
    var items: [ClipboardItem]
    var groups: [ClipboardGroup]
}

struct ClipboardSearchQuery: Sendable, Equatable {
    var text: String
    var limit: Int
    var offset: Int

    init(text: String, limit: Int = 500, offset: Int = 0) {
        self.text = text
        self.limit = limit
        self.offset = max(0, offset)
    }
}

protocol ClipboardHistoryRepository {
    func loadSnapshot() throws -> ClipboardHistorySnapshot
    func loadSnapshot(itemLimit: Int, offset: Int) throws -> ClipboardHistorySnapshot
    func loadItems(limit: Int, offset: Int) throws -> [ClipboardItem]
    func loadItems(contentHash: String, sourceBundleID: String?) throws -> [ClipboardItem]
    func prepareSearchIndex() throws
    func searchItems(_ query: ClipboardSearchQuery) throws -> [ClipboardItem]
    func saveSnapshot(_ snapshot: ClipboardHistorySnapshot) throws
    func insertItems(_ items: [ClipboardItem]) throws
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

    func prepareSearchIndex() throws {}

    func searchItems(_ query: ClipboardSearchQuery) throws -> [ClipboardItem] {
        let normalizedQuery = query.text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        guard !normalizedQuery.isEmpty,
              query.limit > 0 else {
            return []
        }

        var result: [ClipboardItem] = []
        result.reserveCapacity(min(max(query.limit, 0), 500))
        var skippedMatches = 0
        for item in try loadSnapshot().items {
            guard item.cardSearchText.contains(normalizedQuery) else {
                continue
            }

            if skippedMatches < query.offset {
                skippedMatches += 1
                continue
            }

            result.append(item)
            if result.count >= query.limit {
                break
            }
        }
        return result
    }

    func saveItems(_ items: [ClipboardItem]) throws {
        try saveSnapshot(ClipboardHistorySnapshot(items: items, groups: []))
    }

    func insertItems(_ items: [ClipboardItem]) throws {
        guard !items.isEmpty else {
            return
        }

        var snapshot = try loadSnapshot()
        snapshot.items.insert(contentsOf: items, at: 0)
        try saveSnapshot(snapshot)
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

extension ClipboardItem {
    var cardSearchText: String {
        [
            preview,
            linkTitle,
            linkSubtitle,
            fileReferences.map(\.displayName).joined(separator: " "),
            fileReferences.map(\.path).joined(separator: " "),
            ocrText,
            ocrEmails.joined(separator: " "),
            ocrPhoneNumbers.joined(separator: " "),
            ocrURLs.joined(separator: " ")
        ]
        .compactMap { $0 }
        .joined(separator: " ")
        .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}
