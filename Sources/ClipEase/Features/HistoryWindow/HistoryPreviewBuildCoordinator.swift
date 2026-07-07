import Foundation

struct HistoryPreviewSourceSignature: Equatable, Sendable {
    let id: ClipboardItem.ID
    let type: ClipboardItemType
    let createdAt: Date
    let sourceAppName: String
    let sourceBundleID: String?
    let iconName: String
    let iconFileName: String?
    let headerColorHex: String
    let linkTitle: String?
    let linkSubtitle: String?
    let isPinned: Bool
    let groupID: ClipboardGroup.ID?
    let groupedAt: Date?
    let richTextFileName: String?
    let imageFileName: String?
    let imageWidth: Int?
    let imageHeight: Int?
    let imageHash: String?
    let fileReferences: [ClipboardFileReference]
    let text: String

    init(item: ClipboardItem) {
        id = item.id
        type = item.type
        createdAt = item.createdAt
        sourceAppName = item.sourceAppName
        sourceBundleID = item.sourceBundleID
        iconName = item.iconName
        iconFileName = item.iconFileName
        headerColorHex = item.headerColorHex
        linkTitle = item.linkTitle
        linkSubtitle = item.linkSubtitle
        isPinned = item.isPinned
        groupID = item.groupID
        groupedAt = item.groupedAt
        richTextFileName = item.richTextFileName
        imageFileName = item.imageFileName
        imageWidth = item.imageWidth
        imageHeight = item.imageHeight
        imageHash = item.imageHash
        fileReferences = item.fileReferences
        text = item.text
    }

    func matches(item: ClipboardItem) -> Bool {
        id == item.id &&
            type == item.type &&
            createdAt == item.createdAt &&
            sourceAppName == item.sourceAppName &&
            sourceBundleID == item.sourceBundleID &&
            iconName == item.iconName &&
            iconFileName == item.iconFileName &&
            headerColorHex == item.headerColorHex &&
            linkTitle == item.linkTitle &&
            linkSubtitle == item.linkSubtitle &&
            isPinned == item.isPinned &&
            groupID == item.groupID &&
            groupedAt == item.groupedAt &&
            richTextFileName == item.richTextFileName &&
            imageFileName == item.imageFileName &&
            imageWidth == item.imageWidth &&
            imageHeight == item.imageHeight &&
            imageHash == item.imageHash &&
            fileReferences == item.fileReferences &&
            text == item.text
    }
}

struct CachedHistoryPreviewItem: Sendable {
    let signature: HistoryPreviewSourceSignature
    let item: HistoryPreviewItem
}

enum HistoryPreviewBuildCoordinator {
    struct PreviewSignatureUpdate: Sendable {
        let sourceSignature: [HistoryPreviewSourceSignature]
        let hasChanges: Bool
    }

    enum RebuildResult: Sendable {
        case full(
            previewItems: [HistoryPreviewItem],
            nextCache: [ClipboardItem.ID: CachedHistoryPreviewItem],
            sourceAppSnapshot: HistorySourceAppFilterSnapshot,
            cacheHitCount: Int,
            durationMS: Double
        )
        case prepend(
            insertedItems: [HistoryPreviewItem],
            nextCache: [ClipboardItem.ID: CachedHistoryPreviewItem],
            sourceAppSnapshot: HistorySourceAppFilterSnapshot,
            cacheHitCount: Int,
            durationMS: Double
        )

        var sourceAppSnapshot: HistorySourceAppFilterSnapshot {
            switch self {
            case .full(_, _, let sourceAppSnapshot, _, _),
                 .prepend(_, _, let sourceAppSnapshot, _, _):
                sourceAppSnapshot
            }
        }
    }

    struct IncrementalPreviewInsertion: Sendable {
        let insertedItems: [HistoryPreviewItem]
        let cacheHitCount: Int
    }

    static func previewSignatureUpdate(
        sourceItems: [ClipboardItem],
        currentSourceSignature: [HistoryPreviewSourceSignature]
    ) -> PreviewSignatureUpdate {
        guard !currentSourceSignature.isEmpty,
              sourceItems.count >= currentSourceSignature.count else {
            let sourceSignature = sourceItems.map(HistoryPreviewSourceSignature.init)
            return PreviewSignatureUpdate(
                sourceSignature: sourceSignature,
                hasChanges: sourceSignature != currentSourceSignature
            )
        }

        let insertedCount = sourceItems.count - currentSourceSignature.count
        guard insertedCount > 0,
              insertedCount <= 8 else {
            let sourceSignature = sourceItems.map(HistoryPreviewSourceSignature.init)
            return PreviewSignatureUpdate(
                sourceSignature: sourceSignature,
                hasChanges: sourceSignature != currentSourceSignature
            )
        }

        for (offset, signature) in currentSourceSignature.enumerated() {
            guard signature.matches(item: sourceItems[offset + insertedCount]) else {
                let sourceSignature = sourceItems.map(HistoryPreviewSourceSignature.init)
                return PreviewSignatureUpdate(
                    sourceSignature: sourceSignature,
                    hasChanges: sourceSignature != currentSourceSignature
                )
            }
        }

        var sourceSignature = sourceItems.prefix(insertedCount).map(HistoryPreviewSourceSignature.init)
        sourceSignature.reserveCapacity(sourceItems.count)
        sourceSignature.append(contentsOf: currentSourceSignature)
        return PreviewSignatureUpdate(sourceSignature: sourceSignature, hasChanges: true)
    }

