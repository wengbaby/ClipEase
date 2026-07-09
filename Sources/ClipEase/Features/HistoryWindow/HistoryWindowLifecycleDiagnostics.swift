import Foundation

enum HistoryWindowLifecycleDiagnostics {
    enum Event: CaseIterable {
        case openRequest
        case openOrdered
        case openPresented
        case openFirstFrame
        case openPreviewReady
        case closeRequest
        case closeAnimationComplete
        case closeCleanupComplete

        var name: String {
            switch self {
            case .openRequest:
                "history.window.open.request"
            case .openOrdered:
                "history.window.open.ordered"
            case .openPresented:
                "history.window.open.presented"
            case .openFirstFrame:
                "history.window.open.firstFrame"
            case .openPreviewReady:
                "history.window.open.previewReady"
            case .closeRequest:
                "history.window.close.request"
            case .closeAnimationComplete:
                "history.window.close.animationComplete"
            case .closeCleanupComplete:
                "history.window.close.cleanupComplete"
            }
        }
    }

    static let category = "history"

    static func metadata(
        itemCount: Int?,
        wasVisible: Bool,
        shouldAnimate: Bool,
        hasPendingFocus: Bool,
        visibleItemCount: Int?,
        previewItemCount: Int?
    ) -> [String: String] {
        [
            "itemCount": value(itemCount),
            "wasVisible": "\(wasVisible)",
            "shouldAnimate": "\(shouldAnimate)",
            "hasPendingFocus": "\(hasPendingFocus)",
            "visibleItemCount": value(visibleItemCount),
            "previewItemCount": value(previewItemCount)
        ]
    }

    @MainActor
    static func record(
        _ event: Event,
        itemCount: Int?,
        wasVisible: Bool,
        shouldAnimate: Bool,
        hasPendingFocus: Bool,
        visibleItemCount: Int? = nil,
        previewItemCount: Int? = nil
    ) {
        PerformanceDiagnosticsService.shared.recordInstant(
            event.name,
            category: category,
            itemCount: itemCount,
            resultCount: previewItemCount,
            metadata: metadata(
                itemCount: itemCount,
                wasVisible: wasVisible,
                shouldAnimate: shouldAnimate,
                hasPendingFocus: hasPendingFocus,
                visibleItemCount: visibleItemCount,
                previewItemCount: previewItemCount
            )
        )
    }

    private static func value(_ value: Int?) -> String {
        value.map(String.init) ?? "unknown"
    }
}
