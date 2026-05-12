import AppKit
import SwiftUI

struct HistoryPreviewPopoverView: View {
    let item: ClipboardItem
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
    @State private var previewImage: NSImage?

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

            Divider()

            footer
        }
        .frame(width: size.width, height: size.height)
        .background(Color(red: 0.94, green: 0.95, blue: 0.98))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .shadow(color: .black.opacity(0.22), radius: 24, x: 0, y: 12)
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
                Button("在 Finder 中显示", action: onReveal)
                Button("复制图片路径", action: onCopyPath)
            case .color:
                Button("复制 HEX", action: onCopy)
                Button("复制 RGB", action: onCopyRGB)
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
                LazyPreviewTextView(text: item.text)
                    .background(Color.white)
            } else {
                previewPlaceholder
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
            ZStack {
                CheckerboardView()

                if isContentReady, let image = previewImage {
                    ScrollableImagePreview(image: image)
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 52, weight: .regular))
                        .foregroundStyle(Color(red: 0.18, green: 0.55, blue: 1.0))
                }
            }
            .background(Color.white)
            .task(id: isContentReady) {
                guard isContentReady, item.type == .image else {
                    previewImage = nil
                    return
                }

                previewImage = await loadImage()
            }
        }
    }

    private var previewPlaceholder: some View {
        ZStack {
            Color.white

            ProgressView()
                .controlSize(.small)
        }
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

    private var footer: some View {
        HStack {
            Text(item.footer)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)

            Spacer()

            Text(item.relativeTime)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func loadImage() async -> NSImage? {
        guard let imageFileName = item.imageFileName,
              let imageURL = try? ClipEaseStoragePaths.imageFileURL(fileName: imageFileName) else {
            return nil
        }

        let data = await Task.detached(priority: .utility) {
            try? Data(contentsOf: imageURL)
        }.value

        guard let data else {
            return nil
        }

        return NSImage(data: data)
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
