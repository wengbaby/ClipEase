import AppKit
import Combine
import Darwin
import Foundation
struct PerformanceDiagnosticEvent: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let timestamp: Date
    let name: String
    let category: String
    let durationMS: Double
    let itemCount: Int?
    let resultCount: Int?
    let metadata: [String: String]
    let isMainThread: Bool
    let cpuPercent: Double?
    let memoryMB: Double?
    let threadCount: Int?
    let mainThreadLatencyMS: Double?

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        name: String,
        category: String,
        durationMS: Double,
        itemCount: Int? = nil,
        resultCount: Int? = nil,
        metadata: [String: String] = [:],
        isMainThread: Bool = Thread.isMainThread,
        cpuPercent: Double? = nil,
        memoryMB: Double? = nil,
        threadCount: Int? = nil,
        mainThreadLatencyMS: Double? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.name = name
        self.category = category
        self.durationMS = durationMS
        self.itemCount = itemCount
        self.resultCount = resultCount
        self.metadata = metadata
        self.isMainThread = isMainThread
        self.cpuPercent = cpuPercent
        self.memoryMB = memoryMB
        self.threadCount = threadCount
        self.mainThreadLatencyMS = mainThreadLatencyMS
    }
}

struct PerformanceResourceSnapshot: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let timestamp: Date
    let cpuPercent: Double
    let memoryMB: Double
    let residentMemoryBytes: UInt64
    let threadCount: Int
    let mainThreadLatencyMS: Double

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        cpuPercent: Double,
        memoryMB: Double,
        residentMemoryBytes: UInt64,
        threadCount: Int,
        mainThreadLatencyMS: Double
    ) {
        self.id = id
        self.timestamp = timestamp
        self.cpuPercent = cpuPercent
        self.memoryMB = memoryMB
        self.residentMemoryBytes = residentMemoryBytes
        self.threadCount = threadCount
        self.mainThreadLatencyMS = mainThreadLatencyMS
    }
}

@MainActor
final class PerformanceDiagnosticsService: ObservableObject {
    enum StartupMode {
        case production
        case isolated
    }

    static let shared = PerformanceDiagnosticsService()

    @Published var isEnabled: Bool {
        didSet {
            userDefaults.set(isEnabled, forKey: Self.enabledKey)
            guard !isSynchronizingMode else {
                return
            }
            applyMode(isEnabled ? .detailedLocal : .standard)
        }
    }
    @Published private(set) var recentEvents: [PerformanceDiagnosticEvent] = []
    @Published private(set) var recentResourceSnapshots: [PerformanceResourceSnapshot] = []
    @Published private(set) var latestResourceSnapshot: PerformanceResourceSnapshot?
    @Published private(set) var currentLogFileURL: URL?
    @Published private(set) var mode: PerformanceDiagnosticsMode
    @Published private(set) var droppedEventCount = 0
    @Published var retentionDays: Int {
        didSet {
            let clampedRetentionDays = min(
                PerformanceDiagnosticsRetentionPolicy.normalizedRetentionDays(retentionDays),
                PerformanceDiagnosticsMode.detailedLocal.retentionDays
            )
            guard retentionDays == clampedRetentionDays else {
                retentionDays = clampedRetentionDays
                return
            }
            userDefaults.set(retentionDays, forKey: Self.retentionDaysKey)
            guard startupMode == .production else {
                return
            }
            cleanupOldLogs()
        }
    }
    @Published var maxLogSizeMB: Int {
        didSet {
            let clampedMaxLogSizeMB = min(
                PerformanceDiagnosticsRetentionPolicy.normalizedMaxLogSizeMB(maxLogSizeMB),
                PerformanceDiagnosticsMode.detailedLocal.maxLogSizeMB
            )
            guard maxLogSizeMB == clampedMaxLogSizeMB else {
                maxLogSizeMB = clampedMaxLogSizeMB
                return
            }
            userDefaults.set(maxLogSizeMB, forKey: Self.maxLogSizeMBKey)
            guard startupMode == .production else {
                return
            }
            cleanupOldLogs()
        }
    }

