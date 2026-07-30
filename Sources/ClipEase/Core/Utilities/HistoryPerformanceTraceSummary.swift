import Foundation

struct HistoryPerformanceTraceSummary: Equatable, Sendable {
    let traceID: String
    let label: String
    let durationMS: Double
    let markerCount: Int
}

actor HistoryPerformanceTraceSummaryStore {
    static let shared = HistoryPerformanceTraceSummaryStore()
    private let maximumSummaries = 64
    private var summaries: [HistoryPerformanceTraceSummary] = []

    func append(_ summary: HistoryPerformanceTraceSummary) {
        summaries.append(summary)
        if summaries.count > maximumSummaries {
            summaries.removeFirst(summaries.count - maximumSummaries)
        }
    }
}
