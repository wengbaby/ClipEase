import Foundation
import Testing
@testable import ClipEase

@Test func retentionRunScheduleRunsAtStartupAndOnlyOncePerDate() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    var schedule = HistoryRetentionRunSchedule()
    let morning = Date(timeIntervalSince1970: 1_725_955_200)
    let evening = morning.addingTimeInterval(12 * 60 * 60)
    let nextDay = morning.addingTimeInterval(24 * 60 * 60)

    let startupRun = schedule.shouldRun(now: morning, calendar: calendar)
    let sameDayRun = schedule.shouldRun(now: evening, calendar: calendar)
    let nextDayRun = schedule.shouldRun(now: nextDay, calendar: calendar)

    #expect(startupRun)
    #expect(!sameDayRun)
    #expect(nextDayRun)
}

@Test func retentionRunScheduleCanForcePolicyChangeWithoutBreakingDateThrottle() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    var schedule = HistoryRetentionRunSchedule()
    let now = Date(timeIntervalSince1970: 1_725_955_200)

    let startupRun = schedule.shouldRun(now: now, calendar: calendar)
    let forcedRun = schedule.shouldRun(now: now, calendar: calendar, force: true)
    let throttledRun = schedule.shouldRun(now: now, calendar: calendar)

    #expect(startupRun)
    #expect(forcedRun)
    #expect(!throttledRun)
}

@MainActor
@Test func historyStoreRunsRetentionAtStartupAndPolicyChangeButNotEveryUpsert() {
    let repository = RetentionRunRecordingRepository()
    let persistence = ClipboardHistoryPersistence(repository: repository)
    let writer = ClipboardHistorySaveWriter(persistence: persistence)
    let suiteName = "retention-run-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.set(HistoryRetentionPolicy.oneDay.rawValue, forKey: "history.retentionPolicy")
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let store = ClipboardHistoryStore(
        persistence: persistence,
        userDefaults: defaults,
        saveWriter: writer
    )

    store.flushPendingSave()
    #expect(repository.deleteExpiredCount == 1)

    store.addText("first", sourceApp: .clipease)
    store.flushPendingSave()
    store.addText("second", sourceApp: .clipease)
    store.flushPendingSave()
    #expect(repository.deleteExpiredCount == 1)

    store.retentionPolicy = .threeDays
    store.flushPendingSave()
    #expect(repository.deleteExpiredCount == 2)
}

private final class RetentionRunRecordingRepository: ClipboardHistoryRepository, @unchecked Sendable {
    private let lock = NSLock()
    private var storedDeleteExpiredCount = 0

    var deleteExpiredCount: Int {
        lock.withLock { storedDeleteExpiredCount }
    }

    func loadSnapshot() throws -> ClipboardHistorySnapshot {
        ClipboardHistorySnapshot(items: [], groups: [])
    }

    func saveSnapshot(_ snapshot: ClipboardHistorySnapshot) throws {}

    func upsertItem(
        _ item: ClipboardItem,
        deleting deletedIDs: Set<ClipboardItem.ID>,
        groups: [ClipboardGroup]
    ) throws {}

    func deleteExpiredItems(before cutoff: Date) throws -> ClipboardAttachmentCleanup {
        lock.withLock {
            storedDeleteExpiredCount += 1
        }
        return .empty
    }

    func deleteExpiredItemsWithResult(
        before cutoff: Date
    ) throws -> ClipboardHistoryRetentionDeletionResult {
        lock.withLock {
            storedDeleteExpiredCount += 1
        }
        return ClipboardHistoryRetentionDeletionResult(
            cleanup: .empty,
            removedItemIDs: [],
            protectedGroupIDs: []
        )
    }
}
