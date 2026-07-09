import Foundation
import AppKit
import UniformTypeIdentifiers

struct ClipboardItemFocusRequest: Equatable {
    enum Reason: Equatable {
        case inserted
        case refreshed
    }

    let id = UUID()
    let itemID: ClipboardItem.ID
    let reason: Reason

    init(itemID: ClipboardItem.ID, reason: Reason = .inserted) {
        self.itemID = itemID
        self.reason = reason
    }
}

@MainActor
final class ClipboardHistoryStore: ObservableObject {
    @Published private(set) var items: [ClipboardItem] = [] {
        didSet {
            itemsMutationGeneration &+= 1
        }
    }
    private(set) var itemsMutationGeneration: UInt64 = 0
    @Published private(set) var groups: [ClipboardGroup] = []
    @Published private(set) var latestItemFocusRequest: ClipboardItemFocusRequest?
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
    nonisolated static let startupItemPageSize = HistoryPagingService.startupItemPageSize
    nonisolated static let incrementalItemPageSize = HistoryPagingService.incrementalItemPageSize
    private let persistence: ClipboardHistoryPersistence
    private let saveWriter: ClipboardHistorySaveWriter
    private let userDefaults: UserDefaults
    private var domainStore = ClipboardHistoryDomainStore()
    private let selfWriteGuard = ClipboardSelfWriteGuard()
    private let ocrCoordinator = HistoryOCRCoordinator()
    private let linkMetadataCoordinator = HistoryLinkMetadataCoordinator()
    private var deferredSaveTask: Task<Void, Never>?
    private var debugGenerationTask: Task<Void, Never>?
    private var groupIndexByID: [ClipboardGroup.ID: Int] = [:]
    private var saveRevision = 0
    private var isLoadingNextPage = false
    private var didLoadAllPersistedItems = false
    private var pagedLoadTask: Task<Void, Never>?
    private var searchIndexWarmupTask: Task<Void, Never>?

    var debugTextItemCount: Int {
        items.lazy.filter(Self.isDebugTextItem).count
    }

    var hasLoadedAllPersistedItems: Bool {
        didLoadAllPersistedItems
    }

    private var pagingState: HistoryPagingService.State {
        HistoryPagingService.State(
            didLoadAll: didLoadAllPersistedItems,
            isLoadingNextPage: isLoadingNextPage
        )
    }

    init(
        persistence: ClipboardHistoryPersistence = ClipboardHistoryPersistence(),
        userDefaults: UserDefaults = .standard
    ) {
        self.persistence = persistence
        self.saveWriter = ClipboardHistorySaveWriter(persistence: persistence)
        self.userDefaults = userDefaults
        if userDefaults.object(forKey: Self.retentionPolicyKey) == nil {
            self.retentionPolicy = .sevenDays
        } else {
            self.retentionPolicy = HistoryRetentionPolicy(
                rawValue: userDefaults.integer(forKey: Self.retentionPolicyKey)
            ) ?? .sevenDays
        }
        let loadStartedAt = CFAbsoluteTimeGetCurrent()
        let snapshot = persistence.loadSnapshot(itemLimit: Self.startupItemPageSize)
        PerformanceDiagnosticsService.shared.record(
            "history.store.loadStartupPage",
            category: "storage",
            durationMS: (CFAbsoluteTimeGetCurrent() - loadStartedAt) * 1_000,
            itemCount: snapshot.items.count,
            resultCount: snapshot.groups.count,
            metadata: ["limit": "\(Self.startupItemPageSize)"]
        )
        self.items = snapshot.items
        self.groups = snapshot.groups
        self.didLoadAllPersistedItems = HistoryPagingService.didLoadAllAfterStartup(itemCount: snapshot.items.count)
        let sortStartedAt = CFAbsoluteTimeGetCurrent()
        rebuildItemIndexes()
        sortGroups()
        PerformanceDiagnosticsService.shared.record(
            "history.store.sort",
            category: "storage",
            durationMS: (CFAbsoluteTimeGetCurrent() - sortStartedAt) * 1_000,
            itemCount: items.count,
            resultCount: groups.count,
            metadata: ["mode": "snapshotOrder.indexOnly"]
        )
        let didPruneExpiredItems = pruneExpiredItems()
        if didPruneExpiredItems {
            saveImmediately()
        }
        let hashStartedAt = CFAbsoluteTimeGetCurrent()
        rebuildRecentHashes()
        PerformanceDiagnosticsService.shared.record(
            "history.store.rebuildHashes",
            category: "storage",
            durationMS: (CFAbsoluteTimeGetCurrent() - hashStartedAt) * 1_000,
            itemCount: items.count,
            resultCount: domainStore.recentHashCount
        )
        PerformanceDiagnosticsService.shared.record(
            "history.store.initialize",
            category: "storage",
            durationMS: (CFAbsoluteTimeGetCurrent() - loadStartedAt) * 1_000,
            itemCount: items.count,
            resultCount: groups.count,
            metadata: ["mode": "startupPage"]
        )
        itemsMutationGeneration = 1
        scheduleInitialBackgroundPageLoadIfNeeded()
        scheduleSearchIndexWarmup()
    }

    func addText(_ text: String, sourceApp: SourceAppInfo) {
        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedText.isEmpty else {
            return
        }

        if consumeSkippedClipboardText(normalizedText) {
            return
        }

        let item: ClipboardItem
        if let hex = ColorParser.hexColor(from: normalizedText) {
            item = .color(hex, sourceApp: sourceApp)
        } else if let url = URLParser.url(from: normalizedText) {
            item = .link(url, originalText: normalizedText, sourceApp: sourceApp)
        } else {
            item = .text(normalizedText, sourceApp: sourceApp)
        }

        let upsertedItem = upsertClipboardItem(item)

        if upsertedItem.type == .link,
           let url = upsertedItem.url {
            fetchLinkTitle(for: upsertedItem.id, url: url)
        }

        playExternalCopyFeedbackIfNeeded(for: upsertedItem)
    }

