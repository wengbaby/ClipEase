import AppKit

@MainActor
final class RichTextEditorController: NSObject, NSTextViewDelegate {
    private let onCreate: (Data, String) -> Void
    private let panel: NSPanel
    private let textView: NSTextView
    private let characterLabel: NSTextField
    private let wordLabel: NSTextField
    private let lineLabel: NSTextField
    private var fontSize: CGFloat = 20

    init(onCreate: @escaping (Data, String) -> Void) {
        self.onCreate = onCreate

        let panel = RichTextEditorPanel(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 360),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.center()

        let textView = NSTextView(frame: .zero)
        textView.isRichText = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.importsGraphics = false
        textView.usesFontPanel = false
        textView.font = .systemFont(ofSize: 16)
        textView.textColor = .black
        textView.insertionPointColor = .systemBlue
        textView.textContainerInset = NSSize(width: 10, height: 9)
        textView.backgroundColor = .white
        textView.typingAttributes = [
            .font: NSFont.systemFont(ofSize: 16),
            .foregroundColor: NSColor.black
        ]

        self.panel = panel
        self.textView = textView
        self.characterLabel = Self.makeFooterLabel("0 个字符")
        self.wordLabel = Self.makeFooterLabel("0 单词")
        self.lineLabel = Self.makeFooterLabel("0 行")
        super.init()

        textView.delegate = self
        panel.contentView = makeContentView()
    }

    func show() {
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        enforceBlackText()
        panel.makeFirstResponder(textView)
    }

    func textDidChange(_ notification: Notification) {
        enforceBlackText()
        updateFooter()
    }

    func textView(
        _ textView: NSTextView,
        shouldChangeTextIn affectedCharRange: NSRange,
        replacementString: String?
    ) -> Bool {
        textView.typingAttributes = normalizedTypingAttributes()
        return true
    }

