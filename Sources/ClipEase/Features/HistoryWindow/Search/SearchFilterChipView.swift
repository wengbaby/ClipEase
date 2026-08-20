import AppKit
import SwiftUI

struct SearchFilterChipIcon: View {
    let systemImage: String?
    let iconFileName: String?
    let fallbackSystemImage: String

    @State private var icon: NSImage?
    @State private var representedFileName: String?

    var body: some View {
        Group {
            if let icon {
                Image(nsImage: ClipEaseAppIcon.roundedImage(icon, size: NSSize(width: 13, height: 13)))
                    .resizable()
                    .frame(width: 13, height: 13)
            } else {
                Image(systemName: systemImage ?? fallbackSystemImage)
                    .font(.system(size: 12, weight: .medium))
            }
        }
        .task(id: iconFileName) {
            await loadIconIfNeeded()
        }
    }

    @MainActor
    private func loadIconIfNeeded() async {
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

        guard let request = HistoryImageAssetRequest.sourceIcon(
            fileName: iconFileName,
            priority: .visible
        ) else {
            return
        }

        let asset = try? await HistoryImageAssetLoader.shared.loadVisible(request)
        guard !Task.isCancelled,
              representedFileName == iconFileName else {
            return
        }
        icon = asset?.image
    }
}

struct SearchFilterChip: View {
    let title: String
    var systemImage: String? = nil
    var iconFileName: String? = nil
    var fallbackSystemImage: String = "circle"
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                SearchFilterChipIcon(
                    systemImage: systemImage,
                    iconFileName: iconFileName,
                    fallbackSystemImage: fallbackSystemImage
                )

                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .foregroundStyle(isSelected ? .white : .secondary)
            .background(isSelected ? Color(red: 0.18, green: 0.55, blue: 1.0) : Color.black.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct SearchFilterSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                content
            }
        }
    }
}

struct SearchFilterChipGrid<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(minimum: 118), spacing: 8), count: 3),
            alignment: .leading,
            spacing: 8
        ) {
            content
        }
    }
}
