import AppKit
import Foundation
import Testing
@testable import ClipEase

@MainActor
@Test func clipboardMonitorChecksChangeCountBeforeResolvingSourceApplication() {
    let store = ClipboardHistoryStore(
        persistence: ClipboardHistoryPersistence(
            repository: ClipboardMonitorEmptyRepository()
        )
    )
    let pasteboard = NSPasteboard(name: NSPasteboard.Name("ClipEaseTests-\(UUID().uuidString)"))
    var sourceResolutionCount = 0
    let source = SourceAppInfo(
        name: "Source",
        bundleID: "com.example.source",
        iconName: "app.fill",
        iconFileName: nil,
        headerColorHex: "#2E8CFF"
    )
    let snapshot = ClipboardMonitorPasteboardReadSnapshot(
        changeCount: 7,
        types: [],
        strings: [:],
        data: [:],
        fileURLs: []
    )
    let monitor = ClipboardMonitor(
        store: store,
        pasteboard: pasteboard,
        sourceAppProvider: {
            sourceResolutionCount += 1
            return source
        },
        isPaused: { false },
        isIgnored: { _ in false },
        pasteboardSnapshotProvider: { snapshot }
    )
    let resolutionsAfterInitialization = sourceResolutionCount

    monitor.start()
    monitor.stop()

    #expect(sourceResolutionCount == resolutionsAfterInitialization)
}

@MainActor
@Test func sourceApplicationSnapshotUsesMostRecentRapidActivation() {
    let first = SourceAppInfo(
        name: "First",
        bundleID: "com.example.first",
        iconName: "app.fill",
        iconFileName: nil,
        headerColorHex: "#2E8CFF"
    )
    let second = SourceAppInfo(
        name: "Second",
        bundleID: "com.example.second",
        iconName: "app.fill",
        iconFileName: nil,
        headerColorHex: "#2E8CFF"
    )
    let snapshot = ClipboardSourceAppSnapshot(initial: first)

    snapshot.recordActivation(first)
    snapshot.recordActivation(second)

    #expect(snapshot.current.bundleID == second.bundleID)
}

@Test func payloadImportQueueEnforcesResidentTaskAndRetainedDataLimits() {
    var queue = ClipboardPayloadImportQueue<Int>(
        maximumResidentTasks: 4,
        maximumRetainedBytes: 128 * 1_024 * 1_024
    )

    #expect(queue.enqueue(1, retaining: 32 * 1_024 * 1_024) == nil)
    #expect(queue.enqueue(2, retaining: 32 * 1_024 * 1_024) == nil)
    #expect(queue.enqueue(3, retaining: 32 * 1_024 * 1_024) == nil)
    #expect(queue.enqueue(4, retaining: 32 * 1_024 * 1_024) == nil)
    #expect(queue.residentTaskCount == 4)
    #expect(queue.retainedByteCount == 128 * 1_024 * 1_024)
    #expect(queue.enqueue(5, retaining: 1) == .residentTaskLimitExceeded)

    #expect(queue.dequeue() == 1)
    #expect(queue.enqueue(5, retaining: 32 * 1_024 * 1_024 + 1) == .retainedDataLimitExceeded)
}

@Test func appIconCacheCoordinatorChecksCacheBeforeLoadingAndSingleFlightsSameKey() async {
    let coordinator = AppIconCacheCoordinator()
    let cached = CachedAppIcon(fileName: "cached.png", dominantColorHex: "#112233")
    let counter = AppIconLoadCounter()
    let firstLoad = AppIconLoadGate()

    let earlyHit = await coordinator.value(
        for: "com.example.cached|1",
        cachedValue: { cached },
        loadValue: {
            await counter.increment()
            return CachedAppIcon(fileName: "generated.png", dominantColorHex: "#445566")
        }
    )
    #expect(earlyHit?.fileName == cached.fileName)
    #expect(await counter.value == 0)

    async let first = coordinator.value(
        for: "com.example.flight|1",
        cachedValue: { nil },
        loadValue: {
            await counter.increment()
            await firstLoad.wait()
            return CachedAppIcon(fileName: "flight.png", dominantColorHex: "#778899")
        }
    )
    await firstLoad.waitUntilStarted()
    async let second = coordinator.value(
        for: "com.example.flight|1",
        cachedValue: { nil },
        loadValue: {
            await counter.increment()
            return CachedAppIcon(fileName: "duplicate.png", dominantColorHex: "#AABBCC")
        }
    )
    await firstLoad.resume()

    let results = await [first, second]
    #expect(results.allSatisfy { $0?.fileName == "flight.png" })
    #expect(await counter.value == 1)
}

