import Foundation
import Testing
@testable import ClipEase

@Suite
struct EnterpriseDiagnosticsIconCoverageTests {
    @Test
    func iconCacheGenerationRejectsCommitsFromAnInvalidatedToken() {
        let generation = AppIconCacheGeneration()
        let originalToken = generation.begin()

        #expect(generation.isCurrent(originalToken))
        #expect(generation.commitIfCurrent(originalToken))
        #expect(generation.advance() == 1)
        #expect(!generation.isCurrent(originalToken))
        #expect(!generation.commitIfCurrent(originalToken))

        let currentToken = generation.begin()
        #expect(currentToken != originalToken)
        #expect(generation.isCurrent(currentToken))
        #expect(generation.commitIfCurrent(currentToken))
    }

    @Test
    func iconCoordinatorPromotesDiskHitIntoItsMemoryLayer() async {
        let coordinator = AppIconCacheCoordinator()
        let diskProbe = DiagnosticsIconCounter()
        let loaderProbe = DiagnosticsIconCounter()
        let diskIcon = CachedAppIcon(
            fileName: "disk.png",
            dominantColorHex: "#123456"
        )

        let first = await coordinator.value(
            for: "com.example.disk|1",
            cachedValue: {
                await diskProbe.increment()
                return diskIcon
            },
            loadValue: {
                await loaderProbe.increment()
                return CachedAppIcon(
                    fileName: "unexpected.png",
                    dominantColorHex: "#654321"
                )
            }
        )
        let second = await coordinator.value(
            for: "com.example.disk|1",
            cachedValue: {
                await diskProbe.increment()
                return nil
            },
            loadValue: {
                await loaderProbe.increment()
                return nil
            }
        )

        #expect(first == diskIcon)
        #expect(second == diskIcon)
        #expect(await diskProbe.value == 1)
        #expect(await loaderProbe.value == 0)
    }

    @Test
    func iconCoordinatorRechecksSingleFlightAfterSuspendedDiskLookup() async {
        let coordinator = AppIconCacheCoordinator()
        let suspendedDiskLookup = DiagnosticsIconGate()
        let loaderGate = DiagnosticsIconGate()
        let loaderProbe = DiagnosticsIconCounter()
        let generatedIcon = CachedAppIcon(
            fileName: "single-flight.png",
            dominantColorHex: "#ABCDEF"
        )

        async let first: CachedAppIcon? = coordinator.value(
            for: "com.example.race|1",
            cachedValue: {
                await suspendedDiskLookup.wait()
                return nil
            },
            loadValue: {
                await loaderProbe.increment()
                return CachedAppIcon(
                    fileName: "unexpected-first-loader.png",
                    dominantColorHex: "#111111"
                )
            }
        )
        #expect(await suspendedDiskLookup.waitUntilStarted())

        async let second: CachedAppIcon? = coordinator.value(
            for: "com.example.race|1",
            cachedValue: { nil },
            loadValue: {
                await loaderProbe.increment()
                await loaderGate.wait()
                return generatedIcon
            }
        )
        #expect(await loaderGate.waitUntilStarted())

        await suspendedDiskLookup.release()
        await loaderGate.release()
        let values = await [first, second]

        #expect(values == [generatedIcon, generatedIcon])
        #expect(await loaderProbe.value == 1)
    }

    @Test
    func iconCoordinatorSingleFlightsFailureButDoesNotCacheIt() async {
        let coordinator = AppIconCacheCoordinator()
        let loaderGate = DiagnosticsIconGate()
        let loaderProbe = DiagnosticsIconCounter()

        async let first: CachedAppIcon? = coordinator.value(
            for: "com.example.nil|1",
            cachedValue: { nil },
            loadValue: {
                await loaderProbe.increment()
                await loaderGate.wait()
                return nil
            }
        )
        #expect(await loaderGate.waitUntilStarted())

        async let second: CachedAppIcon? = coordinator.value(
            for: "com.example.nil|1",
            cachedValue: { nil },
            loadValue: {
                await loaderProbe.increment()
                return CachedAppIcon(
                    fileName: "duplicate.png",
                    dominantColorHex: "#222222"
                )
            }
        )
        await loaderGate.release()

        let failedValues = await [first, second]
        #expect(failedValues.allSatisfy { $0 == nil })
        #expect(await loaderProbe.value == 1)

        let recoveredIcon = CachedAppIcon(
            fileName: "recovered.png",
            dominantColorHex: "#333333"
        )
        let recovered = await coordinator.value(
            for: "com.example.nil|1",
            cachedValue: { nil },
            loadValue: {
                await loaderProbe.increment()
                return recoveredIcon
            }
        )

        #expect(recovered == recoveredIcon)
        #expect(await loaderProbe.value == 2)
    }

