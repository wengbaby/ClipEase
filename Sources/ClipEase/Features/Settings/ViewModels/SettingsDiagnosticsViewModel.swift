import Foundation

enum SettingsDiagnosticsSeverity: Equatable {
    case normal
    case warning
    case elevated
    case critical
}

enum SettingsDiagnosticsViewModel {
    nonisolated static func visibleSlowEvents(from events: [PerformanceDiagnosticEvent]) -> ArraySlice<PerformanceDiagnosticEvent> {
        events.filter { $0.durationMS >= 16 }.prefix(12)
    }

    nonisolated static func visibleRecentEvents(from events: [PerformanceDiagnosticEvent]) -> ArraySlice<PerformanceDiagnosticEvent> {
        events.prefix(30)
    }

    nonisolated static func visibleErrorEvents(from events: [PerformanceDiagnosticEvent]) -> ArraySlice<PerformanceDiagnosticEvent> {
        events.filter(isErrorEvent).prefix(6)
    }

    nonisolated static func barEvents(from events: [PerformanceDiagnosticEvent]) -> [PerformanceDiagnosticEvent] {
        Array(events.prefix(40).reversed())
    }

    nonisolated static func summaryText(
        recentEvents: [PerformanceDiagnosticEvent],
        fallback: String
    ) -> String {
        let errorCount = recentEvents.filter(isErrorEvent).count
        guard errorCount > 0 else {
            return fallback
        }
        return L("\(fallback)，错误 \(errorCount) 条")
    }

    nonisolated static func isErrorEvent(_ event: PerformanceDiagnosticEvent) -> Bool {
        if event.metadata["error"] != nil || event.metadata["errorType"] != nil {
            return true
        }
        return event.category.localizedCaseInsensitiveContains("error")
            || event.name.localizedCaseInsensitiveContains("error")
            || event.name.localizedCaseInsensitiveContains("failure")
    }

    nonisolated static func detailText(for event: PerformanceDiagnosticEvent) -> String {
        var parts = [
            timeFormatter.string(from: event.timestamp),
            event.category,
            event.isMainThread ? "main" : "background"
        ]
        if let itemCount = event.itemCount {
            parts.append("items=\(itemCount)")
        }
        if let resultCount = event.resultCount {
            parts.append("results=\(resultCount)")
        }
        if let cpuPercent = event.cpuPercent {
            parts.append("cpu=\(PerformanceDiagnosticsService.formatPercent(cpuPercent))")
        }
        if let memoryMB = event.memoryMB {
            parts.append("mem=\(PerformanceDiagnosticsService.formatMB(memoryMB))")
        }
        if let threadCount = event.threadCount {
            parts.append("threads=\(threadCount)")
        }
        if let mainThreadLatencyMS = event.mainThreadLatencyMS {
            parts.append("mainLatency=\(PerformanceDiagnosticsService.formatMS(mainThreadLatencyMS))")
        }
        for key in event.metadata.keys.sorted() {
            if let value = event.metadata[key] {
                parts.append("\(key)=\(value)")
            }
        }
        return parts.joined(separator: "  ")
    }

    nonisolated static func durationSeverity(for durationMS: Double) -> SettingsDiagnosticsSeverity {
        if durationMS >= 100 {
            return .critical
        }
        if durationMS >= 33 {
            return .elevated
        }
        if durationMS >= 16 {
            return .warning
        }
        return .normal
    }

    nonisolated static func cpuSeverity(for cpuPercent: Double) -> SettingsDiagnosticsSeverity {
        if cpuPercent >= 80 {
            return .critical
        }
        if cpuPercent >= 45 {
            return .elevated
        }
        return .normal
    }

    nonisolated static func memorySeverity(for memoryMB: Double) -> SettingsDiagnosticsSeverity {
        if memoryMB >= 1_500 {
            return .critical
        }
        if memoryMB >= 800 {
            return .elevated
        }
        return .normal
    }

    nonisolated private static var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }
}
