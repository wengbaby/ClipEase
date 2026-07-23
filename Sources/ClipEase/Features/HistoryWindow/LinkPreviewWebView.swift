import SwiftUI
@preconcurrency import WebKit

enum LinkPreviewNavigationDecision: Equatable {
    case allow
    case cancel
}

enum LinkPreviewNavigationPolicy {
    static func decision(for url: URL?) -> LinkPreviewNavigationDecision {
        guard let scheme = url?.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return .cancel
        }
        return .allow
    }
}

enum LinkPreviewNavigationURLTrackingPolicy {
    static func urlToTrack(_ url: URL?, isMainFrame: Bool?) -> URL? {
        guard isMainFrame == true else {
            return nil
        }
        return url
    }
}

enum LinkPreviewNavigationFailureDisposition: Equatable {
    case ignore
    case cancelled
    case failure
}

enum LinkPreviewNavigationFailurePolicy {
    static func disposition(
        for error: Error,
        currentNavigationURL: URL?
    ) -> LinkPreviewNavigationFailureDisposition {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain,
           nsError.code == NSURLErrorCancelled {
            return .cancelled
        }

        guard let failingURL = failingURL(from: nsError) else {
            return .failure
        }
        guard failingURL == currentNavigationURL else {
            return .ignore
        }
        return .failure
    }

    private static func failingURL(from error: NSError) -> URL? {
        if let url = error.userInfo[NSURLErrorFailingURLErrorKey] as? URL {
            return url
        }
        if let rawURL = error.userInfo[NSURLErrorFailingURLStringErrorKey] as? String {
            return URL(string: rawURL)
        }
        return nil
    }
}

@MainActor
final class LinkPreviewNavigationLifecycle<ID: Hashable> {
    typealias Generation = UInt64

    private var generation: Generation = 0
    private var currentID: ID?
    private var isDismantled = false

    func begin() -> Generation? {
        guard !isDismantled else {
            return nil
        }
        generation &+= 1
        currentID = nil
        return generation
    }

    func associate(_ id: ID, generation requestedGeneration: Generation) -> Bool {
        guard !isDismantled,
              generation == requestedGeneration else {
            return false
        }
        currentID = id
        return true
    }

    func beginObserved(
        _ id: ID,
        generation observedGeneration: Generation?
    ) -> Generation? {
        guard !isDismantled else {
            return nil
        }
        if let observedGeneration {
            guard generation == observedGeneration,
                  currentID == id else {
                return nil
            }
            return observedGeneration
        }
        generation &+= 1
        currentID = id
        return generation
    }

    func finish(_ id: ID, generation observedGeneration: Generation) -> Bool {
        guard !isDismantled,
              generation == observedGeneration,
              currentID == id else {
            return false
        }
        currentID = nil
        return true
    }

    func finishCurrent() -> Bool {
        guard !isDismantled,
              currentID != nil else {
            return false
        }
        currentID = nil
        return true
    }

    func cancel() {
        guard !isDismantled else {
            return
        }
        generation &+= 1
        currentID = nil
    }

    func dismantle() {
        guard !isDismantled else {
            return
        }
        isDismantled = true
        generation &+= 1
        currentID = nil
    }
}

struct LinkPreviewWebView: NSViewRepresentable {
    let url: URL?
    let onLoadingStateChange: (Bool) -> Void
    let onLoadFailure: (String?) -> Void

