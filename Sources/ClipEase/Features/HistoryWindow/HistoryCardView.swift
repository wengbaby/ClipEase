import SwiftUI
import AppKit

struct HistoryCardView: View, Equatable {
    let item: HistoryPreviewItem
    let searchQuery: String
    let shortcutNumber: Int?
    let isShortcutOverlayVisible: Bool
    let isHovered: Bool
    let isPressed: Bool
    let isEnteringLatestItem: Bool
    let onClick: () -> Void
    let onDoubleClick: () -> Void
    let onRightMouseDown: () -> Void
    let onMenu: () -> NSMenu
    let onFileDragStatus: (String) -> Void
    let onHoverChanged: (Bool) -> Void
    let onPressChanged: (Bool) -> Void
    let onMouseExitedWindow: () -> Void

    nonisolated static func == (lhs: HistoryCardView, rhs: HistoryCardView) -> Bool {
        lhs.item == rhs.item &&
            lhs.searchQuery == rhs.searchQuery &&
            lhs.shortcutNumber == rhs.shortcutNumber &&
            lhs.isShortcutOverlayVisible == rhs.isShortcutOverlayVisible &&
            lhs.isHovered == rhs.isHovered &&
            lhs.isPressed == rhs.isPressed &&
            lhs.isEnteringLatestItem == rhs.isEnteringLatestItem
    }

    @State private var entranceSheenProgress: CGFloat = 0
    @State private var isEntranceSheenVisible = false
    @State private var entranceSheenHideTask: Task<Void, Never>?

    private let entranceSheenDuration: TimeInterval = 1.8

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(item.kind)
                            .font(.system(size: 16, weight: .bold))