    func consumeLatestItemFocusRequest() -> ClipboardItemFocusRequest? {
        let request = latestItemFocusRequest
        latestItemFocusRequest = nil
        return request
    }

    func addRichText(
        _ data: Data,
        plainText: String,
        sourceApp: SourceAppInfo,
        groupID: ClipboardGroup.ID? = nil
    ) {
        let normalizedText = plainText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedText.isEmpty,
              let storedRichText = persistence.saveRichText(data) else {
            return
        }

        if selfWriteGuard.consumeText(normalizedText) {
            persistence.deleteRichText(fileName: storedRichText.fileName)
            return
        }

        var item = ClipboardItem.richText(
            plainText: normalizedText,
            fileName: storedRichText.fileName,
            sourceApp: sourceApp
        )
        let now = Date()
        if let groupID, groupIndexByID[groupID] != nil {
            item.groupID = groupID
            item.groupedAt = now
        }

        let insertedItem = upsertClipboardItem(
            item,
            replacingRichTextFileName: storedRichText.fileName
        )
        playExternalCopyFeedbackIfNeeded(for: insertedItem)
    }

    func addImage(_ image: NSImage, sourceApp: SourceAppInfo) {
        guard let storedImage = persistence.saveImage(image) else {
            return
        }

        if selfWriteGuard.consumeImageHash(storedImage.hash) {
            persistence.deleteImage(fileName: storedImage.fileName)
            return
        }

        var item = ClipboardItem.image(
            fileName: storedImage.fileName,
            width: storedImage.width,
            height: storedImage.height,
            hash: storedImage.hash,
            sourceApp: sourceApp
        )
        item.ocrStatus = .pending

        let insertedItem = upsertClipboardItem(item)
        enqueueOCRIfNeeded(for: insertedItem)
        playExternalCopyFeedbackIfNeeded(for: insertedItem)
    }

    func addFiles(_ urls: [URL], sourceApp: SourceAppInfo) {
        let references = fileReferences(from: urls)
        guard !references.isEmpty else {
            return
        }
        if selfWriteGuard.consumeFiles(urls) {
            return
        }

        let item = ClipboardItem.file(
            references: references,
            sourceApp: sourceApp
        )

        let insertedItem = upsertClipboardItem(item)
        enqueueOCRIfNeeded(for: insertedItem)
        playExternalCopyFeedbackIfNeeded(for: insertedItem)
    }

    func item(with id: ClipboardItem.ID?) -> ClipboardItem? {
        guard let id else {
            return nil
        }

        guard let index = itemIndex(for: id) else {
            return nil
        }

        return items[index]
    }

    func itemIndex(with id: ClipboardItem.ID?) -> Int? {
        guard let id else {
            return nil
        }

        return itemIndex(for: id)
    }

    func cachedItemIndex(with id: ClipboardItem.ID?) -> Int? {
        guard let id,
              let index = domainStore.cachedItemIndex(for: id, in: items) else {
            return nil
        }

        return index
    }

    func loadMoreItemsIfNeeded(visibleUpperBound: Int, preloadMargin: Int = 160) {
        guard HistoryPagingService.shouldLoadMoreItems(
            state: pagingState,
            visibleUpperBound: visibleUpperBound,
            itemCount: items.count,
            preloadMargin: preloadMargin
        ) else {
            return
        }

        loadNextItemPage(reason: "visibleWindow")
    }

    nonisolated func searchItems(_ query: ClipboardSearchQuery) -> [ClipboardItem] {
        let startedAt = CFAbsoluteTimeGetCurrent()
        let items = persistence.searchItems(query)
        let durationMS = (CFAbsoluteTimeGetCurrent() - startedAt) * 1_000
        Task { @MainActor in
            PerformanceDiagnosticsService.shared.record(
                "history.store.searchAll",
                category: "search",
                durationMS: durationMS,
                resultCount: items.count,
                metadata: [
                    "queryLength": "\(query.text.count)",
                    "limit": "\(query.limit)"
                ]
            )
        }
        return items
    }

    private func scheduleSearchIndexWarmup() {
        searchIndexWarmupTask?.cancel()
        let persistence = persistence
        searchIndexWarmupTask = Task.detached(priority: .utility) {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else {
                return
            }

            let startedAt = CFAbsoluteTimeGetCurrent()
            persistence.prepareSearchIndex()
            let durationMS = (CFAbsoluteTimeGetCurrent() - startedAt) * 1_000
            await MainActor.run {
                PerformanceDiagnosticsService.shared.record(
                    "history.store.searchIndexWarmup",
                    category: "search",
                    durationMS: durationMS
                )
            }
        }
    }

    func deleteItem(with id: ClipboardItem.ID?) {
        guard let id else {
            return
        }

        guard let deletedIndex = itemIndex(for: id) else {
            return
        }

        let deletedItems = [items[deletedIndex]]
        items.remove(at: deletedIndex)
        rebuildItemIndexes()
        cancelOCRTasks(for: deletedItems)
        cancelLinkMetadataTasks(for: deletedItems)
        deleteExternalFiles(for: deletedItems)
        removeRecentHashes(for: deletedItems)
        persistIncrementalDelete(itemIDs: [id])
    }

    func clearAllItems() {
        let removedItems = items
        items.removeAll()
        rebuildItemIndexes()
        didLoadAllPersistedItems = true
        cancelAllOCRTasks()
        cancelAllLinkMetadataTasks()
        deleteExternalFiles(for: removedItems)
        domainStore.removeAllRecentHashes()
        selfWriteGuard.removeAll()
        persistDeleteAll()
    }

    func importItems(_ importedItems: [ClipboardItem]) -> Int {
        let sanitizedItems = sanitizedImportedItems(importedItems)
        let newItems = nonDuplicateItems(from: sanitizedItems)

        guard !newItems.isEmpty else {
            return 0
        }

        items.append(contentsOf: newItems)
        sortItems()
        pruneExpiredItems()
        rebuildRecentHashesAndGroupCounts()
        scheduleSave()
        return newItems.count
    }

