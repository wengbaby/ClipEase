import Foundation
import Testing
@testable import ClipEase

@Test func standardDiagnosticsModeHasNoPeriodicPersistence() {
    #expect(PerformanceDiagnosticsMode.standard.resourceSampleInterval == nil)
    #expect(PerformanceDiagnosticsMode.standard.persistenceEnabled == false)
}

@Test func detailedLocalDiagnosticsModeUsesRequiredBoundedPersistencePolicy() {
    #expect(PerformanceDiagnosticsMode.detailedLocal.resourceSampleInterval == 30)
    #expect(PerformanceDiagnosticsMode.detailedLocal.retentionDays == 7)
    #expect(PerformanceDiagnosticsMode.detailedLocal.maxLogSizeMB == 10)
    #expect(PerformanceDiagnosticsMode.detailedLocal.persistenceEnabled)
    #expect(PerformanceDiagnosticsQueuePolicy.maximumPendingEvents > 0)
    #expect(PerformanceDiagnosticsQueuePolicy.batchSize > 1)
}

@Test func diagnosticMetadataNeverRetainsSensitiveClipboardValues() {
    let metadata = PerformanceDiagnosticsPrivacy.sanitizedMetadata([
        "clipboardText": "private clipboard text",
        "url": "https://example.com/private",
        "filePath": "/Users/example/private.png",
        "searchTerm": "private search",
        "imageName": "private.png",
        "cacheKey": "private-cache-key",
        "reason": "privateClipboardValue",
        "appName": "PrivateApp",
        "token": "PrivateToken",
        "group": "PrivateGroup",
        "sourceBundleID": "com.private.application",
        "resultCount": "3"
    ])

    #expect(metadata == ["resultCount": "3"])
}

@Test func diagnosticMetadataOnlyKeepsTypedValuesForPermittedKeys() {
    let metadata = PerformanceDiagnosticsPrivacy.sanitizedMetadata([
        "reason": "session",
        "revision": "42",
        "cpuPercent": "1.25",
        "wasVisible": "true",
        "capturedType": "image",
        "error": "redacted",
        "errorType": "NSError"
    ])

    #expect(metadata == [
        "reason": "session",
        "revision": "42",
        "cpuPercent": "1.25",
        "wasVisible": "true",
        "capturedType": "image",
        "error": "redacted",
        "errorType": "NSError"
    ])
}

@Test func unknownDiagnosticIdentityCannotPersistUserControlledText() {
    #expect(
        PerformanceDiagnosticsPrivacy.sanitizedEventName(
            "search.privateClipboardValue",
            category: "privateCategory"
        ) == "performance.search"
    )
    #expect(PerformanceDiagnosticsPrivacy.sanitizedCategory("privateCategory") == "other")
}

@Test func diagnosticIngressBufferDropsOldestEventsAtItsHardLimit() {
    var buffer = PerformanceDiagnosticsIngressBuffer(capacity: 3)
    for index in 0..<5 {
        buffer.enqueue(PerformanceDiagnosticEvent(
            name: "event-\(index)",
            category: "test",
            durationMS: 0
        ))
    }

    #expect(buffer.count == 3)
    #expect(buffer.droppedEventCount == 2)
    #expect(buffer.removeAll().map(\.name) == ["event-2", "event-3", "event-4"])
}

@Test func performanceSignpostClassifierCoversEnterpriseStagesWithoutDynamicNames() {
    #expect(PerformanceSignpostStage.classify(name: "diagnostics.session.start", category: "diagnostics") == .startup)
    #expect(PerformanceSignpostStage.classify(name: "clipboard.poll", category: "clipboard") == .capture)
    #expect(PerformanceSignpostStage.classify(name: "history.persistence.upsert", category: "storage") == .persistence)
    #expect(PerformanceSignpostStage.classify(name: "history.window.open", category: "lifecycle") == .window)
    #expect(PerformanceSignpostStage.classify(name: "search.applyResults", category: "search") == .search)
    #expect(PerformanceSignpostStage.classify(name: "thumbnail.decode", category: "image") == .imageDecode)
    #expect(PerformanceSignpostStage.classify(name: "history.ocr.item", category: "ocr") == .ocr)
    #expect(PerformanceSignpostStage.classify(name: "history.hidden.cleanup", category: "lifecycle") == .cleanup)
    #expect(PerformanceSignpostStage.classify(name: "application.termination.drain", category: "lifecycle") == .exitDrain)
}

@MainActor
@Test func standardServiceIsSignpostOnlyAndCreatesNoDatabaseOrUITasks() async {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("clipease-standard-diagnostics-\(UUID().uuidString)", isDirectory: true)
    let databaseURL = root.appendingPathComponent("ClipEaseDiagnostics.sqlite")
    let suiteName = "standard-diagnostics-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: root)
    }

    let service = PerformanceDiagnosticsService(
        userDefaults: defaults,
        diagnosticsStoreURL: databaseURL,
        startupMode: .production
    )
    service.record(
        "clipboard.poll",
        category: "clipboard",
        durationMS: 2,
        metadata: ["capturedType": "image"]
    )
    service.recordResourceCheckpoint("session")
    await Task.yield()

    #expect(service.mode == .standard)
    #expect(service.isEnabled == false)
    #expect(service.currentLogFileURL == nil)
    #expect(service.recentEvents.isEmpty)
    #expect(service.recentResourceSnapshots.isEmpty)
    #expect(service.hasOwnedStartupWork == false)
    #expect(FileManager.default.fileExists(atPath: databaseURL.path) == false)
    service.shutdown()
}