    @Test
    func iconCoordinatorDoesNotPromoteDiskHitAcrossInvalidation() async {
        let coordinator = AppIconCacheCoordinator()
        let diskGate = DiagnosticsIconGate()
        let diskProbe = DiagnosticsIconCounter()
        let loaderProbe = DiagnosticsIconCounter()
        let staleIcon = CachedAppIcon(
            fileName: "stale-disk.png",
            dominantColorHex: "#444444"
        )
        let freshIcon = CachedAppIcon(
            fileName: "fresh.png",
            dominantColorHex: "#555555"
        )

        async let staleResult: CachedAppIcon? = coordinator.value(
            for: "com.example.invalidate|1",
            cachedValue: {
                await diskProbe.increment()
                await diskGate.wait()
                return staleIcon
            },
            loadValue: {
                await loaderProbe.increment()
                return nil
            }
        )
        #expect(await diskGate.waitUntilStarted())

        coordinator.invalidateSynchronously()
        await diskGate.release()
        #expect(await staleResult == staleIcon)

        let freshResult = await coordinator.value(
            for: "com.example.invalidate|1",
            cachedValue: {
                await diskProbe.increment()
                return nil
            },
            loadValue: {
                await loaderProbe.increment()
                return freshIcon
            }
        )
        let memoryResult = await coordinator.value(
            for: "com.example.invalidate|1",
            cachedValue: {
                await diskProbe.increment()
                return nil
            },
            loadValue: {
                await loaderProbe.increment()
                return nil
            }
        )

        #expect(freshResult == freshIcon)
        #expect(memoryResult == freshIcon)
        #expect(await diskProbe.value == 2)
        #expect(await loaderProbe.value == 1)
    }

    @Test
    func appIconFileNameReplacesUnsafePathCharacters() {
        let fileName = AppIconCache.expectedFileName(
            forBundleID: "com.example weird/应用#1"
        )

        #expect(fileName == "com.example_weird_应用_1.png")
        #expect(!fileName.contains("/"))
        #expect(fileName.hasSuffix(".png"))
    }

    @Test
    func signposterBeginsEndsAndEmitsEveryFixedEnterpriseStage() {
        let cases: [(name: String, category: String, stage: PerformanceSignpostStage)] = [
            ("APP.LAUNCH", "diagnostics", .startup),
            ("payload.capture", "other", .capture),
            ("history.store.write", "other", .persistence),
            ("paste.item", "interaction", .window),
            ("results.apply", "SEARCH", .search),
            ("IMAGE.asset", "other", .imageDecode),
            ("recognition", "OCR", .ocr),
            ("history.retention", "maintenance", .cleanup),
            ("application.shutdown", "termination", .exitDrain),
            ("unclassified.operation", "misc", .other),
        ]

        #expect(cases.count == PerformanceSignpostStage.allCases.count)
        for testCase in cases {
            let classified = PerformanceSignpostStage.classify(
                name: testCase.name,
                category: testCase.category
            )
            let interval = PerformanceDiagnosticsSignposter.beginInterval(
                name: testCase.name,
                category: testCase.category
            )

            #expect(classified == testCase.stage)
            #expect(reflectedSignpostStage(interval) == testCase.stage)
            PerformanceDiagnosticsSignposter.emitEvent(
                name: testCase.name,
                category: testCase.category
            )
            PerformanceDiagnosticsSignposter.emitEvent(
                name: testCase.name,
                category: testCase.category,
                isError: true
            )
            PerformanceDiagnosticsSignposter.endInterval(interval)
        }
    }