@Test func clearingAppIconCachePreventsStaleInFlightValueFromRepopulatingMemory() async {
    let coordinator = AppIconCacheCoordinator()
    let staleLoad = AppIconLoadGate()
    let counter = AppIconLoadCounter()

    async let staleValue = coordinator.value(
        for: "com.example.clear|1",
        cachedValue: { nil },
        loadValue: {
            await staleLoad.wait()
            return CachedAppIcon(fileName: "stale.png", dominantColorHex: "#111111")
        }
    )
    await staleLoad.waitUntilStarted()

    coordinator.invalidateSynchronously()
    let freshValue = await coordinator.value(
        for: "com.example.clear|1",
        cachedValue: { nil },
        loadValue: {
            await counter.increment()
            return CachedAppIcon(fileName: "fresh.png", dominantColorHex: "#222222")
        }
    )
    await staleLoad.resume()
    _ = await staleValue

    let cachedAfterStaleCompletion = await coordinator.value(
        for: "com.example.clear|1",
        cachedValue: { nil },
        loadValue: {
            await counter.increment()
            return CachedAppIcon(fileName: "unexpected.png", dominantColorHex: "#333333")
        }
    )

    #expect(freshValue?.fileName == "fresh.png")
    #expect(cachedAfterStaleCompletion?.fileName == "fresh.png")
    #expect(await counter.value == 1)
}

@MainActor
@Test func clipboardMonitorStartImmediatelyPollsAndConfiguresBoundedTimer() {
    let payload = ClipboardMonitorPasteboardProbe(
        changeCount: 1,
        text: "started immediately"
    )
    let timerProbe = ClipboardMonitorTimerProbe()
    let monitor = makeClipboardMonitor(
        payload: payload,
        timerScheduler: timerProbe.scheduler
    )
    payload.changeCount = 2

    monitor.start()

    #expect(payload.payloadReadCount == 1)
    #expect(timerProbe.current?.timeInterval == 0.25)
    #expect(timerProbe.current?.tolerance == 0.05)
    monitor.stop()
}

@MainActor
@Test func queuedTimerHandlerAfterStopDoesNotReadChangeCountOrPayload() {
    let payload = ClipboardMonitorPasteboardProbe(
        changeCount: 1,
        text: "must not be read"
    )
    let timerProbe = ClipboardMonitorTimerProbe()
    let monitor = makeClipboardMonitor(
        payload: payload,
        timerScheduler: timerProbe.scheduler
    )
    monitor.start()
    let queuedTimer = timerProbe.current
    let changeCountReadsBeforeStop = payload.changeCountReadCount
    let payloadReadsBeforeStop = payload.payloadReadCount
    payload.changeCount = 2

    monitor.stop()
    queuedTimer?.fireQueuedHandler()
    monitor.pollNow()

    #expect(payload.changeCountReadCount == changeCountReadsBeforeStop)
    #expect(payload.payloadReadCount == payloadReadsBeforeStop)
}

