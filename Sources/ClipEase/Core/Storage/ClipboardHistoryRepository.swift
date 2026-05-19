import Foundation

struct ClipboardHistorySnapshot: Sendable {
    var items: [ClipboardItem]
    var groups: [ClipboardGroup]
}

protocol ClipboardHistoryRepository {
    func loadSnapshot() throws -> ClipboardHistorySnapshot
    func saveSnapshot(_ snapshot: ClipboardHistorySnapshot) throws
}

extension ClipboardHistoryRepository {
    func loadItems() throws -> [ClipboardItem] {
        try loadSnapshot().items
    }

    func saveItems(_ items: [ClipboardItem]) throws {
        try saveSnapshot(ClipboardHistorySnapshot(items: items, groups: []))
    }
}