    nonisolated private static let enabledKey = "performanceDiagnostics.enabled"
    nonisolated private static let retentionDaysKey = "performanceDiagnostics.retentionDays"
    nonisolated private static let maxLogSizeMBKey = "performanceDiagnostics.maxLogSizeMB"
    nonisolated private static let modeKey = "performanceDiagnostics.mode"
    nonisolated private static let maxRecentEvents = 200
    nonisolated private static let maxResourceSnapshots = 120
    nonisolated private static let slowEventThresholdMS = 16.0
    nonisolated private static let diagnosticsUIPublishNanoseconds: UInt64 = 750_000_000
    nonisolated static let shutdownDrainBudgetNanoseconds: UInt64 = 250_000_000
    nonisolated private static var defaultStartupMode: StartupMode {
        CommandLine.arguments.contains("--testing-library") ? .isolated : .production
    }
    private let userDefaults: UserDefaults
    private let fileManager: FileManager
    private var diagnosticsStoreURL: URL?
    private let startupMode: StartupMode
    private let diagnosticsWriter = PerformanceDiagnosticsWriter()
    private var cleanupTask: Task<Void, Never>?
    private var resourceSamplingTask: Task<Void, Never>?
    private var diagnosticsUIPublishTask: Task<Void, Never>?
    private var diagnosticsWritePumpTask: Task<Void, Never>?
    private(set) var diagnosticsWritePumpScheduledDelayNanoseconds: UInt64?
    private var diagnosticsIngressBuffer = PerformanceDiagnosticsIngressBuffer()
    private var diagnosticsWriterDroppedEventCount = 0
    private var recentEventsStore: [PerformanceDiagnosticEvent] = []
    private var recentResourceSnapshotsStore: [PerformanceResourceSnapshot] = []
    private var latestResourceSnapshotStore: PerformanceResourceSnapshot?
    private var isShutDown = false
    private var isSynchronizingMode = false

    init(
        userDefaults: UserDefaults = .standard,
        fileManager: FileManager = .default,
        diagnosticsStoreURL: URL? = nil,
        startupMode: StartupMode = PerformanceDiagnosticsService.defaultStartupMode
    ) {
        let initialMode = PerformanceDiagnosticsMode(
            rawValue: userDefaults.string(forKey: Self.modeKey) ?? ""
        ) ?? .standard
        self.userDefaults = userDefaults
        self.fileManager = fileManager
        self.startupMode = startupMode
        self.mode = initialMode
        self.isEnabled = initialMode == .detailedLocal
        self.retentionDays = min(
            PerformanceDiagnosticsRetentionPolicy.normalizedRetentionDays(
                userDefaults.object(forKey: Self.retentionDaysKey) as? Int
                    ?? initialMode.retentionDays
            ),
            PerformanceDiagnosticsMode.detailedLocal.retentionDays
        )
        self.maxLogSizeMB = min(
            PerformanceDiagnosticsRetentionPolicy.normalizedMaxLogSizeMB(
                userDefaults.object(forKey: Self.maxLogSizeMBKey) as? Int
                    ?? initialMode.maxLogSizeMB
            ),
            PerformanceDiagnosticsMode.detailedLocal.maxLogSizeMB
        )
        self.diagnosticsStoreURL = diagnosticsStoreURL
        if initialMode.persistenceEnabled {
            self.diagnosticsStoreURL = diagnosticsStoreURL
                ?? (try? ClipEaseStoragePaths.diagnosticsStoreURL(fileManager: fileManager))
            currentLogFileURL = self.diagnosticsStoreURL
        } else {
            currentLogFileURL = nil
        }
        userDefaults.set(isEnabled, forKey: Self.enabledKey)
        userDefaults.set(retentionDays, forKey: Self.retentionDaysKey)
        userDefaults.set(maxLogSizeMB, forKey: Self.maxLogSizeMBKey)
        userDefaults.set(mode.rawValue, forKey: Self.modeKey)
        if startupMode == .production, initialMode.persistenceEnabled {
            if diagnosticsStoreURL == nil {
                removeLegacyJSONLogs()
            }
            cleanupOldLogs()
            updateResourceSamplingState()
        }
    }

    var hasOwnedStartupWork: Bool {
        cleanupTask != nil || resourceSamplingTask != nil
    }

