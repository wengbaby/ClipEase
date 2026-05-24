import Foundation

@MainActor
final class HistoryWindowRenderState: ObservableObject {
    static let preheatBatchSize = 18

    @Published private(set) var renderGeneration = UUID()
    private(set) var performanceTrace: HistoryPerformanceTrace?

    func prepareForShow(itemCount: Int) {
        renderGeneration = UUID()
        performanceTrace = HistoryPerformanceTrace(label: "history-open", itemCount: itemCount)
    }

    func prepareForPreload(itemCount: Int) {
        renderGeneration = UUID()
        performanceTrace = HistoryPerformanceTrace(label: "history-preload", itemCount: itemCount)
    }

    func mark(_ name: String) {
        performanceTrace?.mark(name)
    }

    func markAndFinish(_ name: String) {
        performanceTrace?.mark(name)
        performanceTrace = nil
    }

    func finishTrace() {
        performanceTrace = nil
    }
}
