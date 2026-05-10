import SwiftUI

struct HistoryWindowView: View {
    let onClose: () -> Void

    private let sampleItems = HistoryPreviewItem.samples
    @State private var selectedItemID: HistoryPreviewItem.ID?

    var body: some View {
        ZStack {
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 14) {
                toolbar

                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 18) {
                            ForEach(sampleItems) { item in
                                HistoryCardView(
                                    item: item,
                                    isSelected: selectedItemID == item.id
                                )
                                .id(item.id)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    select(item.id, proxy: proxy)
                                }
                            }
                        }
                        .padding(.horizontal, 22)
                        .padding(.bottom, 24)
                    }
                }
            }
            .padding(.top, 18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .focusable()
        .onAppear {
            selectedItemID = sampleItems.first?.id
        }
        .onMoveCommand { direction in
            moveSelection(direction)
        }
        .onExitCommand(perform: onClose)
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

    private func select(_ id: HistoryPreviewItem.ID, proxy: ScrollViewProxy) {
        selectedItemID = id
        withAnimation(.easeOut(duration: 0.16)) {
            proxy.scrollTo(id, anchor: .center)
        }
    }

    private func moveSelection(_ direction: MoveCommandDirection) {
        guard let selectedItemID,
              let selectedIndex = sampleItems.firstIndex(where: { $0.id == selectedItemID }) else {
            self.selectedItemID = sampleItems.first?.id
            return
        }

        switch direction {
        case .left:
            self.selectedItemID = sampleItems[max(selectedIndex - 1, 0)].id
        case .right:
            self.selectedItemID = sampleItems[min(selectedIndex + 1, sampleItems.count - 1)].id
        default:
            break
        }
    }
}