    @Test
    func historyTraceCoversEveryKindSafeMarkerAndSamplingCap() {
        let startup = HistoryPerformanceTrace(kind: .startup, itemCount: 3)
        startup.mark("listeners-ready", metadata: ["itemCount": "3"])
        startup.mark("another-startup-stage")
        #expect(reflectedTraceValue(startup, named: "label", as: String.self) == "app-startup")
        #expect(reflectedTraceValue(startup, named: "markerCount", as: Int.self) == 3)
        #expect(!reflectedTraceOptionalIsNil(startup, named: "intervalState"))
        startup.finish()
        startup.finish()
        #expect(reflectedTraceOptionalIsNil(startup, named: "intervalState"))

        let exitDrain = HistoryPerformanceTrace(kind: .exitDrain)
        exitDrain.mark("drain-complete")
        exitDrain.mark("drain-timeout")
        exitDrain.mark("drain-progress")
        #expect(
            reflectedTraceValue(exitDrain, named: "label", as: String.self)
                == "application-exit-drain"
        )
        exitDrain.finish()
        #expect(reflectedTraceOptionalIsNil(exitDrain, named: "intervalState"))

        let render = HistoryPerformanceTrace(label: "history-open", itemCount: 8)
        render.mark("panel-frame-ready")
        render.mark("panel-ordered")
        render.mark("open-animation-complete")
        render.mark("render-progress")
        for index in 0..<20 {
            render.mark("sample-\(index)", metadata: ["itemCount": "\(index)"])
        }

        #expect(reflectedTraceValue(render, named: "label", as: String.self) == "history-open")
        #expect(reflectedTraceValue(render, named: "markerCount", as: Int.self) == 16)
        #expect(reflectedTraceValue(render, named: "isSamplingCapped", as: Bool.self) == true)
        render.finish()
        #expect(reflectedTraceOptionalIsNil(render, named: "intervalState"))