@MainActor
@Test func userOptInTransitionsToDetailedLocalWithFixedUpperBounds() {
    let suiteName = "detailed-diagnostics-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let databaseURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("clipease-detailed-\(UUID().uuidString).sqlite")
    let service = PerformanceDiagnosticsService(
        userDefaults: defaults,
        diagnosticsStoreURL: databaseURL,
        startupMode: .isolated
    )

    service.isEnabled = true
    service.retentionDays = 30
    service.maxLogSizeMB = 100

    #expect(service.mode == .detailedLocal)
    #expect(service.currentLogFileURL == databaseURL)
    #expect(service.retentionDays == 7)
    #expect(service.maxLogSizeMB == 10)
    #expect(defaults.string(forKey: "performanceDiagnostics.mode") == PerformanceDiagnosticsMode.detailedLocal.rawValue)
    service.shutdown()
}

@MainActor
@Test func detailedLocalBatchDrainsToBoundedPrivateStore() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("clipease-detailed-drain-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let databaseURL = root.appendingPathComponent("ClipEaseDiagnostics.sqlite")
    let suiteName = "detailed-drain-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: root)
    }
    let service = PerformanceDiagnosticsService(
        userDefaults: defaults,
        diagnosticsStoreURL: databaseURL,
        startupMode: .isolated
    )
    service.isEnabled = true
    service.record(
        "clipboard.poll",
        category: "clipboard",
        durationMS: 2,
        resultCount: 3,
        metadata: [
            "resultCount": "3",
            "filePath": "/private/clipboard.png"
        ]
    )

    let drainResult = await service.drainForShutdown(timeoutNanoseconds: 1_000_000_000)
    let storedEvents = try PerformanceDiagnosticsStore(databaseURL: databaseURL)
        .recentEvents(limit: 10)

    #expect(drainResult.outcome == .completed)
    #expect(
        storedEvents.map(\.name)
            == ["clipboard.poll", "diagnostics.detailed-local.enabled"]
    )
    #expect(storedEvents.first?.metadata == ["resultCount": "3"])
}

@Test func diagnosticsDrainDeadlineReturnsWithoutWaitingForUncooperativeWork() async {
    let (releaseStream, releaseContinuation) = AsyncStream<Void>.makeStream(
        bufferingPolicy: .bufferingNewest(1)
    )
    let outcome = await PerformanceDiagnosticsDrainDeadline.run(
        timeoutNanoseconds: 15_000_000
    ) {
        for await _ in releaseStream {
            break
        }
        return 7
    }
    releaseContinuation.yield(())
    releaseContinuation.finish()

    #expect(outcome == .timedOut)
}

@Test func diagnosticsDrainDeadlineCancelsTimedOutWork() async {
    let cancellationProbe = DiagnosticsDeadlineCancellationProbe()
    let (blockingStream, blockingContinuation) = AsyncStream<Void>.makeStream()

    let outcome = await PerformanceDiagnosticsDrainDeadline.run(
        timeoutNanoseconds: 15_000_000
    ) {
        await withTaskCancellationHandler {
            for await _ in blockingStream {}
            return 7
        } onCancel: {
            cancellationProbe.markCancelled()
        }
    }

    #expect(outcome == .timedOut)
    #expect(cancellationProbe.waitForCancellation(timeout: 0.2))
    blockingContinuation.finish()
}

@Test func deterministicPerformanceFixturesExposeRequiredIDsAndStableHashes() {
    let fixtures = PerformanceBenchmarkFixtures.all

    #expect(fixtures.map(\.id) == ["S1K", "T10K", "M100K", "A3K"])
    #expect(fixtures.allSatisfy { !$0.sha256.isEmpty })
    #expect(PerformanceBenchmarkFixtures.all == fixtures)
}

@Test func performanceFixtureManifestMatchesRuntimeSchemaWhenProvided() throws {
    guard let path = ProcessInfo.processInfo.environment["CLIPEASE_PERFORMANCE_FIXTURE_MANIFEST"] else {
        return
    }
    struct Manifest: Decodable { let fixtures: [Fixture] }
    struct Fixture: Decodable { let id: String; let itemCount: Int; let sha256: String; let schema: String }
    let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
    #expect(manifest.fixtures.map(\.id) == PerformanceBenchmarkFixtures.all.map(\.id))
    for (actual, expected) in zip(manifest.fixtures, PerformanceBenchmarkFixtures.all) {
        #expect(actual.itemCount == expected.itemCount)
        #expect(actual.sha256 == expected.sha256)
        #expect(actual.schema == expected.schema)
    }
}

private final class DiagnosticsDeadlineCancellationProbe: @unchecked Sendable {
    private let condition = NSCondition()
    private var isCancelled = false

    func markCancelled() {
        condition.lock()
        isCancelled = true
        condition.broadcast()
        condition.unlock()
    }

    func waitForCancellation(timeout: TimeInterval) -> Bool {
        condition.lock()
        defer { condition.unlock() }
        if !isCancelled {
            _ = condition.wait(until: Date().addingTimeInterval(timeout))
        }
        return isCancelled
    }
}
