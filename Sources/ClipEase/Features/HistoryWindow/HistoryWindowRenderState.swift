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

    func mark(_ name: String) {
        performanceTrace?.mark(name)
    }
}
