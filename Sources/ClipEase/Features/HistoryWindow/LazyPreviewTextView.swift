import AppKit
import SwiftUI

private final class RichTextPreviewValue: @unchecked Sendable {
    let attributedString: NSAttributedString

    init(_ attributedString: NSAttributedString) {
        self.attributedString = attributedString
    }
}

private actor RichTextPreviewCache {
    static let shared = RichTextPreviewCache()

    private var storage: [String: RichTextPreviewValue] = [:]
    private var order: [String] = []
    private let limit = 48

    func value(for key: String) -> RichTextPreviewValue? {
        storage[key]
    }

    func store(_ value: RichTextPreviewValue, for key: String) {
        guard storage[key] == nil else {
            storage[key] = value
            return
        }

        storage[key] = value
        order.append(key)

        if order.count > limit {
            let removedKey = order.removeFirst()
            storage.removeValue(forKey: removedKey)
        }
    }
}

enum RichTextPreviewLoader {
    static func key(richTextFileName: String?, text: String) -> String {
        "\(richTextFileName ?? "plain")|\(text.count)|\(text.unicodeScalars.reduce(5381) { (($0 << 5) &+ $0) &+ Int($1.value) })"
    }

    static func attributedString(
        fileName: String,
        fallbackText: String
    ) async -> NSAttributedString {
        let cacheKey = key(richTextFileName: fileName, text: fallbackText)
        if let cached = await RichTextPreviewCache.shared.value(for: cacheKey) {
            return cached.attributedString
        }

        guard let fileURL = try? ClipEaseStoragePaths.richTextFileURL(fileName: fileName),
              let data = try? Data(contentsOf: fileURL),
              let attributedText = try? NSAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.rtf],
                documentAttributes: nil
              ) else {
            return NSAttributedString(string: fallbackText)
        }

        if attributedText.length > 0 {
            await RichTextPreviewCache.shared.store(RichTextPreviewValue(attributedText), for: cacheKey)
            return attributedText
        }

        return NSAttributedString(string: fallbackText)
    }
}

struct LazyPreviewTextView: NSViewRepresentable {
    let text: String
    let isReady: Bool
    let richTextFileName: String?

    func makeNSView(context: Context) -> NSScrollView {
        let textView = InteractivePreviewTextView()
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

        context.coordinator.update(
            text: text,
            isReady: isReady,
            richTextFileName: richTextFileName,
            in: textView
        )
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    @MainActor
    final class Coordinator {
        weak var textView: NSTextView?
        private var currentText = ""
        private var representedKey = ""
        private var appendTask: Task<Void, Never>?
        private var richTextTask: Task<Void, Never>?

        func update(
            text: String,
            isReady: Bool,
            richTextFileName: String?,
            in textView: NSTextView
        ) {
            guard isReady else {
                appendTask?.cancel()
                richTextTask?.cancel()
                currentText = ""
                representedKey = ""
                textView.string = ""
                return
            }

            let key = RichTextPreviewLoader.key(richTextFileName: richTextFileName, text: text)
            guard representedKey != key else {
                return
            }

            appendTask?.cancel()
            richTextTask?.cancel()
            representedKey = key
            currentText = ""

            if let richTextFileName {
                textView.textStorage?.setAttributedString(NSAttributedString(string: ""))
                richTextTask = Task.detached(priority: .utility) {
                    let attributedString = await RichTextPreviewLoader.attributedString(
                        fileName: richTextFileName,
                        fallbackText: text
                    )

                    await MainActor.run { [weak self, weak textView] in
                        guard let self,
                              let textView,
                              self.representedKey == key,
                              !Task.isCancelled else {
                            return
                        }

                        textView.textStorage?.setAttributedString(attributedString)
                    }
                }
                return
            }

            textView.textStorage?.setAttributedString(NSAttributedString(string: ""))
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
            richTextTask?.cancel()
        }
    }
}

private final class InteractivePreviewTextView: NSTextView {
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }
}