    func importBackupItems(_ importedItems: [ClipboardItem], groups importedGroups: [ClipboardGroup] = []) -> Int {
        let groupIDMapping = importBackupGroups(importedGroups)
        let validGroupIDs = Set(groups.map(\.id))
        let sanitizedItems = importedItems.map { item in
            sanitizedBackupItem(item, groupIDMapping: groupIDMapping, validGroupIDs: validGroupIDs)
        }

        let newItems = nonDuplicateItems(from: sanitizedItems)

        guard !newItems.isEmpty else {
            if !importedGroups.isEmpty {
                saveImmediately()
            }
            return 0
        }

        items.append(contentsOf: newItems)
        sortItems()
        pruneExpiredItems()
        rebuildRecentHashesAndGroupCounts()
        scheduleSave()
        return newItems.count
    }

    func duplicateCount(for importedItems: [ClipboardItem]) -> Int {
        importedItems.count - nonDuplicateItems(from: importedItems).count
    }

    func togglePinned(for id: ClipboardItem.ID?) {
        guard let id,
              let index = itemIndex(for: id) else {
            return
        }

        items[index].isPinned.toggle()
        items[index].pinnedAt = items[index].isPinned ? Date() : nil
        sortItems()
        if let updatedItem = item(with: id) {
            persistIncrementalUpsert(updatedItem, deleting: [])
        } else {
            scheduleSave()
        }
    }

    enum GroupRenameResult: Equatable {
        case renamed
        case unchanged
        case empty
        case duplicate
        case notFound

        init(_ result: GroupService.RenameResult) {
            switch result {
            case .renamed:
                self = .renamed
            case .unchanged:
                self = .unchanged
            case .empty:
                self = .empty
            case .duplicate:
                self = .duplicate
            case .notFound:
                self = .notFound
            }
        }
    }

    @discardableResult
    func createGroup() -> ClipboardGroup {
        let group = ClipboardGroup.makeDefault(
            name: GroupService.uniqueGroupName(baseName: ClipboardGroup.defaultName, groups: groups),
            sortOrder: groups.count
        )
        groups.append(group)
        sortGroups()
        scheduleSave()
        return group
    }

    @discardableResult
    func renameGroup(_ id: ClipboardGroup.ID, name: String) -> GroupRenameResult {
        let result = GroupService.renameGroup(
            id,
            name: name,
            groups: &groups,
            indexByID: &groupIndexByID
        )
        if result == .renamed {
            scheduleSave()
        }
        return GroupRenameResult(result)
    }

    func updateGroupAppearance(_ id: ClipboardGroup.ID, colorHex: String? = nil, iconName: String? = nil) {
        let didUpdate = GroupService.updateGroupAppearance(
            id,
            colorHex: colorHex,
            iconName: iconName,
            groups: &groups,
            indexByID: &groupIndexByID
        )
        guard didUpdate else {
            return
        }

        scheduleSave()
    }

    func deleteGroup(_ id: ClipboardGroup.ID) -> Int {
        let removedItems = items.filter { $0.groupID == id }
        groups.removeAll { $0.id == id }
        items.removeAll { $0.groupID == id }
        rebuildItemIndexes()
        sortGroups()
        cancelOCRTasks(for: removedItems)
        cancelLinkMetadataTasks(for: removedItems)
        deleteExternalFiles(for: removedItems)
        removeRecentHashes(for: removedItems)
        persistIncrementalDelete(
            itemIDs: Set(removedItems.map(\.id)),
            groupIDs: [id]
        )
        return removedItems.count
    }

    func deleteGroups(_ ids: Set<ClipboardGroup.ID>) -> Int {
        guard !ids.isEmpty else {
            return 0
        }

        let removedItems = items.filter { item in
            item.groupID.map(ids.contains) ?? false
        }
        groups.removeAll { ids.contains($0.id) }
        items.removeAll { item in
            item.groupID.map(ids.contains) ?? false
        }
        rebuildItemIndexes()
        sortGroups()
        cancelOCRTasks(for: removedItems)
        cancelLinkMetadataTasks(for: removedItems)
        deleteExternalFiles(for: removedItems)
        removeRecentHashes(for: removedItems)
        persistIncrementalDelete(
            itemIDs: Set(removedItems.map(\.id)),
            groupIDs: ids
        )
        return removedItems.count
    }

    func moveGroup(fromOffsets source: IndexSet, toOffset destination: Int) {
        groups.move(fromOffsets: source, toOffset: destination)
        sortGroups()
        scheduleSave()
    }

    func addItem(_ id: ClipboardItem.ID?, toGroup groupID: ClipboardGroup.ID) {
        guard let id,
              groupIndexByID[groupID] != nil,
              let index = itemIndex(for: id) else {
            return
        }

        let now = Date()
        let oldGroupID = items[index].groupID
        items[index].groupID = groupID
        items[index].groupedAt = now
        updateGroupCountOnMove(from: oldGroupID, to: groupID)
        sortItems()
        scheduleSave()
    }

    @discardableResult
    func addItems(_ ids: Set<ClipboardItem.ID>, toGroup groupID: ClipboardGroup.ID) -> Int {
        guard !ids.isEmpty,
              groupIndexByID[groupID] != nil else {
            return 0
        }

        let now = Date()
        var changedCount = 0
        for index in items.indices where ids.contains(items[index].id) {
            var didChangeItem = false
            let oldGroupID = items[index].groupID
            if items[index].groupID != groupID {
                items[index].groupID = groupID
                items[index].groupedAt = now
                didChangeItem = true
            } else if items[index].groupedAt == nil {
                items[index].groupedAt = now
                didChangeItem = true
            }

            if didChangeItem {
                changedCount += 1
                updateGroupCountOnMove(from: oldGroupID, to: groupID)
            }
        }

        guard changedCount > 0 else {
            return 0
        }

        sortItems()
        scheduleSave()
        return changedCount
    }

