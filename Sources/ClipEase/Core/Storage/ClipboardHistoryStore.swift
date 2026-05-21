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
    @Published private(set) var items: [ClipboardItem] = []
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
    private let persistence: ClipboardHistoryPersistence
    private let saveWriter: ClipboardHistorySaveWriter
    private let userDefaults: UserDefaults
    private var recentHashes: Set<String> = []
    private var itemIDsByHash: [String: Set<ClipboardItem.ID>] = [:]
    private var skippedClipboardTexts: Set<String> = []
    private var skippedImageHashes: Set<String> = []
    private var skippedClipboardFilePathSets: Set<String> = []
    private var ocrTaskByItemID: [ClipboardItem.ID: Task<Void, Never>] = [:]
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
        let snapshot = persistence.loadSnapshot()
        self.items = snapshot.items
        self.groups = snapshot.groups
        sortItems()
        sortGroups()
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

        if skippedClipboardTexts.remove(normalizedText) != nil {
            persistence.deleteRichText(fileName: storedRichText.fileName)
            return
        }

        var item = ClipboardItem.richText(
            plainText: normalizedText,
            fileName: storedRichText.fileName,
            sourceApp: sourceApp
        )
        let now = Date()
        if let groupID, groups.contains(where: { $0.id == groupID }) {
            item.groupID = groupID
            item.groupedAt = now
        }

        upsertClipboardItem(
            item,
            replacingRichTextFileName: storedRichText.fileName
        )
    }

    func addImage(_ image: NSImage, sourceApp: SourceAppInfo) {
        guard let storedImage = persistence.saveImage(image) else {
            return
        }

        if skippedImageHashes.remove(storedImage.hash) != nil {
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
    }

    func addFiles(_ urls: [URL], sourceApp: SourceAppInfo) {
        let references = fileReferences(from: urls)
        guard !references.isEmpty else {
            return
        }

        let item = ClipboardItem.file(
            references: references,
            sourceApp: sourceApp
        )

        let insertedItem = upsertClipboardItem(item)
        enqueueOCRIfNeeded(for: insertedItem)
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
        let sanitizedItems = sanitizedImportedItems(importedItems)
        let newItems = nonDuplicateItems(from: sanitizedItems)

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
        rebuildRecentHashes()
        scheduleSave()
        return newItems.count
    }

    func duplicateCount(for importedItems: [ClipboardItem]) -> Int {
        importedItems.count - nonDuplicateItems(from: importedItems).count
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

    enum GroupRenameResult: Equatable {
        case renamed
        case unchanged
        case empty
        case duplicate
        case notFound
    }

    @discardableResult
    func createGroup() -> ClipboardGroup {
        let group = ClipboardGroup.makeDefault(
            name: uniqueGroupName(baseName: ClipboardGroup.defaultName),
            sortOrder: groups.count
        )
        groups.append(group)
        sortGroups()
        scheduleSave()
        return group
    }

    @discardableResult
    func renameGroup(_ id: ClipboardGroup.ID, name: String) -> GroupRenameResult {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            return .empty
        }

        guard let index = groups.firstIndex(where: { $0.id == id }) else {
            return .notFound
        }

        if normalizedGroupName(groups[index].name) == normalizedGroupName(trimmedName) {
            return .unchanged
        }

        guard isGroupNameAvailable(trimmedName, excluding: id) else {
            return .duplicate
        }

        groups[index].name = trimmedName
        groups[index].updatedAt = Date()
        scheduleSave()
        return .renamed
    }

    func updateGroupAppearance(_ id: ClipboardGroup.ID, colorHex: String? = nil, iconName: String? = nil) {
        guard let index = groups.firstIndex(where: { $0.id == id }) else {
            return
        }

        if let colorHex {
            groups[index].colorHex = colorHex
        }
        if let iconName {
            groups[index].iconName = iconName
        }
        groups[index].updatedAt = Date()
        scheduleSave()
    }

    func deleteGroup(_ id: ClipboardGroup.ID) -> Int {
        let removedItems = items.filter { $0.groupID == id }
        groups.removeAll { $0.id == id }
        items.removeAll { $0.groupID == id }
        sortGroups()
        deleteExternalFiles(for: removedItems)
        rebuildRecentHashes()
        saveImmediately()
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
        sortGroups()
        deleteExternalFiles(for: removedItems)
        rebuildRecentHashes()
        saveImmediately()
        return removedItems.count
    }

    func moveGroup(fromOffsets source: IndexSet, toOffset destination: Int) {
        groups.move(fromOffsets: source, toOffset: destination)
        sortGroups()
        scheduleSave()
    }

    func addItem(_ id: ClipboardItem.ID?, toGroup groupID: ClipboardGroup.ID) {
        guard let id,
              groups.contains(where: { $0.id == groupID }),
              let index = items.firstIndex(where: { $0.id == id }) else {
            return
        }

        let now = Date()
        items[index].groupID = groupID
        items[index].groupedAt = now
        sortItems()
        scheduleSave()
    }

    @discardableResult
    func addItems(_ ids: Set<ClipboardItem.ID>, toGroup groupID: ClipboardGroup.ID) -> Int {
        guard !ids.isEmpty,
              groups.contains(where: { $0.id == groupID }) else {
            return 0
        }

        let now = Date()
        var changedCount = 0
        for index in items.indices where ids.contains(items[index].id) {
            var didChangeItem = false
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
              let index = items.firstIndex(where: { $0.id == id }) else {
            return
        }

        items[index].groupID = nil
        items[index].groupedAt = nil
        scheduleSave()
    }

    func group(with id: ClipboardGroup.ID?) -> ClipboardGroup? {
        guard let id else {
            return nil
        }

        return groups.first { $0.id == id }
    }

    func itemCount(inGroup id: ClipboardGroup.ID) -> Int {
        items.lazy.filter { $0.groupID == id }.count
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

    @discardableResult
    func updateEditableContent(for id: ClipboardItem.ID?, text: String) -> ClipboardItem? {
        guard let id,
              let index = items.firstIndex(where: { $0.id == id }) else {
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
        guard let updatedItem = items.first(where: { $0.id == id }) else {
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
        let persistence = persistence
        Task.detached(priority: .utility) {
            guard let pageMetadata = await LinkTitleFetcher.pageMetadata(for: url) else {
                return
            }

            if let title = pageMetadata.title {
                await MainActor.run {
                    self.updateLinkMetadata(
                        title: title,
                        storedImage: nil,
                        for: id,
                        url: url
                    )
                }
            }

            let storedImage = await LinkTitleFetcher.previewImageData(from: pageMetadata, baseURL: url)
                .flatMap(NSImage.init(data:))
                .flatMap(persistence.saveImage)

            guard let storedImage else {
                return
            }

            await MainActor.run {
                self.updateLinkMetadata(
                    title: nil,
                    storedImage: storedImage,
                    for: id,
                    url: url
                )
            }
        }
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
        guard let index = items.firstIndex(where: { $0.id == id }),
              items[index].type == .link,
              items[index].url == url else {
            return
        }

        let existingItem = items[index]
        guard existingItem.linkTitle != title || storedImage != nil else {
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

    func skipNextClipboardFiles(_ urls: [URL]) {
        let key = clipboardFilePathSetKey(for: urls)
        guard !key.isEmpty else {
            return
        }

        skippedClipboardFilePathSets.insert(key)
    }

    func consumeSkippedClipboardFiles(_ urls: [URL]) -> Bool {
        let key = clipboardFilePathSetKey(for: urls)
        guard !key.isEmpty else {
            return false
        }

        return skippedClipboardFilePathSets.remove(key) != nil
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
              let index = items.firstIndex(where: { $0.id == id }) else {
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
            if let rollbackIndex = items.firstIndex(where: { $0.id == id }) {
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
        guard let updatedItem = items.first(where: { $0.id == id }) else {
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

    private func enqueueOCRIfNeeded(for item: ClipboardItem) {
        guard item.ocrStatus == .pending else {
            return
        }

        ocrTaskByItemID[item.id]?.cancel()
        ocrTaskByItemID[item.id] = Task(priority: .utility) { [weak self] in
            guard let self else {
                return
            }

            await self.performOCR(for: item)
        }
    }

    private func performOCR(for item: ClipboardItem) async {
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

        guard let sourceURL else {
            await MainActor.run {
                self.applyOCRResult(
                    .init(text: "", emails: [], phoneNumbers: [], urls: [], textRegions: []),
                    status: .failed,
                    to: item.id
                )
            }
            return
        }

        await MainActor.run {
            self.setOCRStatus(.processing, for: item.id)
        }

        let result: ClipboardOCRMatch?
        switch item.type {
        case .image:
            result = await ClipboardOCRService.shared.recognizeImage(at: sourceURL)
        case .file:
            result = await ClipboardOCRService.shared.recognizePDF(at: sourceURL)
        default:
            result = nil
        }

        await MainActor.run {
            if let result {
                self.applyOCRResult(result, status: .completed, to: item.id)
            } else {
                self.applyOCRResult(.init(text: "", emails: [], phoneNumbers: [], urls: [], textRegions: []), status: .failed, to: item.id)
            }
        }
    }

    private func setOCRStatus(_ status: ClipboardOCRStatus, for id: ClipboardItem.ID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else {
            return
        }

        items[index].ocrStatus = status
        scheduleSave()
    }

    private func applyOCRResult(_ result: ClipboardOCRMatch, status: ClipboardOCRStatus, to id: ClipboardItem.ID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else {
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
        scheduleSave()
        ocrTaskByItemID[id] = nil
    }

    private func sortItems() {
        items.sort { lhs, rhs in
            if lhs.isPinned != rhs.isPinned {
                return lhs.isPinned && !rhs.isPinned
            }

            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt > rhs.createdAt
            }

            return (lhs.pinnedAt ?? lhs.createdAt) > (rhs.pinnedAt ?? rhs.createdAt)
        }
    }

    private func sortGroups() {
        groups.sort { lhs, rhs in
            lhs.sortOrder == rhs.sortOrder ? lhs.createdAt < rhs.createdAt : lhs.sortOrder < rhs.sortOrder
        }
        for index in groups.indices {
            groups[index].sortOrder = index
        }
    }

    private func scheduleSave() {
        deferredSaveTask?.cancel()
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

    private func saveImmediately() {
        do {
            try saveImmediatelyOrThrow()
        } catch {
            NSLog("ClipEase failed to save clipboard history: \(error.localizedDescription)")
        }
    }

    private func saveImmediatelyOrThrow() throws {
        deferredSaveTask?.cancel()
        deferredSaveTask = nil
        try saveWriter.saveSync(ClipboardHistorySnapshot(items: items, groups: groups), revision: nextSaveRevision())
    }

    private func nextSaveRevision() -> Int {
        saveRevision += 1
        return saveRevision
    }

    private func rebuildRecentHashes() {
        var hashes: Set<String> = []
        var idsByHash: [String: Set<ClipboardItem.ID>] = [:]
        hashes.reserveCapacity(items.count)
        idsByHash.reserveCapacity(items.count)

        for item in items {
            let hash = textHash(for: item)
            hashes.insert(hash)
            idsByHash[hash, default: []].insert(item.id)
        }

        recentHashes = hashes
        itemIDsByHash = idsByHash
    }

    @discardableResult
    private func upsertClipboardItem(
        _ item: ClipboardItem,
        replacingRichTextFileName newRichTextFileName: String? = nil
    ) -> ClipboardItem {
        let hash = Self.textHash(for: item)
        let duplicateIDs = itemIDsByHash[hash] ?? []
        let duplicateItems = items.filter { duplicateIDs.contains($0.id) }
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
        }

        items.insert(insertedItem, at: 0)
        sortItems()
        pruneExpiredItems()
        rebuildRecentHashes()
        scheduleSave()
        latestItemFocusRequest = ClipboardItemFocusRequest(itemID: insertedItem.id, reason: .inserted)
        return insertedItem
    }

    private func textHash(for item: ClipboardItem) -> String {
        Self.textHash(for: item)
    }

    nonisolated private static func textHash(for item: ClipboardItem) -> String {
        switch item.type {
        case .image:
            "\(item.sourceBundleID ?? "unknown"):\(item.imageHash ?? item.id.uuidString)"
        case .file:
            Self.fileHash(for: item.fileReferences, sourceBundleID: item.sourceBundleID)
        case .text, .link, .color:
            "\(item.sourceBundleID ?? "unknown"):\(item.text)"
        }
    }

    nonisolated private static func fileHash(for references: [ClipboardFileReference], sourceBundleID: String?) -> String {
        let paths = references.map { reference in
            "\(reference.orderIndex):\(reference.path)"
        }.joined(separator: "\u{1F}")
        return "\(sourceBundleID ?? "unknown"):files:\(paths)"
    }

    private func clipboardFilePathSetKey(for urls: [URL]) -> String {
        urls
            .filter(\.isFileURL)
            .map { $0.standardizedFileURL.path }
            .sorted()
            .joined(separator: "\u{1F}")
    }

    private func nonDuplicateItems(from importedItems: [ClipboardItem]) -> [ClipboardItem] {
        let existingIDs = Set(items.map(\.id))
        let existingTextHashes = Set(items.map(textHash))
        return importedItems.filter { item in
            !existingIDs.contains(item.id) && !existingTextHashes.contains(textHash(for: item))
        }
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
        var knownNames = Set(groups.map { normalizedGroupName($0.name) })
        var groupsToAppend: [ClipboardGroup] = []

        for importedGroup in importedGroups {
            let normalizedName = normalizedGroupName(importedGroup.name)
            if knownIDs.contains(importedGroup.id) {
                if let existingGroup = groups.first(where: { $0.id == importedGroup.id }),
                   normalizedGroupName(existingGroup.name) == normalizedName {
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

    private func normalizedGroupName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase
    }

    private func isGroupNameAvailable(_ name: String, excluding id: ClipboardGroup.ID? = nil) -> Bool {
        let normalizedName = normalizedGroupName(name)
        return !groups.contains { group in
            if group.id == id {
                return false
            }

            return normalizedGroupName(group.name) == normalizedName
        }
    }

    private func uniqueGroupName(baseName: String) -> String {
        let trimmedBaseName = baseName.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedBaseName = trimmedBaseName.isEmpty ? ClipboardGroup.defaultName : trimmedBaseName

        if isGroupNameAvailable(resolvedBaseName) {
            return resolvedBaseName
        }

        var index = 2
        while true {
            let candidate = "\(resolvedBaseName) \(index)"
            if isGroupNameAvailable(candidate) {
                return candidate
            }
            index += 1
        }
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

    private func pruneExpiredItems(now: Date = Date()) {
        guard let days = retentionPolicy.days else {
            return
        }

        let cutoffDate = Calendar.current.date(
            byAdding: .day,
            value: -days,
            to: now
        ) ?? now
        let validGroupIDs = Set(groups.map(\.id))

        func shouldPrune(_ item: ClipboardItem) -> Bool {
            let hasValidGroup = item.groupID.map(validGroupIDs.contains) ?? false
            return !item.isPinned && !hasValidGroup && item.createdAt < cutoffDate
        }

        let removedItems = items.filter(shouldPrune)

        guard !removedItems.isEmpty else {
            return
        }

        items.removeAll(where: shouldPrune)
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

    func saveAsync(_ snapshot: ClipboardHistorySnapshot, revision: Int) {
        queue.async { [self] in
            do {
                try saveIfCurrent(snapshot, revision: revision)
            } catch {
                NSLog("ClipEase failed to save clipboard history: \(error.localizedDescription)")
            }
        }
    }

    func saveSync(_ snapshot: ClipboardHistorySnapshot, revision: Int) throws {
        try queue.sync { [self] in
            try saveIfCurrent(snapshot, revision: revision)
        }
    }

    private func saveIfCurrent(_ snapshot: ClipboardHistorySnapshot, revision: Int) throws {
        guard revision >= latestRevision else {
            return
        }

        latestRevision = revision
        try persistence.saveSnapshotOrThrow(snapshot)
    }
}
