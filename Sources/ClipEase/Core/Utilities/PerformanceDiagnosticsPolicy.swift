import CryptoKit
import Foundation

enum PerformanceDiagnosticsMode: String, Codable, Sendable {
    case standard
    case detailedLocal

    var resourceSampleInterval: TimeInterval? {
        switch self {
        case .standard: nil
        case .detailedLocal: 30
        }
    }

    var persistenceEnabled: Bool {
        self == .detailedLocal
    }

    var retentionDays: Int {
        self == .detailedLocal ? 7 : PerformanceDiagnosticsRetentionPolicy.defaultPolicy.retentionDays
    }

    var maxLogSizeMB: Int {
        self == .detailedLocal ? 10 : PerformanceDiagnosticsRetentionPolicy.defaultPolicy.maxBytes / PerformanceDiagnosticsRetentionPolicy.bytesPerMiB
    }

    var retentionPolicy: PerformanceDiagnosticsRetentionPolicy {
        PerformanceDiagnosticsRetentionPolicy(
            retentionDays: retentionDays,
            maxLogSizeMB: maxLogSizeMB
        )
    }
}

enum PerformanceDiagnosticsQueuePolicy {
    static let maximumPendingEvents = 256
    static let batchSize = 32
    static let flushIntervalNanoseconds: UInt64 = 1_000_000_000
}

enum PerformanceDiagnosticsShutdownDrainOutcome: Equatable, Sendable {
    case notRequired
    case completed
    case timedOut
}

struct PerformanceDiagnosticsShutdownDrainResult: Equatable, Sendable {
    let outcome: PerformanceDiagnosticsShutdownDrainOutcome
    let droppedEventCount: Int
    let elapsedMS: Double
}

enum PerformanceDiagnosticsPrivacy {
    private static let permittedEventNames: Set<String> = [
        "diagnostics.session.start",
        "diagnostics.detailed-local.enabled",
        "diagnostics.standard.enabled",
        "resource.sample",
        "clipboard.poll",
        "clipboard.payload.staging.failed",
        "clipboard.richText.import",
        "clipboard.richText.import.failed",
        "history.preload.start",
        "history.preload.previewWarm",
        "history.hidden.keepWarm",
        "history.window.open.request",
        "history.window.open.ordered",
        "history.window.open.presented",
        "history.window.open.firstFrame",
        "history.window.open.deferredStartup",
        "history.window.open.previewReady",
        "history.window.close.request",
        "history.window.close.animationComplete",
        "history.window.close.cleanupComplete",
        "history.persistence.save",
        "history.persistence.save.failed",
        "history.persistence.upsert",
        "history.persistence.upsert.failed",
        "history.persistence.upsertBatch.failed",
        "history.persistence.insertDebugItems",
        "history.persistence.insert.failed",
        "history.persistence.delete",
        "history.persistence.delete.failed",
        "history.persistence.deleteAll",
        "history.persistence.deleteAll.failed",
        "history.persistence.retention",
        "history.persistence.retention.failed",
        "history.persistence.compact",
        "history.persistence.compact.failed",
        "history.persistence.saveImmediate.failed",
        "history.persistence.prepareFullSnapshot.failed",
        "history.sqlite.migration",
        "history.sqlite.migration.failed",
        "history.store.initialize",
        "history.store.loadStartupPage",
        "history.store.loadNextPage",
        "history.store.loadAllBeforeFullSave",
        "history.store.searchAll",
        "history.store.searchIndexWarmup",
        "history.store.rebuildHashes",
        "history.store.sort",
        "history.store.upsert",
        "history.store.addDebugTextItems",
        "preview.rebuild.skip",
        "preview.rebuild.background",
        "preview.rebuild.apply",
        "preview.show",
        "search.schedule",
        "search.filter",
        "search.applyResults",
        "search.postApply",
        "search.open",
        "search.close",
        "search.token.remove",
        "filter.button.open",
        "filter.button.close",
        "filter.type.toggle",
        "filter.sourceApp.toggle",
        "filter.date.toggle",
        "filter.group.toggle",
        "card.click",
        "card.contextMenuSelect",
        "paste.item",
        "application.termination.drain"
    ]
    private static let permittedCategories: Set<String> = [
        "clipboard", "diagnostics", "history", "image", "interaction", "lifecycle",
        "ocr", "preview", "resource", "search", "storage", "termination"
    ]
    private static let integerKeys: Set<String> = [
        "revision", "itemCount", "resultCount", "residentMemoryBytes", "threadCount",
        "visibleItemCount", "previewItemCount", "payloadBytes", "reclaimedBytes",
        "cacheStored", "cacheHits", "cacheMisses", "filteredCount", "tokenCount",
        "queryLength", "openID"
    ]
    private static let decimalKeys: Set<String> = [
        "cpuPercent", "memoryMB", "mainThreadLatencyMS", "changeMS", "sourceMS",
        "typesMS", "payloadMS", "parseMS", "storeMS"
    ]
    private static let booleanKeys: Set<String> = [
        "wasVisible", "shouldAnimate", "hasPendingFocus", "hasFilters", "searchVisible",
        "filterPanelVisible", "animated", "immediate", "wasActive"
    ]
    private static let permittedReasons: Set<String> = [
        "session", "interval", "resourceCheckpoint", "window.hidden", "preloaded.hidden",
        "sourceGenerationUnchanged", "sourceSignatureUnchanged"
    ]
    private static let permittedCapturedTypes: Set<String> = [
        "file", "html", "html.scheduled", "image", "image.scheduled", "plainText",
        "richText", "rtf", "rtf.scheduled", "text", "text.fastPath"
    ]
    private static let permittedModes: Set<String> = [
        "background", "incremental", "rebuild", "unfilteredSource"
    ]
    private static let permittedItemTypes: Set<String> = [
        "file", "files", "image", "link", "richText", "text", "url"
    ]

