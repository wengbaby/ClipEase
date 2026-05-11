import Foundation
import AppKit

@MainActor
final class ClipboardHistoryStore: ObservableObject {
    @Published private(set) var items: [ClipboardItem] = []
    @Published var retentionPolicy: HistoryRetentionPolicy {
        didSet {
            userDefaults.set(retentionPolicy.rawValue, forKey: Self.retentionPolicyKey)
            pruneExpiredItems()
            save()
        }
    }

    private static let retentionPolicyKey = "history.retentionPolicy"
    private let persistence: ClipboardHistoryPersistence
    private let userDefaults: UserDefaults
    private var recentHashes: Set<String> = []
    private var skippedClipboardTexts: Set<String> = []
    private var skippedImageHashes: Set<String> = []

    init(
        persistence: ClipboardHistoryPersistence = ClipboardHistoryPersistence(),
        userDefaults: UserDefaults = .standard
    ) {
        self.persistence = persistence
        self.userDefaults = userDefaults
        self.retentionPolicy = HistoryRetentionPolicy(
            rawValue: userDefaults.integer(forKey: Self.retentionPolicyKey)
        ) ?? .forever
        self.items = persistence.loadItems()
        sortItems()
        pruneExpiredItems()
        save()
        rebuildRecentHashes()
    }

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
        if let hex = ColorParser.hexColor(from: normalizedText) {
            item = .color(hex, sourceApp: sourceApp)
        } else if let url = URLParser.url(from: normalizedText) {
            item = .link(url, originalText: normalizedText, sourceApp: sourceApp)
        } else {
            item = .text(normalizedText, sourceApp: sourceApp)
        }