    static func makeConfiguration() -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        return configuration
    }

    func makeNSView(context: Context) -> WKWebView {
        let webView = InteractivePreviewWebView(
            frame: .zero,
            configuration: Self.makeConfiguration()
        )
        webView.allowsBackForwardNavigationGestures = false
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.updateCallbacks(
            onLoadingStateChange: onLoadingStateChange,
            onLoadFailure: onLoadFailure
        )
        context.coordinator.load(url: url, in: webView)
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.dismantle(webView: webView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onLoadingStateChange: onLoadingStateChange,
            onLoadFailure: onLoadFailure
        )
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        typealias StopLoading = @MainActor (WKWebView) -> Void

        private(set) var loadedURL: URL?
        private var onLoadingStateChange: (Bool) -> Void
        private var onLoadFailure: (String?) -> Void
        private let stopLoading: StopLoading
        private let navigationLifecycle: LinkPreviewNavigationLifecycle<ObjectIdentifier>
        private let navigationGenerations = NSMapTable<WKNavigation, NSNumber>(
            keyOptions: [.weakMemory, .objectPointerPersonality],
            valueOptions: .strongMemory
        )
        private var currentNavigationURL: URL?
        private var isDismantled = false

        init(
            onLoadingStateChange: @escaping (Bool) -> Void,
            onLoadFailure: @escaping (String?) -> Void,
            stopLoading: @escaping StopLoading = { $0.stopLoading() },
            navigationLifecycle: LinkPreviewNavigationLifecycle<ObjectIdentifier> = .init()
        ) {
            self.onLoadingStateChange = onLoadingStateChange
            self.onLoadFailure = onLoadFailure
            self.stopLoading = stopLoading
            self.navigationLifecycle = navigationLifecycle
        }

        func updateCallbacks(
            onLoadingStateChange: @escaping (Bool) -> Void,
            onLoadFailure: @escaping (String?) -> Void
        ) {
            guard !isDismantled else {
                return
            }
            self.onLoadingStateChange = onLoadingStateChange
            self.onLoadFailure = onLoadFailure
        }

        func load(url: URL?, in webView: WKWebView) {
            guard !isDismantled,
                  loadedURL != url else {
                return
            }

            if loadedURL != nil {
                stopLoading(webView)
            }
            loadedURL = url
            currentNavigationURL = url

            guard let url else {
                navigationLifecycle.cancel()
                onLoadingStateChange(false)
                onLoadFailure(nil)
                return
            }

            guard LinkPreviewNavigationPolicy.decision(for: url) == .allow else {
                navigationLifecycle.cancel()
                onLoadingStateChange(false)
                onLoadFailure("不支持此链接预览")
                return
            }

            guard let generation = navigationLifecycle.begin() else {
                return
            }
            onLoadingStateChange(true)
            onLoadFailure(nil)
            guard let navigation = webView.load(URLRequest(url: url)) else {
                navigationLifecycle.cancel()
                onLoadingStateChange(false)
                onLoadFailure("无法加载链接预览")
                return
            }
            if navigationLifecycle.associate(
                ObjectIdentifier(navigation),
                generation: generation
            ) {
                record(generation: generation, for: navigation)
            }
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            guard let navigation else {
                return
            }
            let knownGeneration = generation(for: navigation)
            guard let observedGeneration = navigationLifecycle.beginObserved(
                ObjectIdentifier(navigation),
                generation: knownGeneration
            ) else {
                return
            }
            if knownGeneration == nil {
                record(generation: observedGeneration, for: navigation)
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard let navigation,
                  let generation = generation(for: navigation),
                  navigationLifecycle.finish(
                    ObjectIdentifier(navigation),
                    generation: generation
                  ) else {
                return
            }
            onLoadingStateChange(false)
            onLoadFailure(nil)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            handleFailure(
                navigation: navigation,
                error: error
            )
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            handleFailure(
                navigation: navigation,
                error: error
            )
        }

        private func handleFailure(
            navigation: WKNavigation?,
            error: Error
        ) {
            if let navigation {
                guard let generation = generation(for: navigation),
                      navigationLifecycle.finish(
                        ObjectIdentifier(navigation),
                        generation: generation
                      ) else {
                    return
                }
                if LinkPreviewNavigationFailurePolicy.disposition(
                    for: error,
                    currentNavigationURL: nil
                ) == .cancelled {
                    onLoadingStateChange(false)
                    onLoadFailure(nil)
                    return
                }
            } else {
                switch LinkPreviewNavigationFailurePolicy.disposition(
                    for: error,
                    currentNavigationURL: currentNavigationURL
                ) {
                case .ignore, .cancelled:
                    return
                case .failure:
                    break
                }
                guard navigationLifecycle.finishCurrent() else {
                    return
                }
            }
            onLoadingStateChange(false)
            onLoadFailure(error.localizedDescription)
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
        ) {
            switch LinkPreviewNavigationPolicy.decision(for: navigationAction.request.url) {
            case .allow:
                if let trackedURL = LinkPreviewNavigationURLTrackingPolicy.urlToTrack(
                    navigationAction.request.url,
                    isMainFrame: navigationAction.targetFrame?.isMainFrame
                ) {
                    currentNavigationURL = trackedURL
                }
                decisionHandler(.allow)
            case .cancel:
                decisionHandler(.cancel)
            }
        }

        func dismantle(webView: WKWebView) {
            guard !isDismantled else {
                return
            }
            isDismantled = true
            navigationLifecycle.dismantle()
            stopLoading(webView)
            loadedURL = nil
            currentNavigationURL = nil
            navigationGenerations.removeAllObjects()
            webView.navigationDelegate = nil
            webView.uiDelegate = nil
            onLoadingStateChange = { _ in }
            onLoadFailure = { _ in }
        }

        private func generation(for navigation: WKNavigation) -> UInt64? {
            navigationGenerations.object(forKey: navigation)?.uint64Value
        }

        private func record(generation: UInt64, for navigation: WKNavigation) {
            navigationGenerations.setObject(NSNumber(value: generation), forKey: navigation)
        }
    }
}

private final class InteractivePreviewWebView: WKWebView {
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }
}