    func removeItemFromGroup(_ id: ClipboardItem.ID?) {
        guard let id,
              let index = itemIndex(for: id) else {
            return
        }

        let oldGroupID = items[index].groupID
        items[index].groupID = nil
        items[index].groupedAt = nil
        updateGroupCountOnMove(from: oldGroupID, to: nil)
        scheduleSave()
    }

    func group(with id: ClipboardGroup.ID?) -> ClipboardGroup? {
        guard let id else {
            return nil
        }

        guard let index = groupIndex(for: id) else {
            return nil
        }

        return groups[index]
    }

    func itemCount(inGroup id: ClipboardGroup.ID) -> Int {
        domainStore.itemCount(inGroup: id)
    }

    func markUsed(_ id: ClipboardItem.ID?) {
        guard let id,
              let index = itemIndex(for: id),
              !items[index].isPinned else {
            return
        }

        items[index].createdAt = Date()
        sortItems()
        if let updatedItem = item(with: id) {
            persistIncrementalUpsert(updatedItem, deleting: [])
        } else {
            scheduleSave()
        }
    }

    @discardableResult
    func updateEditableContent(for id: ClipboardItem.ID?, text: String) -> ClipboardItem? {
        guard let id,
              let index = itemIndex(for: id) else {
            return nil
        }

        let item = items[index]
        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)

        switch item.type {
        case .text:
            guard !normalizedText.isEmpty else {
                return nil
            }

            items[index] = item.updatingEditableContent(text: normalizedText)
        case .link:
            guard let url = URLParser.url(from: normalizedText) else {
                return nil
            }

            items[index] = item.updatingEditableContent(
                text: normalizedText,
                url: url,
                linkTitle: Self.fallbackLinkTitle(for: url),
                linkSubtitle: url.absoluteString
            )
        case .color:
            guard let hex = ColorParser.hexColor(from: normalizedText) else {
                return nil
            }

            items[index] = item.updatingEditableContent(text: hex)
        case .image, .file:
            return nil
        }

        items[index].createdAt = Date()
        sortItems()
        rebuildRecentHashes()
        scheduleSave()
        guard let updatedItem = self.item(with: id) else {
            return nil
        }
        if let richTextFileName = item.richTextFileName,
           updatedItem.richTextFileName == nil {
            persistence.deleteRichText(fileName: richTextFileName)
        }
        latestItemFocusRequest = ClipboardItemFocusRequest(itemID: updatedItem.id, reason: .refreshed)

        if updatedItem.type == .link,
           let url = updatedItem.url {
            fetchLinkTitle(for: updatedItem.id, url: url)
        }

