import Foundation
import Testing
@testable import ClipEase

@MainActor
@Test func terminationFlushDoesNotReplaceTheFullSnapshotWhenNoRepairIsPending() {
    let repository = TerminationRecordingRepository()
    let persistence = ClipboardHistoryPersistence(repository: repository)
    let writer = ClipboardHistorySaveWriter(persistence: persistence)
    let suiteName = "termination-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.set(HistoryRetentionPolicy.forever.rawValue, forKey: "history.retentionPolicy")
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let store = ClipboardHistoryStore(
        persistence: persistence,
        userDefaults: defaults,
        saveWriter: writer
    )
    repository.resetCounts()

    store.flushPendingSave()

    #expect(repository.saveSnapshotCount == 0)
}

@Test func saveWriterFlushDrainsQueuedIncrementalWritesWithoutFullReplacement() {
    let repository = TerminationRecordingRepository()
    let persistence = ClipboardHistoryPersistence(repository: repository)
    let writer = ClipboardHistorySaveWriter(persistence: persistence)
    let item = ClipboardItem.text("queued", sourceApp: .clipease)

    writer.upsertAsync(
        item,
        deleting: [],
        groups: [],
        revision: 1
    )
    writer.flush()

    #expect(repository.upsertCount == 1)
    #expect(repository.saveSnapshotCount == 0)
}

@Test func applicationTerminationDrainCompletesAfterBothIncrementalWriters() async {
    let report = await ApplicationTerminationDrainCoordinator.drain(
        timeoutNanoseconds: 300_000_000,
        payloadDrain: {},
        historyDrain: { .empty },
        diagnosticsDrain: {
            PerformanceDiagnosticsShutdownDrainResult(
                outcome: .completed,
                droppedEventCount: 2,
                elapsedMS: 1
            )
        }
    )

    #expect(report.outcome == .completed)
    #expect(report.pendingComponents.isEmpty)
    #expect(report.historyDrainResult == .empty)
    #expect(report.diagnosticsDroppedEventCount == 2)
}

@Test func applicationTerminationDrainFlushesHistoryAfterPayloadsFinish() async {
    let probe = TerminationDrainOrderingProbe()

    let report = await ApplicationTerminationDrainCoordinator.drain(
        timeoutNanoseconds: 300_000_000,
        payloadDrain: {
            try? await Task.sleep(for: .milliseconds(25))
            await probe.markPayloadComplete()
        },
        historyDrain: {
            await probe.recordHistoryObservation()
            return .empty
        },
        diagnosticsDrain: {
            PerformanceDiagnosticsShutdownDrainResult(
                outcome: .completed,
                droppedEventCount: 0,
                elapsedMS: 1
            )
        }
    )

    #expect(report.outcome == .completed)
    #expect(await probe.historyObservedCompletedPayload)
}

@Test func applicationTerminationDrainReportsTimedOutComponent() async {
    let report = await ApplicationTerminationDrainCoordinator.drain(
        timeoutNanoseconds: 100_000_000,
        payloadDrain: {},
        historyDrain: {
            try? await Task.sleep(nanoseconds: 500_000_000)
            return .empty
        },
        diagnosticsDrain: {
            PerformanceDiagnosticsShutdownDrainResult(
                outcome: .completed,
                droppedEventCount: 0,
                elapsedMS: 1
            )
        }
    )

    #expect(report.outcome == .timedOut)
    #expect(report.pendingComponents == [.history])
    #expect(report.historyDrainResult == nil)
}

@Test func applicationTerminationDrainReportsTimedOutPayload() async {
    let report = await ApplicationTerminationDrainCoordinator.drain(
        timeoutNanoseconds: 100_000_000,
        payloadDrain: {
            try? await Task.sleep(nanoseconds: 500_000_000)
        },
        historyDrain: { .empty },
        diagnosticsDrain: {
            PerformanceDiagnosticsShutdownDrainResult(
                outcome: .completed,
                droppedEventCount: 0,
                elapsedMS: 1
            )
        }
    )

    #expect(report.outcome == .timedOut)
    #expect(report.pendingComponents == [.payload, .history])
    #expect(report.historyDrainResult == nil)
}

@Test func applicationTerminationPolicyKeepsTheThreeHundredMillisecondContract() {
    #expect(ApplicationTerminationPolicy.totalBudgetNanoseconds == 300_000_000)
    #expect(
        ApplicationTerminationPolicy.coordinatorTimeoutNanoseconds
            < ApplicationTerminationPolicy.totalBudgetNanoseconds
    )
    #expect(
        ApplicationTerminationPolicy.diagnosticsTimeoutNanoseconds
            < ApplicationTerminationPolicy.coordinatorTimeoutNanoseconds
    )
}

@Test func applicationTerminationRequestStateStartsOnlyOneDrainAndRepliesOnce() {
    var state = ApplicationTerminationRequestState()

    #expect(state.request() == .startDrain)
    #expect(state.request() == .waitForDrain)
    let firstReply = state.markReplyIssued()
    let duplicateReply = state.markReplyIssued()
    #expect(firstReply)
    #expect(duplicateReply == false)
    #expect(state.request() == .terminateNow)
}

@Test func applicationTerminationDrainLeavesHeadroomInsideThreeHundredMillisecondBudget() {
    #expect(
        ApplicationTerminationPolicy.diagnosticsTimeoutNanoseconds
            < ApplicationTerminationPolicy.coordinatorTimeoutNanoseconds
    )
    #expect(
        ApplicationTerminationPolicy.coordinatorTimeoutNanoseconds
            < ApplicationTerminationPolicy.totalBudgetNanoseconds
    )
}

private final class TerminationRecordingRepository: ClipboardHistoryRepository, @unchecked Sendable {
    private let lock = NSLock()
    private var storedSaveSnapshotCount = 0
    private var storedUpsertCount = 0

    var saveSnapshotCount: Int {
        lock.withLock { storedSaveSnapshotCount }
    }

    var upsertCount: Int {
        lock.withLock { storedUpsertCount }
    }

    func resetCounts() {
        lock.withLock {
            storedSaveSnapshotCount = 0
            storedUpsertCount = 0
        }
    }

    func loadSnapshot() throws -> ClipboardHistorySnapshot {
        ClipboardHistorySnapshot(items: [], groups: [])
    }

    func saveSnapshot(_ snapshot: ClipboardHistorySnapshot) throws {
        lock.withLock {
            storedSaveSnapshotCount += 1
        }
    }

    func upsertItem(
        _ item: ClipboardItem,
        deleting deletedIDs: Set<ClipboardItem.ID>,
        groups: [ClipboardGroup]
    ) throws {
        lock.withLock {
            storedUpsertCount += 1
        }
    }

    func deleteExpiredItems(before cutoff: Date) throws -> ClipboardAttachmentCleanup {
        .empty
    }

    func deleteExpiredItemsWithResult(
        before cutoff: Date
    ) throws -> ClipboardHistoryRetentionDeletionResult {
        ClipboardHistoryRetentionDeletionResult(
            cleanup: .empty,
            removedItemIDs: [],
            protectedGroupIDs: []
        )
    }
}

private actor TerminationDrainOrderingProbe {
    private var payloadCompleted = false
    private(set) var historyObservedCompletedPayload = false

    func markPayloadComplete() {
        payloadCompleted = true
    }

    func recordHistoryObservation() {
        historyObservedCompletedPayload = payloadCompleted
    }
}