        items.insert(item, at: 0)
        sortItems()
        pruneExpiredItems()
        save()
    }

    func addRichText(_ data: Data, plainText: String, sourceApp: SourceAppInfo) {
        let normalizedText = plainText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedText.isEmpty,
              let storedRichText = persistence.saveRichText(data) else {
            return
        }

        let hash = "\(sourceApp.bundleID ?? "unknown"):\(normalizedText):\(storedRichText.fileName)"
        recentHashes.insert(hash)

        let item = ClipboardItem.richText(
            plainText: normalizedText,
            fileName: storedRichText.fileName,
            sourceApp: sourceApp
        )
        items.insert(item, at: 0)
        sortItems()
        pruneExpiredItems()
        save()
    }

    func addImage(_ image: NSImage, sourceApp: SourceAppInfo) {
        guard let storedImage = persistence.saveImage(image) else {
            return
        }

        if skippedImageHashes.remove(storedImage.hash) != nil {
            persistence.deleteImage(fileName: storedImage.fileName)
            return
        }

        let hash = "\(sourceApp.bundleID ?? "unknown"):\(storedImage.hash)"
        guard !recentHashes.contains(hash) else {
            persistence.deleteImage(fileName: storedImage.fileName)
            return
        }

        recentHashes.insert(hash)
        let item = ClipboardItem.image(
            fileName: storedImage.fileName,
            width: storedImage.width,
            height: storedImage.height,
            hash: storedImage.hash,
            sourceApp: sourceApp
        )

        items.insert(item, at: 0)
        sortItems()
        pruneExpiredItems()
        save()
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

        let deletedItems = items.filter { $0.id == id }
        items.removeAll { $0.id == id }
        deleteExternalFiles(for: deletedItems)
        rebuildRecentHashes()
        save()
    }

    func clearAllItems() {
        let removedItems = items
        items.removeAll()
        deleteExternalFiles(for: removedItems)
        recentHashes.removeAll()
        skippedClipboardTexts.removeAll()
        skippedImageHashes.removeAll()
        save()
    }

    func importItems(_ importedItems: [ClipboardItem]) -> Int {
        let existingIDs = Set(items.map(\.id))
        let existingTextHashes = Set(items.map(textHash))
        let newItems = importedItems.filter { item in
            !existingIDs.contains(item.id) && !existingTextHashes.contains(textHash(for: item))
        }

        guard !newItems.isEmpty else {
            return 0
        }

        items.append(contentsOf: newItems)
        sortItems()
        pruneExpiredItems()
        rebuildRecentHashes()
        save()
        return newItems.count
    }

    func importBackupItems(_ importedItems: [ClipboardItem]) -> Int {
        importItems(importedItems)
    }

    func togglePinned(for id: ClipboardItem.ID?) {
        guard let id,
              let index = items.firstIndex(where: { $0.id == id }) else {
            return
        }

        items[index].isPinned.toggle()
        items[index].pinnedAt = items[index].isPinned ? Date() : nil
        sortItems()
        save()
    }

    func addDebugTextItems(count: Int) {
        guard count > 0 else {
            return
        }

        let now = Date()
        let sourceApp = SourceAppInfo.clipease
        let newItems = (0..<count).map { index in
            ClipboardItem.debugText(
                "轻贴性能测试文本 \(index + 1) keyword-\(index % 25) 搜索测试 \(UUID().uuidString)",
                createdAt: now.addingTimeInterval(TimeInterval(-index)),
                sourceApp: sourceApp
            )
        }

        items.insert(contentsOf: newItems, at: 0)
        sortItems()
        pruneExpiredItems()
        rebuildRecentHashes()
        save()
    }

    func skipNextClipboardText(_ text: String) {
        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedText.isEmpty else {
            return
        }

        skippedClipboardTexts.insert(normalizedText)
    }

    func skipNextClipboardImage(_ item: ClipboardItem) {
        guard let imageHash = item.imageHash else {
            return
        }

        skippedImageHashes.insert(imageHash)
    }

    func imageData(for item: ClipboardItem) -> Data? {
        guard let fileName = item.imageFileName else {
            return nil
        }

        return persistence.imageData(fileName: fileName)
    }

    func thumbnailImage(for item: ClipboardItem) -> NSImage? {
        guard let fileName = item.imageFileName else {
            return nil
        }

        return persistence.thumbnailImage(fileName: fileName)
    }

    func richTextData(for item: ClipboardItem) -> Data? {
        guard let fileName = item.richTextFileName else {
            return nil
        }

        return persistence.richTextData(fileName: fileName)
    }

    func imageFileURL(for item: ClipboardItem) -> URL? {
        guard let fileName = item.imageFileName else {
            return nil
        }

        return try? ClipEaseStoragePaths.imageFileURL(fileName: fileName)
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

    private func save() {
        persistence.saveItems(items)
    }

    private func rebuildRecentHashes() {
        recentHashes = Set(items.map(textHash))
    }

    private func textHash(for item: ClipboardItem) -> String {
        switch item.type {
        case .image:
            "\(item.sourceBundleID ?? "unknown"):\(item.imageHash ?? item.id.uuidString)"
        case .text, .link, .color:
            "\(item.sourceBundleID ?? "unknown"):\(item.text)"
        }
    }

    private func pruneExpiredItems(now: Date = Date()) {
        guard let days = retentionPolicy.days else {
            return
        }

        let cutoffDate = Calendar.current.date(
            byAdding: .day,
            value: -days,
            to: now
        ) ?? now
        let removedItems = items.filter { item in
            !item.isPinned && item.createdAt < cutoffDate
        }

        guard !removedItems.isEmpty else {
            return
        }

        items.removeAll { item in
            !item.isPinned && item.createdAt < cutoffDate
        }
        deleteExternalFiles(for: removedItems)
        rebuildRecentHashes()
    }

    private func deleteExternalFiles(for items: [ClipboardItem]) {
        items.compactMap(\.imageFileName).forEach(persistence.deleteImage)
        items.compactMap(\.richTextFileName).forEach(persistence.deleteRichText)
    }
}
