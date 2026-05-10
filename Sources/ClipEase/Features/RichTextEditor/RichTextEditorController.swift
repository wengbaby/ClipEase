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

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 590),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "新建文本"
        panel.titleVisibility = .hidden
        panel.isReleasedWhenClosed = false
        panel.center()

        let textView = NSTextView()
        textView.isRichText = true
        textView.allowsUndo = true
        textView.importsGraphics = false
        textView.font = .systemFont(ofSize: 20)
        textView.textColor = .labelColor
        textView.insertionPointColor = .systemBlue
        textView.textContainerInset = NSSize(width: 18, height: 16)
        textView.backgroundColor = .white
        textView.typingAttributes = [
            .font: NSFont.systemFont(ofSize: 20),
            .foregroundColor: NSColor.labelColor
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
        panel.makeFirstResponder(textView)
    }

    func textDidChange(_ notification: Notification) {
        updateFooter()
    }

    private func makeContentView() -> NSView {
        let rootView = NSView()
        rootView.wantsLayer = true
        rootView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let toolbar = NSStackView()
        toolbar.orientation = .horizontal
        toolbar.alignment = .centerY
        toolbar.distribution = .gravityAreas
        toolbar.spacing = 18
        toolbar.translatesAutoresizingMaskIntoConstraints = false

        let cancelButton = toolbarButton("取消", action: #selector(cancelAction))
        cancelButton.font = .systemFont(ofSize: 20, weight: .medium)

        let styleGroup = NSStackView()
        styleGroup.orientation = .horizontal
        styleGroup.spacing = 26
        styleGroup.alignment = .centerY
        styleGroup.addArrangedSubview(iconButton("B", action: #selector(toggleBold), font: .boldSystemFont(ofSize: 18)))
        styleGroup.addArrangedSubview(iconButton("I", action: #selector(toggleItalic), font: Self.italicFont(size: 18)))
        styleGroup.addArrangedSubview(iconButton("U", action: #selector(toggleUnderline), font: .systemFont(ofSize: 18)))
        styleGroup.addArrangedSubview(iconButton("S", action: #selector(toggleStrikethrough), font: .systemFont(ofSize: 18)))
        styleGroup.addArrangedSubview(iconButton("A-", action: #selector(decreaseFontSize), font: .systemFont(ofSize: 16, weight: .semibold)))
        styleGroup.addArrangedSubview(iconButton("A+", action: #selector(increaseFontSize), font: .systemFont(ofSize: 16, weight: .semibold)))

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
        scrollView.documentView = textView

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
            toolbar.topAnchor.constraint(equalTo: rootView.topAnchor, constant: 12),
            toolbar.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: 14),
            toolbar.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -14),
            toolbar.heightAnchor.constraint(equalToConstant: 42),

            scrollView.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 10),
            scrollView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: 8),
            scrollView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -8),
            scrollView.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -14),

            footer.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: 20),
            footer.trailingAnchor.constraint(lessThanOrEqualTo: rootView.trailingAnchor, constant: -20),
            footer.bottomAnchor.constraint(equalTo: rootView.bottomAnchor, constant: -16),
            footer.heightAnchor.constraint(equalToConstant: 24)
        ])

        updateFooter()
        return rootView
    }

    private func toolbarButton(_ title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        button.controlSize = .large
        return button
    }

    private func iconButton(_ title: String, action: Selector, font: NSFont) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .texturedRounded
        button.isBordered = false
        button.font = font
        button.contentTintColor = .secondaryLabelColor
        button.setButtonType(.momentaryPushIn)
        return button
    }

    private func primaryButton(_ title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        button.controlSize = .large
        button.keyEquivalent = "\r"
        button.contentTintColor = .white
        return button
    }

    private static func makeFooterLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 17, weight: .medium)
        label.textColor = .secondaryLabelColor
        return label
    }

    private static func italicFont(size: CGFloat) -> NSFont {
        let baseFont = NSFont.systemFont(ofSize: size)
        return NSFontManager.shared.convert(baseFont, toHaveTrait: .italicFontMask)
    }

    private func separatorLabel() -> NSTextField {
        let label = NSTextField(labelWithString: "·")
        label.font = .systemFont(ofSize: 17, weight: .medium)
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
        textView.textStorage?.setAttributedString(mutableText)
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
