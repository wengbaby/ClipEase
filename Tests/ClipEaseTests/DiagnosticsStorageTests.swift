import Foundation
import Testing
@testable import ClipEase

@Test func diagnosticsStorePathIsSeparateFromClipboardHistoryStore() throws {
    let fileManager = FileManager.default
    let historyURL = try ClipEaseStoragePaths.sqliteStoreURL(fileManager: fileManager)
    let diagnosticsURL = try ClipEaseStoragePaths.diagnosticsStoreURL(fileManager: fileManager)

    #expect(historyURL.lastPathComponent == "ClipEase.sqlite")
    #expect(diagnosticsURL.lastPathComponent == "ClipEaseDiagnostics.sqlite")
    #expect(historyURL != diagnosticsURL)
}

@Test func storageUsageExcludesDiagnosticsDatabaseAndLegacyLogs() throws {
    let root = try makeTemporarySupportDirectory()
    try Data(repeating: 1, count: 128).write(to: root.appendingPathComponent("ClipEase.sqlite"))
    try Data(repeating: 1, count: 256).write(to: root.appendingPathComponent("ClipEaseDiagnostics.sqlite"))
    let logs = root.appendingPathComponent("PerformanceLogs", isDirectory: true)
    try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
    try Data(repeating: 1, count: 512).write(to: logs.appendingPathComponent("old.jsonl"))

    let bytes = StorageUsageCalculator.applicationSupportSize(
        root,
        excludedNames: StorageUsageCalculator.defaultHistoryExcludedNames
    )

    #expect(bytes == 128)
}

@Test func diagnosticsRetentionDefaultsToThreeDaysAndFiveMegabytes() {
    let policy = PerformanceDiagnosticsRetentionPolicy.defaultPolicy

    #expect(policy.retentionDays == 3)
    #expect(policy.maxBytes == 5 * 1_024 * 1_024)
}

@MainActor
@Test func diagnosticsErrorEventsIncludeErrorMetadata() {
    let error = NSError(domain: "ClipEaseTests", code: 42, userInfo: [NSLocalizedDescriptionKey: "write failed"])

    let event = PerformanceDiagnosticsService.errorEvent(
        "history.persistence.save.failed",
        category: "storage",
        error: error,
        metadata: ["revision": "7"]
    )

    #expect(event.name == "history.persistence.save.failed")
    #expect(event.category == "storage")
    #expect(event.metadata["revision"] == "7")
    #expect(event.metadata["error"] == "redacted")
    #expect(event.metadata["errorType"] == "NSError")
}

@Test func diagnosticsRetentionRemovesOldRowsAndTrimsToMaxBytes() throws {
    let root = try makeTemporarySupportDirectory()
    let store = try PerformanceDiagnosticsStore(
        databaseURL: root.appendingPathComponent("ClipEaseDiagnostics.sqlite")
    )
    let now = Date()

    try store.append(PerformanceDiagnosticEvent(
        timestamp: now.addingTimeInterval(-5 * 24 * 60 * 60),
        name: "old",
        category: "test",
        durationMS: 1
    ))
    try store.append(PerformanceDiagnosticEvent(
        timestamp: now.addingTimeInterval(-60),
        name: "large-a",
        category: "test",
        durationMS: 1,
        metadata: ["payload": String(repeating: "a", count: 3_000)]
    ))
    try store.append(PerformanceDiagnosticEvent(
        timestamp: now,
        name: "large-b",
        category: "test",
        durationMS: 1,
        metadata: ["payload": String(repeating: "b", count: 3_000)]
    ))

    try store.cleanup(
        policy: PerformanceDiagnosticsRetentionPolicy(retentionDays: 3, maxBytes: 3_500),
        now: now
    )

    let names = try store.recentEvents(limit: 10).map(\.name)
    #expect(!names.contains("old"))
    #expect(names == ["large-b"])
}

