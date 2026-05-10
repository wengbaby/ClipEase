import SwiftUI

struct HistoryWindowView: View {
    @ObservedObject var store: ClipboardHistoryStore
    @ObservedObject var recordingController: RecordingController
    let appMenuController: AppMenuController
    let pasteExecutor: PasteExecutor
    let onClose: () -> Void

    @State private var selectedItemID: HistoryPreviewItem.ID?
    @State private var statusText: String?
    @State private var searchText = ""
    @State private var isSearchVisible = false
    @State private var filter: HistoryFilter = .all
    @State private var canAutoPaste = false
    @State private var isClearConfirmationPresented = false

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
            case .image:
                item.type == .image
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

            Button(action: { pasteItem(selectedItemID) }) {
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
            canAutoPaste = pasteExecutor.canAutoPaste
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
        ZStack {
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

                autoPasteStatusButton

                Spacer()
            }

            HStack(spacing: 10) {
                searchField

                Button(action: toggleSearch) {
                    HStack(spacing: 5) {
                        Image(systemName: isSearchVisible ? "xmark" : "magnifyingglass")
                            .font(.system(size: 12, weight: .semibold))

                        Text("搜索")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.55))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.primary)

                filterMenu
            }

            HStack(spacing: 12) {
                moreMenu
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 22)
        .frame(height: 36)
    }

    private var filterMenu: some View {
        Menu {
            ForEach(HistoryFilter.allCases) { filter in
                Button(filter.title) {
                    self.filter = filter
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.system(size: 12, weight: .semibold))

                Text("筛选")
                    .font(.system(size: 12, weight: .medium))

                Text(filter.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.55))
            .clipShape(Capsule())
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var autoPasteStatusButton: some View {
        Button(action: openAccessibilitySettingsIfNeeded) {
            HStack(spacing: 5) {
                Image(systemName: canAutoPaste ? "keyboard.badge.eye" : "exclamationmark.lock")
                    .font(.system(size: 12, weight: .semibold))

                Text(canAutoPaste ? "自动粘贴" : "需授权")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(canAutoPaste ? Color(red: 0.18, green: 0.55, blue: 1.0) : Color(red: 0.78, green: 0.36, blue: 0.08))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.55))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(canAutoPaste ? "回车会自动粘贴到当前 App" : "点击打开辅助功能权限设置")
    }

    private var recordingStatusButton: some View {
        Button(action: toggleRecording) {
            HStack(spacing: 5) {
                Image(systemName: recordingController.isPaused ? "pause.circle.fill" : "record.circle")
                    .font(.system(size: 12, weight: .semibold))

                Text(recordingController.isPaused ? "已暂停" : "记录中")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(recordingController.isPaused ? Color(red: 0.78, green: 0.36, blue: 0.08) : Color(red: 0.18, green: 0.55, blue: 1.0))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.55))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(recordingController.isPaused ? "点击恢复记录" : "点击暂停记录")
    }

    private var retentionMenu: some View {
        Menu {
            ForEach(HistoryRetentionPolicy.allCases) { policy in
                Button {
                    store.retentionPolicy = policy
                    showStatus("保存期限：\(policy.shortTitle)")
                } label: {
                    HStack {
                        Text(policy.title)
                        if store.retentionPolicy == policy {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 12, weight: .semibold))

                Text(store.retentionPolicy.shortTitle)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(Color(red: 0.18, green: 0.55, blue: 1.0))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.55))
            .clipShape(Capsule())
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("设置普通历史保存期限，置顶内容不会自动清理")
    }

    private var searchField: some View {
        TextField("搜索", text: $searchText)
            .textFieldStyle(.plain)
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 10)
            .frame(width: 220, height: 30)
            .background(Color.white.opacity(isSearchVisible ? 0.72 : 0))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .opacity(isSearchVisible ? 1 : 0)
            .allowsHitTesting(isSearchVisible)
    }

    private var moreMenu: some View {
        Menu {
            Button("新建文本") {
                showStatus("新建文本稍后实现")
            }

            Divider()

            Button("帮助") {
                appMenuController.showHelp()
            }

            Button("设置") {
                appMenuController.showSettingsPlaceholder()
            }

            retentionSettingsMenu

            Divider()

            pauseMenu

            Divider()

            Button("清空历史", role: .destructive) {
                isClearConfirmationPresented = true
            }
            .disabled(store.items.isEmpty)

            Divider()

            Button("退出") {
                appMenuController.quit()
            }

            Button("关于轻贴") {
                appMenuController.showAbout()
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 24, height: 24)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .confirmationDialog(
            "清空全部历史？",
            isPresented: $isClearConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("清空历史", role: .destructive) {
                clearAllItems()
            }

            Button("取消", role: .cancel) {}
        } message: {
            Text("此操作会删除所有普通和置顶记录，以及已保存的图片文件。")
        }
        .help("更多操作")
    }

    private var retentionSettingsMenu: some View {
        Menu("保存期限") {
            ForEach(HistoryRetentionPolicy.allCases) { policy in
                Button {
                    store.retentionPolicy = policy
                    showStatus("保存期限：\(policy.shortTitle)")
                } label: {
                    HStack {
                        Text(policy.title)
                        if store.retentionPolicy == policy {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        }
    }

    private var pauseMenu: some View {
        Menu("暂停") {
            Button("暂停") {
                pauseRecording()
            }

            Button("暂停 15 分钟") {
                pauseRecording(for: 15 * 60, message: "已暂停 15 分钟")
            }

            Button("暂停 30 分钟") {
                pauseRecording(for: 30 * 60, message: "已暂停 30 分钟")
            }

            Button("暂停 1 小时") {
                pauseRecording(for: 60 * 60, message: "已暂停 1 小时")
            }

            Button("暂停 3 小时") {
                pauseRecording(for: 3 * 60 * 60, message: "已暂停 3 小时")
            }

            Button("暂停 6 小时") {
                pauseRecording(for: 6 * 60 * 60, message: "已暂停 6 小时")
            }

            Button("截止到今日") {
                appMenuController.pauseUntilEndOfToday()
                showStatus("已暂停到今日结束")
            }
        }
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

    private func pasteItem(_ id: ClipboardItem.ID?) {
        guard let item = store.item(with: id) else {
            return
        }

        canAutoPaste = pasteExecutor.canAutoPaste
        switch pasteExecutor.pasteToFrontmostApp(item) {
        case .copiedOnly:
            showStatus("已复制")
        case .pasted:
            showStatus("已粘贴")
        }
    }

    private func deleteItem(_ id: ClipboardItem.ID?) {
        store.deleteItem(with: id)
        showStatus("已删除")
    }

    private func clearAllItems() {
        store.clearAllItems()
        selectedItemID = nil
        showStatus("已清空")
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

    private func openAccessibilitySettingsIfNeeded() {
        canAutoPaste = pasteExecutor.canAutoPaste
        guard !canAutoPaste else {
            showStatus("自动粘贴已启用")
            return
        }

        pasteExecutor.openAccessibilitySettings()
        showStatus("请授权轻贴")
    }

    private func toggleRecording() {
        recordingController.togglePaused()
        showStatus(recordingController.isPaused ? "已暂停记录" : "已恢复记录")
    }

    private func pauseRecording() {
        appMenuController.pauseRecording()
        showStatus("已暂停记录")
    }

    private func pauseRecording(for interval: TimeInterval, message: String) {
        appMenuController.pauseRecording(for: interval)
        showStatus(message)
    }
}

private enum HistoryFilter: String, CaseIterable, Identifiable {
    case all
    case text
    case link
    case image
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
        case .image:
            "图片"
        case .pinned:
            "置顶"
        }
    }
}