                        if item.isPinned {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 11, weight: .bold))
                        }

                        groupBadge
                    }

                    Text(item.time)
                        .font(.system(size: 13, weight: .medium))
                }

                Spacer()

                AsyncSourceIconView(
                    iconFileName: item.iconFileName,
                    fallbackSystemName: item.iconName,
                    sourceAppName: item.sourceAppName
                )
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
            .background(item.headerColor)

            preview
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.white)

            footerView
        }
        .frame(width: 250, height: 270)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            if isEntranceSheenVisible {
                entranceSheen
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if let shortcutNumber {
                Text("\(shortcutNumber)")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(Color.black.opacity(0.62))
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .padding(10)
                    .opacity(isShortcutOverlayVisible ? 1 : 0)
            }
        }
        .animation(.easeOut(duration: 0.10), value: isHovered)
        .animation(.easeOut(duration: 0.06), value: isPressed)
        .animation(.easeOut(duration: 0.16), value: isEnteringLatestItem)
        .onAppear {
            updateEntranceSheenAnimation(isEnteringLatestItem)
        }
        .onChange(of: isEnteringLatestItem) { isEntering in
            updateEntranceSheenAnimation(isEntering)
        }
        .onDisappear {
            entranceSheenHideTask?.cancel()
        }
        .overlay(
            CardDragSourceView(
                item: item,
                onClick: onClick,
                onDoubleClick: onDoubleClick,
                onRightMouseDown: onRightMouseDown,
                onMenu: onMenu,
                onInvalid: {
                    onFileDragStatus("未找到可拖出的文件")
                },
                onPartial: {
                    onFileDragStatus("已拖出可用文件")
                },
                onHoverChanged: onHoverChanged,
                onPressChanged: onPressChanged,
                onMouseExitedWindow: onMouseExitedWindow
            )
        )
    }

    private var entranceSheen: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let sheenOpacity = entranceSheenOpacity(for: entranceSheenProgress)
            LinearGradient(
                colors: [
                    .clear,
                    .white.opacity(0.48),
                    .white.opacity(0)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: width * 0.9, height: proxy.size.height)
            .offset(x: -width * 0.95 + entranceSheenProgress * width * 2.1)
            .opacity(sheenOpacity)
            .blendMode(.screen)
            .allowsHitTesting(false)
        }
        .clipped()
        .allowsHitTesting(false)
    }

    private func entranceSheenOpacity(for progress: CGFloat) -> CGFloat {
        guard progress > 0 else {
            return 0
        }
        guard progress > 0.72 else {
            return 1
        }
        return max(0, 1 - ((progress - 0.72) / 0.28))
    }

    private func updateEntranceSheenAnimation(_ isEntering: Bool) {
        guard isEntering else {
            return
        }

        entranceSheenHideTask?.cancel()
        isEntranceSheenVisible = true
        entranceSheenProgress = 0
        withAnimation(.linear(duration: entranceSheenDuration)) {
            entranceSheenProgress = 1
        }
        entranceSheenHideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(entranceSheenDuration * 1_000_000_000))
            guard !Task.isCancelled else {
                return
            }

            isEntranceSheenVisible = false
            entranceSheenProgress = 0
            entranceSheenHideTask = nil
        }
    }

    @ViewBuilder
    private var groupBadge: some View {
        if item.groupID != nil {
            Image(systemName: "folder.fill")
                .font(.system(size: 11, weight: .bold))
        }
    }

    @ViewBuilder
    private var preview: some View {
        switch item.type {
        case .text:
            textPreview
        case .link:
            linkPreview
        case .image:
            imagePreview
        case .color:
            colorPreview
        case .file:
            filePreview
        }
    }

    private var filePreview: some View {
        ZStack {
            if isMultiFilePreview {
                multiFileIconStack
            } else {
                fileIcon(name: primaryFileIconName, size: 78)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .background(Color.white)
    }

    private var multiFileIconStack: some View {
        ZStack {
            fileIcon(name: "doc.fill", size: 58)
                .offset(x: -24, y: -8)
                .opacity(0.78)

            fileIcon(name: "doc.fill", size: 64)
                .offset(x: 18, y: 7)
                .opacity(0.88)

            fileIcon(name: primaryFileIconName, size: 74)
                .offset(x: -2, y: -1)
        }
        .frame(width: 118, height: 92)
    }

    private func fileIcon(name: String, size: CGFloat) -> some View {
        Image(systemName: name)
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(Color(red: 0.18, green: 0.55, blue: 1.0))
            .frame(width: size + 14, height: size + 14)
    }

    private var colorPreview: some View {
        let components = ClipEaseColorComponents(hex: item.preview)

        return ZStack {
            Color.clipeaseHex(item.preview)

            VStack(spacing: 8) {
                Text(item.preview)
                    .font(.system(size: 30, weight: .bold))

                if let components {
                    Text(rgbText(from: components))
                        .font(.system(size: 13, weight: .semibold))
                }
            }
            .foregroundStyle(components?.readableTextColor ?? .white)
        }
    }

    private var imagePreview: some View {
        ZStack {
            CheckerboardView()

            AsyncCardImageView(imageFileName: item.imageFileName, mode: .fillAvailable)
        }
    }

    private var textPreview: some View {
        ZStack {
            if let richTextFileName = item.richTextFileName {
                RichTextCardPreview(
                    fileName: richTextFileName,
                    fallbackText: item.preview,
                    searchQuery: searchQuery
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                highlightedText(item.preview, baseColor: Color(red: 0.12, green: 0.14, blue: 0.17))
                    .font(.system(size: 16, weight: .regular))
                    .lineLimit(textPreviewLineLimit)
                    .truncationMode(.tail)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .mask(alignment: .bottom) {
            VStack(spacing: 0) {
                Color.black
                LinearGradient(
                    colors: [.black, .black.opacity(0.34)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 34)
            }
        }
    }

    private var textPreviewLineLimit: Int {
        item.preview.contains("\n") ? 9 : 8
    }

    private var linkPreview: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.98, green: 0.99, blue: 1.0),
                    Color(red: 0.94, green: 0.96, blue: 0.99)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            if item.imageFileName != nil {
                AsyncCardImageView(
                    imageFileName: item.imageFileName,
                    mode: .fitLinkPreview(minSize: 52, maxSize: 96)
                )
            } else {
                linkFallbackIcon
            }
        }
    }

    private var linkFallbackIcon: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.09, green: 0.28, blue: 0.62),
                        Color(red: 0.05, green: 0.72, blue: 0.78)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 52, height: 52)
            .overlay {
                Image(systemName: "link")
                    .font(.system(size: 23, weight: .bold))
                    .foregroundStyle(.white)
            }
    }

    private var linkFooterTitle: String {
        let trimmedTitle = (item.linkTitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedTitle.isEmpty ? item.preview : trimmedTitle
    }

    private var linkFooterURL: String {
        let trimmedFooter = item.footer.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedFooter.isEmpty ? item.preview : trimmedFooter
    }

    private var linkFooter: some View {
        VStack(spacing: 2) {
            Text(linkFooterTitle)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color(red: 0.16, green: 0.17, blue: 0.19))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity)

            Text(linkFooterURL)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(Color.white)
    }

    private func highlightedText(_ text: String, baseColor: Color) -> Text {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return Text(text).foregroundColor(baseColor)
        }

        var attributedText = AttributedString(text)
        attributedText.foregroundColor = baseColor

        var searchStart = text.startIndex
        var hasMatch = false

        while searchStart < text.endIndex,
              let matchRange = text.range(
                of: query,
                options: [.caseInsensitive, .diacriticInsensitive],
                range: searchStart..<text.endIndex
              ) {
            guard let lowerBound = AttributedString.Index(matchRange.lowerBound, within: attributedText),
                  let upperBound = AttributedString.Index(matchRange.upperBound, within: attributedText) else {
                break
            }

            attributedText[lowerBound..<upperBound].backgroundColor = Color.yellow.opacity(0.55)
            attributedText[lowerBound..<upperBound].foregroundColor = baseColor
            hasMatch = true
            searchStart = matchRange.upperBound
        }

        return hasMatch ? Text(attributedText) : Text(text).foregroundColor(baseColor)
    }

    private func rgbText(from components: ClipEaseColorComponents) -> String {
        let red = Int(round(components.red * 255))
        let green = Int(round(components.green * 255))
        let blue = Int(round(components.blue * 255))
        return "rgb(\(red), \(green), \(blue))"
    }

    @ViewBuilder
    private var footerView: some View {
        if item.type == .file {
            fileFooter
        } else if item.type == .link {
            linkFooter
        } else {
            Text(item.footer)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.white)
        }
    }

    @ViewBuilder
    private var fileFooter: some View {
        if isMultiFilePreview {
            Text(fileFooterText)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 36)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Color.white)
        } else {
            Text(fileFooterText)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.middle)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 36)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Color.white)
        }
    }

    private var primaryFile: HistoryFilePreviewReference? {
        item.filePreviewReferences.first
    }

    private var primaryFileTitle: String {
        guard let primaryFile else {
            return item.preview.isEmpty ? "文件引用" : item.preview.components(separatedBy: .newlines).first ?? item.preview
        }

        return primaryFile.displayName.isEmpty ? primaryFile.path : primaryFile.displayName
    }

    private var primaryFileIconName: String {
        primaryFile?.isDirectory == true ? "folder.fill" : "doc.fill"
    }

    private var isMultiFilePreview: Bool {
        item.filePreviewReferences.count > 1
    }

    private var fileCountText: String {
        let count = item.filePreviewReferences.count
        if count > 1 {
            return "\(count) 个项目"
        }

        if primaryFile?.isDirectory == true {
            return "文件夹"
        }

        return "文件"
    }

    private var fileFooterText: String {
        let statusText = fileStatusSummaryText
        guard !isMultiFilePreview else {
            return [fileCountText, statusText].compactMap { $0 }.joined(separator: " · ")
        }

        let pathText: String
        if let primaryFile {
            pathText = primaryFile.path.isEmpty ? primaryFileTitle : primaryFile.path
        } else {
            pathText = item.footer.isEmpty ? "路径不可用" : item.footer
        }

        return [statusText, pathText].compactMap { $0 }.joined(separator: " · ")
    }

    private var filePathSummaries: [FilePathSummary] {
        if item.filePreviewReferences.isEmpty {
            return [FilePathSummary(path: item.footer.isEmpty ? "路径不可用" : item.footer, status: .unknown)]
        }

        return item.filePreviewReferences.map { reference in
            FilePathSummary(path: reference.path, status: reference.pathStatus)
        }
    }

    private var fileStatusSummaryText: String? {
        let badges = filePathSummaries.compactMap(\.badge)
        guard !badges.isEmpty else {
            return nil
        }

        let counts = Dictionary(grouping: badges, by: { $0 }).mapValues(\.count)
        return counts
            .sorted { left, right in
                if left.value == right.value {
                    return left.key < right.key
                }
                return left.value > right.value
            }
            .map { label, count in
                count > 1 ? "\(label) \(count)" : label
            }
            .joined(separator: " · ")
    }
}