        let normalized = HistoryPerformanceTrace(label: "private-label", itemCount: 0)
        #expect(
            reflectedTraceValue(normalized, named: "label", as: String.self)
                == "history-render"
        )
        normalized.finish()

        var deinitializingTrace: HistoryPerformanceTrace? = HistoryPerformanceTrace(
            kind: .startup
        )
        deinitializingTrace = nil
        #expect(deinitializingTrace == nil)
    }

    @MainActor
    @Test
    func detailedLocalLifecycleRecordsSuccessErrorAndModeTransitionDrain() async throws {
        let context = try DiagnosticsServiceCoverageContext(
            name: "lifecycle",
            startupMode: .isolated
        )
        defer { context.cleanup() }
        let service = context.service

        service.setMode(.detailedLocal)
        service.setMode(.detailedLocal)
        #expect(service.mode == .detailedLocal)
        #expect(service.isEnabled)
        #expect(service.currentLogFileURL == context.databaseURL)

        service.startSession(reason: "user-controlled-value")
        let measuredValue: Int = service.measure(
            "history.persistence.save",
            category: "storage",
            itemCount: 2,
            resultCount: 1,
            metadata: ["revision": "9"]
        ) {
            42
        }
        #expect(measuredValue == 42)

        do {
            let _: Int = try service.measure(
                "history.persistence.upsert",
                category: "storage",
                itemCount: 1
            ) {
                throw DiagnosticsCoverageError.expected
            }
            Issue.record("Expected the measured operation to throw")
        } catch DiagnosticsCoverageError.expected {
            // The error path is the behavior under test.
        }
        service.recordError(
            "history.persistence.save.failed",
            category: "storage",
            error: DiagnosticsCoverageError.expected,
            metadata: ["revision": "10", "filePath": "/private/value"]
        )

        let firstDrain = await service.drainForShutdown(
            timeoutNanoseconds: 2_000_000_000
        )
        let firstEvents = try PerformanceDiagnosticsStore(
            databaseURL: context.databaseURL
        ).recentEvents(limit: 20)

        #expect(firstDrain.outcome == .completed)
        #expect(firstEvents.contains { $0.name == "diagnostics.session.start" })
        #expect(firstEvents.contains {
            $0.name == "history.persistence.save"
                && $0.itemCount == 2
                && $0.resultCount == 1
                && $0.metadata == ["revision": "9"]
        })
        #expect(firstEvents.contains { $0.name == "history.persistence.upsert" })
        #expect(firstEvents.contains {
            $0.name == "history.persistence.save.failed"
                && $0.metadata["error"] == "redacted"
                && $0.metadata["errorType"] == "DiagnosticsCoverageError"
                && $0.metadata["filePath"] == nil
        })

        service.recordInstant(
            "clipboard.poll",
            category: "clipboard",
            itemCount: 999,
            metadata: ["capturedType": "text"]
        )
        service.setMode(.standard)
        let didPersistTransitionEvent = await waitForDiagnosticsEvent(
            databaseURL: context.databaseURL,
            itemCount: 999
        )
        let notRequiredDrain = await service.drainForShutdown()

        #expect(didPersistTransitionEvent)
        #expect(service.mode == .standard)
        #expect(!service.isEnabled)
        #expect(service.currentLogFileURL == nil)
        #expect(service.recentEvents.isEmpty)
        #expect(service.recentResourceSnapshots.isEmpty)
        #expect(service.latestResourceSnapshot == nil)
        #expect(notRequiredDrain.outcome == .notRequired)
        service.shutdown()
    }

    @MainActor
    @Test
    func detailedLocalWritePumpFlushesFullBatchesBeforeFinalDrain() async throws {
        let context = try DiagnosticsServiceCoverageContext(
            name: "write-pump",
            startupMode: .isolated
        )
        defer { context.cleanup() }
        let service = context.service
        service.setMode(.detailedLocal)

        for index in 0..<80 {
            service.record(
                "clipboard.poll",
                category: "clipboard",
                durationMS: Double(index),
                itemCount: index
            )
        }

        #expect(service.diagnosticsWritePumpScheduledDelayNanoseconds == 0)
        let didFlushTwoFullBatches = await waitForDiagnosticsEvent(
            databaseURL: context.databaseURL,
            itemCount: 62
        )
        let eventsBeforeDrain = try PerformanceDiagnosticsStore(
            databaseURL: context.databaseURL
        ).recentEvents(limit: 100)
        #expect(didFlushTwoFullBatches)
        #expect(eventsBeforeDrain.count >= 64)

        let drain = await service.drainForShutdown(
            timeoutNanoseconds: 2_000_000_000
        )
        let allEvents = try PerformanceDiagnosticsStore(
            databaseURL: context.databaseURL
        ).recentEvents(limit: 100)

        #expect(drain.outcome == .completed)
        #expect(allEvents.count == 81)
        #expect(allEvents.filter { $0.name == "clipboard.poll" }.count == 80)
        #expect(allEvents.compactMap(\.itemCount).min() == 0)
        #expect(allEvents.compactMap(\.itemCount).max() == 79)
        service.setMode(.standard)
        service.shutdown()
    }

    @MainActor
    @Test
    func detailedLocalIngressDropsOldestAtCapacityAndDrainPersistsTheBoundedTail() async throws {
        let context = try DiagnosticsServiceCoverageContext(
            name: "bounded-drop",
            startupMode: .isolated
        )
        defer { context.cleanup() }
        let service = context.service
        service.setMode(.detailedLocal)

        for index in 0..<300 {
            service.record(
                "clipboard.poll",
                category: "clipboard",
                durationMS: 1,
                itemCount: index
            )
        }

        let expectedDroppedCount = 301 - PerformanceDiagnosticsQueuePolicy.maximumPendingEvents
        #expect(service.droppedEventCount == expectedDroppedCount)

        let drain = await service.drainForShutdown(
            timeoutNanoseconds: 3_000_000_000
        )
        let storedEvents = try PerformanceDiagnosticsStore(
            databaseURL: context.databaseURL
        ).recentEvents(limit: 400)
        let retainedItemCounts = storedEvents.compactMap(\.itemCount)

        #expect(drain.outcome == .completed)
        #expect(drain.droppedEventCount == expectedDroppedCount)
        #expect(storedEvents.count == PerformanceDiagnosticsQueuePolicy.maximumPendingEvents)
        #expect(storedEvents.allSatisfy { $0.name == "clipboard.poll" })
        #expect(retainedItemCounts.min() == expectedDroppedCount - 1)
        #expect(retainedItemCounts.max() == 299)
        service.setMode(.standard)
        service.shutdown()
    }

    @MainActor
    @Test
    func productionDetailedStartupUsesInjectedSupportPathAndPublishesResourceSample() async throws {
        let root = try makeDiagnosticsCoverageDirectory(name: "production")
        let fileManager = DiagnosticsRootFileManager(rootURL: root)
        let supportDirectory = root.appendingPathComponent("ClipEase", isDirectory: true)
        let legacyDirectory = supportDirectory
            .appendingPathComponent("PerformanceLogs", isDirectory: true)
        try fileManager.createDirectory(
            at: legacyDirectory,
            withIntermediateDirectories: true
        )
        try Data("legacy".utf8).write(
            to: legacyDirectory.appendingPathComponent("legacy.jsonl")
        )
        let suiteName = "enterprise-diagnostics-production-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.set(
            PerformanceDiagnosticsMode.detailedLocal.rawValue,
            forKey: "performanceDiagnostics.mode"
        )
        defaults.set(30, forKey: "performanceDiagnostics.retentionDays")
        defaults.set(100, forKey: "performanceDiagnostics.maxLogSizeMB")
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
        }

        let service = PerformanceDiagnosticsService(
            userDefaults: defaults,
            fileManager: fileManager,
            diagnosticsStoreURL: nil,
            startupMode: .production
        )
        let expectedDatabaseURL = supportDirectory
            .appendingPathComponent("ClipEaseDiagnostics.sqlite")

        #expect(service.mode == .detailedLocal)
        #expect(service.isEnabled)
        #expect(service.retentionDays == 7)
        #expect(service.maxLogSizeMB == 10)
        #expect(service.currentLogFileURL == expectedDatabaseURL)
        #expect(service.hasOwnedStartupWork)
        #expect(!fileManager.fileExists(atPath: legacyDirectory.path))

        for _ in 0..<40 where service.latestResourceSnapshot == nil {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        let snapshot = service.latestResourceSnapshot
        #expect(snapshot != nil)
        #expect((snapshot?.residentMemoryBytes ?? 0) > 0)
        #expect((snapshot?.threadCount ?? 0) > 0)
        #expect(service.recentResourceSnapshots.first == snapshot)
        #expect(service.recentEvents.contains { $0.name == "resource.sample" })

        let drain = await service.drainForShutdown(
            timeoutNanoseconds: 2_000_000_000
        )
        #expect(drain.outcome == .completed)
        service.setMode(.standard)
        service.shutdown()
        try await Task.sleep(nanoseconds: 50_000_000)
    }

    @Test
    func diagnosticsStoreTreatsEmptyBatchAsNoOpAndEnforcesPhysicalTenMiBBound() throws {
        let root = try makeDiagnosticsCoverageDirectory(name: "physical-bound")
        defer { try? FileManager.default.removeItem(at: root) }
        let databaseURL = root.appendingPathComponent("ClipEaseDiagnostics.sqlite")
        let store = try PerformanceDiagnosticsStore(databaseURL: databaseURL)

        try store.append([])
        #expect(try store.recentEvents(limit: 10).isEmpty)

        let maximumBytes = 10 * PerformanceDiagnosticsRetentionPolicy.bytesPerMiB
        let payload = String(repeating: "x", count: maximumBytes - 1_024)
        try store.append(PerformanceDiagnosticEvent(
            name: "physical-bound",
            category: "test",
            durationMS: 1,
            metadata: ["payload": payload]
        ))
        #expect(store.fileSize > UInt64(maximumBytes))

        try store.cleanup(
            policy: PerformanceDiagnosticsRetentionPolicy(
                retentionDays: 30,
                maxBytes: maximumBytes
            )
        )

        #expect(try store.recentEvents(limit: 10).isEmpty)
        let physicalFootprint = [
            databaseURL,
            URL(fileURLWithPath: databaseURL.path + "-wal"),
            URL(fileURLWithPath: databaseURL.path + "-shm")
        ].reduce(0) { total, url in
            let attributes = try? FileManager.default.attributesOfItem(
                atPath: url.path
            )
            let size = attributes?[.size] as? NSNumber
            return total + (size?.intValue ?? 0)
        }
        #expect(physicalFootprint <= maximumBytes)
    }
}

