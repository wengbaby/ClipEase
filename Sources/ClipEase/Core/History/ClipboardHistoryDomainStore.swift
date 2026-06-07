import Foundation

struct ClipboardHistoryDomainStore {
    private var itemIndexByID: [ClipboardItem.ID: Int] = [:]
    private var itemCountByGroupID: [ClipboardGroup.ID: Int] = [:]
    private var itemIDsByHash: [String: Set<ClipboardItem.ID>] = [:]

    var recentHashCount: Int {
        itemIDsByHash.count
    }

    func cachedItemIndex(for id: ClipboardItem.ID, in items: [ClipboardItem]) -> Int? {
        guard let index = itemIndexByID[id],
              items.indices.contains(index),
              items[index].id == id else {
            return nil
        }

        return index
    }

    mutating func itemIndex(for id: ClipboardItem.ID, in items: [ClipboardItem]) -> Int? {
        guard let index = cachedItemIndex(for: id, in: items) else {
            rebuildIndexes(for: items)
            return cachedItemIndex(for: id, in: items)
        }

        return index
    }

    mutating func rebuildIndexes(for items: [ClipboardItem]) {
        var indexByID: [ClipboardItem.ID: Int] = [:]
        var countByGroupID: [ClipboardGroup.ID: Int] = [:]
        indexByID.reserveCapacity(items.count)

        for (index, item) in items.enumerated() {
            indexByID[item.id] = index
            if let groupID = item.groupID {
                countByGroupID[groupID, default: 0] += 1
            }
        }

        itemIndexByID = indexByID
        itemCountByGroupID = countByGroupID
    }

    mutating func updateIndexes(startingAt startIndex: Int, in items: [ClipboardItem]) {
        let safeStartIndex = max(items.startIndex, min(startIndex, items.endIndex))
        for index in safeStartIndex..<items.endIndex {
            itemIndexByID[items[index].id] = index
        }
    }

    func itemCount(inGroup id: ClipboardGroup.ID) -> Int {
        itemCountByGroupID[id] ?? 0
    }

    mutating func updateGroupCountOnMove(
        from oldGroupID: ClipboardGroup.ID?,
        to newGroupID: ClipboardGroup.ID?
    ) {
        GroupService.updateGroupCountOnMove(
            from: oldGroupID,
            to: newGroupID,
            countByGroupID: &itemCountByGroupID
        )
    }

    mutating func incrementGroupCount(for groupID: ClipboardGroup.ID?) {
        guard let groupID else {
            return
        }

        itemCountByGroupID[groupID, default: 0] += 1
    }

    func itemIDs(forContentKey hash: String) -> Set<ClipboardItem.ID> {
        itemIDsByHash[hash] ?? []
    }

    mutating func removeAllRecentHashes() {
        itemIDsByHash.removeAll()
    }

    mutating func rebuildRecentHashes(for items: [ClipboardItem]) {
        var idsByHash: [String: Set<ClipboardItem.ID>] = [:]
        idsByHash.reserveCapacity(items.count)
        for item in items {
            idsByHash[DuplicateResolver.contentKey(for: item), default: []].insert(item.id)
        }
        itemIDsByHash = idsByHash
    }

    mutating func addRecentHash(for item: ClipboardItem) {
        itemIDsByHash[DuplicateResolver.contentKey(for: item), default: []].insert(item.id)
    }

    mutating func removeRecentHashes(for removedItems: [ClipboardItem]) {
        for item in removedItems {
            let hash = DuplicateResolver.contentKey(for: item)
            itemIDsByHash[hash]?.remove(item.id)
            if itemIDsByHash[hash]?.isEmpty == true {
                itemIDsByHash[hash] = nil
            }
        }
    }
}
