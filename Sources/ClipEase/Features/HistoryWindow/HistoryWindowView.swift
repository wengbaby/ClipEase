import SwiftUI

struct HistoryWindowView: View {
    @ObservedObject var store: ClipboardHistoryStore
    let pasteExecutor: PasteExecutor
    let onClose: () -> Void

    @State private var selectedItemID: HistoryPreviewItem.ID?

    private var items: [HistoryPreviewItem] {
        store.items.map(HistoryPreviewItem.init)
    }

    var body: some View {
        ZStack {
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .ignoresSafeArea()

            Button(action: { copyItem(selectedItemID) }) {
                EmptyView()
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.return, modifiers: [])
            .frame(width: 0, height: 0)
            .opacity(0)

            VStack(alignment: .leading, spacing: 14) {
                toolbar

                if items.isEmpty {
                    emptyState
                } else {
                    ScrollViewReader { proxy in
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 20) {
                                ForEach(items) { item in
                                    HistoryCardView(
                                        item: item,
                                        isSelected: selectedItemID == item.id
                                    )
                                    .id(item.id)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        select(item.id, proxy: proxy)
                                    }
                                    .onTapGesture(count: 2) {
                                        copyItem(item.id)
                                    }
                                }
                            }
                            .padding(.horizontal, 28)
                            .padding(.vertical, 8)
                            .padding(.bottom, 22)
                        }
                    }
                }
            }
            .padding(.top, 18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .focusable()
        .onAppear {
            selectedItemID = items.first?.id
        }
        .onChange(of: store.items) { newItems in
            guard let firstItem = newItems.first else {
                selectedItemID = nil
                return
            }

            if selectedItemID == nil || !newItems.contains(where: { $0.id == selectedItemID }) {
                selectedItemID = firstItem.id
            }
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

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 42, weight: .regular))
                .foregroundStyle(Color(red: 0.18, green: 0.55, blue: 1.0))

            Text("复制一段文字后会显示在这里")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 32)
    }

    private func select(_ id: HistoryPreviewItem.ID, proxy: ScrollViewProxy) {
        selectedItemID = id
        withAnimation(.easeOut(duration: 0.16)) {
            proxy.scrollTo(id, anchor: .center)
        }
    }

    private func moveSelection(_ direction: MoveCommandDirection) {
        guard let selectedItemID,
              let selectedIndex = items.firstIndex(where: { $0.id == selectedItemID }) else {
            self.selectedItemID = items.first?.id
            return
        }

        switch direction {
        case .left:
            self.selectedItemID = items[max(selectedIndex - 1, 0)].id
        case .right:
            self.selectedItemID = items[min(selectedIndex + 1, items.count - 1)].id
        default:
            break
        }
    }

    private func copyItem(_ id: ClipboardItem.ID?) {
        guard let item = store.item(with: id) else {
            return
        }

        pasteExecutor.copyToPasteboard(item)
    }
}
