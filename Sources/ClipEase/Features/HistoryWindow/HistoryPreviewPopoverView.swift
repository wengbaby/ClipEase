import AppKit
import SwiftUI

struct HistoryPreviewPopoverView: View {
    let item: ClipboardItem
    let onClose: () -> Void
    let onCopy: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider()

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            footer
        }
        .frame(width: 560, height: 310)
        .background(Color(red: 0.94, green: 0.95, blue: 0.98))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.22), radius: 24, x: 0, y: 12)
        .overlay(alignment: .bottom) {
            Triangle()
                .fill(Color(red: 0.94, green: 0.95, blue: 0.98))
                .frame(width: 26, height: 14)
                .offset(y: 14)
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

            Spacer()

            Button(action: onCopy) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 15, weight: .medium))
            }
            .buttonStyle(.plain)
            .help("复制")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var content: some View {
        switch item.type {
        case .text, .color:
            ScrollView {
                Text(item.text)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(Color(red: 0.12, green: 0.14, blue: 0.17))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(16)
            }
            .background(Color.white)
        case .link:
            VStack(alignment: .leading, spacing: 10) {
                Text(item.linkTitle ?? item.text)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color(red: 0.13, green: 0.14, blue: 0.16))
                    .lineLimit(2)

                Text(item.url?.absoluteString ?? item.text)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color(red: 0.18, green: 0.55, blue: 1.0))
                    .textSelection(.enabled)

                Spacer()
            }
            .padding(18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.white)
        case .image:
            ZStack {
                CheckerboardView()

                if let image = loadImage() {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding(12)
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 52, weight: .regular))
                        .foregroundStyle(Color(red: 0.18, green: 0.55, blue: 1.0))
                }
            }
            .background(Color.white)
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

    private func loadImage() -> NSImage? {
        guard let imageFileName = item.imageFileName,
              let imageURL = try? ClipEaseStoragePaths.imageFileURL(fileName: imageFileName) else {
            return nil
        }

        return NSImage(contentsOf: imageURL)
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
