import SwiftUI

struct HistoryCardView: View {
    let item: HistoryPreviewItem
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.kind)
                        .font(.system(size: 16, weight: .bold))
                    Text(item.time)
                        .font(.system(size: 13, weight: .medium))
                }

                Spacer()

                Image(systemName: item.iconName)
                    .font(.system(size: 27, weight: .semibold))
                    .frame(width: 50, height: 50)
                    .background(Color.white.opacity(0.86))
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
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
        .shadow(
            color: .black.opacity(isSelected ? 0.14 : 0.08),
            radius: isSelected ? 12 : 8,
            x: 0,
            y: isSelected ? 5 : 3
        )
    }

    @ViewBuilder
    private var preview: some View {
        switch item.type {
        case .text:
            Text(item.preview)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(Color(red: 0.12, green: 0.14, blue: 0.17))
                .lineLimit(7)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(16)
        case .link:
            linkPreview
        case .image:
            ZStack {
                CheckerboardView()
                Image(systemName: "photo")
                    .font(.system(size: 58, weight: .regular))
                    .foregroundStyle(Color(red: 0.18, green: 0.55, blue: 1.0))
            }
        case .color:
            ZStack {
                Color.gray
                Text(item.preview)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)
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

                Text(item.linkSubtitle ?? item.preview)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.white)
        }
    }
}
