import AppKit

@MainActor
final class RichTextEditorController: NSObject, NSTextViewDelegate {
    enum Mode {
        case create
        case edit(ClipboardItem)

        var title: String {
            switch self {
            case .create:
                L("新建文本")
            case .edit(let item):
                switch item.type {
                case .text:
                    L("编辑文本")
                case .link:
                    L("编辑链接")
                case .color:
                    L("编辑颜色")
                case .image:
                    L("编辑")
                case .file:
                    L("编辑")
                }
            }
        }

        var actionTitle: String {
            switch self {
            case .create:
                L("创建")
            case .edit:
                L("保存")
            }
        }

        var plainTextActionTitle: String {
            switch self {
            case .create:
                L("创建纯文本")
            case .edit:
                L("保存纯文本")
            }
        }
    }

    private let groups: [ClipboardGroup]
    private var selectedGroupID: ClipboardGroup.ID?
    private let onCreate: (Data, String, ClipboardGroup.ID?) async throws -> ClipboardItem?
    private let onSaveEdit: ((ClipboardItem.ID, String) -> ClipboardItem?)?
    private let mode: Mode
    private let panel: RichTextEditorWindow
    private let textView: NSTextView
    private let characterLabel: NSTextField
    private let wordLabel: NSTextField
    private let lineLabel: NSTextField
    private let errorLabel: NSTextField
    private let hexColorLabel: NSTextField
    private let rgbColorLabel: NSTextField
    private let colorWell: NSColorWell
    private let groupPopUpButton: NSPopUpButton
    private let richTextDataProvider: ((ClipboardItem) -> Data?)?
    private let onSaveRichTextEdit: ((ClipboardItem.ID, Data, String) async throws -> ClipboardItem?)?
    private let richTextSerializer: (NSAttributedString) throws -> Data
    private var actionButton: NSButton?
    private var canSave = true
    private var boldButton: NSButton?
    private var italicButton: NSButton?
    private var underlineButton: NSButton?
    private var strikethroughButton: NSButton?
    private var fontSizePopUpButton: NSPopUpButton?
    private var isClosingAfterSaveOrDiscard = false
    private var baselinePlainText = ""
    private var baselineRTFData: Data?
    private var lastKnownSelectedRange = NSRange(location: 0, length: 0)
    private var isBoldActive = false
    private var isItalicActive = false
    private var isUnderlineActive = false
    private var isStrikethroughActive = false
    private var fontSize: CGFloat = 16
    private var closeAfterSaveCount = 0
    private var discardCount = 0
    private var didNotifyClose = false
    private var saveTask: Task<Void, Never>?
    private(set) var lastSavedItemForTesting: ClipboardItem?
    var onClose: (() -> Void)?