private actor DiagnosticsIconCounter {
    private var storedValue = 0

    var value: Int {
        storedValue
    }

    func increment() {
        storedValue += 1
    }
}

private actor DiagnosticsIconGate {
    private var hasStarted = false
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        hasStarted = true
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func waitUntilStarted() async -> Bool {
        for _ in 0..<10_000 {
            if hasStarted {
                return true
            }
            await Task.yield()
        }
        return hasStarted
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}

private enum DiagnosticsCoverageError: Error {
    case expected
}

@MainActor
private final class DiagnosticsServiceCoverageContext {
    let rootURL: URL
    let databaseURL: URL
    let suiteName: String
    let defaults: UserDefaults
    let service: PerformanceDiagnosticsService

    init(
        name: String,
        startupMode: PerformanceDiagnosticsService.StartupMode
    ) throws {
        rootURL = try makeDiagnosticsCoverageDirectory(name: name)
        databaseURL = rootURL.appendingPathComponent("ClipEaseDiagnostics.sqlite")
        suiteName = "enterprise-diagnostics-\(name)-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        service = PerformanceDiagnosticsService(
            userDefaults: defaults,
            diagnosticsStoreURL: databaseURL,
            startupMode: startupMode
        )
    }

    func cleanup() {
        service.shutdown()
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: rootURL)
    }
}

