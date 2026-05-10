import Foundation

@MainActor
final class ClipboardHistoryStore: ObservableObject {
    @Published private(set) var items: [ClipboardItem] = []

    private let maxInMemoryItems = 80
    private var recentHashes: Set<String> = []
    private var skippedClipboardTexts: Set<String> = []

    func addText(_ text: String, sourceApp: SourceAppInfo) {
        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedText.isEmpty else {
            return
        }

        if skippedClipboardTexts.remove(normalizedText) != nil {
            return
        }

        let hash = "\(sourceApp.bundleID ?? "unknown"):\(normalizedText)"
        guard !recentHashes.contains(hash) else {
            return
        }

        recentHashes.insert(hash)

        let item: ClipboardItem
        if let url = URLParser.url(from: normalizedText) {
            item = .link(url, originalText: normalizedText, sourceApp: sourceApp)
        } else {
            item = .text(normalizedText, sourceApp: sourceApp)
        }

        items.insert(item, at: 0)
        sortItems()
        if items.count > maxInMemoryItems {
            items.removeLast(items.count - maxInMemoryItems)
        }
    }

    func item(with id: ClipboardItem.ID?) -> ClipboardItem? {
        guard let id else {
            return nil
        }

        return items.first { $0.id == id }
    }

    func deleteItem(with id: ClipboardItem.ID?) {
        guard let id else {
            return
        }

        items.removeAll { $0.id == id }
    }

    func togglePinned(for id: ClipboardItem.ID?) {
        guard let id,
              let index = items.firstIndex(where: { $0.id == id }) else {
            return
        }

        items[index].isPinned.toggle()
        items[index].pinnedAt = items[index].isPinned ? Date() : nil
        sortItems()
    }

    func skipNextClipboardText(_ text: String) {
        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedText.isEmpty else {
            return
        }

        skippedClipboardTexts.insert(normalizedText)
    }

    private func sortItems() {
        items.sort { lhs, rhs in
            if lhs.isPinned != rhs.isPinned {
                return lhs.isPinned && !rhs.isPinned
            }

            if lhs.isPinned, rhs.isPinned {
                return (lhs.pinnedAt ?? lhs.createdAt) > (rhs.pinnedAt ?? rhs.createdAt)
            }

            return lhs.createdAt > rhs.createdAt
        }
    }
}