        return updatedItem
    }

    private func fetchLinkTitle(for id: ClipboardItem.ID, url: URL) {
        fetchLinkMetadata(for: id, url: url)
    }

    private func fetchLinkMetadata(for id: ClipboardItem.ID, url: URL) {
        linkMetadataCoordinator.fetch(id: id, url: url, persistence: persistence) { [weak self] title, storedImage, id, url in
            self?.updateLinkMetadata(title: title, storedImage: storedImage, for: id, url: url)
        }
    }

    private func cancelLinkMetadataTasks(for removedItems: [ClipboardItem]) {
        linkMetadataCoordinator.cancelTasks(for: removedItems)
    }

    private func cancelLinkMetadataTasks(for ids: Set<ClipboardItem.ID>) {
        linkMetadataCoordinator.cancelTasks(for: ids)
    }

    private func cancelAllLinkMetadataTasks() {
        linkMetadataCoordinator.cancelAllTasks()
    }

    private func updateLinkTitle(_ title: String, for id: ClipboardItem.ID, url: URL) {
        updateLinkMetadata(title: title, storedImage: nil, for: id, url: url)
    }

    private func updateLinkMetadata(
        title: String?,
        storedImage: StoredClipboardImage?,
        for id: ClipboardItem.ID,
        url: URL
    ) {
        guard let index = itemIndex(for: id),
              LinkMetadataService.canApplyMetadata(to: items[index], expectedURL: url) else {
            return
        }

        let existingItem = items[index]
        guard LinkMetadataService.shouldApplyMetadata(
            title: title,
            storedImage: storedImage,
            to: existingItem
        ) else {
            return
        }

        if let oldImageFileName = existingItem.imageFileName,
           let newImageFileName = storedImage?.fileName,
           oldImageFileName != newImageFileName {
            persistence.deleteImage(fileName: oldImageFileName)
        }

        items[index] = existingItem.updatingLinkMetadata(
            title: title,
            imageFileName: storedImage?.fileName,
            imageWidth: storedImage?.width,
            imageHeight: storedImage?.height,
            imageHash: storedImage?.hash
        )
        persistIncrementalUpsert(items[index], deleting: [])
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
        rebuildItemIndexes()
        rebuildRecentHashes()
        persistIncrementalDelete(itemIDs: Set(removedItems.map(\.id)))
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
        persistDebugItemsIncrementally(newItems)
    }

    private func persistDebugItemsIncrementally(_ items: [ClipboardItem]) {
        let revision = nextSaveRevision()
        let saveWriter = saveWriter
        saveWriter.insertItemsAsync(items, revision: revision)
        PerformanceDiagnosticsService.shared.record(
            "history.store.addDebugTextItems",
            category: "storage",
            durationMS: 0,
            itemCount: items.count,
            metadata: ["revision": "\(revision)"]
        )
    }

    func skipNextClipboardText(_ text: String) {
        selfWriteGuard.skipText(text)
    }

    func consumeSkippedClipboardText(_ text: String) -> Bool {
        selfWriteGuard.consumeText(text)
    }

    func skipNextClipboardImage(_ item: ClipboardItem) {
        selfWriteGuard.skipImageHash(item.imageHash)
    }

    func skipNextClipboardImageHash(_ hash: String) {
        selfWriteGuard.skipImageHash(hash)
    }

    func skipNextClipboardFiles(_ urls: [URL]) {
        selfWriteGuard.skipFiles(urls)
    }

    func consumeSkippedClipboardFiles(_ urls: [URL]) -> Bool {
        selfWriteGuard.consumeFiles(urls)
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

    @discardableResult
    func updateRichTextContent(for id: ClipboardItem.ID?, data: Data, plainText: String) throws -> ClipboardItem? {
        guard let id,
              let index = itemIndex(for: id) else {
            return nil
        }

        let item = items[index]
        let normalizedText = plainText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard item.type == .text,
              !normalizedText.isEmpty else {
            return nil
        }

        let storedRichText = try persistence.saveRichTextOrThrow(data)
        items[index] = item.updatingEditableContent(
            text: normalizedText,
            richTextFileName: storedRichText.fileName
        )
        items[index].createdAt = Date()
        sortItems()
        rebuildRecentHashes()

        do {
            try saveImmediatelyOrThrow()
        } catch {
            if let rollbackIndex = itemIndex(for: id) {
                items[rollbackIndex] = item
                sortItems()
            }
            rebuildRecentHashes()
            // Keep the new RTF if JSON partially saved a reference to it; health cleanup can remove orphans later.
            throw error
        }

        if let richTextFileName = item.richTextFileName {
            persistence.deleteRichText(fileName: richTextFileName)
        }
        guard let updatedItem = self.item(with: id) else {
            return nil
        }

        latestItemFocusRequest = ClipboardItemFocusRequest(itemID: updatedItem.id, reason: .refreshed)
        return updatedItem
    }

    func imageFileURL(for item: ClipboardItem) -> URL? {
        guard let fileName = item.imageFileName else {
            return nil
        }

        return try? ClipEaseStoragePaths.imageFileURL(fileName: fileName)
    }

    func ocrResult(for item: ClipboardItem) -> ClipboardOCRMatch? {
        guard !item.ocrText.isEmpty || !item.ocrEmails.isEmpty || !item.ocrPhoneNumbers.isEmpty || !item.ocrURLs.isEmpty else {
            return nil
        }

        return ClipboardOCRMatch(
            text: item.ocrText,
            emails: item.ocrEmails,
            phoneNumbers: item.ocrPhoneNumbers,
            urls: item.ocrURLs,
            textRegions: item.ocrTextRegions
        )
    }

    func ocrBadgeItems(for item: ClipboardItem) -> [String] {
        var results: [String] = []
        results.append(contentsOf: item.ocrEmails)
        results.append(contentsOf: item.ocrPhoneNumbers)
        results.append(contentsOf: item.ocrURLs)
        return results
    }

    func setOCRInteractiveThrottleActive(_ isActive: Bool) {
        ocrCoordinator.setInteractiveThrottleActive(isActive)
    }

    private func enqueueOCRIfNeeded(for item: ClipboardItem) {
        guard item.ocrStatus == .pending else {
            return
        }

        let sourceURL: URL?
        switch item.type {
        case .image:
            sourceURL = imageFileURL(for: item)
        case .file:
            sourceURL = item.fileReferences.first(where: { $0.isOCRCandidate }).map { URL(fileURLWithPath: $0.path) }
        default:
            sourceURL = nil
        }

        ocrCoordinator.enqueue(
            item: item,
            sourceURL: sourceURL,
            setProcessing: { [weak self] id in
                self?.setOCRStatus(.processing, for: id)
            },
            applyResult: { [weak self] result, status, id in
                self?.applyOCRResult(result, status: status, to: id)
            }
        )
    }

    private func setOCRStatus(_ status: ClipboardOCRStatus, for id: ClipboardItem.ID) {
        guard let index = itemIndex(for: id) else {
            return
        }

        items[index].ocrStatus = status
        persistIncrementalUpsert(items[index], deleting: [])
    }

    private func applyOCRResult(_ result: ClipboardOCRMatch, status: ClipboardOCRStatus, to id: ClipboardItem.ID) {
        guard let index = itemIndex(for: id) else {
            return
        }

        items[index] = items[index].updatingOCR(
            status: status,
            text: result.text,
            emails: result.emails,
            phoneNumbers: result.phoneNumbers,
            urls: result.urls,
            textRegions: result.textRegions
        )
        sortItems()
        if let updatedItem = item(with: id) {
            persistIncrementalUpsert(updatedItem, deleting: [])
        } else {
            scheduleSave()
        }
    }

    private func cancelOCRTasks(for removedItems: [ClipboardItem]) {
        ocrCoordinator.cancelTasks(for: removedItems)
    }

    private func cancelOCRTasks(for ids: Set<ClipboardItem.ID>) {
        ocrCoordinator.cancelTasks(for: ids)
    }

    private func cancelAllOCRTasks() {
        ocrCoordinator.cancelAllTasks()
    }

    private func sortItems() {
        items.sort(by: Self.shouldSortBefore)
        rebuildItemIndexes()
    }

    private func insertItemMaintainingSort(_ item: ClipboardItem) {
        let insertionIndex = sortedInsertionIndex(for: item)
        items.insert(item, at: insertionIndex)
        updateItemIndexes(startingAt: insertionIndex)
        domainStore.incrementGroupCount(for: item.groupID)
    }

    private func sortedInsertionIndex(for item: ClipboardItem) -> Int {
        var low = items.startIndex
        var high = items.endIndex

        while low < high {
            let mid = low + (high - low) / 2
            if Self.shouldSortBefore(item, items[mid]) {
                high = mid
            } else {
                low = mid + 1
            }
        }

        return low
    }

    private func updateItemIndexes(startingAt startIndex: Int) {
        domainStore.updateIndexes(startingAt: startIndex, in: items)
    }

    private static func shouldSortBefore(_ lhs: ClipboardItem, _ rhs: ClipboardItem) -> Bool {
        if lhs.isPinned != rhs.isPinned {
            return lhs.isPinned && !rhs.isPinned
        }

        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt > rhs.createdAt
        }

        return (lhs.pinnedAt ?? lhs.createdAt) > (rhs.pinnedAt ?? rhs.createdAt)
    }

    private func persistedDuplicateItems(for item: ClipboardItem) -> [ClipboardItem] {
        guard !didLoadAllPersistedItems,
              let contentHash = item.contentHash else {
            return []
        }

        return persistence.loadItems(
            contentHash: contentHash,
            sourceBundleID: nil
        )
    }

    private func itemIndex(for id: ClipboardItem.ID) -> Int? {
        domainStore.itemIndex(for: id, in: items)
    }

    private func groupIndex(for id: ClipboardGroup.ID) -> Int? {
        GroupService.groupIndex(for: id, groups: groups, indexByID: &groupIndexByID)
    }

    private func rebuildItemIndexes() {
        domainStore.rebuildIndexes(for: items)
    }

    private func sortGroups() {
        groupIndexByID = GroupService.sortGroupsAndBuildIndex(&groups)
    }

    private func rebuildGroupIndex() {
        groupIndexByID = GroupService.rebuildGroupIndex(groups)
    }

    private func scheduleSave() {
        deferredSaveTask?.cancel()
        if !didLoadAllPersistedItems {
            loadAllPersistedItemsBeforeFullSave()
        }
        let snapshot = ClipboardHistorySnapshot(items: items, groups: groups)
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

    private func scheduleInitialBackgroundPageLoadIfNeeded() {
        guard !didLoadAllPersistedItems else {
            return
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 600_000_000)
            self.loadNextItemPage(reason: "startupBackground")
        }
    }

    private func loadNextItemPage(reason: String) {
        guard !didLoadAllPersistedItems,
              !isLoadingNextPage else {
            return
        }

        isLoadingNextPage = true
        let request = HistoryPagingService.nextPageRequest(itemCount: items.count)
        let persistence = persistence
        pagedLoadTask = Task(priority: .utility) {
            let startedAt = CFAbsoluteTimeGetCurrent()
            let page = await Task.detached(priority: .utility) {
                persistence.loadItems(limit: request.limit, offset: request.offset)
            }.value
            let durationMS = (CFAbsoluteTimeGetCurrent() - startedAt) * 1_000
            mergeLoadedPage(
                page,
                offset: request.offset,
                limit: request.limit,
                durationMS: durationMS,
                reason: reason
            )
        }
    }

    private func mergeLoadedPage(
        _ page: [ClipboardItem],
        offset: Int,
        limit: Int,
        durationMS: Double,
        reason: String
    ) {
        defer {
            isLoadingNextPage = false
            pagedLoadTask = nil
        }

        switch HistoryPagingService.mergeResult(
            pageCount: page.count,
            requestedOffset: offset,
            currentItemCount: items.count,
            limit: limit
        ) {
        case .stale:
            return
        case .append(let didLoadAll):
            appendLoadedItems(page)
            didLoadAllPersistedItems = didLoadAll
        }

        PerformanceDiagnosticsService.shared.record(
            "history.store.loadNextPage",
            category: "storage",
            durationMS: durationMS,
            itemCount: page.count,
            resultCount: items.count,
            metadata: [
                "offset": "\(offset)",
                "limit": "\(limit)",
                "reason": reason,
                "didLoadAll": "\(didLoadAllPersistedItems)"
            ]
        )
    }

    private func appendLoadedItems(_ page: [ClipboardItem]) {
        let existingIDs = Set(items.map(\.id))
        let newItems = page.filter { !existingIDs.contains($0.id) }
        guard !newItems.isEmpty else {
            return
        }

        items.append(contentsOf: newItems)
        sortItems()
        for item in newItems {
            addRecentHash(for: item)
        }
    }

    private func persistIncrementalUpsert(_ item: ClipboardItem, deleting deletedIDs: Set<ClipboardItem.ID>) {
        deferredSaveTask?.cancel()
        deferredSaveTask = nil
        let groups = groups
        let revision = nextSaveRevision()
        let saveWriter = saveWriter
        saveWriter.upsertAsync(item, deleting: deletedIDs, groups: groups, revision: revision)
    }

    private func persistIncrementalDelete(
        itemIDs: Set<ClipboardItem.ID>,
        groupIDs: Set<ClipboardGroup.ID> = []
    ) {
        deferredSaveTask?.cancel()
        deferredSaveTask = nil
        pagedLoadTask?.cancel()
        pagedLoadTask = nil
        let revision = nextSaveRevision()
        let saveWriter = saveWriter
        saveWriter.deleteAsync(itemIDs: itemIDs, groupIDs: groupIDs, revision: revision)
    }

    private func persistDeleteAll() {
        deferredSaveTask?.cancel()
        deferredSaveTask = nil
        let revision = nextSaveRevision()
        let saveWriter = saveWriter
        saveWriter.deleteAllAsync(revision: revision)
    }

    private func saveImmediately() {
        do {
            try saveImmediatelyOrThrow()
        } catch {
            NSLog("ClipEase failed to save clipboard history: \(error.localizedDescription)")
            PerformanceDiagnosticsService.shared.recordError(
                "history.persistence.saveImmediate.failed",
                category: "storage",
                error: error
            )
        }
    }

    private func saveImmediatelyOrThrow() throws {
        deferredSaveTask?.cancel()
        deferredSaveTask = nil
        loadAllPersistedItemsBeforeFullSave()
        try saveWriter.saveSync(ClipboardHistorySnapshot(items: items, groups: groups), revision: nextSaveRevision())
    }

    private func loadAllPersistedItemsBeforeFullSave() {
        guard !didLoadAllPersistedItems else {
            return
        }

        pagedLoadTask?.cancel()
        pagedLoadTask = nil
        isLoadingNextPage = false
        let startedAt = CFAbsoluteTimeGetCurrent()
        var loadedCount = 0

        while !didLoadAllPersistedItems {
            let offset = items.count
            let page = persistence.loadItems(limit: Self.incrementalItemPageSize, offset: offset)
            if page.isEmpty {
                didLoadAllPersistedItems = true
                break
            }

            appendLoadedItems(page)
            loadedCount += page.count
            didLoadAllPersistedItems = page.count < Self.incrementalItemPageSize
        }

        PerformanceDiagnosticsService.shared.record(
            "history.store.loadAllBeforeFullSave",
            category: "storage",
            durationMS: (CFAbsoluteTimeGetCurrent() - startedAt) * 1_000,
            itemCount: loadedCount,
            resultCount: items.count
        )
    }

    private func nextSaveRevision() -> Int {
        saveRevision += 1
        return saveRevision
    }

    private func rebuildRecentHashesAndGroupCounts() {
        rebuildItemIndexes()
        rebuildRecentHashes()
    }

    private func rebuildRecentHashes() {
        domainStore.rebuildRecentHashes(for: items)
    }

    private func addRecentHash(for item: ClipboardItem) {
        domainStore.addRecentHash(for: item)
    }

    private func removeRecentHashes(for removedItems: [ClipboardItem]) {
        domainStore.removeRecentHashes(for: removedItems)
    }

    private func updateGroupCountOnMove(from oldGroupID: ClipboardGroup.ID?, to newGroupID: ClipboardGroup.ID?) {
        domainStore.updateGroupCountOnMove(from: oldGroupID, to: newGroupID)
    }

    @discardableResult
    private func upsertClipboardItem(
        _ item: ClipboardItem,
        replacingRichTextFileName newRichTextFileName: String? = nil
    ) -> ClipboardItem {
        let startedAt = CFAbsoluteTimeGetCurrent()
        let hash = DuplicateResolver.contentKey(for: item)
        let cachedDuplicateIDs = domainStore.itemIDs(forContentKey: hash)
        let cachedDuplicateItems = cachedDuplicateIDs.compactMap { self.item(with: $0) }
        let persistedDuplicateItems = persistedDuplicateItems(for: item)
        let duplicateItems = DuplicateResolver.mergedDuplicateItems(
            cachedItems: cachedDuplicateItems,
            persistedItems: persistedDuplicateItems
        )
        let duplicateIDs = Set(duplicateItems.map(\.id))
        let firstDuplicate = duplicateItems.first
        var insertedItem = item

        if let firstDuplicate {
            insertedItem.isPinned = firstDuplicate.isPinned
            insertedItem.pinnedAt = firstDuplicate.pinnedAt
            insertedItem.groupID = firstDuplicate.groupID
            insertedItem.groupedAt = firstDuplicate.groupedAt

            let insertedRichTextFileName = newRichTextFileName ?? item.richTextFileName
            for duplicate in duplicateItems {
                if let oldRichTextFileName = duplicate.richTextFileName,
                   oldRichTextFileName != insertedRichTextFileName {
                    persistence.deleteRichText(fileName: oldRichTextFileName)
                }
                if let oldImageFileName = duplicate.imageFileName,
                   oldImageFileName != insertedItem.imageFileName {
                    persistence.deleteImage(fileName: oldImageFileName)
                }
            }
            items.removeAll { duplicateIDs.contains($0.id) }
            rebuildItemIndexes()
            cancelOCRTasks(for: duplicateIDs)
            cancelLinkMetadataTasks(for: duplicateIDs)
            removeRecentHashes(for: duplicateItems)
        }

        insertItemMaintainingSort(insertedItem)
        let didPruneExpiredItems = pruneExpiredItems()
        addRecentHash(for: insertedItem)
        if didPruneExpiredItems {
            scheduleSave()
        } else {
            persistIncrementalUpsert(insertedItem, deleting: duplicateIDs)
        }
        latestItemFocusRequest = ClipboardItemFocusRequest(itemID: insertedItem.id, reason: .inserted)
        PerformanceDiagnosticsService.shared.record(
            "history.store.upsert",
            category: "storage",
            durationMS: (CFAbsoluteTimeGetCurrent() - startedAt) * 1_000,
            itemCount: items.count,
            resultCount: duplicateItems.count,
            metadata: [
                "type": insertedItem.type.rawValue,
                "didPruneExpiredItems": "\(didPruneExpiredItems)",
                "persistence": didPruneExpiredItems ? "snapshot" : "incremental"
            ]
        )
        return insertedItem
    }

    private func playExternalCopyFeedbackIfNeeded(for item: ClipboardItem) {
        guard !item.isFromClipEase else {
            return
        }

        ClipEaseSoundPlayer.shared.playCopyFeedback()
    }

    private func clipboardFilePathSetKey(for urls: [URL]) -> String {
        urls
            .filter(\.isFileURL)
            .map { $0.standardizedFileURL.path }
            .sorted()
            .joined(separator: "\u{1F}")
    }

    private func nonDuplicateItems(from importedItems: [ClipboardItem]) -> [ClipboardItem] {
        DuplicateResolver.nonDuplicateItems(importedItems: importedItems, existingItems: items)
    }

    private func sanitizedImportedItems(_ importedItems: [ClipboardItem]) -> [ClipboardItem] {
        let validGroupIDs = Set(groups.map(\.id))
        return importedItems.map { item in
            sanitizedImportedItem(item, validGroupIDs: validGroupIDs)
        }
    }

    private func sanitizedImportedItem(
        _ item: ClipboardItem,
        validGroupIDs: Set<ClipboardGroup.ID>
    ) -> ClipboardItem {
        guard let groupID = item.groupID,
              validGroupIDs.contains(groupID) else {
            var sanitizedItem = item
            sanitizedItem.groupID = nil
            sanitizedItem.groupedAt = nil
            return sanitizedItem
        }

        var sanitizedItem = item
        sanitizedItem.groupedAt = item.groupedAt ?? item.createdAt
        return sanitizedItem
    }

    private func importBackupGroups(_ importedGroups: [ClipboardGroup]) -> [ClipboardGroup.ID: ClipboardGroup.ID] {
        guard !importedGroups.isEmpty else {
            return [:]
        }

        var mapping: [ClipboardGroup.ID: ClipboardGroup.ID] = [:]
        var knownIDs = Set(groups.map(\.id))
        var knownNames = Set(groups.map { GroupService.normalizedGroupName($0.name) })
        var groupsToAppend: [ClipboardGroup] = []

        for importedGroup in importedGroups {
            let normalizedName = GroupService.normalizedGroupName(importedGroup.name)
            if knownIDs.contains(importedGroup.id) {
                if let existingGroup = groups.first(where: { $0.id == importedGroup.id }),
                   GroupService.normalizedGroupName(existingGroup.name) == normalizedName {
                    mapping[importedGroup.id] = importedGroup.id
                }
                continue
            }

            guard !knownNames.contains(normalizedName) else {
                continue
            }

            var group = importedGroup
            group.sortOrder = groups.count + groupsToAppend.count
            groupsToAppend.append(group)
            knownIDs.insert(group.id)
            knownNames.insert(normalizedName)
            mapping[importedGroup.id] = group.id
        }

        guard !groupsToAppend.isEmpty else {
            return mapping
        }

        groups.append(contentsOf: groupsToAppend)
        sortGroups()
        return mapping
    }

    private func sanitizedBackupItem(
        _ item: ClipboardItem,
        groupIDMapping: [ClipboardGroup.ID: ClipboardGroup.ID],
        validGroupIDs: Set<ClipboardGroup.ID>
    ) -> ClipboardItem {
        guard let importedGroupID = item.groupID else {
            return item
        }

        var sanitizedItem = item
        guard let resolvedGroupID = groupIDMapping[importedGroupID] else {
            sanitizedItem.groupID = nil
            sanitizedItem.groupedAt = nil
            return sanitizedItem
        }

        if validGroupIDs.contains(resolvedGroupID) {
            sanitizedItem.groupID = resolvedGroupID
            sanitizedItem.groupedAt = item.groupedAt ?? item.createdAt
        } else {
            sanitizedItem.groupID = nil
            sanitizedItem.groupedAt = nil
        }
        return sanitizedItem
    }

    private static func fallbackLinkTitle(for url: URL) -> String {
        let path = url.path(percentEncoded: false)
        if !path.isEmpty, path != "/" {
            return URL(fileURLWithPath: path).lastPathComponent
        }

        return url.host(percentEncoded: false) ?? url.absoluteString
    }

    private func fileReferences(from urls: [URL]) -> [ClipboardFileReference] {
        let itemID = UUID()
        let createdAt = Date()
        var seenPaths = Set<String>()

        return urls.compactMap { url -> URL? in
            guard url.isFileURL else {
                return nil
            }

            let standardizedURL = url.standardizedFileURL
            guard seenPaths.insert(standardizedURL.path).inserted else {
                return nil
            }

            return standardizedURL
        }
        .enumerated()
        .map { index, url in
            fileReference(
                for: url,
                itemID: itemID,
                orderIndex: index,
                createdAt: createdAt
            )
        }
    }

    private func fileReference(
        for url: URL,
        itemID: UUID,
        orderIndex: Int,
        createdAt: Date
    ) -> ClipboardFileReference {
        let checkedAt = Date()
        let resourceKeys: Set<URLResourceKey> = [
            .contentTypeKey,
            .fileAllocatedSizeKey,
            .fileSizeKey,
            .isAliasFileKey,
            .isDirectoryKey,
            .isReadableKey,
            .ubiquitousItemDownloadingStatusKey,
            .contentModificationDateKey,
        ]
        let values = try? url.resourceValues(forKeys: resourceKeys)

        return ClipboardFileReference(
            itemID: itemID,
            orderIndex: orderIndex,
            path: url.path,
            displayName: url.lastPathComponent,
            fileExtension: url.pathExtension.isEmpty ? nil : url.pathExtension,
            contentType: contentTypeIdentifier(for: url, values: values),
            fileSize: values?.fileSize ?? values?.fileAllocatedSize,
            modifiedAt: values?.contentModificationDate,
            isDirectory: values?.isDirectory ?? false,
            isAlias: values?.isAliasFile ?? false,
            pathStatus: pathStatus(for: url, values: values),
            lastCheckedAt: checkedAt,
            createdAt: createdAt
        )
    }

    private func contentTypeIdentifier(for url: URL, values: URLResourceValues?) -> String? {
        if #available(macOS 11.0, *), let contentType = values?.contentType {
            return contentType.identifier
        }

        return UTType(filenameExtension: url.pathExtension)?.identifier
    }

    private func pathStatus(for url: URL, values: URLResourceValues?) -> ClipboardFilePathStatus {
        if values?.ubiquitousItemDownloadingStatus == .notDownloaded {
            return .placeholder
        }

        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return .missing
        }

        if values?.isReadable == false || !FileManager.default.isReadableFile(atPath: url.path) {
            return .permissionDenied
        }

        return .available
    }

    @discardableResult
    private func pruneExpiredItems(now: Date = Date()) -> Bool {
        let validGroupIDs = Set(groups.map(\.id))
        let removedItems = HistoryRetentionService.expiredItems(
            in: items,
            policy: retentionPolicy,
            validGroupIDs: validGroupIDs,
            now: now
        )

        guard !removedItems.isEmpty else {
            return false
        }

        let removedIDs = Set(removedItems.map(\.id))
        items.removeAll { removedIDs.contains($0.id) }
        rebuildItemIndexes()
        cancelOCRTasks(for: removedItems)
        cancelLinkMetadataTasks(for: removedItems)
        deleteExternalFiles(for: removedItems)
        rebuildRecentHashes()
        return true
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
