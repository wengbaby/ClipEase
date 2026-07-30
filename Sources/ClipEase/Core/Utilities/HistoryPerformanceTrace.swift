import Foundation
import os

enum PerformanceSignpostStage: String, CaseIterable, Sendable {
    case startup
    case capture
    case persistence
    case window
    case search
    case imageDecode
    case ocr
    case cleanup
    case exitDrain
    case other

    static func classify(name: String, category: String) -> PerformanceSignpostStage {
        let normalizedName = name.lowercased()
        let normalizedCategory = category.lowercased()

        if normalizedName.contains("termination")
            || normalizedName.contains("exit.drain")
            || normalizedCategory == "termination" {
            return .exitDrain
        }
        if normalizedName.contains("cleanup")
            || normalizedName.contains("hidden")
            || normalizedName.contains("retention")
            || normalizedName.contains("compact") {
            return .cleanup
        }
        if normalizedName.contains("ocr") || normalizedCategory == "ocr" {
            return .ocr
        }
        if normalizedName.contains("image")
            || normalizedName.contains("thumbnail")
            || normalizedCategory == "image" {
            return .imageDecode
        }
        if normalizedName.contains("search") || normalizedCategory == "search" {
            return .search
        }
        if normalizedName.hasPrefix("clipboard.")
            || normalizedName.contains("capture")
            || normalizedCategory == "clipboard" {
            return .capture
        }
        if normalizedName.contains("persistence")
            || normalizedName.contains("sqlite")
            || normalizedName.hasPrefix("history.store.")
            || normalizedCategory == "storage" {
            return .persistence
        }
        if normalizedName.contains("window")
            || normalizedName.contains("preload")
            || normalizedName.contains("preview")
            || normalizedName.hasPrefix("card.")
            || normalizedName.hasPrefix("paste.")
            || normalizedCategory == "lifecycle" {
            return .window
        }
        if normalizedName.contains("session.start")
            || normalizedName.contains("startup")
            || normalizedName == "app.launch" {
            return .startup
        }
        return .other
    }
}

struct PerformanceSignpostIntervalToken: @unchecked Sendable {
    fileprivate let stage: PerformanceSignpostStage
    fileprivate let state: OSSignpostIntervalState
}

enum PerformanceDiagnosticsSignposter {
    private static let signposter = OSSignposter(
        subsystem: "com.wpc.ClipEase",
        category: "enterprise-performance"
    )

    static func emitEvent(name: String, category: String, isError: Bool = false) {
        let stage = PerformanceSignpostStage.classify(name: name, category: category)
        if isError {
            emitError(stage)
        } else {
            emitEvent(stage)
        }
    }

    static func beginInterval(name: String, category: String) -> PerformanceSignpostIntervalToken {
        let stage = PerformanceSignpostStage.classify(name: name, category: category)
        let state: OSSignpostIntervalState
        switch stage {
        case .startup:
            state = signposter.beginInterval("app.startup")
        case .capture:
            state = signposter.beginInterval("clipboard.capture")
        case .persistence:
            state = signposter.beginInterval("storage.operation")
        case .window:
            state = signposter.beginInterval("history.window")
        case .search:
            state = signposter.beginInterval("history.search")
        case .imageDecode:
            state = signposter.beginInterval("asset.image-decode")
        case .ocr:
            state = signposter.beginInterval("asset.ocr")
        case .cleanup:
            state = signposter.beginInterval("maintenance.cleanup")
        case .exitDrain:
            state = signposter.beginInterval("application.exit-drain")
        case .other:
            state = signposter.beginInterval("performance.other")
        }
        return PerformanceSignpostIntervalToken(stage: stage, state: state)
    }

    static func endInterval(_ token: PerformanceSignpostIntervalToken) {
        switch token.stage {
        case .startup:
            signposter.endInterval("app.startup", token.state)
        case .capture:
            signposter.endInterval("clipboard.capture", token.state)
        case .persistence:
            signposter.endInterval("storage.operation", token.state)
        case .window:
            signposter.endInterval("history.window", token.state)
        case .search:
            signposter.endInterval("history.search", token.state)
        case .imageDecode:
            signposter.endInterval("asset.image-decode", token.state)
        case .ocr:
            signposter.endInterval("asset.ocr", token.state)
        case .cleanup:
            signposter.endInterval("maintenance.cleanup", token.state)
        case .exitDrain:
            signposter.endInterval("application.exit-drain", token.state)
        case .other:
            signposter.endInterval("performance.other", token.state)
        }
    }

    private static func emitEvent(_ stage: PerformanceSignpostStage) {
        switch stage {
        case .startup:
            signposter.emitEvent("app.startup.event")
        case .capture:
            signposter.emitEvent("clipboard.capture.event")
        case .persistence:
            signposter.emitEvent("storage.operation.event")
        case .window:
            signposter.emitEvent("history.window.event")
        case .search:
            signposter.emitEvent("history.search.event")
        case .imageDecode:
            signposter.emitEvent("asset.image-decode.event")
        case .ocr:
            signposter.emitEvent("asset.ocr.event")
        case .cleanup:
            signposter.emitEvent("maintenance.cleanup.event")
        case .exitDrain:
            signposter.emitEvent("application.exit-drain.event")
        case .other:
            signposter.emitEvent("performance.other.event")
        }
    }

    private static func emitError(_ stage: PerformanceSignpostStage) {
        switch stage {
        case .startup:
            signposter.emitEvent("app.startup.error")
        case .capture:
            signposter.emitEvent("clipboard.capture.error")
        case .persistence:
            signposter.emitEvent("storage.operation.error")
        case .window:
            signposter.emitEvent("history.window.error")
        case .search:
            signposter.emitEvent("history.search.error")
        case .imageDecode:
            signposter.emitEvent("asset.image-decode.error")
        case .ocr:
            signposter.emitEvent("asset.ocr.error")
        case .cleanup:
            signposter.emitEvent("maintenance.cleanup.error")
        case .exitDrain:
            signposter.emitEvent("application.exit-drain.error")
        case .other:
            signposter.emitEvent("performance.other.error")
        }
    }
}

