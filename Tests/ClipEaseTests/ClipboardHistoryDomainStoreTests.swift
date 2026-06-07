import Foundation
import Testing
@testable import ClipEase

@Test func clipboardHistoryDomainStoreRebuildsIndexesAndGroupCounts() {
    let groupID = UUID()
    let ungrouped = ClipboardItem.text("ungrouped", sourceApp: .clipease)
    var grouped = ClipboardItem.text("grouped", sourceApp: .clipease)
    grouped.groupID = groupID

    var domainStore = ClipboardHistoryDomainStore()
    domainStore.rebuildIndexes(for: [ungrouped, grouped])

    #expect(domainStore.itemIndex(for: ungrouped.id, in: [ungrouped, grouped]) == 0)
    #expect(domainStore.itemIndex(for: grouped.id, in: [ungrouped, grouped]) == 1)
    #expect(domainStore.itemCount(inGroup: groupID) == 1)
}

@Test func clipboardHistoryDomainStoreRepairsStaleItemIndex() {
    let first = ClipboardItem.text("first", sourceApp: .clipease)
    let second = ClipboardItem.text("second", sourceApp: .clipease)

    var domainStore = ClipboardHistoryDomainStore()
    domainStore.rebuildIndexes(for: [first, second])

    #expect(domainStore.itemIndex(for: first.id, in: [second, first]) == 1)
    #expect(domainStore.itemIndex(for: second.id, in: [second, first]) == 0)
}

@Test func clipboardHistoryDomainStoreTracksRecentHashes() {
    let first = ClipboardItem.text("first", sourceApp: .clipease)
    let second = ClipboardItem.text("second", sourceApp: .clipease)

    var domainStore = ClipboardHistoryDomainStore()
    domainStore.rebuildRecentHashes(for: [first])
    domainStore.addRecentHash(for: second)

    #expect(domainStore.itemIDs(forContentKey: DuplicateResolver.contentKey(for: first)) == [first.id])
    #expect(domainStore.itemIDs(forContentKey: DuplicateResolver.contentKey(for: second)) == [second.id])

    domainStore.removeRecentHashes(for: [first])

    #expect(domainStore.itemIDs(forContentKey: DuplicateResolver.contentKey(for: first)).isEmpty)
    #expect(domainStore.itemIDs(forContentKey: DuplicateResolver.contentKey(for: second)) == [second.id])
}

@Test func clipboardHistoryDomainStoreUpdatesGroupCountOnMove() {
    let oldID = UUID()
    let newID = UUID()
    var item = ClipboardItem.text("grouped", sourceApp: .clipease)
    item.groupID = oldID

    var domainStore = ClipboardHistoryDomainStore()
    domainStore.rebuildIndexes(for: [item])

    domainStore.updateGroupCountOnMove(from: oldID, to: newID)

    #expect(domainStore.itemCount(inGroup: oldID) == 0)
    #expect(domainStore.itemCount(inGroup: newID) == 1)
}
