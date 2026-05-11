import SwiftUI
import AppKit

struct HistoryCardView: View {
    let item: HistoryPreviewItem
    let isSelected: Bool
    let searchQuery: String
    let shortcutNumber: Int?
    let isShortcutOverlayVisible: Bool

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
                    }

                    Text(item.time)
                        .font(.system(size: 13, weight: .medium))
                }

                Spacer()

                sourceIcon
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
            .background(item.headerColor)

            preview
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.white)

            Text(item.footer)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.white)
        }
        .frame(width: 250, height: 270)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isSelected ? Color(red: 0.18, green: 0.55, blue: 1.0) : Color.black.opacity(0.08), lineWidth: isSelected ? 4 : 1)
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
                    .scaleEffect(isShortcutOverlayVisible ? 1 : 0.86)
                    .animation(.easeOut(duration: 0.12), value: isShortcutOverlayVisible)
            }
        }
        .shadow(
            color: .black.opacity(isSelected ? 0.14 : 0.08),
            radius: isSelected ? 12 : 8,
            x: 0,
            y: isSelected ? 5 : 3
        )
    }

    private var sourceIcon: some View {
        ZStack {
            if let icon = loadSourceIcon() {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 64, height: 64)
            } else {
                Image(systemName: item.iconName)
                    .font(.system(size: 34, weight: .semibold))
            }
        }
        .frame(width: 64, height: 64)
        .help(item.sourceAppName)
    }

    @ViewBuilder
    private var preview: some View {
        switch item.type {
        case .text:
            highlightedText(item.preview, baseColor: Color(red: 0.12, green: 0.14, blue: 0.17))
                .font(.system(size: 16, weight: .regular))
                .lineLimit(7)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(16)
        case .link:
            linkPreview
        case .image:
            imagePreview
        case .color:
            colorPreview
        }
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

            if let image = loadImage() {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(10)
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 58, weight: .regular))
                    .foregroundStyle(Color(red: 0.18, green: 0.55, blue: 1.0))
            }
        }
    }

    private var linkPreview: some View {
        VStack(spacing: 0) {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.98, green: 0.99, blue: 1.0),
                        Color(red: 0.94, green: 0.96, blue: 0.99)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

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
                    .frame(width: 62, height: 62)
                    .overlay {
                        Image(systemName: "link")
                            .font(.system(size: 27, weight: .bold))
                            .foregroundStyle(.white)
                    }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.linkTitle ?? item.preview)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color(red: 0.16, green: 0.17, blue: 0.19))
                    .lineLimit(1)

                highlightedText(item.linkSubtitle ?? item.preview, baseColor: Color.secondary)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.white)
        }
    }

    private func loadImage() -> NSImage? {
        guard let imageFileName = item.imageFileName,
              let imageURL = try? ClipEaseStoragePaths.imageFileURL(fileName: imageFileName) else {
            return nil
        }

        return NSImage(contentsOf: imageURL)
    }

    private func loadSourceIcon() -> NSImage? {
        guard let iconFileName = item.iconFileName,
              let iconURL = try? ClipEaseStoragePaths.appIconFileURL(fileName: iconFileName) else {
            return nil
        }

        return NSImage(contentsOf: iconURL)
    }

    private func highlightedText(_ text: String, baseColor: Color) -> Text {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty,
              let range = text.range(
                of: query,
                options: [.caseInsensitive, .diacriticInsensitive]
              ) else {
            return Text(text).foregroundColor(baseColor)
        }

        let prefix = String(text[..<range.lowerBound])
        let match = String(text[range])
        let suffix = String(text[range.upperBound...])

        return Text(prefix).foregroundColor(baseColor)
            + Text(match)
                .foregroundColor(Color(red: 0.02, green: 0.42, blue: 0.95))
                .fontWeight(.bold)
            + Text(suffix).foregroundColor(baseColor)
    }

    private func rgbText(from components: ClipEaseColorComponents) -> String {
        let red = Int(round(components.red * 255))
        let green = Int(round(components.green * 255))
        let blue = Int(round(components.blue * 255))
        return "rgb(\(red), \(green), \(blue))"
    }
}