    private func makeContentView() -> NSView {
        let rootView = NSView()
        rootView.wantsLayer = true
        rootView.layer?.backgroundColor = NSColor(red: 0.91, green: 0.91, blue: 0.93, alpha: 1.0).cgColor
        rootView.layer?.cornerRadius = 12
        rootView.layer?.masksToBounds = true

        let toolbar = DraggableToolbarView(panel: panel)
        toolbar.orientation = .horizontal
        toolbar.alignment = .centerY
        toolbar.distribution = .gravityAreas
        toolbar.spacing = 18
        toolbar.translatesAutoresizingMaskIntoConstraints = false

        let cancelButton = toolbarButton("取消", action: #selector(cancelAction))
        cancelButton.font = .systemFont(ofSize: 12, weight: .medium)

        let styleGroup = NSStackView()
        styleGroup.orientation = .horizontal
        styleGroup.spacing = 20
        styleGroup.alignment = .centerY
        styleGroup.addArrangedSubview(iconButton("B", action: #selector(toggleBold), font: .boldSystemFont(ofSize: 12)))
        styleGroup.addArrangedSubview(iconButton("I", action: #selector(toggleItalic), font: Self.italicFont(size: 12)))
        styleGroup.addArrangedSubview(iconButton("U", action: #selector(toggleUnderline), font: .systemFont(ofSize: 12)))
        styleGroup.addArrangedSubview(iconButton("S", action: #selector(toggleStrikethrough), font: .systemFont(ofSize: 12)))
        styleGroup.addArrangedSubview(iconButton("A-", action: #selector(decreaseFontSize), font: .systemFont(ofSize: 12, weight: .semibold)))
        styleGroup.addArrangedSubview(iconButton("A+", action: #selector(increaseFontSize), font: .systemFont(ofSize: 12, weight: .semibold)))

        let createButton = primaryButton("创建", action: #selector(createAction))

        toolbar.addView(cancelButton, in: .leading)
        toolbar.addView(styleGroup, in: .center)
        toolbar.addView(createButton, in: .trailing)

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        scrollView.wantsLayer = true
        scrollView.layer?.cornerRadius = 8
        scrollView.layer?.backgroundColor = NSColor.white.cgColor
        scrollView.contentView.postsBoundsChangedNotifications = true
        scrollView.documentView = textView
        configureTextViewForScrollView(textView, scrollView: scrollView)
        textView.drawsBackground = true

        let footer = NSStackView()
        footer.orientation = .horizontal
        footer.spacing = 14
        footer.alignment = .centerY
        footer.translatesAutoresizingMaskIntoConstraints = false
        footer.addArrangedSubview(characterLabel)
        footer.addArrangedSubview(separatorLabel())
        footer.addArrangedSubview(wordLabel)
        footer.addArrangedSubview(separatorLabel())
        footer.addArrangedSubview(lineLabel)

        rootView.addSubview(toolbar)
        rootView.addSubview(scrollView)
        rootView.addSubview(footer)

        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: rootView.topAnchor, constant: 6),
            toolbar.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: 8),
            toolbar.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -8),
            toolbar.heightAnchor.constraint(equalToConstant: 26),

            scrollView.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 6),
            scrollView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: 4),
            scrollView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -4),
            scrollView.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -8),

            footer.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: 12),
            footer.trailingAnchor.constraint(lessThanOrEqualTo: rootView.trailingAnchor, constant: -12),
            footer.bottomAnchor.constraint(equalTo: rootView.bottomAnchor, constant: -8),
            footer.heightAnchor.constraint(equalToConstant: 20)
        ])

        updateFooter()
        return rootView
    }

    private func configureTextViewForScrollView(_ textView: NSTextView, scrollView: NSScrollView) {
        let contentSize = scrollView.contentSize
        textView.minSize = NSSize(width: 0, height: contentSize.height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(
            width: contentSize.width,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = true
    }

    private func toolbarButton(_ title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.contentTintColor = .labelColor
        return button
    }

    private func iconButton(_ title: String, action: Selector, font: NSFont) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .texturedRounded
        button.isBordered = false
        button.font = font
        button.contentTintColor = .secondaryLabelColor
        button.setButtonType(.momentaryPushIn)
        button.widthAnchor.constraint(greaterThanOrEqualToConstant: 18).isActive = true
        return button
    }

    private func primaryButton(_ title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.contentTintColor = .white
        button.font = .systemFont(ofSize: 12, weight: .semibold)
        return button
    }

    private static func makeFooterLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .secondaryLabelColor
        return label
    }

    private static func italicFont(size: CGFloat) -> NSFont {
        let baseFont = NSFont.systemFont(ofSize: size)
        return NSFontManager.shared.convert(baseFont, toHaveTrait: .italicFontMask)
    }

    private func separatorLabel() -> NSTextField {
        let label = NSTextField(labelWithString: "·")
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .tertiaryLabelColor
        return label
    }

    private func updateFooter() {
        let text = textView.string
        characterLabel.stringValue = "\(text.count) 个字符"
        wordLabel.stringValue = "\(wordCount(in: text)) 单词"
        lineLabel.stringValue = "\(max(1, text.components(separatedBy: .newlines).count)) 行"
    }

    private func wordCount(in text: String) -> Int {
        let words = text.split { character in
            character.isWhitespace || character.isNewline
        }
        return words.count
    }

    private func applyToSelection(_ transform: (NSMutableAttributedString, NSRange) -> Void) {
        let range = textView.selectedRange()
        let targetRange = range.length > 0 ? range : NSRange(location: 0, length: textView.attributedString().length)
        guard targetRange.length > 0 else {
            return
        }

        let mutableText = NSMutableAttributedString(attributedString: textView.attributedString())
        transform(mutableText, targetRange)
        applyBlackColor(to: mutableText)
        textView.textStorage?.setAttributedString(mutableText)
        enforceBlackText()
        textView.setSelectedRange(range)
        updateFooter()
    }

    @objc private func toggleBold() {
        applyToSelection { text, range in
            text.enumerateAttribute(.font, in: range) { value, subrange, _ in
                let font = value as? NSFont ?? .systemFont(ofSize: self.fontSize)
                let traits = NSFontManager.shared.traits(of: font)
                let convertedFont = traits.contains(.boldFontMask)
                    ? NSFontManager.shared.convert(font, toNotHaveTrait: .boldFontMask)
                    : NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
                text.addAttribute(.font, value: convertedFont, range: subrange)
            }
        }
    }

    @objc private func toggleItalic() {
        applyToSelection { text, range in
            text.enumerateAttribute(.font, in: range) { value, subrange, _ in
                let font = value as? NSFont ?? .systemFont(ofSize: self.fontSize)
                let traits = NSFontManager.shared.traits(of: font)
                let convertedFont = traits.contains(.italicFontMask)
                    ? NSFontManager.shared.convert(font, toNotHaveTrait: .italicFontMask)
                    : NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
                text.addAttribute(.font, value: convertedFont, range: subrange)
            }
        }
    }

    @objc private func toggleUnderline() {
        applyToSelection { text, range in
            text.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        }
    }

    @objc private func toggleStrikethrough() {
        applyToSelection { text, range in
            text.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        }
    }

    @objc private func increaseFontSize() {
        changeFontSize(by: 2)
    }

    @objc private func decreaseFontSize() {
        changeFontSize(by: -2)
    }

    private func changeFontSize(by delta: CGFloat) {
        fontSize = min(48, max(10, fontSize + delta))
        applyToSelection { text, range in
            text.enumerateAttribute(.font, in: range) { value, subrange, _ in
                let font = value as? NSFont ?? .systemFont(ofSize: self.fontSize)
                let convertedFont = NSFontManager.shared.convert(font, toSize: self.fontSize)
                text.addAttribute(.font, value: convertedFont, range: subrange)
            }
        }
        textView.typingAttributes[.font] = NSFont.systemFont(ofSize: fontSize)
        enforceBlackText()
    }

    private func enforceBlackText() {
        textView.textColor = .black
        textView.insertionPointColor = .systemBlue
        textView.typingAttributes = normalizedTypingAttributes()

        guard let textStorage = textView.textStorage,
              textStorage.length > 0 else {
            return
        }

        textStorage.addAttribute(
            .foregroundColor,
            value: NSColor.black,
            range: NSRange(location: 0, length: textStorage.length)
        )
    }

    private func normalizedTypingAttributes() -> [NSAttributedString.Key: Any] {
        var attributes = textView.typingAttributes
        attributes[.foregroundColor] = NSColor.black
        if attributes[.font] == nil {
            attributes[.font] = NSFont.systemFont(ofSize: fontSize)
        }
        return attributes
    }

    private func applyBlackColor(to text: NSMutableAttributedString) {
        guard text.length > 0 else {
            return
        }

        text.addAttribute(
            .foregroundColor,
            value: NSColor.black,
            range: NSRange(location: 0, length: text.length)
        )
    }

    @objc private func cancelAction() {
        panel.close()
    }

    @objc private func createAction() {
        let plainText = textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !plainText.isEmpty else {
            NSSound.beep()
            return
        }

        let range = NSRange(location: 0, length: textView.attributedString().length)
        guard let data = try? textView.attributedString().data(
            from: range,
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        ) else {
            return
        }

        onCreate(data, plainText)
        panel.close()
    }
}

private final class RichTextEditorPanel: NSPanel {
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        true
    }
}

private final class DraggableToolbarView: NSStackView {
    private weak var panel: NSPanel?

    init(panel: NSPanel) {
        self.panel = panel
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func mouseDown(with event: NSEvent) {
        panel?.performDrag(with: event)
    }
}