private struct FilePathSummary: Identifiable {
    let id = UUID()
    let path: String
    let status: ClipboardFilePathStatus

    var badge: String? {
        switch status {
        case .available:
            nil
        case .missing:
            "缺失"
        case .permissionDenied:
            "无权限"
        case .placeholder:
            "占位"
        case .unknown:
            "未确认"
        }
    }
}

private struct AsyncSourceIconView: View {
    let iconFileName: String?
    let fallbackSystemName: String
    let sourceAppName: String

    @State private var icon: NSImage?
    @State private var representedFileName: String?
    @State private var loadTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 64, height: 64)
            } else {
                Image(systemName: fallbackSystemName)
                    .font(.system(size: 34, weight: .semibold))
            }
        }
        .frame(width: 64, height: 64)
        .clipShape(RoundedRectangle(cornerRadius: ClipEaseAppIcon.nativeAppIconCornerRadius(for: NSSize(width: 64, height: 64)), style: .continuous))
        .help(sourceAppName)
        .task(id: iconFileName) {
            await loadIconIfNeeded()
        }
        .onDisappear {
            loadTask?.cancel()
            loadTask = nil
        }
    }

    @MainActor
    private func loadIconIfNeeded() async {
        loadTask?.cancel()
        representedFileName = iconFileName

        guard let iconFileName else {
            icon = nil
            return
        }

        let cacheKey = "app-icon:\(iconFileName)"
        if let cachedIcon = ImageMemoryCache.shared.cachedImage(for: cacheKey) {
            icon = cachedIcon
            return
        }

        icon = nil
        loadTask = Task.detached(priority: .utility) {
            let loadedIcon = HistoryCardAssetLoadGate.shared.load {
                HistoryCardAssetLoader.loadSourceIcon(fileName: iconFileName)
            }
            await MainActor.run {
                guard representedFileName == iconFileName else {
                    return
                }

                if let loadedIcon {
                    ImageMemoryCache.shared.store(loadedIcon, for: cacheKey)
                }
                icon = loadedIcon
            }
        }
    }
}

private struct AsyncCardImageView: View {
    enum Mode: Equatable {
        case fillAvailable
        case fitLinkPreview(minSize: CGFloat, maxSize: CGFloat)
    }

    let imageFileName: String?
    let mode: Mode

    @State private var image: NSImage?
    @State private var representedFileName: String?
    @State private var loadTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            if let image {
                imageView(image)
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 58, weight: .regular))
                    .foregroundStyle(Color(red: 0.18, green: 0.55, blue: 1.0))
            }
        }
        .task(id: imageFileName) {
            await loadImageIfNeeded()
        }
        .onDisappear {
            loadTask?.cancel()
            loadTask = nil
        }
    }

    @ViewBuilder
    private func imageView(_ image: NSImage) -> some View {
        switch mode {
        case .fillAvailable:
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .fitLinkPreview(let minSize, let maxSize):
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(
                    width: min(max(image.size.width, minSize), maxSize),
                    height: min(max(image.size.height, minSize), maxSize)
                )
        }
    }

    @MainActor
    private func loadImageIfNeeded() async {
        loadTask?.cancel()
        representedFileName = imageFileName

        guard let imageFileName else {
            image = nil
            return
        }

        let cacheKey = "history-thumbnail:\(imageFileName)"
        if let cachedImage = ImageMemoryCache.shared.cachedImage(for: cacheKey) {
            image = cachedImage
            return
        }

        image = nil
        loadTask = Task.detached(priority: .utility) {
            let loadedImage = HistoryCardAssetLoadGate.shared.load {
                HistoryCardAssetLoader.loadImageThumbnail(fileName: imageFileName)
            }
            await MainActor.run {
                guard representedFileName == imageFileName else {
                    return
                }

                if let loadedImage {
                    ImageMemoryCache.shared.store(loadedImage, for: cacheKey)
                }
                image = loadedImage
            }
        }
    }
}

final class HistoryCardAssetLoadGate: @unchecked Sendable {
    static let shared = HistoryCardAssetLoadGate()

    private let semaphore = DispatchSemaphore(value: 3)

    private init() {}

    func load<T>(_ operation: () -> T) -> T {
        semaphore.wait()
        defer { semaphore.signal() }
        return operation()
    }
}

private enum HistoryCardAssetLoader {
    static func loadSourceIcon(fileName: String) -> NSImage? {
        guard let iconURL = try? ClipEaseStoragePaths.appIconFileURL(fileName: fileName) else {
            return nil
        }

        return NSImage(contentsOf: iconURL).map {
            ClipEaseAppIcon.roundedImage($0, size: NSSize(width: 64, height: 64))
        }
    }