    func shutdown() {
        isShutDown = true
        cleanupTask?.cancel()
        cleanupTask = nil
        resourceSamplingTask?.cancel()
        resourceSamplingTask = nil
        diagnosticsUIPublishTask?.cancel()
        diagnosticsUIPublishTask = nil
        guard mode.persistenceEnabled else {
            return
        }
        Task { [weak self] in
            _ = await self?.drainForShutdown()
        }
    }

    func drainForShutdown(
        timeoutNanoseconds: UInt64 = PerformanceDiagnosticsService.shutdownDrainBudgetNanoseconds
    ) async -> PerformanceDiagnosticsShutdownDrainResult {
        let startedAt = CFAbsoluteTimeGetCurrent()
        guard let diagnosticsStoreURL, mode.persistenceEnabled else {
            return PerformanceDiagnosticsShutdownDrainResult(
                outcome: .notRequired,
                droppedEventCount: droppedEventCount,
                elapsedMS: (CFAbsoluteTimeGetCurrent() - startedAt) * 1_000
            )
        }

        diagnosticsWritePumpTask?.cancel()
        diagnosticsWritePumpTask = nil
        diagnosticsWritePumpScheduledDelayNanoseconds = nil
        let bufferedEvents = diagnosticsIngressBuffer.removeAll()
        let ingressDroppedEventCount = diagnosticsIngressBuffer.droppedEventCount
        let diagnosticsWriter = diagnosticsWriter
        let retentionPolicy = PerformanceDiagnosticsRetentionPolicy(
            retentionDays: retentionDays,
            maxLogSizeMB: maxLogSizeMB
        )
        let deadlineOutcome = await PerformanceDiagnosticsDrainDeadline.run(
            timeoutNanoseconds: timeoutNanoseconds
        ) {
            var writerDroppedEventCount = 0
            for event in bufferedEvents {
                writerDroppedEventCount = await diagnosticsWriter.enqueue(
                    event,
                    to: diagnosticsStoreURL,
                    policy: retentionPolicy
                )
            }
            writerDroppedEventCount = await diagnosticsWriter.drain(
                to: diagnosticsStoreURL,
                policy: retentionPolicy
            )
            return writerDroppedEventCount
        }

        let outcome: PerformanceDiagnosticsShutdownDrainOutcome
        switch deadlineOutcome {
        case .completed(let writerDroppedEventCount):
            diagnosticsWriterDroppedEventCount = writerDroppedEventCount
            droppedEventCount = ingressDroppedEventCount + writerDroppedEventCount
            outcome = .completed
        case .timedOut:
            droppedEventCount = ingressDroppedEventCount + diagnosticsWriterDroppedEventCount
            outcome = .timedOut
        }

        return PerformanceDiagnosticsShutdownDrainResult(
            outcome: outcome,
            droppedEventCount: droppedEventCount,
            elapsedMS: (CFAbsoluteTimeGetCurrent() - startedAt) * 1_000
        )
    }

    func setMode(_ mode: PerformanceDiagnosticsMode) {
        isSynchronizingMode = true
        if isEnabled != (mode == .detailedLocal) {
            isEnabled = mode == .detailedLocal
        }
        isSynchronizingMode = false
        userDefaults.set(isEnabled, forKey: Self.enabledKey)
        applyMode(mode)
    }

    private func applyMode(_ mode: PerformanceDiagnosticsMode) {
        guard self.mode != mode else {
            return
        }

        if self.mode.persistenceEnabled, !mode.persistenceEnabled {
            scheduleModeTransitionDrain()
        }

        self.mode = mode
        userDefaults.set(mode.rawValue, forKey: Self.modeKey)
        if mode == .detailedLocal {
            retentionDays = mode.retentionDays
            maxLogSizeMB = mode.maxLogSizeMB
            if diagnosticsStoreURL == nil {
                diagnosticsStoreURL = try? ClipEaseStoragePaths.diagnosticsStoreURL(fileManager: fileManager)
            }
            currentLogFileURL = diagnosticsStoreURL
            if startupMode == .production {
                removeLegacyJSONLogs()
            }
        } else {
            cleanupTask?.cancel()
            cleanupTask = nil
            resourceSamplingTask?.cancel()
            resourceSamplingTask = nil
            diagnosticsUIPublishTask?.cancel()
            diagnosticsUIPublishTask = nil
            currentLogFileURL = nil
            recentEventsStore.removeAll(keepingCapacity: false)
            recentResourceSnapshotsStore.removeAll(keepingCapacity: false)
            latestResourceSnapshotStore = nil
            recentEvents = []
            recentResourceSnapshots = []
            latestResourceSnapshot = nil
        }
        updateResourceSamplingState()
        if mode.persistenceEnabled {
            cleanupOldLogs()
        }
        recordInstant(
            mode.persistenceEnabled ? "diagnostics.detailed-local.enabled" : "diagnostics.standard.enabled",
            category: "diagnostics"
        )
    }

