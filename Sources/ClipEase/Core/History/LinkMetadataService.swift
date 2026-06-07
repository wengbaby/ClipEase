import Foundation

struct LinkMetadataService {
    private var generationByItemID: [ClipboardItem.ID: Int] = [:]

    mutating func nextGeneration(for id: ClipboardItem.ID) -> Int {
        let generation = (generationByItemID[id] ?? 0) + 1
        generationByItemID[id] = generation
        return generation
    }

    func hasInFlightTask(for id: ClipboardItem.ID) -> Bool {
        generationByItemID[id] != nil
    }

    mutating func finishTask(for id: ClipboardItem.ID, generation: Int) -> Bool {
        guard generationByItemID[id] == generation else {
            return false
        }

        generationByItemID[id] = nil
        return true
    }

    mutating func cancelTasks(for ids: Set<ClipboardItem.ID>) {
        for id in ids {
            generationByItemID[id] = nil
        }
    }

    mutating func cancelAllTasks() {
        generationByItemID.removeAll()
    }

    static func canApplyMetadata(to item: ClipboardItem, expectedURL: URL) -> Bool {
        item.type == .link && item.url == expectedURL
    }

    static func shouldApplyMetadata(
        title: String?,
        storedImage: StoredClipboardImage?,
        to item: ClipboardItem
    ) -> Bool {
        item.linkTitle != title || storedImage != nil
    }
}
