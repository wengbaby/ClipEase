import Foundation
import Testing
@testable import ClipEase

@Test func historyWindowLifecycleDiagnosticsDefinesStableEventOrder() {
    #expect(HistoryWindowLifecycleDiagnostics.Event.allCases.map(\.name) == [
        "history.window.open.request",
        "history.window.open.ordered",
        "history.window.open.presented",
        "history.window.open.firstFrame",
        "history.window.open.previewReady",
        "history.window.close.request",
        "history.window.close.animationComplete",
        "history.window.close.cleanupComplete"
    ])
}

@Test func historyWindowLifecycleDiagnosticsBuildsFixedMetadataKeys() {
    let metadata = HistoryWindowLifecycleDiagnostics.metadata(
        itemCount: 42,
        wasVisible: false,
        shouldAnimate: true,
        hasPendingFocus: true,
        visibleItemCount: 12,
        previewItemCount: 30
    )

    #expect(metadata == [
        "hasPendingFocus": "true",
        "itemCount": "42",
        "previewItemCount": "30",
        "shouldAnimate": "true",
        "visibleItemCount": "12",
        "wasVisible": "false"
    ])
}

@Test func historyWindowLifecycleDiagnosticsUsesUnknownForUnavailableCounts() {
    let metadata = HistoryWindowLifecycleDiagnostics.metadata(
        itemCount: nil,
        wasVisible: true,
        shouldAnimate: false,
        hasPendingFocus: false,
        visibleItemCount: nil,
        previewItemCount: nil
    )

    #expect(metadata["itemCount"] == "unknown")
    #expect(metadata["visibleItemCount"] == "unknown")
    #expect(metadata["previewItemCount"] == "unknown")
    #expect(metadata["wasVisible"] == "true")
    #expect(metadata["shouldAnimate"] == "false")
    #expect(metadata["hasPendingFocus"] == "false")
    #expect(Set(metadata.keys) == [
        "itemCount",
        "wasVisible",
        "shouldAnimate",
        "hasPendingFocus",
        "visibleItemCount",
        "previewItemCount"
    ])
}
