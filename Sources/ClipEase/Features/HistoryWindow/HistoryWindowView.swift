import SwiftUI

struct HistoryWindowView: View {
    @ObservedObject var store: ClipboardHistoryStore
    let pasteExecutor: PasteExecutor
    let onClose: () -> Void

    @State private var selectedItemID: HistoryPreviewItem.ID?
    @State private var statusText: String?
    @State private var searchText = ""
    @State private var isSearchVisible = false
    @State private var filter: HistoryFilter = .all

    private var items: [HistoryPreviewItem] {
        store.items.map(HistoryPreviewItem.init)
    }

    private var filteredItems: [HistoryPreviewItem] {
        let filteredByType = items.filter { item in
            switch filter {
            case .all:
                true
            case .text:
                item.type == .text
            case .link:
                item.type == .link
            case .pinned:
                item.isPinned
            }
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return filteredByType
        }

        return filteredByType.filter { item in
            item.searchText.localizedCaseInsensitiveContains(query)
        }
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
                } else if filteredItems.isEmpty {
                    emptySearchState
                } else {
                    ScrollViewReader { proxy in
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 20) {
                                ForEach(filteredItems) { item in
                                    HistoryCardView(
                                        item: item,
                                        isSelected: selectedItemID == item.id
                                    )
                                    .id(item.id)
                                    .contentShape(Rectangle())
                                    .highPriorityGesture(
                                        immediateSelectionGesture(for: item),
                                        including: .all
                                    )
                                    .contextMenu {
                                        Button("复制") {
                                            copyItem(item.id)
                                        }

                                        Button(item.isPinned ? "取消置顶" : "置顶") {
                                            togglePinned(item.id)
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
                        .onChange(of: selectedItemID) { id in
                            guard let id else {
                                return
                            }

                            withAnimation(.easeOut(duration: 0.12)) {
                                proxy.scrollTo(id, anchor: .center)
                            }
                        }
                    }
                }
            }
            .padding(.top, 18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .focusable()
        .onAppear {
            selectedItemID = filteredItems.first?.id
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
        .onChange(of: searchText) { _ in
            ensureSelectionInFilteredItems()
        }
        .onChange(of: filter) { _ in
            ensureSelectionInFilteredItems()
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

            if isSearchVisible {
                TextField("搜索", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(width: 220)
                    .background(Color.white.opacity(0.72))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            Button(action: toggleSearch) {
                Image(systemName: isSearchVisible ? "xmark" : "magnifyingglass")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)

            Menu {
                ForEach(HistoryFilter.allCases) { filter in
                    Button(filter.title) {
                        self.filter = filter
                    }
                }
            } label: {
                Text(filter.title)
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.55))
                    .clipShape(Capsule())
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
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

    private var emptySearchState: some View {
        VStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 38, weight: .regular))
                .foregroundStyle(Color(red: 0.18, green: 0.55, blue: 1.0))

            Text("没有找到匹配的历史")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 32)
    }

    private func moveSelection(_ direction: MoveCommandDirection) {
        guard let currentSelectedID = selectedItemID,
              let selectedIndex = filteredItems.firstIndex(where: { $0.id == currentSelectedID }) else {
            self.selectedItemID = filteredItems.first?.id
            return
        }

        let nextID: HistoryPreviewItem.ID
        switch direction {
        case .left:
            nextID = filteredItems[max(selectedIndex - 1, 0)].id
        case .right:
            nextID = filteredItems[min(selectedIndex + 1, filteredItems.count - 1)].id
        default:
            return
        }

        selectedItemID = nextID
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

    private func togglePinned(_ id: ClipboardItem.ID?) {
        guard let item = store.item(with: id) else {
            return
        }

        store.togglePinned(for: id)
        showStatus(item.isPinned ? "已取消置顶" : "已置顶")
    }

    private func immediateSelectionGesture(for item: HistoryPreviewItem) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                if selectedItemID != item.id {
                    selectedItemID = item.id
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

    private func toggleSearch() {
        if isSearchVisible {
            searchText = ""
            isSearchVisible = false
        } else {
            isSearchVisible = true
        }
    }

    private func ensureSelectionInFilteredItems() {
        if let selectedItemID,
           filteredItems.contains(where: { $0.id == selectedItemID }) {
            return
        }

        selectedItemID = filteredItems.first?.id
    }
}

private enum HistoryFilter: String, CaseIterable, Identifiable {
    case all
    case text
    case link
    case pinned

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .all:
            "全部"
        case .text:
            "文字"
        case .link:
            "链接"
        case .pinned:
            "置顶"
        }
    }
}
