import Foundation

enum DuplicateResolver {
    static func contentKey(for item: ClipboardItem) -> String {
        switch item.type {
        case .image:
            "\(sourceKey(for: item)):\(item.imageHash ?? item.id.uuidString)"
        case .file:
            fileContentKey(for: item.fileReferences, sourceBundleID: item.sourceBundleID)
        case .text, .link, .color:
            "\(sourceKey(for: item)):\(item.text)"
        }
    }

    static func mergedDuplicateItems(
        cachedItems: [ClipboardItem],
        persistedItems: [ClipboardItem]
    ) -> [ClipboardItem] {
        guard !persistedItems.isEmpty else {
            return cachedItems
        }

        var seenIDs = Set<ClipboardItem.ID>()
        var mergedItems: [ClipboardItem] = []
        mergedItems.reserveCapacity(cachedItems.count + persistedItems.count)
        for item in cachedItems + persistedItems where seenIDs.insert(item.id).inserted {
            mergedItems.append(item)
        }
        return mergedItems
    }

    static func nonDuplicateItems(
        importedItems: [ClipboardItem],
        existingItems: [ClipboardItem]
    ) -> [ClipboardItem] {
        let existingIDs = Set(existingItems.map(\.id))
        let existingContentKeys = Set(existingItems.map(contentKey))
        return importedItems.filter { item in
            !existingIDs.contains(item.id) && !existingContentKeys.contains(contentKey(for: item))
        }
    }

    private static func fileContentKey(
        for references: [ClipboardFileReference],
        sourceBundleID: String?
    ) -> String {
        let paths = references.map { reference in
            "\(reference.orderIndex):\(reference.path)"
        }.joined(separator: "\u{1F}")
        return "\(sourceBundleID ?? "unknown"):files:\(paths)"
    }

    private static func sourceKey(for item: ClipboardItem) -> String {
        item.sourceBundleID ?? "unknown"
    }
}