@MainActor
@Test func suspendedClipboardMonitorDoesNotReadPayloadAndResumePollsImmediately() {
    let payload = ClipboardMonitorPasteboardProbe(changeCount: 1, text: "initial")
    let timerProbe = ClipboardMonitorTimerProbe()
    let lifecycleState = ClipboardMonitorLifecycleState()
    var isPaused = false
    let monitor = makeClipboardMonitor(
        payload: payload,
        isPaused: { isPaused },
        timerScheduler: timerProbe.scheduler,
        lifecycleState: lifecycleState
    )
    monitor.start()

    isPaused = true
    monitor.refreshSuspensionState()
    payload.changeCount = 2
    payload.text = "while paused"
    monitor.pollNow()
    timerProbe.fireCurrent()
    #expect(payload.payloadReadCount == 0)
    #expect(timerProbe.current?.isInvalidated == true)

    isPaused = false
    monitor.refreshSuspensionState()
    #expect(payload.payloadReadCount == 1)

    lifecycleState.apply(.willSleep)
    monitor.refreshSuspensionState()
    payload.changeCount = 3
    payload.text = "while sleeping"
    monitor.pollNow()
    #expect(payload.payloadReadCount == 1)

    lifecycleState.apply(.didWake)
    monitor.refreshSuspensionState()
    #expect(payload.payloadReadCount == 2)

    lifecycleState.apply(.sessionLocked)
    monitor.refreshSuspensionState()
    payload.changeCount = 4
    payload.text = "while locked"
    monitor.pollNow()
    #expect(payload.payloadReadCount == 2)

    lifecycleState.apply(.sessionUnlocked)
    monitor.refreshSuspensionState()
    #expect(payload.payloadReadCount == 3)
    monitor.stop()
}

@MainActor
@Test func stoppingPayloadImportsCannotLetOldCompletionDequeueResumedImport() async {
    let payload = ClipboardMonitorPasteboardProbe(
        changeCount: 1,
        imageData: Data([1])
    )
    let importer = ClipboardMonitorPayloadImportGate()
    let timerProbe = ClipboardMonitorTimerProbe()
    let monitor = makeClipboardMonitor(
        payload: payload,
        timerScheduler: timerProbe.scheduler,
        payloadImporter: { request in
            try await importer.importPayload(request)
        }
    )

    payload.changeCount = 2
    monitor.start()
    await importer.waitForCallCount(1)
    monitor.stop()

    #expect(!monitor.hasActivePayloadImportForTesting)
    #expect(monitor.payloadImportPumpDiagnosticsForTesting.ownedRequestCount == 0)

    payload.changeCount = 3
    monitor.start()
    await importer.waitForCallCount(2)
    #expect(monitor.hasActivePayloadImportForTesting)
    #expect(monitor.payloadImportPumpDiagnosticsForTesting.ownedRequestCount == 1)

    await importer.resumeCall(at: 0)
    await Task.yield()
    #expect(monitor.hasActivePayloadImportForTesting)
    #expect(monitor.payloadImportPumpDiagnosticsForTesting.ownedRequestCount == 1)

    await importer.resumeCall(at: 1)
    await importer.waitForFinishedCallCount(2)
    await Task.yield()
    #expect(!monitor.hasActivePayloadImportForTesting)
    #expect(monitor.payloadImportPumpDiagnosticsForTesting.ownedRequestCount == 0)
    monitor.stop()
}

@MainActor
private func makeClipboardMonitor(
    payload: ClipboardMonitorPasteboardProbe,
    isPaused: @escaping () -> Bool = { false },
    timerScheduler: ClipboardMonitorTimerScheduler,
    lifecycleState: ClipboardMonitorLifecycleState = ClipboardMonitorLifecycleState(),
    payloadImporter: ClipboardMonitorPayloadImporter? = nil,
    payloadStager: ClipboardPayloadStager = makeClipboardMonitorTestPayloadStager()
) -> ClipboardMonitor {
    let store = ClipboardHistoryStore(
        persistence: ClipboardHistoryPersistence(
            repository: ClipboardMonitorEmptyRepository()
        )
    )
    let pasteboard = NSPasteboard(name: NSPasteboard.Name("ClipEaseTests-\(UUID().uuidString)"))
    return ClipboardMonitor(
        store: store,
        pasteboard: pasteboard,
        sourceAppProvider: {
            SourceAppInfo(
                name: "Source",
                bundleID: "com.example.source",
                iconName: "app.fill",
                iconFileName: nil,
                headerColorHex: "#2E8CFF"
            )
        },
        isPaused: isPaused,
        isIgnored: { _ in false },
        timerScheduler: timerScheduler,
        pasteboardChangeCountProvider: { payload.readChangeCount() },
        pasteboardSnapshotProvider: { payload.readPayload() },
        payloadImporter: payloadImporter,
        payloadStager: payloadStager,
        lifecycleState: lifecycleState,
        observesSystemLifecycle: false
    )
}

