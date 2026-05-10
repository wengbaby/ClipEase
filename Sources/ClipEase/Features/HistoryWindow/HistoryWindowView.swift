import SwiftUI

struct HistoryWindowView: View {
    let onClose: () -> Void

    private let sampleItems = HistoryPreviewItem.samples

    var body: some View {
        ZStack {
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 14) {
                toolbar

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 18) {
                        ForEach(sampleItems) { item in
                            HistoryCardView(item: item)
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.bottom, 24)
                }
            }
            .padding(.top, 18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Text("轻贴")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)

            Spacer()

            Button(action: {}) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)

            Button(action: {}) {
                Text("全部")
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.55))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 22)
    }
}