    init(
        groups: [ClipboardGroup] = [],
        selectedGroupID: ClipboardGroup.ID? = nil,
        mode: Mode = .create,
        onCreate: @escaping (Data, String, ClipboardGroup.ID?) async throws -> ClipboardItem? = { _, _, _ in nil },
        onSaveEdit: ((ClipboardItem.ID, String) -> ClipboardItem?)? = nil,
        richTextDataProvider: ((ClipboardItem) -> Data?)? = nil,
        onSaveRichTextEdit: ((ClipboardItem.ID, Data, String) async throws -> ClipboardItem?)? = nil,
        richTextSerializer: ((NSAttributedString) throws -> Data)? = nil
    ) {
        self.groups = groups
        self.selectedGroupID = groups.contains(where: { $0.id == selectedGroupID }) ? selectedGroupID : nil
        self.onCreate = onCreate
        self.onSaveEdit = onSaveEdit
        self.richTextDataProvider = richTextDataProvider
        self.onSaveRichTextEdit = onSaveRichTextEdit
        self.richTextSerializer = richTextSerializer ?? { attributedString in
            try attributedString.data(
                from: NSRange(location: 0, length: attributedString.length),
                documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
            )
        }
        self.mode = mode

        let panel = RichTextEditorWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 440),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = mode.title
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.managed, .moveToActiveSpace]
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.minSize = NSSize(width: 600, height: 360)
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
        self.characterLabel = Self.makeFooterLabel(L("0 个字符"))
        self.wordLabel = Self.makeFooterLabel(L("0 单词"))
        self.lineLabel = Self.makeFooterLabel(L("0 行"))
        self.errorLabel = Self.makeFooterLabel("")
        self.hexColorLabel = Self.makeFooterLabel("HEX --")
        self.rgbColorLabel = Self.makeFooterLabel("RGB --")
        self.colorWell = NSColorWell(frame: NSRect(x: 0, y: 0, width: 52, height: 26))
        self.groupPopUpButton = NSPopUpButton(frame: .zero, pullsDown: false)
        super.init()

        panel.editorTextView = textView
        panel.onEscape = { [weak self] in
            self?.requestCloseEditor()
        }
        textView.delegate = self
        panel.delegate = self
        panel.contentView = makeContentView()
        loadInitialContent()
        panel.onCommandW = { [weak self] in
            self?.requestCloseEditor()
        }
        panel.onCommandS = { [weak self] in
            self?.createAction()
        }
        panel.onCommandB = { [weak self] in
            self?.toggleBold()
        }
        panel.onCommandI = { [weak self] in
            self?.toggleItalic()
        }
        panel.onCommandU = { [weak self] in
            self?.toggleUnderline()
        }
    }

    func show() {
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        enforceDefaultTypingAttributes()
        panel.makeFirstResponder(textView)
    }

    func setDraftForTesting(_ draft: String) {
        textView.string = draft
        updateFooter()
    }

    func saveForTesting() async {
        createAction()
        await saveTask?.value
    }

    func savePlainTextForTesting() async {
        createPlainTextAction()
        await saveTask?.value
    }

    var draftForTesting: String {
        textView.string
    }

    var errorMessageForTesting: String? {
        errorLabel.stringValue.isEmpty ? nil : errorLabel.stringValue
    }

    var didCloseAfterSaveForTesting: Bool {
        isClosingAfterSaveOrDiscard
    }

    var closeCountForTesting: Int {
        closeAfterSaveCount
    }

    var isSavingForTesting: Bool {
        saveTask != nil
    }

    var discardCountForTesting: Int {
        discardCount
    }

    func requestCloseForTesting() {
        requestCloseEditor()
    }

    func requestDiscardForTesting() {
        discardAndClose()
    }

    func requestCommandWForTesting() {
        requestCloseEditor()
    }

    func textDidChange(_ notification: Notification) {
        enforceDefaultTypingAttributes()
        updateColorLabels(from: textView.string)
        updateFooter()
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        let selectedRange = textView.selectedRange()
        if selectedRange.length > 0 {
            lastKnownSelectedRange = selectedRange
        }
        syncStyleStateFromSelection()
    }

    func textView(
        _ textView: NSTextView,
        shouldChangeTextIn affectedCharRange: NSRange,
        replacementString: String?
    ) -> Bool {
        textView.typingAttributes = normalizedTypingAttributes()
        return true
    }

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard commandSelector == #selector(NSResponder.cancelOperation(_:)) else {
            return false
        }

        panel.close()
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

        let titleLabel = NSTextField(labelWithString: mode.title)
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 118).isActive = true

        let styleGroup = NSStackView()
        styleGroup.orientation = .horizontal
        styleGroup.spacing = 20
        styleGroup.alignment = .centerY
        let boldButton = iconButton("B", action: #selector(toggleBold), font: .boldSystemFont(ofSize: 12))
        let italicButton = iconButton("I", action: #selector(toggleItalic), font: Self.italicFont(size: 12))
        let underlineButton = iconButton("U", action: #selector(toggleUnderline), font: .systemFont(ofSize: 12))
        let strikethroughButton = iconButton("S", action: #selector(toggleStrikethrough), font: .systemFont(ofSize: 12))
        self.boldButton = boldButton
        self.italicButton = italicButton
        self.underlineButton = underlineButton
        self.strikethroughButton = strikethroughButton
        let fontSizePopUpButton = NSPopUpButton(frame: .zero, pullsDown: false)
        self.fontSizePopUpButton = fontSizePopUpButton
        configureFontSizePopUpButton(fontSizePopUpButton)
        styleGroup.addArrangedSubview(boldButton)
        styleGroup.addArrangedSubview(italicButton)
        styleGroup.addArrangedSubview(underlineButton)
        styleGroup.addArrangedSubview(strikethroughButton)
        styleGroup.addArrangedSubview(fontSizePopUpButton)
        styleGroup.addArrangedSubview(toolbarButton(L("清除格式"), action: #selector(clearFormattingAction)))

        let createButton = primaryButton(mode.actionTitle, action: #selector(createAction))
        actionButton = createButton
        let plainTextButton = toolbarButton(mode.plainTextActionTitle, action: #selector(createPlainTextAction))
        let cancelButton = toolbarButton(L("取消"), action: #selector(cancelAction))
        cancelButton.font = .systemFont(ofSize: 12, weight: .medium)
        configureGroupPopUpButton()

        toolbar.addView(titleLabel, in: .leading)
        toolbar.addView(styleGroup, in: .center)
        let trailingGroup = NSStackView()
        trailingGroup.orientation = .horizontal
        trailingGroup.spacing = 8
        trailingGroup.alignment = .centerY
        if case .create = mode {
            trailingGroup.addArrangedSubview(groupPopUpButton)
        }
        trailingGroup.addArrangedSubview(createButton)
        trailingGroup.addArrangedSubview(plainTextButton)
        trailingGroup.addArrangedSubview(cancelButton)
        toolbar.addView(trailingGroup, in: .trailing)

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

        let colorEditorView = makeColorEditorView()

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
        footer.addArrangedSubview(separatorLabel())
        errorLabel.textColor = .systemRed
        errorLabel.isHidden = true
        footer.addArrangedSubview(errorLabel)

        rootView.addSubview(toolbar)
        if let colorEditorView {
            rootView.addSubview(colorEditorView)
        }
        rootView.addSubview(scrollView)
        rootView.addSubview(footer)

        let scrollTopAnchor = colorEditorView?.bottomAnchor ?? toolbar.bottomAnchor
        let scrollTopConstant: CGFloat = colorEditorView == nil ? 6 : 8

        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: rootView.topAnchor, constant: 6),
            toolbar.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: 78),
            toolbar.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -8),
            toolbar.heightAnchor.constraint(equalToConstant: 26),

            scrollView.topAnchor.constraint(equalTo: scrollTopAnchor, constant: scrollTopConstant),
            scrollView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: 4),
            scrollView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -4),
            scrollView.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -8),

            footer.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: 12),
            footer.trailingAnchor.constraint(lessThanOrEqualTo: rootView.trailingAnchor, constant: -12),
            footer.bottomAnchor.constraint(equalTo: rootView.bottomAnchor, constant: -8),
            footer.heightAnchor.constraint(equalToConstant: 20)
        ])

        if let colorEditorView {
            NSLayoutConstraint.activate([
                colorEditorView.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 8),
                colorEditorView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: 12),
                colorEditorView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -12),
                colorEditorView.heightAnchor.constraint(equalToConstant: 32)
            ])
        }

        updateFooter()
        return rootView
    }

    private func makeColorEditorView() -> NSView? {
        guard case .edit(let item) = mode,
              item.type == .color else {
            return nil
        }

        let stackView = NSStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.orientation = .horizontal
        stackView.spacing = 10
        stackView.alignment = .centerY
        colorWell.target = self
        colorWell.action = #selector(colorWellChanged)
        if let color = nsColor(fromHex: item.text) {
            colorWell.color = color
        }
        stackView.addArrangedSubview(colorWell)
        stackView.addArrangedSubview(hexColorLabel)
        stackView.addArrangedSubview(separatorLabel())
        stackView.addArrangedSubview(rgbColorLabel)
        updateColorLabels(from: textView.string.isEmpty ? item.text : textView.string)
        return stackView
    }

    private func loadInitialContent() {
        guard case .edit(let item) = mode else {
            return
        }

        if let richTextFileName = item.richTextFileName {
            guard let data = richTextDataProvider?(item),
                  let attributedString = try? NSAttributedString(
                    data: data,
                    options: [.documentType: NSAttributedString.DocumentType.rtf],
                    documentAttributes: nil
                  ) else {
                textView.string = item.text
                canSave = false
                actionButton?.isEnabled = false
                showValidationError("无法读取富文本文件：\(richTextFileName)")
                return
            }

            textView.textStorage?.setAttributedString(attributedString)
        } else {
            textView.string = item.text
        }

        textView.setSelectedRange(NSRange(location: 0, length: textView.attributedString().length))
        syncStyleStateFromSelection()
        enforceDefaultTypingAttributes()
        captureBaselineContent()
        updateFooter()
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
        button.refusesFirstResponder = true
        return button
    }

    private func iconButton(_ title: String, action: Selector, font: NSFont) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .texturedRounded
        button.isBordered = false
        button.font = font
        button.contentTintColor = .secondaryLabelColor
        button.setButtonType(.momentaryPushIn)
        button.refusesFirstResponder = true
        button.wantsLayer = true
        button.layer?.cornerRadius = 7
        button.widthAnchor.constraint(greaterThanOrEqualToConstant: 18).isActive = true
        button.heightAnchor.constraint(equalToConstant: 22).isActive = true
        return button
    }

    private func primaryButton(_ title: String, action: Selector) -> NSButton {
        let button = BlueActionButton(title: title, target: self, action: action)
        button.font = .systemFont(ofSize: 12, weight: .semibold)
        button.widthAnchor.constraint(greaterThanOrEqualToConstant: 46).isActive = true
        button.heightAnchor.constraint(equalToConstant: 24).isActive = true
        return button
    }

    private func configureGroupPopUpButton() {
        groupPopUpButton.target = self
        groupPopUpButton.action = #selector(selectGroupAction)
        groupPopUpButton.controlSize = .small
        groupPopUpButton.font = .systemFont(ofSize: 12, weight: .medium)
        groupPopUpButton.addItem(withTitle: L("全部剪切板"))
        groupPopUpButton.lastItem?.representedObject = nil

        groups.forEach { group in
            groupPopUpButton.addItem(withTitle: group.name)
            groupPopUpButton.lastItem?.representedObject = group.id.uuidString
        }

        if let selectedGroupID,
           let item = groupPopUpButton.itemArray.first(where: { ($0.representedObject as? String) == selectedGroupID.uuidString }) {
            groupPopUpButton.select(item)
        }
        groupPopUpButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 118).isActive = true
    }

    private func configureFontSizePopUpButton(_ popUpButton: NSPopUpButton) {
        popUpButton.target = self
        popUpButton.action = #selector(selectFontSizeAction)
        popUpButton.controlSize = .small
        popUpButton.font = .systemFont(ofSize: 12, weight: .medium)
        [12, 14, 16, 18, 20, 24, 28, 32, 40, 48].forEach { size in
            popUpButton.addItem(withTitle: "\(size)")
            popUpButton.lastItem?.representedObject = CGFloat(size)
        }
        popUpButton.selectItem(withTitle: "\(Int(fontSize))")
        popUpButton.widthAnchor.constraint(equalToConstant: 58).isActive = true
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
        characterLabel.stringValue = L("\(text.count) 个字符")
        wordLabel.stringValue = L("\(wordCount(in: text)) 单词")
        lineLabel.stringValue = L("\(max(1, text.components(separatedBy: .newlines).count)) 行")
        errorLabel.isHidden = errorLabel.stringValue.isEmpty
    }

    @objc private func colorWellChanged() {
        let hex = hexString(from: colorWell.color)
        textView.string = hex
        textView.setSelectedRange(NSRange(location: textView.string.count, length: 0))
        enforceDefaultTypingAttributes()
        updateColorLabels(from: hex)
        updateFooter()
        panel.makeFirstResponder(textView)
    }

    private func captureBaselineContent() {
        baselinePlainText = textView.string
        baselineRTFData = currentRTFData()
    }

    private func currentRTFData() -> Data? {
        let range = NSRange(location: 0, length: textView.attributedString().length)
        return try? textView.attributedString().data(
            from: range,
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
    }

    private var hasUnsavedChanges: Bool {
        textView.string != baselinePlainText || currentRTFData() != baselineRTFData
    }

    private func updateColorLabels(from text: String) {
        guard case .edit(let item) = mode,
              item.type == .color else {
            return
        }

        guard let hex = ColorParser.hexColor(from: text),
              let color = nsColor(fromHex: hex) else {
            hexColorLabel.stringValue = "HEX --"
            rgbColorLabel.stringValue = "RGB --"
            return
        }

        if hexString(from: colorWell.color) != hex {
            colorWell.color = color
        }
        hexColorLabel.stringValue = "HEX \(hex)"
        rgbColorLabel.stringValue = "RGB \(rgbString(from: color))"
    }

    private func nsColor(fromHex hex: String) -> NSColor? {
        let normalized = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard normalized.count == 6,
              let value = Int(normalized, radix: 16) else {
            return nil
        }

        return NSColor(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255.0,
            green: CGFloat((value >> 8) & 0xFF) / 255.0,
            blue: CGFloat(value & 0xFF) / 255.0,
            alpha: 1.0
        )
    }

    private func hexString(from color: NSColor) -> String {
        let rgbColor = color.usingColorSpace(.sRGB) ?? color
        let red = Int(round(rgbColor.redComponent * 255))
        let green = Int(round(rgbColor.greenComponent * 255))
        let blue = Int(round(rgbColor.blueComponent * 255))
        return String(format: "#%02X%02X%02X", red, green, blue)
    }

    private func rgbString(from color: NSColor) -> String {
        let rgbColor = color.usingColorSpace(.sRGB) ?? color
        let red = Int(round(rgbColor.redComponent * 255))
        let green = Int(round(rgbColor.greenComponent * 255))
        let blue = Int(round(rgbColor.blueComponent * 255))
        return "\(red), \(green), \(blue)"
    }

    private func wordCount(in text: String) -> Int {
        let words = text.split { character in
            character.isWhitespace || character.isNewline
        }
        return words.count
    }

    private func applyToSelection(_ transform: (NSMutableAttributedString, NSRange) -> Void) {
        restoreLastSelectionIfNeeded()
        let range = textView.selectedRange()
        guard range.length > 0 else {
            updateTypingAttributes()
            return
        }

        let mutableText = NSMutableAttributedString(attributedString: textView.attributedString())
        transform(mutableText, range)
        applyDefaultColorIfMissing(to: mutableText, range: range)
        textView.textStorage?.setAttributedString(mutableText)
        enforceDefaultTypingAttributes()
        textView.setSelectedRange(range)
        updateFooter()
    }

    private func restoreLastSelectionIfNeeded() {
        guard lastKnownSelectedRange.length > 0,
              textView.selectedRange().length == 0,
              NSMaxRange(lastKnownSelectedRange) <= textView.attributedString().length else {
            return
        }

        textView.setSelectedRange(lastKnownSelectedRange)
    }

    @objc private func toggleBold() {
        isBoldActive.toggle()
        applyToSelection { text, range in
            text.enumerateAttribute(.font, in: range) { value, subrange, _ in
                let font = value as? NSFont ?? .systemFont(ofSize: self.fontSize)
                let convertedFont = self.font(font, setting: .bold, enabled: self.isBoldActive)
                text.addAttribute(.font, value: convertedFont, range: subrange)
            }
        }
        updateStyleButtons()
    }

    @objc private func toggleItalic() {
        isItalicActive.toggle()
        applyToSelection { text, range in
            text.enumerateAttribute(.font, in: range) { value, subrange, _ in
                let font = value as? NSFont ?? .systemFont(ofSize: self.fontSize)
                let convertedFont = self.font(font, setting: .italic, enabled: self.isItalicActive)
                text.addAttribute(.font, value: convertedFont, range: subrange)
            }
        }
        updateStyleButtons()
    }

    @objc private func toggleUnderline() {
        isUnderlineActive.toggle()
        applyToSelection { text, range in
            if self.isUnderlineActive {
                text.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            } else {
                text.removeAttribute(.underlineStyle, range: range)
            }
        }
        updateStyleButtons()
    }

    @objc private func toggleStrikethrough() {
        isStrikethroughActive.toggle()
        applyToSelection { text, range in
            if self.isStrikethroughActive {
                text.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            } else {
                text.removeAttribute(.strikethroughStyle, range: range)
            }
        }
        updateStyleButtons()
    }

    @objc private func increaseFontSize() {
        changeFontSize(by: 2)
    }

    @objc private func decreaseFontSize() {
        changeFontSize(by: -2)
    }

    @objc private func selectFontSizeAction() {
        guard let size = fontSizePopUpButton?.selectedItem?.representedObject as? CGFloat else {
            return
        }

        let delta = size - fontSize
        guard abs(delta) > 0.1 else {
            return
        }

        changeFontSize(by: delta)
    }

    @objc private func clearFormattingAction() {
        let selectedRange = textView.selectedRange()
        let targetRange = selectedRange.length > 0
            ? selectedRange
            : NSRange(location: 0, length: textView.attributedString().length)
        guard targetRange.length > 0 else {
            return
        }

        let source = textView.attributedString().attributedSubstring(from: targetRange).string
        let plain = NSAttributedString(
            string: source,
            attributes: [
                .font: NSFont.systemFont(ofSize: fontSize),
                .foregroundColor: NSColor.black
            ]
        )
        textView.textStorage?.replaceCharacters(in: targetRange, with: plain)
        textView.setSelectedRange(NSRange(location: targetRange.location, length: plain.length))
        syncStyleStateFromSelection()
        enforceDefaultTypingAttributes()
        updateFooter()
    }

    private func changeFontSize(by delta: CGFloat) {
        fontSize = min(48, max(10, fontSize + delta))
        fontSizePopUpButton?.selectItem(withTitle: "\(Int(fontSize.rounded()))")
        applyToSelection { text, range in
            text.enumerateAttribute(.font, in: range) { value, subrange, _ in
                let font = value as? NSFont ?? .systemFont(ofSize: self.fontSize)
                let convertedFont = self.font(font, withPointSize: self.fontSize)
                text.addAttribute(.font, value: convertedFont, range: subrange)
            }
        }
        updateTypingAttributes()
    }

    private func enforceDefaultTypingAttributes() {
        textView.textColor = .black
        textView.insertionPointColor = .systemBlue
        textView.typingAttributes = normalizedTypingAttributes()
    }

    private func normalizedTypingAttributes() -> [NSAttributedString.Key: Any] {
        var attributes = textView.typingAttributes
        attributes[.foregroundColor] = NSColor.black
        attributes[.font] = typingFont()
        if isUnderlineActive {
            attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
        } else {
            attributes.removeValue(forKey: .underlineStyle)
        }
        if isStrikethroughActive {
            attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        } else {
            attributes.removeValue(forKey: .strikethroughStyle)
        }
        return attributes
    }

    private func updateTypingAttributes() {
        textView.typingAttributes = normalizedTypingAttributes()
        panel.makeFirstResponder(textView)
    }

    private func typingFont() -> NSFont {
        var font = NSFont.systemFont(ofSize: fontSize)
        if isBoldActive {
            font = self.font(font, setting: .bold, enabled: true)
        }
        if isItalicActive {
            font = self.font(font, setting: .italic, enabled: true)
        }
        return font
    }

    private func font(
        _ font: NSFont,
        setting trait: NSFontDescriptor.SymbolicTraits,
        enabled: Bool
    ) -> NSFont {
        var symbolicTraits = font.fontDescriptor.symbolicTraits
        if enabled {
            symbolicTraits.insert(trait)
        } else {
            symbolicTraits.remove(trait)
        }

        let descriptor = font.fontDescriptor.withSymbolicTraits(symbolicTraits)
        if let convertedFont = NSFont(descriptor: descriptor, size: font.pointSize),
           self.font(convertedFont, has: trait) == enabled {
            return convertedFont
        }

        let managerTrait: NSFontTraitMask = trait == .bold ? .boldFontMask : .italicFontMask
        let managerFont = enabled
            ? NSFontManager.shared.convert(font, toHaveTrait: managerTrait)
            : NSFontManager.shared.convert(font, toNotHaveTrait: managerTrait)
        if self.font(managerFont, has: trait) == enabled {
            return managerFont
        }

        return fallbackSystemFont(pointSize: font.pointSize, symbolicTraits: symbolicTraits)
    }

    private func font(_ font: NSFont, has trait: NSFontDescriptor.SymbolicTraits) -> Bool {
        let traits = NSFontManager.shared.traits(of: font)
        if trait == .bold {
            return traits.contains(.boldFontMask) || font.fontDescriptor.symbolicTraits.contains(.bold)
        }

        return traits.contains(.italicFontMask) || font.fontDescriptor.symbolicTraits.contains(.italic)
    }

    private func fallbackSystemFont(
        pointSize: CGFloat,
        symbolicTraits: NSFontDescriptor.SymbolicTraits
    ) -> NSFont {
        let weight: NSFont.Weight = symbolicTraits.contains(.bold) ? .bold : .regular
        var font = NSFont.systemFont(ofSize: pointSize, weight: weight)
        if symbolicTraits.contains(.italic) {
            font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
        }

        return font
    }

    private func font(_ font: NSFont, withPointSize pointSize: CGFloat) -> NSFont {
        if let resizedFont = NSFont(descriptor: font.fontDescriptor, size: pointSize) {
            return resizedFont
        }

        return fallbackSystemFont(pointSize: pointSize, symbolicTraits: font.fontDescriptor.symbolicTraits)
    }

    private func updateStyleButtons() {
        updateToggleButton(boldButton, isActive: isBoldActive)
        updateToggleButton(italicButton, isActive: isItalicActive)
        updateToggleButton(underlineButton, isActive: isUnderlineActive)
        updateToggleButton(strikethroughButton, isActive: isStrikethroughActive)
        updateTypingAttributes()
    }

    private func refreshStyleButtonsOnly() {
        updateToggleButton(boldButton, isActive: isBoldActive)
        updateToggleButton(italicButton, isActive: isItalicActive)
        updateToggleButton(underlineButton, isActive: isUnderlineActive)
        updateToggleButton(strikethroughButton, isActive: isStrikethroughActive)
    }

    private func syncStyleStateFromSelection() {
        let attributes = representativeTypingAttributes()
        let font = attributes[.font] as? NSFont ?? textView.font ?? .systemFont(ofSize: fontSize)
        let traits = NSFontManager.shared.traits(of: font)
        let symbolicTraits = font.fontDescriptor.symbolicTraits

        isBoldActive = traits.contains(.boldFontMask) || symbolicTraits.contains(.bold)
        isItalicActive = traits.contains(.italicFontMask) || symbolicTraits.contains(.italic)
        isUnderlineActive = (attributes[.underlineStyle] as? Int ?? 0) != 0
        isStrikethroughActive = (attributes[.strikethroughStyle] as? Int ?? 0) != 0
        fontSize = font.pointSize
        fontSizePopUpButton?.selectItem(withTitle: "\(Int(fontSize.rounded()))")
        refreshStyleButtonsOnly()
    }

    private func representativeTypingAttributes() -> [NSAttributedString.Key: Any] {
        let selectedRange = textView.selectedRange()
        let storage = textView.textStorage
        guard let storage,
              storage.length > 0 else {
            return textView.typingAttributes
        }

        let location: Int
        if selectedRange.length > 0 {
            location = selectedRange.location
        } else {
            location = max(0, selectedRange.location - 1)
        }

        return storage.attributes(
            at: min(location, storage.length - 1),
            effectiveRange: nil
        )
    }

    private func updateToggleButton(_ button: NSButton?, isActive: Bool) {
        button?.contentTintColor = isActive ? .controlAccentColor : .secondaryLabelColor
        button?.layer?.backgroundColor = isActive
            ? NSColor.controlAccentColor.withAlphaComponent(0.18).cgColor
            : NSColor.clear.cgColor
    }

    private func applyDefaultColorIfMissing(to text: NSMutableAttributedString, range: NSRange) {
        guard text.length > 0, range.length > 0 else {
            return
        }

        text.enumerateAttribute(.foregroundColor, in: range) { value, subrange, _ in
            guard value == nil else {
                return
            }

            text.addAttribute(.foregroundColor, value: NSColor.black, range: subrange)
        }
    }

    @objc private func cancelAction() {
        requestCloseEditor()
    }

    @objc private func selectGroupAction() {
        guard let uuidString = groupPopUpButton.selectedItem?.representedObject as? String,
              let id = UUID(uuidString: uuidString) else {
            selectedGroupID = nil
            return
        }

        selectedGroupID = id
    }

    @objc private func createAction() {
        guard saveTask == nil else {
            return
        }
        let plainText = textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !plainText.isEmpty else {
            showValidationError(L("内容不能为空"))
            return
        }

        if case .edit(let item) = mode {
            commitEdit(item: item, plainText: plainText)
            return
        }

        let data: Data
        do {
            data = try richTextSerializer(textView.attributedString())
        } catch {
            showValidationError("富文本保存失败：\(error.localizedDescription)")
            return
        }

        commitCreate(data: data, plainText: plainText)
    }

    @objc private func createPlainTextAction() {
        guard saveTask == nil else {
            return
        }
        let plainText = textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !plainText.isEmpty else {
            showValidationError(L("内容不能为空"))
            return
        }

        if case .edit(let item) = mode {
            guard onSaveEdit?(item.id, plainText) != nil else {
                showValidationError(L("保存失败"))
                return
            }
            closeAfterSave()
            return
        }

        let attributed = NSAttributedString(
            string: plainText,
            attributes: [
                .font: NSFont.systemFont(ofSize: 16),
                .foregroundColor: NSColor.black
            ]
        )
        let data: Data
        do {
            data = try richTextSerializer(attributed)
        } catch {
            showValidationError("纯文本保存失败：\(error.localizedDescription)")
            return
        }

        commitCreate(data: data, plainText: plainText)
    }

    private func commitCreate(data: Data, plainText: String) {
        beginSave { [weak self] in
            guard let self else {
                return
            }
            do {
                guard let savedItem = try await self.onCreate(
                    data,
                    plainText,
                    self.selectedGroupID
                ) else {
                    self.showValidationError(L("保存失败"))
                    return
                }
                guard !Task.isCancelled else {
                    return
                }
                self.lastSavedItemForTesting = savedItem
                self.closeAfterSave()
            } catch {
                guard !Task.isCancelled else {
                    return
                }
                self.showValidationError("保存失败：\(error.localizedDescription)")
            }
        }
    }

    private func beginSave(_ operation: @escaping @MainActor () async -> Void) {
        guard saveTask == nil else {
            return
        }
        actionButton?.isEnabled = false
        saveTask = Task { @MainActor [weak self] in
            await operation()
            self?.actionButton?.isEnabled = true
            self?.saveTask = nil
        }
    }

    private func commitEdit(item: ClipboardItem, plainText: String) {
        guard canSave else {
            showValidationError(L("无法读取原富文本，不能保存"))
            return
        }

        if item.type == .text {
            commitRichTextEdit(item: item, plainText: plainText)
            return
        }

        let normalizedText: String
        switch item.type {
        case .text:
            normalizedText = plainText
        case .link:
            guard URLParser.url(from: plainText) != nil else {
                showValidationError(L("请输入 http:// 或 https:// 链接"))
                return
            }
            normalizedText = plainText
        case .color:
            guard let hex = ColorParser.hexColor(from: plainText) else {
                showValidationError(L("请输入有效 HEX 颜色"))
                return
            }
            normalizedText = hex
        case .image:
            showValidationError(L("此类型暂不支持编辑"))
            return
        case .file:
            showValidationError(L("此类型暂不支持编辑"))
            return
        }

        guard onSaveEdit?(item.id, normalizedText) != nil else {
            showValidationError(L("保存失败"))
            return
        }

        closeAfterSave()
    }

    private func commitRichTextEdit(item: ClipboardItem, plainText: String) {
        let data: Data
        do {
            data = try richTextSerializer(textView.attributedString())
        } catch {
            showValidationError("富文本保存失败：\(error.localizedDescription)")
            return
        }

        beginSave { [weak self] in
            guard let self else {
                return
            }
            do {
                guard let savedItem = try await self.onSaveRichTextEdit?(
                    item.id,
                    data,
                    plainText
                ) else {
                    self.showValidationError(L("保存失败"))
                    return
                }
                guard !Task.isCancelled else {
                    return
                }
                self.lastSavedItemForTesting = savedItem
                self.closeAfterSave()
            } catch {
                guard !Task.isCancelled else {
                    return
                }
                self.showValidationError("保存失败：\(error.localizedDescription)")
            }
        }
    }

    private func closeAfterSave() {
        guard !isClosingAfterSaveOrDiscard else {
            return
        }
        closeAfterSaveCount += 1
        captureBaselineContent()
        isClosingAfterSaveOrDiscard = true
        closeColorPanelIfNeeded()
        panel.close()
    }

    private func requestCloseEditor() {
        guard saveTask == nil else {
            showValidationError(L("正在保存，请稍候"))
            return
        }
        guard hasUnsavedChanges else {
            isClosingAfterSaveOrDiscard = true
            panel.close()
            return
        }

        let alert = NSAlert()
        alert.messageText = L("保存更改？")
        alert.informativeText = L("关闭前是否保存当前富文本内容？")
        alert.addButton(withTitle: mode.actionTitle)
        alert.addButton(withTitle: L("不保存"))
        alert.addButton(withTitle: L("取消"))
        alert.beginSheetModal(for: panel) { [weak self] response in
            guard let self else {
                return
            }

            switch response {
            case .alertFirstButtonReturn:
                self.createAction()
            case .alertSecondButtonReturn:
                self.discardAndClose()
            default:
                break
            }
        }
    }

    private func discardAndClose() {
        guard saveTask == nil,
              !isClosingAfterSaveOrDiscard else {
            if saveTask != nil {
                showValidationError(L("正在保存，请稍候"))
            }
            return
        }
        discardCount += 1
        isClosingAfterSaveOrDiscard = true
        closeColorPanelIfNeeded()
        panel.close()
    }

    private func closeColorPanelIfNeeded() {
        guard case .edit(let item) = mode,
              item.type == .color else {
            return
        }

        colorWell.deactivate()
        NSColorPanel.shared.close()
    }

    private func showValidationError(_ message: String) {
        errorLabel.stringValue = message
        updateFooter()
        NSSound.beep()
        panel.makeFirstResponder(textView)
    }
}