private func makeClipboardMonitorTestPayloadStager() -> ClipboardPayloadStager {
    ClipboardPayloadStager(
        directoryProvider: {
            URL(fileURLWithPath: "/test/payload-staging", isDirectory: true)
        },
        fileSystem: ClipboardPayloadStagingFileSystem(
            createDirectory: { _ in },
            writeAtomically: { _, _ in },
            readData: { _ in Data() },
            removeItem: { _ in }
        )
    )
}

@MainActor
private final class ClipboardMonitorPasteboardProbe {
    var changeCount: Int
    var text: String?
    var imageData: Data?
    private(set) var changeCountReadCount = 0
    private(set) var payloadReadCount = 0

    init(changeCount: Int, text: String? = nil, imageData: Data? = nil) {
        self.changeCount = changeCount
        self.text = text
        self.imageData = imageData
    }

    func readChangeCount() -> Int {
        changeCountReadCount += 1
        return changeCount
    }

    func readPayload() -> ClipboardMonitorPasteboardReadSnapshot {
        payloadReadCount += 1
        if let imageData {
            let type = NSPasteboard.PasteboardType("public.png")
            return ClipboardMonitorPasteboardReadSnapshot(
                changeCount: changeCount,
                types: [type],
                strings: [:],
                data: [type: imageData],
                fileURLs: []
            )
        }
        return ClipboardMonitorPasteboardReadSnapshot(
            changeCount: changeCount,
            types: text == nil ? [] : [.string],
            strings: text.map { [.string: $0] } ?? [:],
            data: [:],
            fileURLs: []
        )
    }
}

@MainActor
private final class ClipboardMonitorFakeTimerToken: ClipboardMonitorTimerToken {
    let timeInterval: TimeInterval
    var tolerance: TimeInterval = 0
    private(set) var isInvalidated = false
    private let handler: @MainActor () -> Void

    init(timeInterval: TimeInterval, handler: @escaping @MainActor () -> Void) {
        self.timeInterval = timeInterval
        self.handler = handler
    }

    func invalidate() {
        isInvalidated = true
    }

    func fire() {
        guard !isInvalidated else { return }
        handler()
    }

    func fireQueuedHandler() {
        handler()
    }
}

@MainActor
private final class ClipboardMonitorTimerProbe {
    private(set) var tokens: [ClipboardMonitorFakeTimerToken] = []

    var current: ClipboardMonitorFakeTimerToken? {
        tokens.last
    }

    lazy var scheduler = ClipboardMonitorTimerScheduler { [weak self] interval, handler in
        let token = ClipboardMonitorFakeTimerToken(
            timeInterval: interval,
            handler: handler
        )
        self?.tokens.append(token)
        return token
    }

    func fireCurrent() {
        current?.fire()
    }
}

private actor ClipboardMonitorPayloadImportGate {
    private var continuations: [CheckedContinuation<Void, Never>?] = []
    private var finishedCallCount = 0

    func importPayload(
        _ request: ClipboardMonitorPayloadImportRequest
    ) async throws -> ClipboardMonitorPayloadImportResult {
        let callIndex = continuations.count
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
        finishedCallCount += 1
        _ = callIndex
        throw CancellationError()
    }

    func waitForCallCount(_ expectedCount: Int) async {
        while continuations.count < expectedCount {
            await Task.yield()
        }
    }

    func resumeCall(at index: Int) {
        guard continuations.indices.contains(index),
              let continuation = continuations[index] else {
            return
        }
        continuations[index] = nil
        continuation.resume()
    }

    func waitForFinishedCallCount(_ expectedCount: Int) async {
        while finishedCallCount < expectedCount {
            await Task.yield()
        }
    }
}

private actor AppIconLoadGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var hasStarted = false

    func wait() async {
        hasStarted = true
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func waitUntilStarted() async {
        while !hasStarted {
            await Task.yield()
        }
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}

private actor AppIconLoadCounter {
    private(set) var value = 0

    func increment() {
        value += 1
    }
}

private struct ClipboardMonitorEmptyRepository: ClipboardHistoryRepository {
    func loadSnapshot() throws -> ClipboardHistorySnapshot {
        ClipboardHistorySnapshot(items: [], groups: [])
    }

    func saveSnapshot(_ snapshot: ClipboardHistorySnapshot) throws {}
}
