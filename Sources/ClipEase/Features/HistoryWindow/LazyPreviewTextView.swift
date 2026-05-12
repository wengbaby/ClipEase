import AppKit
import SwiftUI

struct LazyPreviewTextView: NSViewRepresentable {
    let text: String
    let isReady: Bool

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 16, height: 16)
        textView.font = .systemFont(ofSize: 15, weight: .regular)
        textView.textColor = NSColor(red: 0.12, green: 0.14, blue: 0.17, alpha: 1)
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: 0,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.autoresizingMask = [.width]

        let scrollView = NSScrollView()
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .white
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.documentView = textView
        context.coordinator.textView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else {
            return
        }

        context.coordinator.update(text: text, isReady: isReady, in: textView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    @MainActor
    final class Coordinator {
        weak var textView: NSTextView?
        private var currentText = ""
        private var representedText = ""
        private var appendTask: Task<Void, Never>?

        func update(text: String, isReady: Bool, in textView: NSTextView) {
            guard isReady else {
                appendTask?.cancel()
                currentText = ""
                representedText = ""
                textView.string = ""
                return
            }

            guard representedText != text else {
                return
            }

            appendTask?.cancel()
            representedText = text
            currentText = ""
            textView.string = ""
            append(text, to: textView)
        }

        private func append(_ text: String, to textView: NSTextView) {
            let chunkSize = 8_000
            let chunks = stride(from: 0, to: text.count, by: chunkSize).map { offset in
                let start = text.index(text.startIndex, offsetBy: offset)
                let end = text.index(start, offsetBy: min(chunkSize, text.distance(from: start, to: text.endIndex)))
                return String(text[start..<end])
            }

            appendTask = Task { @MainActor [weak self, weak textView] in
                guard let self, let textView else {
                    return
                }

                for chunk in chunks {
                    guard !Task.isCancelled else {
                        return
                    }

                    self.currentText += chunk
                    textView.string = self.currentText
                    try? await Task.sleep(nanoseconds: 12_000_000)
                }
            }
        }

        deinit {
            appendTask?.cancel()
        }
    }
}
