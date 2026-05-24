import SwiftUI
import AppKit

struct PersistentPopoverPresenter<Content: View>: NSViewRepresentable {
    @Binding var isPresented: Bool
    let arrowEdge: Edge
    let onDismiss: () -> Void
    @ViewBuilder var content: () -> Content

    func makeNSView(context: Context) -> AnchorView {
        let view = AnchorView()
        view.onFrameChange = { [weak coordinator = context.coordinator] in
            coordinator?.reposition()
        }
        context.coordinator.anchorView = view
        context.coordinator.isPresented = isPresented
        context.coordinator.arrowEdge = arrowEdge
        context.coordinator.onDismiss = onDismiss
        context.coordinator.updateContent(content())
        context.coordinator.updatePresentation()
        return view
    }

    func updateNSView(_ nsView: AnchorView, context: Context) {
        nsView.onFrameChange = { [weak coordinator = context.coordinator] in
            coordinator?.reposition()
        }
        context.coordinator.anchorView = nsView
        context.coordinator.isPresented = isPresented
        context.coordinator.arrowEdge = arrowEdge
        context.coordinator.onDismiss = onDismiss
        context.coordinator.updateContent(content())
        context.coordinator.updatePresentation()
    }

    static func dismantleNSView(_ nsView: AnchorView, coordinator: Coordinator) {
        coordinator.close(callDismiss: false)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(isPresented: $isPresented)
    }

    final class AnchorView: NSView {
        var onFrameChange: (() -> Void)?

        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            notifyFrameChangeSoon()
        }

        override func setFrameOrigin(_ newOrigin: NSPoint) {
            super.setFrameOrigin(newOrigin)
            notifyFrameChangeSoon()
        }

        override func setFrameSize(_ newSize: NSSize) {
            super.setFrameSize(newSize)
            notifyFrameChangeSoon()
        }

        private func notifyFrameChangeSoon() {
            DispatchQueue.main.async { [weak self] in
                self?.onFrameChange?()
            }
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSPopoverDelegate {
        private let isPresentedBinding: Binding<Bool>
        weak var anchorView: AnchorView?
        var isPresented = false
        var arrowEdge: Edge = .bottom
        var onDismiss: () -> Void = {}
        private var popover: NSPopover?
        private var hostingController: NSHostingController<Content>?

        init(isPresented: Binding<Bool>) {
            self.isPresentedBinding = isPresented
        }

        func updateContent(_ content: Content) {
            if let hostingController {
                hostingController.rootView = content
            } else {
                hostingController = NSHostingController(rootView: content)
            }
        }

        func updatePresentation() {
            if isPresented {
                show()
            } else {
                close(callDismiss: false)
            }
        }

        func show() {
            guard let anchorView,
                  anchorView.window != nil,
                  let hostingController else {
                DispatchQueue.main.async { [weak self] in
                    self?.updatePresentation()
                }
                return
            }

            let popover = popover ?? makePopover(hostingController: hostingController)
            if self.popover == nil {
                self.popover = popover
            }

            guard !popover.isShown else {
                return
            }

            popover.show(
                relativeTo: anchorView.bounds,
                of: anchorView,
                preferredEdge: nsRectEdge(for: arrowEdge)
            )
            scheduleReposition()
        }

        func reposition() {
            guard isPresented,
                  let popover,
                  popover.isShown,
                  let anchorView,
                  anchorView.window != nil else {
                return
            }

            popover.show(
                relativeTo: anchorView.bounds,
                of: anchorView,
                preferredEdge: nsRectEdge(for: arrowEdge)
            )
        }

        private func scheduleReposition() {
            DispatchQueue.main.async { [weak self] in
                self?.reposition()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
                self?.reposition()
            }
        }

        func close(callDismiss: Bool) {
            guard let popover else {
                return
            }

            if popover.isShown {
                popover.performClose(nil)
            }
            self.popover = nil
            if callDismiss {
                isPresentedBinding.wrappedValue = false
                onDismiss()
            }
        }

        func popoverDidClose(_ notification: Notification) {
            popover = nil
            guard isPresentedBinding.wrappedValue else {
                return
            }

            isPresentedBinding.wrappedValue = false
            onDismiss()
        }

        private func makePopover(hostingController: NSHostingController<Content>) -> NSPopover {
            let popover = NSPopover()
            popover.behavior = .applicationDefined
            popover.animates = true
            popover.contentViewController = hostingController
            popover.delegate = self
            return popover
        }

        private func nsRectEdge(for edge: Edge) -> NSRectEdge {
            switch edge {
            case .top:
                .maxY
            case .bottom:
                .minY
            case .leading:
                .minX
            case .trailing:
                .maxX
            }
        }
    }
}