extension RichTextEditorController: NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard saveTask == nil else {
            showValidationError(L("正在保存，请稍候"))
            return false
        }
        guard !isClosingAfterSaveOrDiscard,
              hasUnsavedChanges else {
            return true
        }

        requestCloseEditor()
        return false
    }

    func windowWillClose(_ notification: Notification) {
        guard !didNotifyClose else {
            return
        }
        didNotifyClose = true
        onClose?()
    }
}

private final class RichTextEditorWindow: NSWindow {
    var onCommandW: (() -> Void)?
    var onCommandS: (() -> Void)?
    var onCommandB: (() -> Void)?
    var onCommandI: (() -> Void)?
    var onCommandU: (() -> Void)?
    var onEscape: (() -> Void)?
    weak var editorTextView: NSTextView?

    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        true
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command),
              let key = event.charactersIgnoringModifiers?.lowercased() else {
            return super.performKeyEquivalent(with: event)
        }

        switch key {
        case "a":
            editorTextView?.selectAll(nil)
            return true
        case "c":
            editorTextView?.copy(nil)
            return true
        case "x":
            editorTextView?.cut(nil)
            return true
        case "v":
            editorTextView?.paste(nil)
            return true
        case "z":
            if event.modifierFlags.contains(.shift) {
                editorTextView?.undoManager?.redo()
            } else {
                editorTextView?.undoManager?.undo()
            }
            return true
        case "w":
            onCommandW?()
            return true
        case "s":
            onCommandS?()
            return true
        case "b":
            onCommandB?()
            return true
        case "i":
            onCommandI?()
            return true
        case "u":
            onCommandU?()
            return true
        default:
            return super.performKeyEquivalent(with: event)
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onEscape?()
            return
        }

        if event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers?.lowercased() == "w" {
            onCommandW?()
            return
        }

        super.keyDown(with: event)
    }
}

private final class DraggableToolbarView: NSStackView {
    private weak var panel: NSWindow?

    init(panel: NSWindow) {
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

private final class BlueActionButton: NSButton {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    convenience init(title: String, target: AnyObject?, action: Selector?) {
        self.init(frame: .zero)
        self.title = title
        self.target = target
        self.action = action
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    override var isHighlighted: Bool {
        didSet {
            needsDisplay = true
        }
    }

    private func configure() {
        isBordered = false
        wantsLayer = true
        focusRingType = .none
    }

    override func draw(_ dirtyRect: NSRect) {
        let bounds = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: bounds, xRadius: 7, yRadius: 7)
        (isHighlighted ? NSColor.systemBlue.withAlphaComponent(0.72) : NSColor.systemBlue).setFill()
        path.fill()

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font ?? NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let attributedTitle = NSAttributedString(string: title, attributes: attributes)
        let titleSize = attributedTitle.size()
        let titleRect = NSRect(
            x: (self.bounds.width - titleSize.width) / 2,
            y: (self.bounds.height - titleSize.height) / 2,
            width: titleSize.width,
            height: titleSize.height
        )
        attributedTitle.draw(in: titleRect)
    }
}