    static func loadImageThumbnail(fileName: String) -> NSImage? {
        guard let thumbnailURL = try? ClipEaseStoragePaths.thumbnailFileURL(fileName: fileName),
              let imageURL = try? ClipEaseStoragePaths.imageFileURL(fileName: fileName) else {
            return nil
        }

        if let thumbnail = NSImage(contentsOf: thumbnailURL) {
            return thumbnail
        }

        guard let image = NSImage(contentsOf: imageURL) else {
            return nil
        }

        guard let thumbnail = image.clipeaseCardThumbnail(maxPixelSize: CGSize(width: 500, height: 360)),
              let thumbnailData = thumbnail.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: thumbnailData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return image
        }

        try? FileManager.default.createDirectory(
            at: thumbnailURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? pngData.write(to: thumbnailURL, options: [.atomic])
        return thumbnail
    }
}

private struct RichTextCardPreview: View {
    let fileName: String
    let fallbackText: String
    let searchQuery: String

    @State private var attributedText: AttributedString?
    @State private var representedKey = ""
    @State private var loadTask: Task<Void, Never>?

    var body: some View {
        Text(attributedText ?? fallbackAttributedText)
            .font(.system(size: 16, weight: .regular))
            .lineLimit(9)
            .truncationMode(.tail)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 2)
            .task(id: renderKey) {
                await loadIfNeeded()
            }
            .onDisappear {
                loadTask?.cancel()
                loadTask = nil
            }
    }

    private var fallbackAttributedText: AttributedString {
        RichTextCardPreviewCache.swiftUIAttributedString(
            from: RichTextCardPreviewCache.fallbackAttributedString(fallbackText),
            searchQuery: searchQuery
        )
    }

    private var renderKey: String {
        "\(fileName)|\(fallbackText.hashValue)|\(searchQuery)"
    }

    @MainActor
    private func loadIfNeeded() async {
        let key = renderKey
        guard representedKey != key else {
            return
        }

        representedKey = key
        loadTask?.cancel()

        if let cachedText = RichTextCardPreviewCache.shared.cachedAttributedString(fileName: fileName) {
            attributedText = RichTextCardPreviewCache.swiftUIAttributedString(
                from: cachedText,
                searchQuery: searchQuery
            )
            return
        }

        attributedText = fallbackAttributedText
        loadTask = Task.detached(priority: .utility) {
            let loadedText = HistoryCardAssetLoadGate.shared.load {
                RichTextCardPreviewCache.loadAttributedString(
                    fileName: fileName,
                    fallbackText: fallbackText
                )
            }

            let renderedText = RichTextCardPreviewCache.swiftUIAttributedString(
                from: loadedText,
                searchQuery: searchQuery
            )

            await MainActor.run {
                guard representedKey == key,
                      !Task.isCancelled else {
                    return
                }

                RichTextCardPreviewCache.shared.store(loadedText, fileName: fileName)
                attributedText = renderedText
            }
        }
    }
}

@MainActor
final class RichTextCardPreviewCache {
    static let shared = RichTextCardPreviewCache()

    nonisolated private static let maxPreviewCharacters = 2_000

    private let cache = NSCache<NSString, NSAttributedString>()

    private init() {
        cache.countLimit = 64
    }

    func cachedAttributedString(fileName: String) -> NSAttributedString? {
        guard let fileURL = try? ClipEaseStoragePaths.richTextFileURL(fileName: fileName) else {
            return nil
        }

        let cacheKey = Self.cacheKey(fileName: fileName, fileURL: fileURL)
        return cache.object(forKey: cacheKey as NSString)
    }

    func store(_ attributedText: NSAttributedString, fileName: String) {
        guard let fileURL = try? ClipEaseStoragePaths.richTextFileURL(fileName: fileName) else {
            return
        }

        let cacheKey = Self.cacheKey(fileName: fileName, fileURL: fileURL)
        cache.setObject(attributedText, forKey: cacheKey as NSString)
    }

    nonisolated static func swiftUIAttributedString(
        from attributedText: NSAttributedString,
        searchQuery: String
    ) -> AttributedString {
        let highlightedText = highlighted(attributedText, searchQuery: searchQuery)
        return (try? AttributedString(highlightedText, including: \.appKit)) ??
            AttributedString(highlightedText.string)
    }

