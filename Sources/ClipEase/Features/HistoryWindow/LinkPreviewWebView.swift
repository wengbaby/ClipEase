import SwiftUI
import WebKit

struct LinkPreviewWebView: NSViewRepresentable {
    let url: URL?
    let onLoadingStateChange: (Bool) -> Void
    let onLoadFailure: (String?) -> Void

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        let webView = InteractivePreviewWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = false
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard let url,
              context.coordinator.loadedURL != url else {
            return
        }

        context.coordinator.loadedURL = url
        context.coordinator.onLoadingStateChange = onLoadingStateChange
        context.coordinator.onLoadFailure = onLoadFailure
        onLoadingStateChange(true)
        onLoadFailure(nil)
        webView.load(URLRequest(url: url))
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onLoadingStateChange: onLoadingStateChange,
            onLoadFailure: onLoadFailure
        )
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var loadedURL: URL?
        var onLoadingStateChange: (Bool) -> Void
        var onLoadFailure: (String?) -> Void

        init(
            onLoadingStateChange: @escaping (Bool) -> Void,
            onLoadFailure: @escaping (String?) -> Void
        ) {
            self.onLoadingStateChange = onLoadingStateChange
            self.onLoadFailure = onLoadFailure
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            onLoadingStateChange(false)
            onLoadFailure(nil)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            onLoadingStateChange(false)
            onLoadFailure(error.localizedDescription)
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            onLoadingStateChange(false)
            onLoadFailure(error.localizedDescription)
        }
    }
}

private final class InteractivePreviewWebView: WKWebView {
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }
}
