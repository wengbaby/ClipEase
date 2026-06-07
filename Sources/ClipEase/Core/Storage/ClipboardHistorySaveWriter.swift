import Foundation

final class ClipboardHistorySaveWriter: @unchecked Sendable {
    private let queue = DispatchQueue(label: "app.clipease.history-save", qos: .utility)
    private let persistence: ClipboardHistoryPersistence
    private let compactionScheduler = ClipboardDatabaseCompactionScheduler()
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
                recordPersistenceError("history.persistence.save.failed", error: error, revision: revision)
            }
        }
    }

    func upsertAsync(_ item: ClipboardItem, deleting deletedIDs: Set<ClipboardItem.ID>, groups: [ClipboardGroup], revision: Int) {
        queue.async { [self] in
            do {
                try upsertIfCurrent(item, deleting: deletedIDs, groups: groups, revision: revision)
            } catch {
                NSLog("ClipEase failed to upsert clipboard history: \(error.localizedDescription)")
                recordPersistenceError("history.persistence.upsert.failed", error: error, revision: revision)
            }
        }
    }

    func insertItemsAsync(_ items: [ClipboardItem], revision: Int) {
        queue.async { [self] in
            do {
                try insertItemsIfCurrent(items, revision: revision)
            } catch {
                NSLog("ClipEase failed to insert clipboard history items: \(error.localizedDescription)")
                recordPersistenceError("history.persistence.insert.failed", error: error, revision: revision)
            }
        }
    }

    func deleteAsync(
        itemIDs: Set<ClipboardItem.ID>,
        groupIDs: Set<ClipboardGroup.ID>,
        revision: Int
    ) {
        queue.async { [self] in
            do {
                try deleteIfCurrent(itemIDs: itemIDs, groupIDs: groupIDs, revision: revision)
            } catch {
                NSLog("ClipEase failed to delete clipboard history items: \(error.localizedDescription)")
                recordPersistenceError("history.persistence.delete.failed", error: error, revision: revision)
            }
        }
    }

    func deleteAllAsync(revision: Int) {
        queue.async { [self] in
            do {
                try deleteAllIfCurrent(revision: revision)
            } catch {
                NSLog("ClipEase failed to clear clipboard history: \(error.localizedDescription)")
                recordPersistenceError("history.persistence.deleteAll.failed", error: error, revision: revision)
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
        compactDatabaseIfNeeded()
    }

    private func upsertIfCurrent(
        _ item: ClipboardItem,
        deleting deletedIDs: Set<ClipboardItem.ID>,
        groups: [ClipboardGroup],
        revision: Int
    ) throws {
        guard revision >= latestRevision else {
            return
        }

        latestRevision = revision
        let startedAt = CFAbsoluteTimeGetCurrent()
        try persistence.upsertItemOrThrow(item, deleting: deletedIDs, groups: groups)
        compactDatabaseIfNeeded()
        let durationMS = (CFAbsoluteTimeGetCurrent() - startedAt) * 1_000
        Task { @MainActor in
            PerformanceDiagnosticsService.shared.record(
                "history.persistence.upsert",
                category: "storage",
                durationMS: durationMS,
                itemCount: deletedIDs.count,
                resultCount: 1,
                metadata: ["revision": "\(revision)", "type": item.type.rawValue]
            )
        }
    }

    private func insertItemsIfCurrent(_ items: [ClipboardItem], revision: Int) throws {
        guard revision >= latestRevision,
              !items.isEmpty else {
            return
        }

        latestRevision = revision
        let startedAt = CFAbsoluteTimeGetCurrent()
        try persistence.insertItemsOrThrow(items)
        compactDatabaseIfNeeded()
        let durationMS = (CFAbsoluteTimeGetCurrent() - startedAt) * 1_000
        Task { @MainActor in
            PerformanceDiagnosticsService.shared.record(
                "history.persistence.insertDebugItems",
                category: "storage",
                durationMS: durationMS,
                itemCount: items.count,
                metadata: ["revision": "\(revision)"]
            )
        }
    }

    private func deleteIfCurrent(
        itemIDs: Set<ClipboardItem.ID>,
        groupIDs: Set<ClipboardGroup.ID>,
        revision: Int
    ) throws {
        guard revision >= latestRevision else {
            return
        }

        latestRevision = revision
        let startedAt = CFAbsoluteTimeGetCurrent()
        try persistence.deleteItemsOrThrow(with: itemIDs, deletingGroups: groupIDs)
        compactDatabaseIfNeeded()
        let durationMS = (CFAbsoluteTimeGetCurrent() - startedAt) * 1_000
        Task { @MainActor in
            PerformanceDiagnosticsService.shared.record(
                "history.persistence.delete",
                category: "storage",
                durationMS: durationMS,
                itemCount: itemIDs.count,
                resultCount: groupIDs.count,
                metadata: ["revision": "\(revision)"]
            )
        }
    }

    private func deleteAllIfCurrent(revision: Int) throws {
        guard revision >= latestRevision else {
            return
        }

        latestRevision = revision
        let startedAt = CFAbsoluteTimeGetCurrent()
        try persistence.deleteAllItemsAndGroupsOrThrow()
        compactDatabaseIfNeeded(force: true)
        let durationMS = (CFAbsoluteTimeGetCurrent() - startedAt) * 1_000
        Task { @MainActor in
            PerformanceDiagnosticsService.shared.record(
                "history.persistence.deleteAll",
                category: "storage",
                durationMS: durationMS,
                metadata: ["revision": "\(revision)"]
            )
        }
    }

    private func compactDatabaseIfNeeded(force: Bool = false) {
        let now = Date()
        guard compactionScheduler.shouldRun(now: now, force: force) else {
            return
        }

        compactionScheduler.markRun(at: now)
        let startedAt = CFAbsoluteTimeGetCurrent()
        let result: ClipboardDatabaseCompactionResult
        do {
            result = try persistence.compactDatabaseIfNeededOrThrow()
        } catch {
            NSLog("ClipEase failed to compact clipboard history database: \(error.localizedDescription)")
            recordPersistenceError("history.persistence.compact.failed", error: error, revision: latestRevision)
            return
        }

        guard case .compacted = result else {
            return
        }

        let durationMS = (CFAbsoluteTimeGetCurrent() - startedAt) * 1_000
        Task { @MainActor in
            PerformanceDiagnosticsService.shared.record(
                "history.persistence.compact",
                category: "storage",
                durationMS: durationMS,
                resultCount: result.reclaimedBytes,
                metadata: ["reclaimedBytes": "\(result.reclaimedBytes)"]
            )
        }
    }

    private func recordPersistenceError(_ name: String, error: Error, revision: Int) {
        Task { @MainActor in
            PerformanceDiagnosticsService.shared.recordError(
                name,
                category: "storage",
                error: error,
                metadata: ["revision": "\(revision)"]
            )
        }
    }
}