    nonisolated static func loadAttributedString(fileName: String, fallbackText: String) -> NSAttributedString {
        guard let fileURL = try? ClipEaseStoragePaths.richTextFileURL(fileName: fileName) else {
            return fallbackAttributedString(fallbackText)
        }

        guard let data = try? Data(contentsOf: fileURL),
              let attributedText = try? NSAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.rtf],
                documentAttributes: nil
              ) else {
            return fallbackAttributedString(fallbackText)
        }

        return previewTextPreservingRichAttributes(attributedText)
    }

    private static func cacheKey(fileName: String, fileURL: URL) -> String {
        "\(fileName)|\(modificationStamp(for: fileURL))"
    }

    nonisolated private static func modificationStamp(for fileURL: URL) -> TimeInterval {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let modificationDate = attributes[.modificationDate] as? Date else {
            return 0
        }

        return modificationDate.timeIntervalSince1970
    }

    nonisolated private static func previewTextPreservingRichAttributes(
        _ attributedText: NSAttributedString
    ) -> NSAttributedString {
        let sourceText: NSAttributedString
        if attributedText.length > maxPreviewCharacters {
            let previewRange = NSRange(location: 0, length: maxPreviewCharacters)
            let truncatedText = NSMutableAttributedString(attributedString: attributedText.attributedSubstring(from: previewRange))
            truncatedText.append(
                NSAttributedString(
                    string: "…",
                    attributes: attributedText.attributes(
                        at: max(0, maxPreviewCharacters - 1),
                        effectiveRange: nil
                    )
                )
            )
            sourceText = truncatedText
        } else {
            sourceText = attributedText
        }

        let mutableText = NSMutableAttributedString(attributedString: sourceText)
        let fullRange = NSRange(location: 0, length: mutableText.length)
        mutableText.enumerateAttributes(in: fullRange) { attributes, range, _ in
            if attributes[.font] == nil {
                mutableText.addAttribute(
                    .font,
                    value: NSFont.systemFont(ofSize: 16, weight: .regular),
                    range: range
                )
            }

            if attributes[.foregroundColor] == nil {
                mutableText.addAttribute(
                    .foregroundColor,
                    value: NSColor.labelColor,
                    range: range
                )
            }
        }
        return mutableText
    }

    nonisolated private static func highlighted(
        _ attributedText: NSAttributedString,
        searchQuery: String
    ) -> NSAttributedString {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return attributedText
        }

        let mutableText = NSMutableAttributedString(attributedString: attributedText)
        let fullText = mutableText.string as NSString
        var searchRange = NSRange(location: 0, length: fullText.length)

        while searchRange.length > 0 {
            let matchRange = fullText.range(
                of: query,
                options: [.caseInsensitive, .diacriticInsensitive],
                range: searchRange
            )
            guard matchRange.location != NSNotFound else {
                break
            }

            mutableText.addAttribute(
                .backgroundColor,
                value: NSColor.systemYellow.withAlphaComponent(0.55),
                range: matchRange
            )

            let nextLocation = matchRange.location + max(matchRange.length, 1)
            searchRange = NSRange(
                location: nextLocation,
                length: max(0, fullText.length - nextLocation)
            )
        }

        return mutableText
    }

    nonisolated static func fallbackAttributedString(_ text: String) -> NSAttributedString {
        NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.systemFont(ofSize: 16, weight: .regular),
                .foregroundColor: NSColor(red: 0.12, green: 0.14, blue: 0.17, alpha: 1)
            ]
        )
    }
}

private struct FileCardDragSourceView: NSViewRepresentable {
    let item: HistoryPreviewItem
    let onClick: () -> Void
    let onDoubleClick: () -> Void
    let onRightMouseDown: () -> Void
    let onMenu: () -> NSMenu
    let onInvalid: () -> Void
    let onPartial: () -> Void
    let onHoverChanged: (Bool) -> Void
    let onPressChanged: (Bool) -> Void
    let onMouseExitedWindow: () -> Void

    func makeNSView(context: Context) -> FileCardDragSourceNSView {
        let view = FileCardDragSourceNSView()
        view.item = item
        view.onClick = onClick
        view.onDoubleClick = onDoubleClick
        view.onRightMouseDown = onRightMouseDown
        view.onMenu = onMenu
        view.onInvalid = onInvalid
        view.onPartial = onPartial
        view.onHoverChanged = onHoverChanged
        view.onPressChanged = onPressChanged
        view.onMouseExitedWindow = onMouseExitedWindow
        return view
    }

    func updateNSView(_ nsView: FileCardDragSourceNSView, context: Context) {
        nsView.item = item
        nsView.onClick = onClick
        nsView.onDoubleClick = onDoubleClick
        nsView.onRightMouseDown = onRightMouseDown
        nsView.onMenu = onMenu
        nsView.onInvalid = onInvalid
        nsView.onPartial = onPartial
        nsView.onHoverChanged = onHoverChanged
        nsView.onPressChanged = onPressChanged
        nsView.onMouseExitedWindow = onMouseExitedWindow
    }

    static func dismantleNSView(_ nsView: FileCardDragSourceNSView, coordinator: ()) {
        nsView.removeMonitor()
    }
}

private typealias CardDragSourceView = FileCardDragSourceView

private final class CardDragPasteboardWriter: NSObject, NSPasteboardWriting {
    private let fileURL: URL?
    private let fallbackText: String

    init(fileURL: URL?, fallbackText: String) {
        self.fileURL = fileURL
        self.fallbackText = fallbackText
        super.init()
    }

    func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
        var types: [NSPasteboard.PasteboardType] = []
        if let fileURL {
            types.append(contentsOf: (fileURL as NSURL).writableTypes(for: pasteboard))
        }
        types.append(.string)
        return Array(NSOrderedSet(array: types)) as? [NSPasteboard.PasteboardType] ?? types
    }

    func pasteboardPropertyList(
        forType type: NSPasteboard.PasteboardType
    ) -> Any? {
        if let fileURL,
           (fileURL as NSURL).writableTypes(for: NSPasteboard(name: .drag)).contains(type),
           let propertyList = (fileURL as NSURL).pasteboardPropertyList(forType: type) {
            return propertyList
        }

        if type == .string {
            return fallbackText
        }

        return nil
    }
}

private final class FileCardDragSourceNSView: NSView, NSDraggingSource {
    private enum PendingCardDragPayload {
        case file([NSDraggingItem], fallbackIconName: String)
        case generic(NSDraggingItem, fallbackIconName: String)

        var draggingItems: [NSDraggingItem] {
            switch self {
            case .file(let items, _):
                items
            case .generic(let item, _):
                [item]
            }
        }

        var fallbackIconName: String {
            switch self {
            case .file(_, let fallbackIconName),
                 .generic(_, let fallbackIconName):
                fallbackIconName
            }
        }
    }

    var item: HistoryPreviewItem?
    var onClick: (() -> Void)?
    var onDoubleClick: (() -> Void)?
    var onRightMouseDown: (() -> Void)?
    var onMenu: (() -> NSMenu)?
    var onInvalid: (() -> Void)?
    var onPartial: (() -> Void)?
    var onHoverChanged: ((Bool) -> Void)?
    var onPressChanged: ((Bool) -> Void)?
    var onMouseExitedWindow: (() -> Void)?