    func recordInstant(
        _ name: String,
        category: String,
        itemCount: Int? = nil,
        resultCount: Int? = nil,
        metadata: [String: String] = [:]
    ) {
        record(
            name,
            category: category,
            durationMS: 0,
            itemCount: itemCount,
            resultCount: resultCount,
            metadata: metadata
        )
    }

    func record(
        _ name: String,
        category: String,
        durationMS: Double,
        itemCount: Int? = nil,
        resultCount: Int? = nil,
        metadata: [String: String] = [:]
    ) {
        PerformanceDiagnosticsSignposter.emitEvent(name: name, category: category)
        guard mode.persistenceEnabled, isEnabled else {
            return
        }

        let event = PerformanceDiagnosticEvent(
            name: PerformanceDiagnosticsPrivacy.sanitizedEventName(name, category: category),
            category: PerformanceDiagnosticsPrivacy.sanitizedCategory(category),
            durationMS: durationMS,
            itemCount: itemCount,
            resultCount: resultCount,
            metadata: PerformanceDiagnosticsPrivacy.sanitizedMetadata(metadata)
        )
        appendRecentEventForUI(event)
        write(event)
    }

    func recordError(
        _ name: String,
        category: String,
        error: Error,
        metadata: [String: String] = [:]
    ) {
        PerformanceDiagnosticsSignposter.emitEvent(
            name: name,
            category: category,
            isError: true
        )
        guard mode.persistenceEnabled, isEnabled else {
            return
        }
        let event = Self.errorEvent(name, category: category, error: error, metadata: metadata)
        appendRecentEventForUI(event)
        write(event)
    }

    nonisolated static func errorEvent(
        _ name: String,
        category: String,
        error: Error,
        metadata: [String: String] = [:]
    ) -> PerformanceDiagnosticEvent {
        var errorMetadata = PerformanceDiagnosticsPrivacy.sanitizedMetadata(metadata)
        errorMetadata["error"] = "redacted"
        errorMetadata["errorType"] = String(describing: type(of: error))
        return PerformanceDiagnosticEvent(
            name: PerformanceDiagnosticsPrivacy.sanitizedEventName(name, category: category),
            category: PerformanceDiagnosticsPrivacy.sanitizedCategory(category),
            durationMS: 0,
            metadata: errorMetadata
        )
    }

    func recordResourceCheckpoint(_ reason: String) {
        guard isEnabled, mode.persistenceEnabled else {
            return
        }

        Task.detached(priority: .utility) { [weak self] in
            let latencyMS = await Self.measureMainThreadLatencyMS()
            guard let snapshot = Self.captureResourceSnapshot(mainThreadLatencyMS: latencyMS) else {
                return
            }

            await MainActor.run {
                self?.storeResourceSnapshot(snapshot, reason: "resourceCheckpoint")
            }
        }
    }

    func startSession(reason: String) {
        _ = reason
        recordInstant("diagnostics.session.start", category: "diagnostics", metadata: ["reason": "session"])
        if mode.persistenceEnabled {
            recordResourceCheckpoint("session")
        }
    }

    func measure<T>(
        _ name: String,
        category: String,
        itemCount: Int? = nil,
        resultCount: Int? = nil,
        metadata: [String: String] = [:],
        operation: () throws -> T
    ) rethrows -> T {
        let startedAt = CFAbsoluteTimeGetCurrent()
        let signpostInterval = PerformanceDiagnosticsSignposter.beginInterval(
            name: name,
            category: category
        )
        defer {
            PerformanceDiagnosticsSignposter.endInterval(signpostInterval)
        }
        do {
            let value = try operation()
            record(
                name,
                category: category,
                durationMS: (CFAbsoluteTimeGetCurrent() - startedAt) * 1_000,
                itemCount: itemCount,
                resultCount: resultCount,
                metadata: metadata
            )
            return value
        } catch {
            var nextMetadata = metadata
            nextMetadata["error"] = String(describing: error)
            record(
                name,
                category: category,
                durationMS: (CFAbsoluteTimeGetCurrent() - startedAt) * 1_000,
                itemCount: itemCount,
                resultCount: resultCount,
                metadata: nextMetadata
            )
            throw error
        }
    }

