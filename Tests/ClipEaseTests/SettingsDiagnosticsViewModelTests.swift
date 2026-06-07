import Foundation
import Testing
@testable import ClipEase

@Test func settingsDiagnosticsDetailTextIncludesStableMetadataOrder() {
    let date = Date(timeIntervalSince1970: 12 * 60 * 60 + 34 * 60 + 56.789)
    let event = PerformanceDiagnosticEvent(
        timestamp: date,
        name: "history.search",
        category: "search",
        durationMS: 42.5,
        itemCount: 12,
        resultCount: 3,
        metadata: [
            "query": "abc",
            "phase": "filter"
        ],
        isMainThread: false,
        cpuPercent: 12.3,
        memoryMB: 456.7,
        threadCount: 8,
        mainThreadLatencyMS: 9.1
    )

    let text = SettingsDiagnosticsViewModel.detailText(for: event)

    #expect(text.contains("20:34:56.789"))
    #expect(text.contains("search"))
    #expect(text.contains("background"))
    #expect(text.contains("items=12"))
    #expect(text.contains("results=3"))
    #expect(text.contains("cpu=12.3%"))
    #expect(text.contains("mem=456.7 MB"))
    #expect(text.contains("threads=8"))
    #expect(text.contains("mainLatency=9.1 ms"))
    #expect(text.range(of: "phase=filter")!.lowerBound < text.range(of: "query=abc")!.lowerBound)
}

@Test func settingsDiagnosticsViewModelLimitsSlowAndRecentEvents() {
    let events = (0..<45).map { index in
        PerformanceDiagnosticEvent(
            name: "event.\(index)",
            category: "test",
            durationMS: Double(index),
            isMainThread: true
        )
    }

    #expect(SettingsDiagnosticsViewModel.visibleSlowEvents(from: events).count == 12)
    #expect(SettingsDiagnosticsViewModel.visibleRecentEvents(from: events).count == 30)
    #expect(SettingsDiagnosticsViewModel.barEvents(from: events).count == 40)
}

@Test func settingsDiagnosticsViewModelSurfacesRecentErrorEvents() {
    let events = (0..<8).map { index in
        PerformanceDiagnosticEvent(
            name: "error.\(index)",
            category: "storage",
            durationMS: 0,
            metadata: [
                "error": "failed \(index)",
                "operation": "save"
            ]
        )
    } + [
        PerformanceDiagnosticEvent(name: "normal", category: "search", durationMS: 4)
    ]

    let errors = SettingsDiagnosticsViewModel.visibleErrorEvents(from: events)

    #expect(errors.count == 6)
    #expect(errors.first?.name == "error.0")
    #expect(errors.allSatisfy { SettingsDiagnosticsViewModel.isErrorEvent($0) })
}

@Test func settingsDiagnosticsSummaryIncludesErrorCount() {
    let events = [
        PerformanceDiagnosticEvent(name: "normal", category: "search", durationMS: 4),
        PerformanceDiagnosticEvent(
            name: "persist.failure",
            category: "storage",
            durationMS: 0,
            metadata: ["error": "disk full"]
        )
    ]

    let summary = SettingsDiagnosticsViewModel.summaryText(
        recentEvents: events,
        fallback: "最近 2 条，平均 2.0 ms，最高 4.0 ms"
    )

    #expect(summary == "最近 2 条，平均 2.0 ms，最高 4.0 ms，错误 1 条")
}

@Test func settingsDiagnosticsSeverityLevelsMatchExistingThresholds() {
    #expect(SettingsDiagnosticsViewModel.durationSeverity(for: 8) == .normal)
    #expect(SettingsDiagnosticsViewModel.durationSeverity(for: 16) == .warning)
    #expect(SettingsDiagnosticsViewModel.durationSeverity(for: 33) == .elevated)
    #expect(SettingsDiagnosticsViewModel.durationSeverity(for: 100) == .critical)
    #expect(SettingsDiagnosticsViewModel.cpuSeverity(for: 44.9) == .normal)
    #expect(SettingsDiagnosticsViewModel.cpuSeverity(for: 45) == .elevated)
    #expect(SettingsDiagnosticsViewModel.cpuSeverity(for: 80) == .critical)
    #expect(SettingsDiagnosticsViewModel.memorySeverity(for: 799.9) == .normal)
    #expect(SettingsDiagnosticsViewModel.memorySeverity(for: 800) == .elevated)
    #expect(SettingsDiagnosticsViewModel.memorySeverity(for: 1_500) == .critical)
}
