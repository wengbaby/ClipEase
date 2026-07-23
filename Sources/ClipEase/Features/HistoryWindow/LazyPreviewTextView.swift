import AppKit
import SwiftUI

final class RichTextPreviewValue: @unchecked Sendable {
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

    static func value(
        fileName: String,
        fallbackText: String
    ) async -> RichTextPreviewValue {
        let cacheKey = key(richTextFileName: fileName, text: fallbackText)
        if let cached = await RichTextPreviewCache.shared.value(for: cacheKey) {
            return cached
        }

        guard let fileURL = try? ClipEaseStoragePaths.richTextFileURL(fileName: fileName),
              let data = try? Data(contentsOf: fileURL),
              let attributedText = try? NSAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.rtf],
                documentAttributes: nil
              ) else {
            return RichTextPreviewValue(NSAttributedString(string: fallbackText))
        }

        if attributedText.length > 0 {
            let value = RichTextPreviewValue(attributedText)
            await RichTextPreviewCache.shared.store(value, for: cacheKey)
            return value
        }

        return RichTextPreviewValue(NSAttributedString(string: fallbackText))
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

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        coordinator.cancel()
        scrollView.documentView = nil
    }

    @MainActor
    final class Coordinator {
        weak var textView: NSTextView?
        private var representedKey = ""
        private var appendTask: Task<Void, Never>?
        private var richTextTask: Task<Void, Never>?
        private let waitBetweenChunks: @MainActor () async -> Void
        private let loadRichText: @Sendable (String, String) async -> RichTextPreviewValue

        init(
            waitBetweenChunks: @escaping @MainActor () async -> Void = {
                try? await Task.sleep(nanoseconds: 12_000_000)
            },
            loadRichText: @escaping @Sendable (String, String) async -> RichTextPreviewValue = { fileName, fallbackText in
                await RichTextPreviewLoader.value(
                    fileName: fileName,
                    fallbackText: fallbackText
                )
            }
        ) {
            self.waitBetweenChunks = waitBetweenChunks
            self.loadRichText = loadRichText
        }

        @discardableResult
        func update(
            text: String,
            isReady: Bool,
            richTextFileName: String?,
            in textView: NSTextView
        ) -> Task<Void, Never>? {
            guard isReady else {
                cancelPendingTasks()
                representedKey = ""
                textView.string = ""
                return nil
            }

            let key = RichTextPreviewLoader.key(richTextFileName: richTextFileName, text: text)
            guard representedKey != key else {
                return appendTask ?? richTextTask
            }

            cancelPendingTasks()
            representedKey = key

            if let richTextFileName {
                textView.textStorage?.setAttributedString(NSAttributedString(string: ""))
                let loadRichText = self.loadRichText
                richTextTask = Task.detached(priority: .utility) { [weak self, weak textView] in
                    let richTextValue = await loadRichText(richTextFileName, text)

                    await MainActor.run { [weak self, weak textView] in
                        guard let self,
                              let textView,
                              self.representedKey == key,
                              !Task.isCancelled else {
                            return
                        }

                        textView.textStorage?.setAttributedString(richTextValue.attributedString)
                    }
                }
                return richTextTask
            }

            textView.textStorage?.setAttributedString(NSAttributedString(string: ""))
            append(text, to: textView)
            return appendTask
        }

        private func append(_ text: String, to textView: NSTextView) {
            let chunkSize = 8_000
            let waitBetweenChunks = self.waitBetweenChunks

            appendTask = Task { @MainActor [weak textView] in
                var renderedText = ""
                var start = text.startIndex

                while start < text.endIndex {
                    guard !Task.isCancelled else {
                        return
                    }

                    let end = text.index(
                        start,
                        offsetBy: chunkSize,
                        limitedBy: text.endIndex
                    ) ?? text.endIndex
                    guard Self.append(
                        text[start..<end],
                        to: &renderedText,
                        in: textView
                    ) else {
                        return
                    }

                    start = end
                    if start < text.endIndex {
                        await waitBetweenChunks()
                    }
                }
            }
        }

        func cancel() {
            cancelPendingTasks()
            representedKey = ""
            textView = nil
        }

        private func cancelPendingTasks() {
            appendTask?.cancel()
            appendTask = nil
            richTextTask?.cancel()
            richTextTask = nil
        }

        private static func append(
            _ chunk: Substring,
            to renderedText: inout String,
            in textView: NSTextView?
        ) -> Bool {
            guard let textView else {
                return false
            }
            renderedText.append(contentsOf: chunk)
            textView.string = renderedText
            return true
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