    func openLogsDirectory() {
        if diagnosticsStoreURL == nil {
            diagnosticsStoreURL = try? ClipEaseStoragePaths.diagnosticsStoreURL(fileManager: fileManager)
        }
        guard let directory = diagnosticsStoreURL?.deletingLastPathComponent() else {
            return
        }
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(directory)
    }

    func cleanupOldLogs() {
        guard startupMode == .production, mode.persistenceEnabled else {
            return
        }
        cleanupTask?.cancel()
        let policy = PerformanceDiagnosticsRetentionPolicy(
            retentionDays: retentionDays,
            maxLogSizeMB: maxLogSizeMB
        )
        let diagnosticsStoreURL = diagnosticsStoreURL
        cleanupTask = Task.detached(priority: .utility) {
            guard let diagnosticsStoreURL,
                  let store = try? PerformanceDiagnosticsStore(databaseURL: diagnosticsStoreURL) else {
                return
            }
            try? store.cleanup(policy: policy)
        }
    }

    var slowEvents: [PerformanceDiagnosticEvent] {
        recentEvents.filter { $0.durationMS >= Self.slowEventThresholdMS }
    }

    var summaryText: String {
        guard !recentEvents.isEmpty else {
            return L("暂无性能事件")
        }

        let durations = recentEvents.map(\.durationMS)
        let maxDuration = durations.max() ?? 0
        let averageDuration = durations.reduce(0, +) / Double(durations.count)
        if let latestResourceSnapshot {
            return L("最近 \(recentEvents.count) 条，平均 \(Self.formatMS(averageDuration))，最高 \(Self.formatMS(maxDuration))，CPU \(Self.formatPercent(latestResourceSnapshot.cpuPercent))，内存 \(Self.formatMB(latestResourceSnapshot.memoryMB))")
        }
        return L("最近 \(recentEvents.count) 条，平均 \(Self.formatMS(averageDuration))，最高 \(Self.formatMS(maxDuration))")
    }

    nonisolated static func formatMS(_ value: Double) -> String {
        String(format: "%.1f ms", value)
    }

    nonisolated static func formatPercent(_ value: Double) -> String {
        String(format: "%.1f%%", value)
    }

    nonisolated static func formatMB(_ value: Double) -> String {
        String(format: "%.1f MB", value)
    }

    private func updateResourceSamplingState() {
        guard startupMode == .production else {
            return
        }
        resourceSamplingTask?.cancel()
        resourceSamplingTask = nil

        guard isEnabled, let resourceSampleInterval = mode.resourceSampleInterval else {
            return
        }

        resourceSamplingTask = Task.detached(priority: .utility) { [weak self] in
            while !Task.isCancelled {
                let latencyMS = await Self.measureMainThreadLatencyMS()
                if let snapshot = Self.captureResourceSnapshot(mainThreadLatencyMS: latencyMS) {
                    await MainActor.run {
                        guard let self, !self.isShutDown else {
                            return
                        }
                        self.storeResourceSnapshot(snapshot, reason: "interval")
                    }
                }

                try? await Task.sleep(nanoseconds: UInt64(resourceSampleInterval * 1_000_000_000))
            }
        }
    }