private final class DiagnosticsRootFileManager: FileManager, @unchecked Sendable {
    private let rootURL: URL

    init(rootURL: URL) {
        self.rootURL = rootURL
        super.init()
    }

    override func url(
        for directory: FileManager.SearchPathDirectory,
        in domain: FileManager.SearchPathDomainMask,
        appropriateFor url: URL?,
        create shouldCreate: Bool
    ) throws -> URL {
        if shouldCreate {
            try createDirectory(
                at: rootURL,
                withIntermediateDirectories: true
            )
        }
        return rootURL
    }
}

private func makeDiagnosticsCoverageDirectory(name: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(
        "clipease-enterprise-\(name)-\(UUID().uuidString)",
        isDirectory: true
    )
    try FileManager.default.createDirectory(
        at: url,
        withIntermediateDirectories: true
    )
    return url
}

private func waitForDiagnosticsEvent(
    databaseURL: URL,
    itemCount: Int
) async -> Bool {
    for _ in 0..<100 {
        if let events = try? PerformanceDiagnosticsStore(
            databaseURL: databaseURL
        ).recentEvents(limit: 100),
           events.contains(where: { $0.itemCount == itemCount }) {
            return true
        }
        try? await Task.sleep(nanoseconds: 20_000_000)
    }
    return false
}

private func reflectedTraceValue<Value>(
    _ trace: HistoryPerformanceTrace,
    named name: String,
    as type: Value.Type
) -> Value? {
    Mirror(reflecting: trace).children
        .first(where: { $0.label == name })?
        .value as? Value
}

private func reflectedTraceOptionalIsNil(
    _ trace: HistoryPerformanceTrace,
    named name: String
) -> Bool {
    guard let value = Mirror(reflecting: trace).children
        .first(where: { $0.label == name })?
        .value else {
        return false
    }
    let mirror = Mirror(reflecting: value)
    return mirror.displayStyle == .optional && mirror.children.isEmpty
}

private func reflectedSignpostStage(
    _ token: PerformanceSignpostIntervalToken
) -> PerformanceSignpostStage? {
    Mirror(reflecting: token).children
        .first(where: { $0.label == "stage" })?
        .value as? PerformanceSignpostStage
}