enum HistoryPerformanceTraceKind: Sendable {
    case startup
    case historyRender
    case exitDrain

    var summaryLabel: String {
        switch self {
        case .startup:
            "app-startup"
        case .historyRender:
            "history-render"
        case .exitDrain:
            "application-exit-drain"
        }
    }
}

final class HistoryPerformanceTrace: @unchecked Sendable {
    private let lock = NSLock()
    private let id = UUID().uuidString.prefix(8)
    private let startedAt = CFAbsoluteTimeGetCurrent()
    private let label: String
    private let kind: HistoryPerformanceTraceKind
    private let signposter: OSSignposter
    private let signpostID: OSSignpostID
    private var intervalState: OSSignpostIntervalState?
    private var markerCount = 0
    private var isSamplingCapped = false

    convenience init(label: String, itemCount: Int) {
        let safeLabel: String
        switch label {
        case "history-open", "history-preload":
            safeLabel = label
        default:
            safeLabel = HistoryPerformanceTraceKind.historyRender.summaryLabel
        }
        self.init(kind: .historyRender, label: safeLabel, itemCount: itemCount)
    }

    init(kind: HistoryPerformanceTraceKind, itemCount: Int = 0) {
        self.kind = kind
        self.label = kind.summaryLabel
        let signposter = OSSignposter(subsystem: "com.wpc.ClipEase", category: "history-performance")
        self.signposter = signposter
        self.signpostID = signposter.makeSignpostID()
        self.intervalState = Self.beginInterval(
            kind: kind,
            signposter: signposter,
            id: signpostID
        )
        mark("start", metadata: ["itemCount": "\(itemCount)"])
    }

    private init(kind: HistoryPerformanceTraceKind, label: String, itemCount: Int) {
        self.kind = kind
        self.label = label
        let signposter = OSSignposter(subsystem: "com.wpc.ClipEase", category: "history-performance")
        self.signposter = signposter
        self.signpostID = signposter.makeSignpostID()
        self.intervalState = Self.beginInterval(
            kind: kind,
            signposter: signposter,
            id: signpostID
        )
        mark("start", metadata: ["itemCount": "\(itemCount)"])
    }

    func mark(_ name: String, metadata: [String: String] = [:]) {
        let shouldEmit = lock.withLock { () -> Bool in
            guard intervalState != nil, !isSamplingCapped else {
                return false
            }
            markerCount += 1
            if markerCount >= 16 {
                isSamplingCapped = true
            }
            return true
        }
        guard shouldEmit else {
            return
        }

        _ = PerformanceDiagnosticsPrivacy.sanitizedMetadata(metadata)
        emitSafeStage(for: name)
    }

    func finish() {
        let result = lock.withLock { () -> (OSSignpostIntervalState, HistoryPerformanceTraceSummary)? in
            guard let intervalState else {
                return nil
            }
            self.intervalState = nil
            let summary = HistoryPerformanceTraceSummary(
                traceID: String(id),
                label: label,
                durationMS: (CFAbsoluteTimeGetCurrent() - startedAt) * 1_000,
                markerCount: min(markerCount, 16)
            )
            return (intervalState, summary)
        }
        guard let (intervalState, summary) = result else {
            return
        }

        Self.endInterval(
            kind: kind,
            signposter: signposter,
            state: intervalState
        )
        Task { await HistoryPerformanceTraceSummaryStore.shared.append(summary) }
    }

    deinit {
        finish()
    }

    private func emitSafeStage(for name: String) {
        switch kind {
        case .startup:
            if name == "listeners-ready" {
                signposter.emitEvent("app.startup.listeners-ready", id: signpostID)
            } else {
                signposter.emitEvent("app.startup.stage", id: signpostID)
            }
        case .exitDrain:
            if name == "drain-complete" {
                signposter.emitEvent("application.exit-drain.complete", id: signpostID)
            } else if name == "drain-timeout" {
                signposter.emitEvent("application.exit-drain.timeout", id: signpostID)
            } else {
                signposter.emitEvent("application.exit-drain.stage", id: signpostID)
            }
        case .historyRender:
            switch name {
            case "panel-frame-ready":
                signposter.emitEvent("history.render.panel-frame-ready", id: signpostID)
            case "panel-ordered":
                signposter.emitEvent("history.render.panel-ordered", id: signpostID)
            case "open-animation-complete":
                signposter.emitEvent("history.render.open-animation-complete", id: signpostID)
            default:
                signposter.emitEvent("history.render.stage", id: signpostID)
            }
        }
    }

    private static func beginInterval(
        kind: HistoryPerformanceTraceKind,
        signposter: OSSignposter,
        id: OSSignpostID
    ) -> OSSignpostIntervalState {
        switch kind {
        case .startup:
            signposter.beginInterval("app.startup", id: id)
        case .historyRender:
            signposter.beginInterval("history.render", id: id)
        case .exitDrain:
            signposter.beginInterval("application.exit-drain", id: id)
        }
    }

    private static func endInterval(
        kind: HistoryPerformanceTraceKind,
        signposter: OSSignposter,
        state: OSSignpostIntervalState
    ) {
        switch kind {
        case .startup:
            signposter.endInterval("app.startup", state)
        case .historyRender:
            signposter.endInterval("history.render", state)
        case .exitDrain:
            signposter.endInterval("application.exit-drain", state)
        }
    }
}
