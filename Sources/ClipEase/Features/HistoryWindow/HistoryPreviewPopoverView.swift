import AppKit
import PDFKit
import SwiftUI
@preconcurrency import VisionKit

struct HistoryPreviewPopoverView: View {
    let item: ClipboardItem
    let ocrResult: ClipboardOCRMatch?
    let arrowX: CGFloat
    let size: CGSize
    let isContentReady: Bool
    let onClose: () -> Void
    let onCopy: () -> Void
    let onOpen: () -> Void
    let onReveal: () -> Void
    let onCopyURL: () -> Void
    let onCopyMarkdown: () -> Void
    let onCopyPath: () -> Void
    let onCopyRGB: () -> Void
    @State private var previewImage: PreviewImage?
    @State private var filePreviewImage: PreviewImage?
    @State private var selectedFileReferenceID: ClipboardFileReference.ID?
    @State private var isOCRHighlightEnabled = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            popoverBody

            Triangle()
                .fill(Color(red: 0.94, green: 0.95, blue: 0.98))
                .frame(width: 26, height: 14)
                .padding(.leading, arrowX - 13)
        }
        .frame(width: size.width, height: size.height + 14, alignment: .topLeading)
    }

    private var popoverBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider()

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .animation(.easeOut(duration: 0.16), value: isContentReady)

            Divider()

            if item.type != .image {
                ocrSection
            }
            footer
        }
        .frame(width: size.width, height: size.height)
        .background(Color(red: 0.94, green: 0.95, blue: 0.98))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .transition(.opacity.combined(with: .scale(scale: 0.985)))
    }

    private var ocrSection: some View {
        let badges = (ocrResult?.emails ?? []) + (ocrResult?.phoneNumbers ?? []) + (ocrResult?.urls ?? [])
        return Group {
            if !badges.isEmpty {
                Divider()
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(badges, id: \.self) { badge in
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(badge, forType: .string)
                            } label: {
                                Text(badge)
                                    .font(.system(size: 11, weight: .semibold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color.gray.opacity(0.18))
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("复制") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(badge, forType: .string)
                                }
                                Button("分享") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(badge, forType: .string)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            Text(item.kind)
                .font(.system(size: 15, weight: .semibold))

            Text("来自 \(item.sourceAppName)")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()

            Button(action: onCopy) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 15, weight: .medium))
            }
            .buttonStyle(.plain)
            .help("复制")

            if item.type != .text {
                actionMenu
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var actionMenu: some View {
        Menu {
            switch item.type {
            case .link:
                Button("打开链接", action: onOpen)
                Button("复制链接地址", action: onCopyURL)
                Button("复制为 Markdown 链接", action: onCopyMarkdown)
            case .image:
                Button("打开图片", action: onOpen)
                Button("复制图片") {
                    onCopy()
                }
                Button("在 Finder 中显示", action: onReveal)
                Button("复制图片路径", action: onCopyPath)
            case .color:
                Button("复制 HEX", action: onCopy)
                Button("复制 RGB", action: onCopyRGB)
            case .file:
                Button("打开文件", action: onOpen)
                Button("复制文件") {
                    onCopy()
                }
                Button("在 Finder 中显示", action: onReveal)
                Button("复制路径", action: onCopyPath)
            case .text:
                EmptyView()
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 15, weight: .medium))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("更多操作")
    }

    @ViewBuilder
    private var content: some View {
        switch item.type {
        case .text:
            if isContentReady {
                LazyPreviewTextView(
                    text: item.text,
                    isReady: isContentReady,
                    richTextFileName: item.richTextFileName
                )
                    .background(Color.white)
            } else {
                previewPlaceholder
            }
        case .file:
            filePreviewContent
                .overlay(alignment: .bottomTrailing) {
                    ocrToggleButton
                        .padding(12)
                }
        case .color:
            colorContent
        case .link:
            ZStack(alignment: .bottomTrailing) {
                if isContentReady {
                    LinkPreviewWebView(url: item.url)
                        .background(Color.white)
                } else {
                    previewPlaceholder
                }

                Button(action: onOpen) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(Color.black.opacity(0.62))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .padding(12)
            }
        case .image:
            imageContent
                .task(id: isContentReady) {
                    guard isContentReady, item.type == .image else {
                        previewImage = nil
                        return
                    }

                    previewImage = await loadImage()
                }
                .overlay(alignment: .bottomTrailing) {
                    ocrToggleButton
                        .padding(12)
                }
        }
    }

    private var imageContent: some View {
        ZStack {
            if isContentReady, let image = previewImage {
                LiveTextImagePreview(
                    image: image.image,
                    url: image.url,
                    isHighlighted: isOCRHighlightEnabled
                )
                .frame(width: imageContentSize.width, height: imageContentSize.height)
                .transition(.opacity)
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 52, weight: .regular))
                    .foregroundStyle(Color(red: 0.18, green: 0.55, blue: 1.0))
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .background(Color.white)
    }

    private var imageContentSize: CGSize {
        CGSize(
            width: size.width,
            height: max(1, size.height - previewChromeHeight)
        )
    }

    private var previewChromeHeight: CGFloat {
        let headerHeight: CGFloat = 41
        let footerHeight: CGFloat = 41
        let dividerHeight: CGFloat = 2
        return headerHeight + footerHeight + dividerHeight
    }

    private var ocrToggleButton: some View {
        Group {
            if item.type == .image || ocrResult != nil {
                Button {
                    isOCRHighlightEnabled.toggle()
                } label: {
                    Image(systemName: isOCRHighlightEnabled ? "sparkles.rectangle.stack.fill" : "sparkles.rectangle.stack")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(Color.black.opacity(0.62))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("识别文字")
            }
        }
    }

    private func fittedImageSize(_ imageSize: CGSize, in containerSize: CGSize) -> CGSize {
        guard imageSize.width > 0,
              imageSize.height > 0,
              containerSize.width > 0,
              containerSize.height > 0 else {
            return containerSize
        }

        let scale = min(containerSize.width / imageSize.width, containerSize.height / imageSize.height)
        return CGSize(
            width: floor(imageSize.width * scale),
            height: floor(imageSize.height * scale)
        )
    }

    private var previewPlaceholder: some View {
        ZStack {
            Color.white

            ProgressView()
                .controlSize(.small)
        }
        .transition(.opacity)
    }

    private var colorContent: some View {
        let components = ClipEaseColorComponents(hex: item.text)

        return ZStack {
            Color.clipeaseHex(item.text)

            VStack(spacing: 10) {
                Text(item.text)
                    .font(.system(size: 36, weight: .bold))
                    .textSelection(.enabled)

                if let components {
                    Text(rgbText(from: components))
                        .font(.system(size: 16, weight: .semibold))
                        .textSelection(.enabled)
                }
            }
            .foregroundStyle(components?.readableTextColor ?? .white)
        }
    }

    private var filePreviewContent: some View {
        let references = item.fileReferences
        let selectedReference = selectedFileReference(from: references)

        return ZStack(alignment: .bottomTrailing) {
            HStack(spacing: 0) {
                filePreviewPane(for: selectedReference)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider()

                fileReferenceList(references)
                    .frame(width: min(240, max(180, size.width * 0.32)))
            }

            if isOCRHighlightEnabled {
                Color.gray.opacity(0.18)
                    .allowsHitTesting(false)
            }
        }
        .background(Color.white)
        .onAppear {
            synchronizeSelectedFileReference(with: references)
        }
        .onChange(of: item.id) { _ in
            selectedFileReferenceID = nil
            synchronizeSelectedFileReference(with: references)
        }
        .onChange(of: references.map(\.id)) { _ in
            synchronizeSelectedFileReference(with: references)
        }
    }

    @ViewBuilder
    private func filePreviewPane(for reference: ClipboardFileReference?) -> some View {
        if let reference,
           fileIsPreviewable(reference),
           FileManager.default.isReadableFile(atPath: reference.path) {
            switch filePreviewKind(for: reference) {
            case .text:
                FileTextPreviewView(url: URL(fileURLWithPath: reference.path))
            case .pdf:
                FilePDFPreviewView(url: URL(fileURLWithPath: reference.path))
            case .image:
                fileImagePreview(reference)
            case .quickLook:
                HistoryFileQuickLookPreviewView(url: URL(fileURLWithPath: reference.path))
            }
        } else {
            fileFallbackPreview(reference)
        }
    }

    private func fileImagePreview(_ reference: ClipboardFileReference) -> some View {
        ZStack {
            if let filePreviewImage,
               filePreviewImage.url.path == reference.path {
                LiveTextImagePreview(
                    image: filePreviewImage.image,
                    url: filePreviewImage.url,
                    isHighlighted: isOCRHighlightEnabled
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                previewPlaceholder
            }
        }
        .task(id: reference.path) {
            filePreviewImage = await loadPreviewImage(url: URL(fileURLWithPath: reference.path))
        }
    }

    private func fileReferenceList(_ references: [ClipboardFileReference]) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                if references.isEmpty {
                    missingFileReferenceRow
                } else {
                    ForEach(references) { reference in
                        Button {
                            selectedFileReferenceID = reference.id
                        } label: {
                            fileReferenceRow(
                                reference: reference,
                                isSelected: selectedFileReferenceID == reference.id
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(12)
        }
        .background(Color(red: 0.97, green: 0.98, blue: 1.0))
    }

    private var missingFileReferenceRow: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "questionmark.document")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color(red: 0.18, green: 0.55, blue: 1.0))
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text("文件路径不可用")
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(item.text.isEmpty ? "剪贴板记录没有可预览路径" : item.text)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .textSelection(.enabled)

                Text("缺少路径")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func fileReferenceRow(reference: ClipboardFileReference, isSelected: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: reference.isDirectory ? "folder.fill" : "doc.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(isSelected ? Color.white : Color(red: 0.18, green: 0.55, blue: 1.0))
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(fileDisplayName(reference))
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(isSelected ? Color.white : Color.primary)

                Text(reference.path)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isSelected ? Color.white.opacity(0.82) : Color.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)

                Text(fileStatusText(reference))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.white.opacity(0.82) : Color.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isSelected ? Color(red: 0.18, green: 0.55, blue: 1.0) : Color.clear)
        )
    }

    private func fileFallbackPreview(_ reference: ClipboardFileReference?) -> some View {
        VStack(spacing: 14) {
            if let reference {
                Image(nsImage: ClipEaseAppIcon.roundedImage(NSWorkspace.shared.icon(forFile: reference.path), size: NSSize(width: 72, height: 72)))
                    .resizable()
                    .frame(width: 72, height: 72)

                VStack(spacing: 6) {
                    Text(fileDisplayName(reference))
                        .font(.system(size: 18, weight: .semibold))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .truncationMode(.middle)
                        .textSelection(.enabled)

                    Text(reference.path)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .multilineTextAlignment(.center)
                        .truncationMode(.middle)
                        .textSelection(.enabled)

                    Text(fileStatusText(reference))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 24)
            } else {
                Image(systemName: "questionmark.document")
                    .font(.system(size: 56, weight: .regular))
                    .foregroundStyle(Color(red: 0.18, green: 0.55, blue: 1.0))

                Text("文件路径不可用")
                    .font(.system(size: 18, weight: .semibold))

                Text(item.text.isEmpty ? "剪贴板记录没有可预览路径" : item.text)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .multilineTextAlignment(.center)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .padding(.horizontal, 24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
    }

    private func previewableFileReference(from references: [ClipboardFileReference]) -> ClipboardFileReference? {
        references.first(where: fileIsPreviewable) ?? references.first
    }

    private func selectedFileReference(from references: [ClipboardFileReference]) -> ClipboardFileReference? {
        if let selectedFileReferenceID,
           let selectedReference = references.first(where: { $0.id == selectedFileReferenceID }) {
            return selectedReference
        }

        return previewableFileReference(from: references)
    }

    private func synchronizeSelectedFileReference(with references: [ClipboardFileReference]) {
        guard !references.isEmpty else {
            selectedFileReferenceID = nil
            return
        }

        if let selectedFileReferenceID,
           references.contains(where: { $0.id == selectedFileReferenceID }) {
            return
        }

        selectedFileReferenceID = previewableFileReference(from: references)?.id
    }

    private func fileIsPreviewable(_ reference: ClipboardFileReference) -> Bool {
        guard !reference.path.isEmpty,
              !reference.isDirectory,
              reference.pathStatus == .available || reference.pathStatus == .unknown else {
            return false
        }

        return FileManager.default.fileExists(atPath: reference.path)
    }

    private func filePreviewKind(for reference: ClipboardFileReference) -> FilePreviewKind {
        let ext = (reference.fileExtension ?? URL(fileURLWithPath: reference.path).pathExtension)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let contentType = reference.contentType?.lowercased() ?? ""

        if ext == "pdf" || contentType.contains("pdf") {
            return .pdf
        }

        if ["png", "jpg", "jpeg", "heic", "heif", "webp", "gif", "tiff", "bmp"].contains(ext) ||
            contentType.hasPrefix("image/") {
            return .image
        }

        if officeLikeFileExtensions.contains(ext) ||
            contentType.contains("officedocument") ||
            contentType.contains("openxmlformats") ||
            contentType.contains("ms-excel") ||
            contentType.contains("msword") ||
            contentType.contains("powerpoint") ||
            contentType.contains("spreadsheet") ||
            contentType.contains("presentation") ||
            contentType.contains("comma-separated-values") ||
            contentType.contains("rtf") {
            return .quickLook
        }

        if contentType.hasPrefix("text/") ||
            plainTextFileExtensions.contains(ext) {
            return .text
        }

        return .quickLook
    }

    private var officeLikeFileExtensions: Set<String> {
        [
            "doc", "docx", "docm", "dot", "dotx", "dotm",
            "xls", "xlsx", "xlsm", "xlsb", "xlt", "xltx", "xltm",
            "ppt", "pptx", "pptm", "pot", "potx", "potm", "pps", "ppsx", "ppsm",
            "csv", "rtf", "numbers", "pages", "key"
        ]
    }

    private var plainTextFileExtensions: Set<String> {
        [
            "txt", "md", "markdown", "json", "xml", "log", "swift", "js", "ts", "tsx", "jsx",
            "html", "css", "py", "sh", "zsh", "yaml", "yml", "toml", "plist"
        ]
    }

    private func fileDisplayName(_ reference: ClipboardFileReference) -> String {
        if !reference.displayName.isEmpty {
            return reference.displayName
        }

        let lastPathComponent = URL(fileURLWithPath: reference.path).lastPathComponent
        return lastPathComponent.isEmpty ? reference.path : lastPathComponent
    }

    private func fileStatusText(_ reference: ClipboardFileReference) -> String {
        if reference.path.isEmpty {
            return "缺少路径"
        }

        switch reference.pathStatus {
        case .available:
            return reference.isDirectory ? "文件夹" : "可预览"
        case .missing:
            return "路径缺失"
        case .permissionDenied:
            return "权限不足"
        case .placeholder:
            return "占位文件"
        case .unknown:
            if FileManager.default.fileExists(atPath: reference.path) {
                return reference.isDirectory ? "文件夹" : "状态未确认"
            }
            return "路径未确认"
        }
    }

    private var footer: some View {
        HStack {
            if item.type != .file {
                Text(item.footer)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)

                Spacer()
            }

            Text(item.relativeTime)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)

            if item.type == .file {
                Spacer()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func loadImage() async -> PreviewImage? {
        guard let imageFileName = item.imageFileName,
              let imageURL = try? ClipEaseStoragePaths.imageFileURL(fileName: imageFileName) else {
            return nil
        }

        return await loadPreviewImage(url: imageURL, preferredSize: {
            guard let width = item.imageWidth,
                  let height = item.imageHeight,
                  width > 0,
                  height > 0 else {
                return nil
            }
            return NSSize(width: width, height: height)
        }())
    }

    private func loadPreviewImage(url imageURL: URL, preferredSize: NSSize? = nil) async -> PreviewImage? {
        let data = await Task.detached(priority: .utility) {
            try? Data(contentsOf: imageURL)
        }.value

        guard let data else {
            return nil
        }

        guard let image = NSImage(data: data) else {
            return nil
        }
        if let preferredSize {
            image.size = preferredSize
        }

        return PreviewImage(image: image, url: imageURL)
    }

    private func rgbText(from components: ClipEaseColorComponents) -> String {
        let red = Int(round(components.red * 255))
        let green = Int(round(components.green * 255))
        let blue = Int(round(components.blue * 255))
        return "rgb(\(red), \(green), \(blue))"
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

private struct PreviewImage {
    let image: NSImage
    let url: URL
}

private enum FilePreviewKind {
    case text
    case pdf
    case image
    case quickLook
}

private struct FileTextPreviewView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> NSScrollView {
        let textView = FileInteractiveTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 16, height: 16)
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textColor = NSColor.labelColor
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.autoresizingMask = [.width]
        textView.string = "正在读取文件内容..."

        let scrollView = NSScrollView()
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .white
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.documentView = textView
        context.coordinator.load(url: url, in: textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView,
              context.coordinator.url != url else {
            return
        }

        context.coordinator.url = url
        textView.string = "正在读取文件内容..."
        context.coordinator.load(url: url, in: textView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    nonisolated private static func text(from url: URL) async -> String {
        await Task.detached(priority: .utility) {
            textSynchronously(from: url)
        }.value
    }

    nonisolated private static func textSynchronously(from url: URL) -> String {
        if let attributedString = try? NSAttributedString(
            url: url,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil
        ), attributedString.length > 0 {
            return attributedString.string
        }

        if let text = try? String(contentsOf: url, encoding: .utf8) {
            return text
        }

        if let text = try? String(contentsOf: url, encoding: .unicode) {
            return text
        }

        return "无法读取文件内容"
    }

    @MainActor
    final class Coordinator {
        var url: URL
        private var loadTask: Task<Void, Never>?

        init(url: URL) {
            self.url = url
        }

        func load(url: URL, in textView: NSTextView) {
            loadTask?.cancel()
            let expectedURL = url
            loadTask = Task { @MainActor [weak self, weak textView] in
                let text = await FileTextPreviewView.text(from: url)
                guard !Task.isCancelled,
                      self?.url == expectedURL,
                      let textView else {
                    return
                }

                textView.string = text
            }
        }

        deinit {
            loadTask?.cancel()
        }
    }
}

private final class FileInteractiveTextView: NSTextView {
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.rightMouseDown(with: event)
    }
}

private struct FilePDFPreviewView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = .white
        view.document = PDFDocument(url: url)
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        guard context.coordinator.url != url else {
            return
        }

        context.coordinator.url = url
        view.document = PDFDocument(url: url)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    final class Coordinator {
        var url: URL

        init(url: URL) {
            self.url = url
        }
    }
}

@available(macOS 13.0, *)
private struct LiveTextImagePreview: NSViewRepresentable {
    let image: NSImage
    let url: URL
    let isHighlighted: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> LiveTextImagePreviewView {
        let view = LiveTextImagePreviewView()
        view.configure(image: image, url: url, isHighlighted: isHighlighted, coordinator: context.coordinator)
        return view
    }

    func updateNSView(_ view: LiveTextImagePreviewView, context: Context) {
        view.configure(image: image, url: url, isHighlighted: isHighlighted, coordinator: context.coordinator)
    }

    @MainActor
    final class Coordinator: NSObject, ImageAnalysisOverlayViewDelegate {
        weak var containerView: LiveTextImagePreviewView?

        func contentView(for overlayView: ImageAnalysisOverlayView) -> NSView? {
            containerView
        }
    }
}

@available(macOS 13.0, *)
@MainActor
private final class LiveTextImagePreviewView: NSView {
    private let imageView = NSImageView()
    private let overlayView: ImageAnalysisOverlayView
    private let analyzer = ImageAnalyzer()
    private var representedURL: URL?
    private var analysisTask: Task<Void, Never>?

    override init(frame frameRect: NSRect) {
        let delegate = LiveTextOverlayDelegate()
        overlayView = ImageAnalysisOverlayView(delegate)
        super.init(frame: frameRect)
        delegate.containerView = self
        overlayView.delegate = delegate

        wantsLayer = true
        layer?.backgroundColor = NSColor.white.cgColor
        layer?.masksToBounds = true

        imageView.imageFrameStyle = .none
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        imageView.allowsCutCopyPaste = true
        imageView.isEditable = false

        overlayView.preferredInteractionTypes = [.textSelection, .dataDetectors]
        overlayView.isSupplementaryInterfaceHidden = true
        overlayView.selectableItemsHighlighted = false
        overlayView.trackingImageView = imageView

        addSubview(imageView)
        addSubview(overlayView)
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        imageView.frame = aspectFitRect(for: imageView.image?.size ?? .zero, in: bounds)
        overlayView.frame = bounds
        overlayView.setContentsRectNeedsUpdate()
    }

    func configure(
        image: NSImage,
        url: URL,
        isHighlighted: Bool,
        coordinator: LiveTextImagePreview.Coordinator
    ) {
        coordinator.containerView = self
        if imageView.image !== image {
            imageView.image = image
            needsLayout = true
        }
        overlayView.selectableItemsHighlighted = isHighlighted
        overlayView.setContentsRectNeedsUpdate()

        guard representedURL != url else {
            return
        }
        representedURL = url
        overlayView.analysis = nil
        analysisTask?.cancel()

        guard ImageAnalyzer.isSupported else {
            return
        }

        let analysisImage = image
        analysisTask = Task { [weak self] in
            guard let self else {
                return
            }
            var configuration = ImageAnalyzer.Configuration([.text])
            configuration.locales = preferredOCRLocales()
            do {
                let analysis = try await analyzer.analyze(
                    analysisImage,
                    orientation: .up,
                    configuration: configuration
                )
                await MainActor.run {
                    guard self.representedURL == url else {
                        return
                    }
                    self.overlayView.analysis = analysis
                    self.overlayView.selectableItemsHighlighted = isHighlighted
                    self.overlayView.setContentsRectNeedsUpdate()
                }
            } catch {
                await MainActor.run {
                    guard self.representedURL == url else {
                        return
                    }
                    self.overlayView.analysis = nil
                }
            }
        }
    }

    private func preferredOCRLocales() -> [String] {
        let supported = Set(ImageAnalyzer.supportedTextRecognitionLanguages)
        return ["zh-Hans", "en-US"].filter { supported.contains($0) }
    }

    private func aspectFitRect(for imageSize: NSSize, in bounds: NSRect) -> NSRect {
        guard imageSize.width > 0,
              imageSize.height > 0,
              bounds.width > 0,
              bounds.height > 0 else {
            return bounds
        }

        let scale = min(bounds.width / imageSize.width, bounds.height / imageSize.height, 1)
        let width = floor(imageSize.width * scale)
        let height = floor(imageSize.height * scale)
        return NSRect(
            x: floor(bounds.midX - width / 2),
            y: floor(bounds.midY - height / 2),
            width: width,
            height: height
        )
    }
}

@available(macOS 13.0, *)
@MainActor
private final class LiveTextOverlayDelegate: NSObject, ImageAnalysisOverlayViewDelegate {
    weak var containerView: NSView?

    func contentView(for overlayView: ImageAnalysisOverlayView) -> NSView? {
        containerView
    }
}