    private func storeResourceSnapshot(_ snapshot: PerformanceResourceSnapshot, reason: String) {
        guard isEnabled, mode.persistenceEnabled, !isShutDown else {
            return
        }

        latestResourceSnapshotStore = snapshot
        recentResourceSnapshotsStore.insert(snapshot, at: 0)
        if recentResourceSnapshotsStore.count > Self.maxResourceSnapshots {
            recentResourceSnapshotsStore.removeLast(recentResourceSnapshotsStore.count - Self.maxResourceSnapshots)
        }

        let event = PerformanceDiagnosticEvent(
            timestamp: snapshot.timestamp,
            name: "resource.sample",
            category: "resource",
            durationMS: snapshot.mainThreadLatencyMS,
            metadata: PerformanceDiagnosticsPrivacy.sanitizedMetadata([
                "reason": reason,
                "cpuPercent": String(format: "%.2f", snapshot.cpuPercent),
                "memoryMB": String(format: "%.2f", snapshot.memoryMB),
                "residentMemoryBytes": "\(snapshot.residentMemoryBytes)",
                "threadCount": "\(snapshot.threadCount)",
                "mainThreadLatencyMS": String(format: "%.2f", snapshot.mainThreadLatencyMS)
            ]),
            cpuPercent: snapshot.cpuPercent,
            memoryMB: snapshot.memoryMB,
            threadCount: snapshot.threadCount,
            mainThreadLatencyMS: snapshot.mainThreadLatencyMS
        )
        appendRecentEventForUI(event)
        write(event)
    }

    private func appendRecentEventForUI(_ event: PerformanceDiagnosticEvent) {
        recentEventsStore.insert(event, at: 0)
        if recentEventsStore.count > Self.maxRecentEvents {
            recentEventsStore.removeLast(recentEventsStore.count - Self.maxRecentEvents)
        }
        scheduleDiagnosticsUIPublish()
    }