@Test func diagnosticsWriterUsesTheSuppliedRetentionPolicy() async throws {
    let root = try makeTemporarySupportDirectory()
    let databaseURL = root.appendingPathComponent("ClipEaseDiagnostics.sqlite")
    let now = Date()
    let writer = PerformanceDiagnosticsWriter(
        cleanupInterval: 60 * 60,
        now: { now }
    )
    let policy = PerformanceDiagnosticsRetentionPolicy(
        retentionDays: 1,
        maxLogSizeMB: 5
    )

    _ = await writer.enqueue(
        PerformanceDiagnosticEvent(
            timestamp: now.addingTimeInterval(-2 * 24 * 60 * 60),
            name: "expired-by-user-policy",
            category: "test",
            durationMS: 1
        ),
        to: databaseURL,
        policy: policy
    )
    _ = await writer.drain(to: databaseURL, policy: policy)

    let store = try PerformanceDiagnosticsStore(databaseURL: databaseURL)
    #expect(try store.recentEvents(limit: 10).isEmpty)
}

@Test func diagnosticsWriterRateLimitsCleanupUntilPolicyChanges() async throws {
    let root = try makeTemporarySupportDirectory()
    let databaseURL = root.appendingPathComponent("ClipEaseDiagnostics.sqlite")
    let now = Date()
    let writer = PerformanceDiagnosticsWriter(
        cleanupInterval: 60 * 60,
        now: { now }
    )
    let initialPolicy = PerformanceDiagnosticsRetentionPolicy(
        retentionDays: 3,
        maxLogSizeMB: 5
    )

    for index in 0..<2 {
        _ = await writer.enqueue(
            PerformanceDiagnosticEvent(
                timestamp: now,
                name: "batch-\(index)",
                category: "test",
                durationMS: 1
            ),
            to: databaseURL,
            policy: initialPolicy
        )
        _ = await writer.drain(to: databaseURL, policy: initialPolicy)
    }

    #expect(await writer.cleanupRunCount == 1)

    let changedPolicy = PerformanceDiagnosticsRetentionPolicy(
        retentionDays: 1,
        maxLogSizeMB: 5
    )
    _ = await writer.enqueue(
        PerformanceDiagnosticEvent(
            timestamp: now,
            name: "changed-policy",
            category: "test",
            durationMS: 1
        ),
        to: databaseURL,
        policy: changedPolicy
    )
    _ = await writer.drain(to: databaseURL, policy: changedPolicy)

    #expect(await writer.cleanupRunCount == 2)
}

@Test(arguments: [1, 10])
func diagnosticsWriterEnforcesPhysicalLimitAfterEveryFlush(
    maxLogSizeMB: Int
) async throws {
    let root = try makeTemporarySupportDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let databaseURL = root.appendingPathComponent("ClipEaseDiagnostics.sqlite")
    let now = Date()
    let writer = PerformanceDiagnosticsWriter(
        cleanupInterval: 60 * 60,
        now: { now }
    )
    let policy = PerformanceDiagnosticsRetentionPolicy(
        retentionDays: 3,
        maxLogSizeMB: maxLogSizeMB
    )

    _ = await writer.enqueue(
        PerformanceDiagnosticEvent(
            timestamp: now,
            name: "initial-cleanup",
            category: "test",
            durationMS: 1
        ),
        to: databaseURL,
        policy: policy
    )
    _ = await writer.drain(to: databaseURL, policy: policy)
    #expect(await writer.cleanupRunCount == 1)

    let payload = String(repeating: "x", count: 512 * 1_024)
    for index in 0..<(maxLogSizeMB * 2 + 3) {
        _ = await writer.enqueue(
            PerformanceDiagnosticEvent(
                timestamp: now,
                name: "size-pressure-\(index)",
                category: "test",
                durationMS: 1,
                metadata: ["payload": payload]
            ),
            to: databaseURL,
            policy: policy
        )
        _ = await writer.drain(to: databaseURL, policy: policy)

        #expect(
            diagnosticsPhysicalFootprint(at: databaseURL) <= policy.maxBytes,
            "writer flush \(index) exceeded \(maxLogSizeMB) MiB"
        )
    }

    #expect(await writer.cleanupRunCount > 1)
    #expect(await writer.cleanupRunCount < maxLogSizeMB * 2 + 4)
}

private func makeTemporarySupportDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("clipease-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func diagnosticsPhysicalFootprint(at databaseURL: URL) -> Int {
    [
        databaseURL,
        URL(fileURLWithPath: databaseURL.path + "-wal"),
        URL(fileURLWithPath: databaseURL.path + "-shm")
    ].reduce(0) { total, url in
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let size = attributes?[.size] as? NSNumber
        return total + (size?.intValue ?? 0)
    }
}
