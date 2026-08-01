import Foundation

enum HistoryWindowLifecycleDiagnostics {
    @MainActor private static var nextOpenID: UInt64 = 0
    @MainActor private(set) static var activeOpenID: String?

    enum Event: CaseIterable {
        case openRequest
        case openOrdered
        case openPresented
        case openFirstFrame
        case openDeferredStartup
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
            case .openDeferredStartup:
                "history.window.open.deferredStartup"
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

    @MainActor
    static func beginOpen() -> String {
        nextOpenID &+= 1
        if nextOpenID == 0 {
            nextOpenID = 1
        }
        let openID = String(nextOpenID)
        activeOpenID = openID
        return openID
    }

    @MainActor
    static func finishOpen() {
        activeOpenID = nil
    }

    static func metadata(
        itemCount: Int?,
        wasVisible: Bool,
        shouldAnimate: Bool,
        hasPendingFocus: Bool,
        visibleItemCount: Int?,
        previewItemCount: Int?,
        openID: String? = nil
    ) -> [String: String] {
        var metadata = [
            "itemCount": value(itemCount),
            "wasVisible": "\(wasVisible)",
            "shouldAnimate": "\(shouldAnimate)",
            "hasPendingFocus": "\(hasPendingFocus)",
            "visibleItemCount": value(visibleItemCount),
            "previewItemCount": value(previewItemCount)
        ]
        if let openID {
            metadata["openID"] = openID
        }
        return metadata
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
        if event == .openRequest {
            _ = beginOpen()
        }
        let openID = activeOpenID
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
                previewItemCount: previewItemCount,
                openID: openID
            )
        )
        if event == .closeCleanupComplete {
            finishOpen()
        }
    }

    private static func value(_ value: Int?) -> String {
        value.map(String.init) ?? "unknown"
    }
}
