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
            }
        }

        func bindScrollViewIfNeeded() {
            guard let scrollView = enclosingScrollView else {
                return
            }

            HistoryScrollCoordinator.shared.update(scrollView: scrollView)
            onBind?()
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }
    }
}
