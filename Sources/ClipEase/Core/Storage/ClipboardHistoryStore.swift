import Foundation
import AppKit

@MainActor
final class ClipboardHistoryStore: ObservableObject {
    @Published private(set) var items: [ClipboardItem] = []
    @Published var retentionPolicy: HistoryRetentionPolicy {
        didSet {
            userDefaults.set(retentionPolicy.rawValue, forKey: Self.retentionPolicyKey)
            pruneExpiredItems()
            saveImmediately()
        }
    }

    nonisolated private static let retentionPolicyKey = "history.retentionPolicy"
    nonisolated private static let debugTextPrefix = "轻贴性能测试文本 "
    nonisolated private static let deferredSaveDelay: UInt64 = 350_000_000
    nonisolated private static let debugBatchSize = 500
    private let persistence: ClipboardHistoryPersistence
    private let saveWriter: ClipboardHistorySaveWriter
    private let userDefaults: UserDefaults
    private var recentHashes: Set<String> = []
    private var skippedClipboardTexts: Set<String> = []
    private var skippedImageHashes: Set<String> = []
    private var deferredSaveTask: Task<Void, Never>?
    private var debugGenerationTask: Task<Void, Never>?
    private var saveRevision = 0

    var debugTextItemCount: Int {
        items.lazy.filter(Self.isDebugTextItem).count
    }

    init(
        persistence: ClipboardHistoryPersistence = ClipboardHistoryPersistence(),
        userDefaults: UserDefaults = .standard
    ) {
        self.persistence = persistence
        self.saveWriter = ClipboardHistorySaveWriter(persistence: persistence)
        self.userDefaults = userDefaults
        self.retentionPolicy = HistoryRetentionPolicy(
            rawValue: userDefaults.integer(forKey: Self.retentionPolicyKey)
        ) ?? .forever
        self.items = persistence.loadItems()
        sortItems()
        pruneExpiredItems()
        saveImmediately()
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
        scheduleSave()

        if item.type == .link,
           item.linkTitle == "/",
           let url = item.url {
            fetchLinkTitle(for: item.id, url: url)
        }
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
        scheduleSave()
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
        scheduleSave()
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
        saveImmediately()
    }

    func clearAllItems() {
        let removedItems = items
        items.removeAll()
        deleteExternalFiles(for: removedItems)
        recentHashes.removeAll()
        skippedClipboardTexts.removeAll()
        skippedImageHashes.removeAll()
        saveImmediately()
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
        scheduleSave()
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
        scheduleSave()
    }

    func markUsed(_ id: ClipboardItem.ID?) {
        guard let id,
              let index = items.firstIndex(where: { $0.id == id }),
              !items[index].isPinned else {
            return
        }

        items[index].createdAt = Date()
        sortItems()
        scheduleSave()
    }

    private func fetchLinkTitle(for id: ClipboardItem.ID, url: URL) {
        Task.detached(priority: .utility) {
            guard let title = await LinkTitleFetcher.title(for: url) else {
                return
            }

            await MainActor.run {
                self.updateLinkTitle(title, for: id)
            }
        }
    }

    private func updateLinkTitle(_ title: String, for id: ClipboardItem.ID) {
        guard let index = items.firstIndex(where: { $0.id == id }),
              items[index].type == .link,
              items[index].linkTitle != title else {
            return
        }

        items[index].linkTitle = title
        scheduleSave()
    }

    func addDebugTextItems(count: Int) {
        guard count > 0 else {
            return
        }

        debugGenerationTask?.cancel()
        let sourceApp = SourceAppInfo.clipease
        debugGenerationTask = Task(priority: .utility) { [weak self] in
            let newItems = await ClipboardHistoryStore.makeDebugTextItems(
                count: count,
                sourceApp: sourceApp
            )

            guard !Task.isCancelled else {
                return
            }

            await MainActor.run {
                guard let self else {
                    return
                }

                self.mergeDebugTextItems(newItems)
                self.debugGenerationTask = nil
            }
        }
    }

    func clearDebugTextItems() -> Int {
        debugGenerationTask?.cancel()
        debugGenerationTask = nil
        let removedItems = items.filter(Self.isDebugTextItem)
        guard !removedItems.isEmpty else {
            return 0
        }

        items.removeAll(where: Self.isDebugTextItem)
        rebuildRecentHashes()
        saveImmediately()
        return removedItems.count
    }

    func flushPendingSave() {
        debugGenerationTask?.cancel()
        debugGenerationTask = nil
        saveImmediately()
    }

    private func mergeDebugTextItems(_ newItems: [ClipboardItem]) {
        guard !newItems.isEmpty else {
            return
        }

        items.insert(contentsOf: newItems, at: 0)
        sortItems()
        pruneExpiredItems()
        rebuildRecentHashes()
        scheduleSave()
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

    private func scheduleSave() {
        deferredSaveTask?.cancel()
        let snapshot = items
        let revision = nextSaveRevision()
        let saveWriter = saveWriter

        deferredSaveTask = Task.detached(priority: .utility) {
            do {
                try await Task.sleep(nanoseconds: ClipboardHistoryStore.deferredSaveDelay)
            } catch {
                return
            }

            guard !Task.isCancelled else {
                return
            }

            saveWriter.saveAsync(snapshot, revision: revision)
        }
    }

    private func saveImmediately() {
        deferredSaveTask?.cancel()
        deferredSaveTask = nil
        saveWriter.saveSync(items, revision: nextSaveRevision())
    }

    private func nextSaveRevision() -> Int {
        saveRevision += 1
        return saveRevision
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

    private static func isDebugTextItem(_ item: ClipboardItem) -> Bool {
        item.type == .text
            && item.sourceBundleID == SourceAppInfo.clipease.bundleID
            && item.text.hasPrefix(debugTextPrefix)
    }

    nonisolated private static func makeDebugTextItems(
        count: Int,
        sourceApp: SourceAppInfo
    ) async -> [ClipboardItem] {
        let now = Date()
        var items: [ClipboardItem] = []
        items.reserveCapacity(count)

        for index in 0..<count {
            if Task.isCancelled {
                return []
            }

            items.append(
                ClipboardItem.debugText(
                    "\(debugTextPrefix)\(index + 1) keyword-\(index % 25) 搜索测试 \(UUID().uuidString)",
                    createdAt: now.addingTimeInterval(TimeInterval(-index)),
                    sourceApp: sourceApp
                )
            )

            if index > 0, index % debugBatchSize == 0 {
                await Task.yield()
            }
        }

        return items
    }
}

private final class ClipboardHistorySaveWriter: @unchecked Sendable {
    private let queue = DispatchQueue(label: "app.clipease.history-save", qos: .utility)
    private let persistence: ClipboardHistoryPersistence
    private var latestRevision = 0

    init(persistence: ClipboardHistoryPersistence) {
        self.persistence = persistence
    }

    func saveAsync(_ items: [ClipboardItem], revision: Int) {
        queue.async { [self] in
            saveIfCurrent(items, revision: revision)
        }
    }

    func saveSync(_ items: [ClipboardItem], revision: Int) {
        queue.sync { [self] in
            saveIfCurrent(items, revision: revision)
        }
    }

    private func saveIfCurrent(_ items: [ClipboardItem], revision: Int) {
        guard revision >= latestRevision else {
            return
        }

        latestRevision = revision
        persistence.saveItems(items)
    }
}