    private func scheduleDiagnosticsUIPublish() {
        guard diagnosticsUIPublishTask == nil else {
            return
        }

        diagnosticsUIPublishTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: Self.diagnosticsUIPublishNanoseconds)
            publishDiagnosticsUI()
        }
    }

    private func publishDiagnosticsUI() {
        diagnosticsUIPublishTask = nil
        if recentEvents != recentEventsStore {
            recentEvents = recentEventsStore
        }
        if recentResourceSnapshots != recentResourceSnapshotsStore {
            recentResourceSnapshots = recentResourceSnapshotsStore
        }
        if latestResourceSnapshot != latestResourceSnapshotStore {
            latestResourceSnapshot = latestResourceSnapshotStore
        }
    }

    private func write(_ event: PerformanceDiagnosticEvent) {
        guard mode.persistenceEnabled, diagnosticsStoreURL != nil else {
            return
        }

        diagnosticsIngressBuffer.enqueue(event)
        droppedEventCount = diagnosticsIngressBuffer.droppedEventCount
            + diagnosticsWriterDroppedEventCount
        scheduleDiagnosticsWritePump()
    }

    private func scheduleDiagnosticsWritePump() {
        let delay = diagnosticsIngressBuffer.count >= PerformanceDiagnosticsQueuePolicy.batchSize
            ? 0
            : PerformanceDiagnosticsQueuePolicy.flushIntervalNanoseconds
        if let scheduledDelay = diagnosticsWritePumpScheduledDelayNanoseconds {
            guard delay < scheduledDelay else {
                return
            }
            diagnosticsWritePumpTask?.cancel()
            diagnosticsWritePumpTask = nil
        }
        diagnosticsWritePumpScheduledDelayNanoseconds = delay
        diagnosticsWritePumpTask = Task { @MainActor [weak self] in
            if delay > 0 {
                do {
                    try await Task.sleep(nanoseconds: delay)
                } catch {
                    return
                }
            } else {
                await Task.yield()
            }
            await self?.flushNextDiagnosticsBatch()
        }
    }

    private func flushNextDiagnosticsBatch() async {
        diagnosticsWritePumpTask = nil
        diagnosticsWritePumpScheduledDelayNanoseconds = nil
        guard mode.persistenceEnabled, let diagnosticsStoreURL else {
            return
        }

        let batch = diagnosticsIngressBuffer.removeFirst(
            PerformanceDiagnosticsQueuePolicy.batchSize
        )
        let retentionPolicy = PerformanceDiagnosticsRetentionPolicy(
            retentionDays: retentionDays,
            maxLogSizeMB: maxLogSizeMB
        )
        for event in batch {
            diagnosticsWriterDroppedEventCount = await diagnosticsWriter.enqueue(
                event,
                to: diagnosticsStoreURL,
                policy: retentionPolicy
            )
        }
        droppedEventCount = diagnosticsIngressBuffer.droppedEventCount
            + diagnosticsWriterDroppedEventCount

        if !diagnosticsIngressBuffer.isEmpty {
            scheduleDiagnosticsWritePump()
        }
    }

    private func scheduleModeTransitionDrain() {
        diagnosticsWritePumpTask?.cancel()
        diagnosticsWritePumpTask = nil
        diagnosticsWritePumpScheduledDelayNanoseconds = nil
        guard let diagnosticsStoreURL else {
            _ = diagnosticsIngressBuffer.removeAll()
            return
        }

        let bufferedEvents = diagnosticsIngressBuffer.removeAll()
        let diagnosticsWriter = diagnosticsWriter
        let retentionPolicy = PerformanceDiagnosticsRetentionPolicy(
            retentionDays: retentionDays,
            maxLogSizeMB: maxLogSizeMB
        )
        Task.detached(priority: .utility) {
            for event in bufferedEvents {
                _ = await diagnosticsWriter.enqueue(
                    event,
                    to: diagnosticsStoreURL,
                    policy: retentionPolicy
                )
            }
            _ = await diagnosticsWriter.drain(
                to: diagnosticsStoreURL,
                policy: retentionPolicy
            )
        }
    }

    private func removeLegacyJSONLogs() {
        guard let directory = try? ClipEaseStoragePaths.applicationSupportDirectory(fileManager: fileManager)
            .appendingPathComponent("PerformanceLogs", isDirectory: true),
              fileManager.fileExists(atPath: directory.path) else {
            return
        }
        try? fileManager.removeItem(at: directory)
    }

    nonisolated private static func measureMainThreadLatencyMS() async -> Double {
        let startedAt = CFAbsoluteTimeGetCurrent()
        await MainActor.run {}
        return (CFAbsoluteTimeGetCurrent() - startedAt) * 1_000
    }

    nonisolated private static func captureResourceSnapshot(mainThreadLatencyMS: Double) -> PerformanceResourceSnapshot? {
        guard let residentMemoryBytes = currentResidentMemoryBytes(),
              let threadInfo = currentThreadResourceInfo() else {
            return nil
        }

        let memoryMB = Double(residentMemoryBytes) / 1_048_576
        return PerformanceResourceSnapshot(
            cpuPercent: threadInfo.cpuPercent,
            memoryMB: memoryMB,
            residentMemoryBytes: residentMemoryBytes,
            threadCount: threadInfo.threadCount,
            mainThreadLatencyMS: mainThreadLatencyMS
        )
    }

    nonisolated private static func currentResidentMemoryBytes() -> UInt64? {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
                task_info(
                    mach_task_self_,
                    task_flavor_t(MACH_TASK_BASIC_INFO),
                    reboundPointer,
                    &count
                )
            }
        }

        guard result == KERN_SUCCESS else {
            return nil
        }
        return UInt64(info.resident_size)
    }

    nonisolated private static func currentThreadResourceInfo() -> (cpuPercent: Double, threadCount: Int)? {
        var threadList: thread_act_array_t?
        var threadCount = mach_msg_type_number_t(0)
        let result = task_threads(mach_task_self_, &threadList, &threadCount)
        guard result == KERN_SUCCESS, let threadList else {
            return nil
        }

        defer {
            let size = vm_size_t(Int(threadCount) * MemoryLayout<thread_t>.stride)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: threadList), size)
        }

        var cpuPercent = 0.0
        for index in 0..<Int(threadCount) {
            var info = thread_basic_info()
            var infoCount = mach_msg_type_number_t(THREAD_INFO_MAX)
            let infoResult = withUnsafeMutablePointer(to: &info) { pointer in
                pointer.withMemoryRebound(to: integer_t.self, capacity: Int(infoCount)) { reboundPointer in
                    thread_info(
                        threadList[index],
                        thread_flavor_t(THREAD_BASIC_INFO),
                        reboundPointer,
                        &infoCount
                    )
                }
            }

            if infoResult == KERN_SUCCESS,
               info.flags & TH_FLAGS_IDLE == 0 {
                cpuPercent += Double(info.cpu_usage) / Double(TH_USAGE_SCALE) * 100
            }
        }

        return (cpuPercent, Int(threadCount))
    }
}