    private var mouseDownEvent: NSEvent?
    private var trackingArea: NSTrackingArea?
    private var didNotifyMouseExitedWindow = false
    private var pendingDragPayload: PendingCardDragPayload?
    private var didSelectForDrag = false
    private let clickMoveTolerance: CGFloat = 5
    private let dragStartDistance: CGFloat = 4
    private let dragPreviewController = CardDragPreviewWindowController()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }

    func removeMonitor() {
        mouseDownEvent = nil
        pendingDragPayload = nil
        didSelectForDrag = false
        resetTransientInteractionState()
        dragPreviewController.finish()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .enabledDuringMouseDrag, .inVisibleRect],
            owner: self
        )
        trackingArea = area
        addTrackingArea(area)
    }

    override func mouseEntered(with event: NSEvent) {
        onHoverChanged?(true)
    }

    override func mouseMoved(with event: NSEvent) {
        onHoverChanged?(bounds.contains(convert(event.locationInWindow, from: nil)))
    }

    override func mouseExited(with event: NSEvent) {
        resetTransientInteractionState()
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownEvent = event
        onPressChanged?(true)
    }

    override func mouseDragged(with event: NSEvent) {
        handleDrag(event)
        updateFloatingDragIfNeeded(event)
        startNativeDragIfNeeded(event)
    }

    override func mouseUp(with event: NSEvent) {
        guard let startingEvent = mouseDownEvent else {
            pendingDragPayload = nil
            didSelectForDrag = false
            dragPreviewController.finish()
            resetTransientInteractionState()
            return
        }

        mouseDownEvent = nil
        pendingDragPayload = nil
        didSelectForDrag = false
        dragPreviewController.finish()
        resetTransientInteractionState()
        let deltaX = event.locationInWindow.x - startingEvent.locationInWindow.x
        let deltaY = event.locationInWindow.y - startingEvent.locationInWindow.y
        guard hypot(deltaX, deltaY) <= clickMoveTolerance else {
            return
        }

        if event.clickCount >= 2 {
            onDoubleClick?()
        } else {
            onClick?()
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        resetTransientInteractionState()
        onRightMouseDown?()
        guard let menu = onMenu?() else {
            return
        }

        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    private func handleDrag(_ event: NSEvent) {
        guard let mouseDownEvent,
              let item,
              isDraggableCard(item),
              draggableText(for: item) != nil,
              pendingDragPayload == nil,
              shouldStartDrag(from: mouseDownEvent, to: event) else {
            return
        }

        onPressChanged?(false)
        if !didSelectForDrag {
            didSelectForDrag = true
            onClick?()
        }
        didNotifyMouseExitedWindow = false
        if item.type == .file {
            pendingDragPayload = prepareFileDragPayload(with: event)
        } else if item.type == .image {
            pendingDragPayload = prepareImageDragPayload()
        } else {
            pendingDragPayload = prepareTextDragPayload(text: draggableText(for: item) ?? "")
        }

        if let payload = pendingDragPayload {
            startFloatingPreview(with: event, fallbackIconName: payload.fallbackIconName)
        }
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        .copy
    }

    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool {
        true
    }

    func draggingSession(_ session: NSDraggingSession, movedTo screenPoint: NSPoint) {
        let isInsideSourceCard = isScreenPointInsideSourceCard(screenPoint)
        dragPreviewController.update(mouseScreenLocation: screenPoint, isInsideSourceCard: isInsideSourceCard)
        notifyWindowExitIfNeeded(screenPoint)
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        pendingDragPayload = nil
        didSelectForDrag = false
        dragPreviewController.finish()
        resetTransientInteractionState()
    }

    private func shouldStartDrag(from startEvent: NSEvent, to event: NSEvent) -> Bool {
        let deltaX = event.locationInWindow.x - startEvent.locationInWindow.x
        let deltaY = event.locationInWindow.y - startEvent.locationInWindow.y
        return hypot(deltaX, deltaY) >= dragStartDistance
    }

    private func resetTransientInteractionState() {
        onPressChanged?(false)
        onHoverChanged?(false)
    }

    private func updateFloatingDragIfNeeded(_ event: NSEvent) {
        guard pendingDragPayload != nil else {
            return
        }

        let screenPoint = window?.convertPoint(toScreen: event.locationInWindow) ?? NSEvent.mouseLocation
        dragPreviewController.update(
            mouseScreenLocation: screenPoint,
            isInsideSourceCard: isScreenPointInsideSourceCard(screenPoint)
        )
    }

    private func startNativeDragIfNeeded(_ event: NSEvent) {
        guard let pendingDragPayload,
              isMouseEventOutsideWindow(event) else {
            return
        }

        startNativeDrag(payload: pendingDragPayload, event: event)
    }

    private func startNativeDrag(payload: PendingCardDragPayload, event: NSEvent) {
        guard isMouseEventOutsideWindow(event) else {
            return
        }

        let draggingItems = payload.draggingItems
        let screenPoint = window?.convertPoint(toScreen: event.locationInWindow) ?? NSEvent.mouseLocation
        self.pendingDragPayload = nil
        self.mouseDownEvent = nil
        setDragFrames(for: draggingItems, dragImage: transparentDragImage(), event: event)
        beginDraggingSession(with: draggingItems, event: event, source: self)
        notifyWindowExitIfNeeded(screenPoint)
    }

    private func prepareFileDragPayload(with event: NSEvent) -> PendingCardDragPayload? {
        let result = validFileDragURLs(for: item)
        let fallbackText = fileFallbackText(for: item)
        guard !result.urls.isEmpty else {
            onInvalid?()
            guard !fallbackText.isEmpty else {
                return nil
            }

            return prepareFileFallbackTextDragPayload(text: fallbackText)
        }

        if result.hasInvalidReferences {
            onPartial?()
        }

        let draggingItems = result.urls.map { url in
            _ = NSDraggingItem(pasteboardWriter: url as NSURL)
            return NSDraggingItem(
                pasteboardWriter: CardDragPasteboardWriter(fileURL: url, fallbackText: fallbackText)
            )
        }
        return .file(draggingItems, fallbackIconName: result.urls.count > 1 ? "doc.on.doc.fill" : "doc.fill")
    }

    private func prepareFileFallbackTextDragPayload(text: String) -> PendingCardDragPayload {
        let draggingItem = NSDraggingItem(
            pasteboardWriter: CardDragPasteboardWriter(fileURL: nil, fallbackText: text)
        )
        return .generic(draggingItem, fallbackIconName: "doc.fill")
    }

    private func prepareImageDragPayload() -> PendingCardDragPayload? {
        guard let item,
              let imageFileName = item.imageFileName,
              let imageURL = try? ClipEaseStoragePaths.imageFileURL(fileName: imageFileName) else {
            return nil
        }

        let draggingItem = NSDraggingItem(
            pasteboardWriter: CardDragPasteboardWriter(fileURL: imageURL, fallbackText: imageURL.path)
        )
        return .generic(draggingItem, fallbackIconName: "photo.fill")
    }

    private func prepareTextDragPayload(text: String) -> PendingCardDragPayload? {
        guard !text.isEmpty else {
            return nil
        }

        let draggingItem = NSDraggingItem(
            pasteboardWriter: CardDragPasteboardWriter(fileURL: nil, fallbackText: text)
        )
        return .generic(draggingItem, fallbackIconName: "text.alignleft")
    }

    private func startFloatingPreview(with event: NSEvent, fallbackIconName: String) {
        let screenPoint = window?.convertPoint(toScreen: event.locationInWindow) ?? NSEvent.mouseLocation
        dragPreviewController.show(
            image: cardDragImage(fallbackIconName: fallbackIconName),
            mouseScreenLocation: screenPoint,
            isInsideSourceCard: true
        )
    }

    private func setDragFrames(
        for draggingItems: [NSDraggingItem],
        dragImage: NSImage,
        event: NSEvent
    ) {
        let imageSize = dragImage.size
        let location = convert(event.locationInWindow, from: nil)
        let frame = NSRect(
            x: location.x - imageSize.width / 2,
            y: location.y - imageSize.height / 2,
            width: imageSize.width,
            height: imageSize.height
        )

        draggingItems.forEach { draggingItem in
            draggingItem.setDraggingFrame(frame, contents: dragImage)
        }
    }

    private func isDraggableCard(_ item: HistoryPreviewItem) -> Bool {
        switch item.type {
        case .text, .link, .color, .file, .image:
            true
        }
    }

    private func validFileDragURLs(for item: HistoryPreviewItem?) -> (urls: [URL], hasInvalidReferences: Bool) {
        guard let item,
              item.type == .file else {
            return ([], false)
        }

        var hasInvalidReferences = false
        let urls = item.filePreviewReferences.compactMap { reference -> URL? in
            guard !reference.path.isEmpty else {
                hasInvalidReferences = true
                return nil
            }

            let url = URL(fileURLWithPath: reference.path).standardizedFileURL
            guard FileManager.default.fileExists(atPath: url.path) else {
                hasInvalidReferences = true
                return nil
            }

            return url
        }

        return (urls, hasInvalidReferences)
    }

    private func draggableText(for item: HistoryPreviewItem) -> String? {
        let text: String
        switch item.type {
        case .text, .link, .color:
            text = item.preview
        case .file:
            text = fileFallbackText(for: item)
        case .image:
            guard let imageFileName = item.imageFileName,
                  let imageURL = try? ClipEaseStoragePaths.imageFileURL(fileName: imageFileName) else {
                return nil
            }
            text = imageURL.path
        }

        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedText.isEmpty ? nil : text
    }

    private func fileFallbackText(for item: HistoryPreviewItem?) -> String {
        guard let item else {
            return ""
        }

        let referenceText = item.filePreviewReferences
            .map { reference in
                let path = reference.path.trimmingCharacters(in: .whitespacesAndNewlines)
                if !path.isEmpty {
                    return path
                }
                return reference.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

        if !referenceText.isEmpty {
            return referenceText
        }

        return item.preview.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func cardDragImage(fallbackIconName: String) -> NSImage {
        if let snapshot = snapshotDragImage() {
            return snapshot
        }

        return fallbackDragImage(iconName: fallbackIconName)
    }

    private func transparentDragImage() -> NSImage {
        return NSImage(size: NSSize(width: 1, height: 1))
    }

    private func snapshotDragImage() -> NSImage? {
        guard bounds.width > 0,
              bounds.height > 0,
              let contentView = window?.contentView else {
            return nil
        }

        let windowRect = convert(bounds, to: nil)
        let contentRect = contentView.convert(windowRect, from: nil)
        guard let bitmap = contentView.bitmapImageRepForCachingDisplay(in: contentRect) else {
            return nil
        }

        contentView.cacheDisplay(in: contentRect, to: bitmap)

        let shadowPadding: CGFloat = 16
        let sourceSize = bounds.size
        let targetSize = NSSize(
            width: floor(sourceSize.width),
            height: floor(sourceSize.height)
        )
        let canvasSize = NSSize(
            width: targetSize.width + shadowPadding * 2,
            height: targetSize.height + shadowPadding * 2
        )
        let image = NSImage(size: canvasSize)
        image.lockFocus()

        if let context = NSGraphicsContext.current?.cgContext {
            context.setShadow(
                offset: CGSize(width: 0, height: -8),
                blur: 18,
                color: NSColor.black.withAlphaComponent(0.22).cgColor
            )
        }

        let imageRect = NSRect(
            x: shadowPadding,
            y: shadowPadding,
            width: targetSize.width,
            height: targetSize.height
        )
        let path = NSBezierPath(roundedRect: imageRect, xRadius: 8, yRadius: 8)
        path.addClip()
        bitmap.draw(
            in: imageRect,
            from: .zero,
            operation: .sourceOver,
            fraction: 0.86,
            respectFlipped: true,
            hints: nil
        )

        image.unlockFocus()
        image.size = canvasSize
        return image
    }

    private func fallbackDragImage(iconName: String) -> NSImage {
        let size = NSSize(width: 92, height: 76)
        let image = NSImage(size: size)
        image.lockFocus()

        if let context = NSGraphicsContext.current?.cgContext {
            context.setShadow(
                offset: CGSize(width: 0, height: -5),
                blur: 12,
                color: NSColor.black.withAlphaComponent(0.18).cgColor
            )
        }

        let cardRect = NSRect(x: 10, y: 10, width: 72, height: 56)
        NSColor.windowBackgroundColor.withAlphaComponent(0.82).setFill()
        NSBezierPath(roundedRect: cardRect, xRadius: 8, yRadius: 8).fill()

        let symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 36, weight: .semibold)
        let symbol = NSImage(systemSymbolName: iconName, accessibilityDescription: nil)?
            .withSymbolConfiguration(symbolConfiguration)
        symbol?.draw(
            in: NSRect(x: 28, y: 20, width: 36, height: 36),
            from: .zero,
            operation: .sourceOver,
            fraction: 0.82
        )

        image.unlockFocus()
        return image
    }

    private func isScreenPointInsideSourceCard(_ screenPoint: NSPoint) -> Bool {
        guard let window else {
            return false
        }

        let windowPoint = window.convertPoint(fromScreen: screenPoint)
        let localPoint = convert(windowPoint, from: nil)
        return bounds.contains(localPoint)
    }

    private func notifyWindowExitIfNeeded(_ screenPoint: NSPoint) {
        guard !didNotifyMouseExitedWindow,
              let window,
              !window.frame.contains(screenPoint) else {
            return
        }

        didNotifyMouseExitedWindow = true
        onMouseExitedWindow?()
    }

    private func isMouseEventOutsideWindow(_ event: NSEvent) -> Bool {
        guard let window else {
            return true
        }

        let screenPoint = window.convertPoint(toScreen: event.locationInWindow)
        return !window.frame.contains(screenPoint)
    }
}

@MainActor
private final class CardDragPreviewWindowController {
    private var panel: NSPanel?
    private var imageView: NSImageView?
    private var currentImageSize: NSSize = .zero
    private var lastInsideSourceCard: Bool?
    private let shadowPadding: CGFloat = 18

    func show(image: NSImage, mouseScreenLocation: NSPoint, isInsideSourceCard: Bool) {
        currentImageSize = image.size
        let imageView = NSImageView(image: image)
        imageView.imageScaling = .scaleAxesIndependently
        imageView.wantsLayer = true
        imageView.layer?.masksToBounds = false
        self.imageView = imageView

        let frame = frame(
            mouseScreenLocation: mouseScreenLocation,
            isInsideSourceCard: isInsideSourceCard
        )
        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.contentView = imageView
        panel.orderFrontRegardless()
        self.panel = panel
        lastInsideSourceCard = isInsideSourceCard
    }

    func update(mouseScreenLocation: NSPoint, isInsideSourceCard: Bool) {
        guard let panel else {
            return
        }

        let nextFrame = frame(
            mouseScreenLocation: mouseScreenLocation,
            isInsideSourceCard: isInsideSourceCard
        )
        guard lastInsideSourceCard != isInsideSourceCard else {
            panel.setFrame(nextFrame, display: false)
            return
        }

        lastInsideSourceCard = isInsideSourceCard
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.08
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(nextFrame, display: false)
        }
    }

    func finish() {
        panel?.orderOut(nil)
        panel = nil
        imageView = nil
        currentImageSize = .zero
        lastInsideSourceCard = nil
    }

    private func frame(mouseScreenLocation: NSPoint, isInsideSourceCard: Bool) -> NSRect {
        let scale: CGFloat = isInsideSourceCard ? 1.06 : 0.48
        let size = NSSize(
            width: max(1, currentImageSize.width * scale),
            height: max(1, currentImageSize.height * scale)
        )
        return NSRect(
            x: mouseScreenLocation.x - size.width / 2,
            y: mouseScreenLocation.y - size.height / 2 + shadowPadding,
            width: size.width,
            height: size.height
        )
    }
}

private extension NSImage {
    func clipeaseCardThumbnail(maxPixelSize: CGSize) -> NSImage? {
        guard let source = cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let sourceWidth = CGFloat(source.width)
        let sourceHeight = CGFloat(source.height)
        guard sourceWidth > 0, sourceHeight > 0 else {
            return nil
        }

        let scale = min(maxPixelSize.width / sourceWidth, maxPixelSize.height / sourceHeight, 1)
        let targetSize = NSSize(
            width: max(1, floor(sourceWidth * scale)),
            height: max(1, floor(sourceHeight * scale))
        )
        let thumbnail = NSImage(size: targetSize)
        thumbnail.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        NSImage(cgImage: source, size: NSSize(width: sourceWidth, height: sourceHeight))
            .draw(
                in: NSRect(origin: .zero, size: targetSize),
                from: NSRect(origin: .zero, size: NSSize(width: sourceWidth, height: sourceHeight)),
                operation: .copy,
                fraction: 1
            )
        thumbnail.unlockFocus()
        return thumbnail
    }
}
