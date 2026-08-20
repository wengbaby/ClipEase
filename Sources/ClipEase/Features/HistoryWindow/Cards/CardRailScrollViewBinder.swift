import SwiftUI
import AppKit

struct CardRailScrollViewBinder: NSViewRepresentable {
    let onBind: () -> Void

    func makeNSView(context: Context) -> BindingView {
        let view = BindingView()
        view.onBind = onBind
        view.bindScrollViewSoon()
        return view
    }

    func updateNSView(_ nsView: BindingView, context: Context) {
        nsView.onBind = onBind
        nsView.bindScrollViewSoon()
    }

    final class BindingView: NSView {
        var onBind: (() -> Void)?
        private var isBindScheduled = false
        private var bindingRetryCount = 0

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            bindScrollViewSoon()
        }

        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            bindScrollViewSoon()
        }

        override func layout() {
            super.layout()
            bindScrollViewSoon()
        }

        func bindScrollViewSoon() {
            guard !isBindScheduled else {
                return
            }

            isBindScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else {
                    return
                }

                self.isBindScheduled = false
                self.bindScrollViewIfNeeded()
                self.scheduleBindingRetryIfNeeded()
            }
        }

        func bindScrollViewIfNeeded() {
            guard let scrollView = enclosingScrollView else {
                return
            }

            HistoryScrollCoordinator.shared.update(scrollView: scrollView)
            onBind?()
            if let visibleRect = HistoryScrollCoordinator.shared.visibleDocumentRect,
               visibleRect.width > 0,
               visibleRect.height > 0 {
                bindingRetryCount = 0
            }
        }

        func scheduleBindingRetryIfNeeded() {
            let hasUsableVisibleRect = HistoryScrollCoordinator.shared.visibleDocumentRect.map {
                $0.width > 0 && $0.height > 0
            } == true
            guard bindingRetryCount < 60,
                  enclosingScrollView == nil || !hasUsableVisibleRect else {
                return
            }

            bindingRetryCount += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.016) { [weak self] in
                self?.bindScrollViewSoon()
            }
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }
    }
}
