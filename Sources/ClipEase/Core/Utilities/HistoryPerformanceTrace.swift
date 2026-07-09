import Foundation

final class HistoryPerformanceTrace: @unchecked Sendable {
    private let id = UUID().uuidString.prefix(8)
    private let startedAt = CFAbsoluteTimeGetCurrent()
    private var lastMarkAt = CFAbsoluteTimeGetCurrent()
    private let label: String

    init(label: String, itemCount: Int) {
        self.label = label
        mark("start items=\(itemCount)")
    }

    func mark(_ name: String, metadata: [String: String] = [:]) {
        let now = CFAbsoluteTimeGetCurrent()
        let totalMS = (now - startedAt) * 1_000
        let deltaMS = (now - lastMarkAt) * 1_000
        lastMarkAt = now
        NSLog("ClipEasePerf[\(id)] \(label) \(name) total=\(String(format: "%.1f", totalMS))ms delta=\(String(format: "%.1f", deltaMS))ms")
        var eventMetadata = metadata
        eventMetadata["traceID"] = String(id)
        eventMetadata["totalMS"] = String(format: "%.1f", totalMS)
        Task { @MainActor in
            PerformanceDiagnosticsService.shared.record(
                "\(label).\(name)",
                category: "history",
                durationMS: deltaMS,
                metadata: eventMetadata
            )
        }
    }
}
