import SwiftUI

struct HistoryWindowView: View {
    @ObservedObject var store: ClipboardHistoryStore
    let pasteExecutor: PasteExecutor
    let onClose: () -> Void

    @State private var selectedItemID: HistoryPreviewItem.ID?
    @State private var statusText: String?

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
                                    .gesture(cardTapGesture(for: item, proxy: proxy))
                                    .contextMenu {
                                        Button("复制") {
                                            copyItem(item.id)
                                        }

                                        Button("删除", role: .destructive) {
                                            deleteItem(item.id)
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 28)
                            .padding(.vertical, 8)
                            .padding(.bottom, 22)
                        }
                        .onMoveCommand { direction in
                            moveSelection(direction, proxy: proxy)
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

            if let statusText {
                Text(statusText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(red: 0.18, green: 0.55, blue: 1.0))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.55))
                    .clipShape(Capsule())
            }

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

    private func moveSelection(
        _ direction: MoveCommandDirection,
        proxy: ScrollViewProxy
    ) {
        guard let currentSelectedID = selectedItemID,
              let selectedIndex = items.firstIndex(where: { $0.id == currentSelectedID }) else {
            self.selectedItemID = items.first?.id
            return
        }

        let nextID: HistoryPreviewItem.ID
        switch direction {
        case .left:
            nextID = items[max(selectedIndex - 1, 0)].id
        case .right:
            nextID = items[min(selectedIndex + 1, items.count - 1)].id
        default:
            return
        }

        selectedItemID = nextID
        withAnimation(.easeOut(duration: 0.12)) {
            proxy.scrollTo(nextID, anchor: .center)
        }
    }

    private func copyItem(_ id: ClipboardItem.ID?) {
        guard let item = store.item(with: id) else {
            return
        }

        pasteExecutor.copyToPasteboard(item)
        showStatus("已复制")
    }

    private func deleteItem(_ id: ClipboardItem.ID?) {
        store.deleteItem(with: id)
        showStatus("已删除")
    }

    private func cardTapGesture(
        for item: HistoryPreviewItem,
        proxy: ScrollViewProxy
    ) -> some Gesture {
        TapGesture(count: 2)
            .exclusively(before: TapGesture(count: 1))
            .onEnded { value in
                switch value {
                case .first:
                    selectedItemID = item.id
                    copyItem(item.id)
                case .second:
                    select(item.id, proxy: proxy)
                }
            }
    }

    private func showStatus(_ text: String) {
        statusText = text
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            if statusText == text {
                statusText = nil
            }
        }
    }
}
