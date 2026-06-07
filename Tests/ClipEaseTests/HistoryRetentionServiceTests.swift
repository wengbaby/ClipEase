import Foundation
import Testing
@testable import ClipEase

@Test func historyRetentionServiceDoesNotPruneWhenPolicyIsForever() {
    let oldItem = ClipboardItem.retentionFixture(createdAt: Date(timeIntervalSince1970: 0))

    let result = HistoryRetentionService.expiredItems(
        in: [oldItem],
        policy: .forever,
        validGroupIDs: [],
        now: Date(timeIntervalSince1970: 10 * 24 * 60 * 60)
    )

    #expect(result.isEmpty)
}

@Test func historyRetentionServicePrunesOnlyExpiredUngroupedUnpinnedItems() {
    let now = Date(timeIntervalSince1970: 10 * 24 * 60 * 60)
    let old = ClipboardItem.retentionFixture(createdAt: Date(timeIntervalSince1970: 0))
    var pinned = ClipboardItem.retentionFixture(createdAt: Date(timeIntervalSince1970: 0))
    pinned.isPinned = true
    var grouped = ClipboardItem.retentionFixture(createdAt: Date(timeIntervalSince1970: 0))
    grouped.groupID = UUID()
    let recent = ClipboardItem.retentionFixture(createdAt: now.addingTimeInterval(-12 * 60 * 60))

    let result = HistoryRetentionService.expiredItems(
        in: [old, pinned, grouped, recent],
        policy: .oneDay,
        validGroupIDs: [grouped.groupID!],
        now: now
    )

    #expect(result.map(\.id) == [old.id])
}

@Test func historyRetentionServicePrunesItemsInMissingGroups() {
    let now = Date(timeIntervalSince1970: 10 * 24 * 60 * 60)
    var missingGroupItem = ClipboardItem.retentionFixture(createdAt: Date(timeIntervalSince1970: 0))
    missingGroupItem.groupID = UUID()

    let result = HistoryRetentionService.expiredItems(
        in: [missingGroupItem],
        policy: .oneDay,
        validGroupIDs: [],
        now: now
    )

    #expect(result.map(\.id) == [missingGroupItem.id])
}

private extension ClipboardItem {
    static func retentionFixture(createdAt: Date) -> ClipboardItem {
        var item = ClipboardItem.text("retention", sourceApp: .clipease)
        item.createdAt = createdAt
        return item
    }
}
