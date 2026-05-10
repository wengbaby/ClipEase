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
        .frame(width: 260, height: 280)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isSelected ? Color(red: 0.18, green: 0.55, blue: 1.0) : Color.black.opacity(0.08), lineWidth: isSelected ? 4 : 1)
        }
        .scaleEffect(isSelected ? 1.02 : 1.0)
        .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 4)
        .animation(.easeOut(duration: 0.12), value: isSelected)
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
}
