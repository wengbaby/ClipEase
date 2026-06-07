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
    #expect(event.metadata["error"] == "write failed")
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

private func makeTemporarySupportDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("clipease-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