    static func shouldApplyResult(
        isTaskCancelled: Bool,
        generation: UInt64,
        currentGeneration: UInt64
    ) -> Bool {
        !isTaskCancelled && generation == currentGeneration
    }

    static func rebuild(
        sourceItems: [ClipboardItem],
        sourceSignature: [HistoryPreviewSourceSignature],
        currentPreviewItems: [HistoryPreviewItem],
        currentSourceSignature: [HistoryPreviewSourceSignature],
        currentPreviewItemCache: [ClipboardItem.ID: CachedHistoryPreviewItem],
        retainedCacheIDs: Set<ClipboardItem.ID>
    ) throws -> RebuildResult {
        let startedAt = CFAbsoluteTimeGetCurrent()
        if let insertion = incrementalPreviewInsertion(
            sourceItems: sourceItems,
            sourceSignature: sourceSignature,
            currentPreviewItems: currentPreviewItems,
            currentSourceSignature: currentSourceSignature
        ) {
            var nextCache: [ClipboardItem.ID: CachedHistoryPreviewItem] = [:]
            nextCache.reserveCapacity(min(retainedCacheIDs.count, sourceItems.count))

            for (index, item) in sourceItems.enumerated() {
                try Task.checkCancellation()
                guard retainedCacheIDs.contains(item.id) else {
                    continue
                }

                let signature = sourceSignature[index]
                let previewItem: HistoryPreviewItem
                if index < insertion.insertedItems.count {
                    previewItem = insertion.insertedItems[index]
                } else {
                    previewItem = currentPreviewItems[index - insertion.insertedItems.count]
                }
                nextCache[item.id] = CachedHistoryPreviewItem(
                    signature: signature,
                    item: previewItem
                )

                if nextCache.count >= retainedCacheIDs.count {
                    break
                }
            }

            try Task.checkCancellation()
            let sourceAppSnapshot = HistorySourceAppFilter.snapshot(from: sourceItems)
            let durationMS = (CFAbsoluteTimeGetCurrent() - startedAt) * 1_000
            return .prepend(
                insertedItems: insertion.insertedItems,
                nextCache: nextCache,
                sourceAppSnapshot: sourceAppSnapshot,
                cacheHitCount: insertion.cacheHitCount,
                durationMS: durationMS
            )
        }

        var previewItems: [HistoryPreviewItem] = []
        previewItems.reserveCapacity(sourceItems.count)
        var cacheHitCount = 0
        var nextCache: [ClipboardItem.ID: CachedHistoryPreviewItem] = [:]
        nextCache.reserveCapacity(min(retainedCacheIDs.count, sourceItems.count))

        for (index, item) in sourceItems.enumerated() {
            try Task.checkCancellation()
            let signature = sourceSignature[index]
            let previewItem: HistoryPreviewItem
            if let cachedItem = currentPreviewItemCache[item.id],
               cachedItem.signature == signature {
                previewItem = cachedItem.item
                cacheHitCount += 1
            } else {
                previewItem = HistoryPreviewItem(item: item)
            }

            previewItems.append(previewItem)
            if retainedCacheIDs.contains(item.id) {
                nextCache[item.id] = CachedHistoryPreviewItem(
                    signature: signature,
                    item: previewItem
                )
            }
        }

        try Task.checkCancellation()
        let sourceAppSnapshot = HistorySourceAppFilter.snapshot(from: sourceItems)
        let durationMS = (CFAbsoluteTimeGetCurrent() - startedAt) * 1_000
        return .full(
            previewItems: previewItems,
            nextCache: nextCache,
            sourceAppSnapshot: sourceAppSnapshot,
            cacheHitCount: cacheHitCount,
            durationMS: durationMS
        )
    }

    static func incrementalPreviewInsertion(
        sourceItems: [ClipboardItem],
        sourceSignature: [HistoryPreviewSourceSignature],
        currentPreviewItems: [HistoryPreviewItem],
        currentSourceSignature: [HistoryPreviewSourceSignature]
    ) -> IncrementalPreviewInsertion? {
        guard !currentPreviewItems.isEmpty,
              sourceItems.count >= currentPreviewItems.count,
              currentSourceSignature.count == currentPreviewItems.count,
              sourceSignature.count == sourceItems.count else {
            return nil
        }

        let insertedCount = sourceItems.count - currentPreviewItems.count
        guard insertedCount >= 0,
              insertedCount <= 8,
              sourceSignature.dropFirst(insertedCount).elementsEqual(currentSourceSignature) else {
            return nil
        }

        var insertedItems: [HistoryPreviewItem] = []
        insertedItems.reserveCapacity(insertedCount)

        for index in 0..<insertedCount {
            insertedItems.append(HistoryPreviewItem(item: sourceItems[index]))
        }

        return IncrementalPreviewInsertion(
            insertedItems: insertedItems,
            cacheHitCount: currentPreviewItems.count
        )
    }
}
