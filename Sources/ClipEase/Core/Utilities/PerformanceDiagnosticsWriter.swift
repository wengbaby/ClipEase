import Foundation

struct PerformanceDiagnosticsIngressBuffer {
    private let capacity: Int
    private var events: [PerformanceDiagnosticEvent] = []
    private(set) var droppedEventCount = 0

    init(capacity: Int = PerformanceDiagnosticsQueuePolicy.maximumPendingEvents) {
        self.capacity = max(1, capacity)
        events.reserveCapacity(min(self.capacity, PerformanceDiagnosticsQueuePolicy.batchSize))
    }

    var count: Int {
        events.count
    }

    var isEmpty: Bool {
        events.isEmpty
    }

    mutating func enqueue(_ event: PerformanceDiagnosticEvent) {
        if events.count == capacity {
            events.removeFirst()
            droppedEventCount += 1
        }
        events.append(event)
    }

    mutating func removeFirst(_ maximumCount: Int) -> [PerformanceDiagnosticEvent] {
        let count = min(maximumCount, events.count)
        guard count > 0 else {
            return []
        }
        let batch = Array(events.prefix(count))
        events.removeFirst(count)
        return batch
    }

    mutating func removeAll() -> [PerformanceDiagnosticEvent] {
        let result = events
        events.removeAll(keepingCapacity: true)
        return result
    }
}

actor PerformanceDiagnosticsWriter {
    private struct CleanupState {
        let date: Date
        let policy: PerformanceDiagnosticsRetentionPolicy
    }

    private var pendingEvents: [PerformanceDiagnosticEvent] = []
    private var droppedEventCount = 0
    private var isFlushScheduled = false
    private var flushGeneration: UInt64 = 0
    private var pendingDatabaseURL: URL?
    private var pendingPolicy: PerformanceDiagnosticsRetentionPolicy?
    private var cleanupStateByDatabaseURL: [URL: CleanupState] = [:]
    private let cleanupInterval: TimeInterval
    private let now: @Sendable () -> Date
    private(set) var cleanupRunCount = 0

    init(
        cleanupInterval: TimeInterval = 15 * 60,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.cleanupInterval = max(0, cleanupInterval)
        self.now = now
    }

    func enqueue(
        _ event: PerformanceDiagnosticEvent,
        to databaseURL: URL,
        policy: PerformanceDiagnosticsRetentionPolicy
    ) -> Int {
        updateDestination(databaseURL, policy: policy)
        if pendingEvents.count == PerformanceDiagnosticsQueuePolicy.maximumPendingEvents {
            pendingEvents.removeFirst()
            droppedEventCount += 1
        }
        pendingEvents.append(event)

        if pendingEvents.count >= PerformanceDiagnosticsQueuePolicy.batchSize {
            flush()
        } else {
            scheduleFlush()
        }
        return droppedEventCount
    }

    func drain(
        to databaseURL: URL,
        policy: PerformanceDiagnosticsRetentionPolicy
    ) -> Int {
        updateDestination(databaseURL, policy: policy)
        flush()
        return droppedEventCount
    }

    private func updateDestination(
        _ databaseURL: URL,
        policy: PerformanceDiagnosticsRetentionPolicy
    ) {
        if let pendingDatabaseURL,
           pendingDatabaseURL.standardizedFileURL != databaseURL.standardizedFileURL,
           !pendingEvents.isEmpty {
            flush()
        }
        pendingDatabaseURL = databaseURL
        pendingPolicy = policy
    }

    private func scheduleFlush() {
        guard !isFlushScheduled else {
            return
        }
        isFlushScheduled = true
        flushGeneration &+= 1
        let generation = flushGeneration
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: PerformanceDiagnosticsQueuePolicy.flushIntervalNanoseconds)
            await self?.runScheduledFlush(generation: generation)
        }
    }

    private func runScheduledFlush(generation: UInt64) {
        guard isFlushScheduled, generation == flushGeneration else {
            return
        }
        flush()
    }

    private func flush() {
        isFlushScheduled = false
        flushGeneration &+= 1
        guard !pendingEvents.isEmpty,
              let databaseURL = pendingDatabaseURL,
              let policy = pendingPolicy else {
            return
        }
        let batch = pendingEvents
        pendingEvents.removeAll(keepingCapacity: true)
        guard let store = try? PerformanceDiagnosticsStore(databaseURL: databaseURL) else {
            droppedEventCount += batch.count
            return
        }
        do {
            try store.append(batch)
        } catch {
            droppedEventCount += batch.count
            return
        }

        let cleanupDate = now()
        let cleanupKey = databaseURL.standardizedFileURL
        let regularCleanupIsDue = cleanupIsDue(
            for: cleanupKey,
            policy: policy,
            at: cleanupDate
        )
        guard regularCleanupIsDue
                || store.physicalFootprintBytes > policy.maxBytes else {
            return
        }
        do {
            try store.cleanup(policy: policy, now: cleanupDate)
            cleanupStateByDatabaseURL[cleanupKey] = CleanupState(
                date: cleanupDate,
                policy: policy
            )
            cleanupRunCount += 1
        } catch {
            // Keep the previous cleanup state so a later batch can retry.
        }
    }

    private func cleanupIsDue(
        for databaseURL: URL,
        policy: PerformanceDiagnosticsRetentionPolicy,
        at date: Date
    ) -> Bool {
        guard let previous = cleanupStateByDatabaseURL[databaseURL] else {
            return true
        }
        return previous.policy != policy
            || date.timeIntervalSince(previous.date) >= cleanupInterval
    }
}
