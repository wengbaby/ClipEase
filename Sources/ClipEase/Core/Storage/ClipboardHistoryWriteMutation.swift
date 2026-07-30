import Foundation

enum ClipboardHistoryWriteMutationError: LocalizedError {
    case itemNotFound(ClipboardItem.ID)

    var errorDescription: String? {
        switch self {
        case .itemNotFound(let itemID):
            "Clipboard item \(itemID.uuidString) does not exist."
        }
    }
}

struct ClipboardHistoryWriteBatchPolicy: Equatable, Sendable {
    static let enterpriseDefault = ClipboardHistoryWriteBatchPolicy(
        maximumDelayMilliseconds: 20,
        maximumMutationCount: 50
    )

    let maximumDelayMilliseconds: Int
    let maximumMutationCount: Int

    init(maximumDelayMilliseconds: Int, maximumMutationCount: Int) {
        self.maximumDelayMilliseconds = max(0, maximumDelayMilliseconds)
        self.maximumMutationCount = max(1, maximumMutationCount)
    }
}

struct ClipboardHistoryWriteDrainResult: Equatable, Sendable {
    let attemptedMutationCount: Int
    let committedMutationCount: Int
    let requiresFullResync: Bool

    static let empty = ClipboardHistoryWriteDrainResult(
        attemptedMutationCount: 0,
        committedMutationCount: 0,
        requiresFullResync: false
    )
}

struct ClipboardHistoryTerminationDrainHandle: Sendable {
    private let drainOperation: @Sendable () async -> ClipboardHistoryWriteDrainResult

    init(
        drainOperation: @escaping @Sendable () async -> ClipboardHistoryWriteDrainResult
    ) {
        self.drainOperation = drainOperation
    }

    func drain() async -> ClipboardHistoryWriteDrainResult {
        await drainOperation()
    }
}

struct ClipboardHistoryItemMutationFields: OptionSet, Equatable, Sendable {
    let rawValue: UInt8

    static let ocr = ClipboardHistoryItemMutationFields(rawValue: 1 << 0)
    static let pin = ClipboardHistoryItemMutationFields(rawValue: 1 << 1)
    static let group = ClipboardHistoryItemMutationFields(rawValue: 1 << 2)
    static let metadata = ClipboardHistoryItemMutationFields(rawValue: 1 << 3)
    static let content = ClipboardHistoryItemMutationFields(rawValue: 1 << 4)
}

struct ClipboardHistoryItemMutation: Equatable, Sendable {
    let item: ClipboardItem
    let fields: ClipboardHistoryItemMutationFields

    init(item: ClipboardItem, fields: ClipboardHistoryItemMutationFields) {
        self.item = item
        self.fields = fields
    }

    func merging(_ newer: ClipboardHistoryItemMutation) -> ClipboardHistoryItemMutation? {
        guard item.id == newer.item.id else {
            return nil
        }
        return ClipboardHistoryItemMutation(
            item: newer.item,
            fields: fields.union(newer.fields)
        )
    }
}

struct ClipboardHistoryUpsertMutation: Equatable, Sendable {
    let item: ClipboardItem
    let deletedIDs: Set<ClipboardItem.ID>
    let groups: [ClipboardGroup]
}

enum ClipboardHistoryRepositoryMutation: Equatable, Sendable {
    case upsert(ClipboardHistoryUpsertMutation)
    case update(ClipboardHistoryItemMutation)

    var item: ClipboardItem {
        switch self {
        case .upsert(let mutation):
            mutation.item
        case .update(let mutation):
            mutation.item
        }
    }

    var itemID: ClipboardItem.ID {
        item.id
    }
}