    static func sanitizedMetadata(_ metadata: [String: String]) -> [String: String] {
        metadata.reduce(into: [:]) { result, element in
            guard isPermitted(key: element.key, value: element.value) else {
                return
            }
            result[element.key] = element.value
        }
    }

    static func sanitizedEventName(_ name: String, category: String) -> String {
        guard permittedEventNames.contains(name) else {
            let stage = PerformanceSignpostStage.classify(name: name, category: category)
            return "performance.\(stage.rawValue)"
        }
        return name
    }

    static func sanitizedCategory(_ category: String) -> String {
        permittedCategories.contains(category) ? category : "other"
    }

    private static func isPermitted(key: String, value: String) -> Bool {
        guard value.count <= 64 else {
            return false
        }

        if integerKeys.contains(key) {
            return Int64(value) != nil || UInt64(value) != nil
        }
        if decimalKeys.contains(key) {
            return Double(value)?.isFinite == true
        }
        if booleanKeys.contains(key) {
            return value == "true" || value == "false"
        }

        switch key {
        case "reason":
            return permittedReasons.contains(value)
        case "capturedType":
            return permittedCapturedTypes.contains(value)
        case "mode":
            return permittedModes.contains(value)
        case "type", "itemType":
            return permittedItemTypes.contains(value)
        case "error":
            return value == "redacted"
        case "errorType":
            return isIdentifier(value)
        default:
            return false
        }
    }

    private static func isIdentifier(_ value: String) -> Bool {
        !value.isEmpty && value.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics
                .union(CharacterSet(charactersIn: "._"))
                .contains($0)
        }
    }
}

enum PerformanceDiagnosticsDeadlineOutcome<Value: Sendable>: Sendable {
    case completed(Value)
    case timedOut
}

extension PerformanceDiagnosticsDeadlineOutcome: Equatable where Value: Equatable {}

enum PerformanceDiagnosticsDrainDeadline {
    static func run<Value: Sendable>(
        timeoutNanoseconds: UInt64,
        operation: @escaping @Sendable () async -> Value
    ) async -> PerformanceDiagnosticsDeadlineOutcome<Value> {
        await withCheckedContinuation { continuation in
            let gate = PerformanceDiagnosticsDeadlineGate(continuation: continuation)
            let operationTask = Task(priority: .high) {
                gate.resolve(.completed(await operation()))
            }
            gate.install(operationTask: operationTask)
            let boundedTimeout = min(timeoutNanoseconds, UInt64(Int.max))
            DispatchQueue.global(qos: .userInitiated).asyncAfter(
                deadline: .now() + .nanoseconds(Int(boundedTimeout))
            ) {
                gate.resolve(.timedOut)
            }
        }
    }
}

private final class PerformanceDiagnosticsDeadlineGate<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<PerformanceDiagnosticsDeadlineOutcome<Value>, Never>?
    private var operationTask: Task<Void, Never>?
    private var isResolved = false
    private var shouldCancelLateOperation = false

    init(continuation: CheckedContinuation<PerformanceDiagnosticsDeadlineOutcome<Value>, Never>) {
        self.continuation = continuation
    }

    func install(operationTask: Task<Void, Never>) {
        let shouldCancel = lock.withLock {
            guard !isResolved else {
                return shouldCancelLateOperation
            }
            self.operationTask = operationTask
            return false
        }
        if shouldCancel {
            operationTask.cancel()
        }
    }

    func resolve(_ outcome: PerformanceDiagnosticsDeadlineOutcome<Value>) {
        let resolution: (
            continuation: CheckedContinuation<
                PerformanceDiagnosticsDeadlineOutcome<Value>,
                Never
            >?,
            operationTask: Task<Void, Never>?
        ) = lock.withLock {
            guard !isResolved, let continuation = self.continuation else {
                return (nil, nil)
            }
            let didTimeOut: Bool
            if case .timedOut = outcome {
                didTimeOut = true
            } else {
                didTimeOut = false
            }
            isResolved = true
            shouldCancelLateOperation = didTimeOut
            self.continuation = nil
            let operationTask = didTimeOut ? self.operationTask : nil
            self.operationTask = nil
            return (continuation, operationTask)
        }
        resolution.operationTask?.cancel()
        resolution.continuation?.resume(returning: outcome)
    }
}

struct PerformanceBenchmarkFixture: Equatable, Sendable {
    let id: String
    let itemCount: Int
    let sha256: String
    let schema: String
}

enum PerformanceBenchmarkFixtures {
    static let all: [PerformanceBenchmarkFixture] = [
        fixture(id: "S1K", itemCount: 1_000, kind: "text"),
        fixture(id: "T10K", itemCount: 10_000, kind: "text"),
        fixture(id: "M100K", itemCount: 100_000, kind: "mixed"),
        fixture(id: "A3K", itemCount: 3_000, kind: "richImageFile")
    ]

    static func payload(for fixture: PerformanceBenchmarkFixture) -> Data {
        Data((0..<fixture.itemCount).map { index in
            "\(fixture.id)|\(index)|ClipEase deterministic benchmark\n"
        }.joined().utf8)
    }

    private static func fixture(id: String, itemCount: Int, kind: String) -> PerformanceBenchmarkFixture {
        let canonical = "v1|PerformanceFixture|\(kind)|\(id)|\(itemCount)"
        let hash = SHA256.hash(data: Data(canonical.utf8)).map { String(format: "%02x", $0) }.joined()
        return PerformanceBenchmarkFixture(id: id, itemCount: itemCount, sha256: hash, schema: "PerformanceFixture/v1")
    }
}
