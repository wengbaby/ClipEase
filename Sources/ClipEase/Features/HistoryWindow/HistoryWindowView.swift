import SwiftUI
import AppKit

struct HistoryWindowView: View {
    @ObservedObject var store: ClipboardHistoryStore
    @ObservedObject var previewState: HistoryPreviewState
    @ObservedObject var recordingController: RecordingController
    let appMenuController: AppMenuController
    let pasteExecutor: PasteExecutor
    let onClose: () -> Void
    let onPreview: (ClipboardItem, CGRect) -> Void
    let onClosePreview: () -> Void

    @State private var selectedItemID: HistoryPreviewItem.ID?
    @State private var statusText: String?
    @State private var searchText = ""
    @State private var isSearchVisible = false
    @State private var filter: HistoryFilter = .all
    @State private var canAutoPaste = false
    @State private var isClearConfirmationPresented = false
    @State private var cardFrames: [ClipboardItem.ID: CGRect] = [:]
    @State private var isCommandKeyPressed = false
    @FocusState private var isSearchFocused: Bool

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
            LinearGradient(
                colors: [
                    Color(red: 0.82, green: 0.77, blue: 0.94),
                    Color(red: 0.72, green: 0.84, blue: 0.92),
                    Color(red: 0.90, green: 0.78, blue: 0.92)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .ignoresSafeArea()

            Button(action: { pasteItem(selectedItemID) }) {
                EmptyView()
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.return, modifiers: [])
            .frame(width: 0, height: 0)
            .opacity(0)

            Button(action: togglePreviewForSelectedItem) {
                EmptyView()
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.space, modifiers: [])
            .frame(width: 0, height: 0)
            .opacity(0)

            Button(action: openSearch) {
                EmptyView()
            }
            .buttonStyle(.plain)
            .keyboardShortcut("f", modifiers: [.command])
            .frame(width: 0, height: 0)
            .opacity(0)

            Button(action: { copyItem(selectedItemID) }) {
                EmptyView()
            }
            .buttonStyle(.plain)
            .keyboardShortcut("c", modifiers: [.command])
            .frame(width: 0, height: 0)
            .opacity(0)

            Button(action: { deleteItem(selectedItemID) }) {
                EmptyView()
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.delete, modifiers: [])
            .frame(width: 0, height: 0)
            .opacity(0)

            Button(action: { togglePinned(selectedItemID) }) {
                EmptyView()
            }
            .buttonStyle(.plain)
            .keyboardShortcut("p", modifiers: [.command])
            .frame(width: 0, height: 0)
            .opacity(0)

            NumberShortcutHandler { isPressed in
                isCommandKeyPressed = isPressed
            } onNumber: { number in
                selectVisibleCard(number: number)
            }
            .frame(width: 0, height: 0)

            VStack(alignment: .leading, spacing: 14) {
                toolbar

                if items.isEmpty {
                    emptyState
                } else if filteredItems.isEmpty {
                    emptySearchState
                } else {
                    ScrollViewReader { proxy in
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(spacing: 20) {
                                ForEach(filteredItems) { item in
                                    HistoryCardView(
                                        item: item,
                                        isSelected: selectedItemID == item.id,
                                        searchQuery: searchText,
                                        shortcutNumber: shortcutNumber(for: item.id),
                                        isShortcutOverlayVisible: isCommandKeyPressed,
                                        entranceOffset: 0
                                    )
                                    .id(item.id)
                                    .background(
                                        GeometryReader { proxy in
                                            Color.clear.preference(
                                                key: CardFramePreferenceKey.self,
                                                value: [item.id: proxy.frame(in: .named("historyWindow"))]
                                            )
                                        }
                                    )
                                    .contentShape(Rectangle())
                                    .highPriorityGesture(
                                        immediateSelectionGesture(for: item),
                                        including: .all
                                    )
                                    .simultaneousGesture(
                                        TapGesture(count: 2)
                                            .onEnded {
                                                pasteItem(item.id)
                                            }
                                    )
                                    .contextMenu {
                                        Button("粘贴") {
                                            pasteItem(item.id)
                                        }

                                        Button("复制") {
                                            copyItem(item.id)
                                        }

                                        if item.type == .text || item.type == .link || item.type == .color {
                                            Button("复制纯文本") {
                                                copyPlainTextItem(item.id)
                                            }

                                            Button("粘贴为纯文本") {
                                                pastePlainTextItem(item.id)
                                            }
                                        }

                                        if item.type == .link {
                                            Button("打开链接") {
                                                openLink(item.id)
                                            }

                                            Button("复制链接地址") {
                                                copyLinkURL(item.id)
                                            }

                                            Button("复制为 Markdown 链接") {
                                                copyMarkdownLink(item.id)
                                            }
                                        }

                                        if item.type == .color {
                                            Button("复制 HEX") {
                                                copyColorHex(item.id)
                                            }

                                            Button("复制 RGB") {
                                                copyColorRGB(item.id)
                                            }
                                        }

                                        Button("预览") {
                                            showPreview(item.id)
                                        }

                                        Button(item.isPinned ? "取消置顶" : "置顶") {
                                            togglePinned(item.id)
                                        }

                                        Button("删除", role: .destructive) {
                                            deleteItem(item.id)
                                        }

                                        if item.type == .image {
                                            Button("打开图片") {
                                                openImage(item.id)
                                            }

                                            Button("复制图片路径") {
                                                copyImagePath(item.id)
                                            }

                                            Button("在 Finder 中显示") {
                                                revealImageInFinder(item.id)
                                            }
                                        }

                                        if let sourceItem = store.item(with: item.id),
                                           sourceItem.sourceBundleID != nil {
                                            Divider()

                                            Button("忽略 \(sourceItem.sourceAppName)") {
                                                ignoreSourceApp(item.id)
                                            }

                                            Button("复制来源 App 名称") {
                                                copySourceAppName(item.id)
                                            }

                                            Button("复制来源 Bundle ID") {
                                                copySourceBundleID(item.id)
                                            }
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
                        .onPreferenceChange(CardFramePreferenceKey.self) { frames in
                            cardFrames = frames
                        }
                    }
                }
            }
            .padding(.top, 18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .coordinateSpace(name: "historyWindow")
        .focusable()
        .onAppear {
            selectedItemID = filteredItems.first?.id
            canAutoPaste = pasteExecutor.canAutoPaste
        }
        .onChange(of: store.items) { newItems in
            guard let firstItem = newItems.first else {
                selectedItemID = nil
                closePreview()
                return
            }

            if selectedItemID == nil || !newItems.contains(where: { $0.id == selectedItemID }) {
                selectedItemID = firstItem.id
            }

            if let previewedItemID = previewState.itemID,
               !newItems.contains(where: { $0.id == previewedItemID }) {
                closePreview()
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
        .onExitCommand {
            closePreview()
            onClose()
        }
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
                recordingStatusButton
                retentionMenu

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

                pinnedFilterButton

                if isSearchVisible || !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || filter != .all {
                    resultCountBadge
                }
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
                Button {
                    self.filter = filter
                    showStatus("筛选：\(filter.title)")
                } label: {
                    HStack {
                        Text(filter.title)
                        if self.filter == filter {
                            Image(systemName: "checkmark")
                        }
                    }
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

    private var resultCountBadge: some View {
        Text("\(filteredItems.count) / \(items.count)")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.45))
            .clipShape(Capsule())
            .help("当前筛选结果数量 / 全部数量")
    }

    private var pinnedFilterButton: some View {
        Button(action: togglePinnedFilter) {
            Image(systemName: filter == .pinned ? "pin.fill" : "pin")
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 26, height: 26)
                .background(Color.white.opacity(filter == .pinned ? 0.72 : 0.45))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(filter == .pinned ? Color(red: 0.18, green: 0.55, blue: 1.0) : .secondary)
        .transaction { transaction in
            transaction.animation = nil
        }
        .help(filter == .pinned ? "显示全部" : "只看置顶")
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
        HStack(spacing: 6) {
            TextField("搜索", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .medium))
                .focused($isSearchFocused)
                .onSubmit {
                    pasteItem(selectedItemID)
                }

            if !searchText.isEmpty {
                Button(action: clearSearch) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("清空搜索")
            }
        }
        .padding(.horizontal, 10)
        .frame(width: isSearchVisible ? 220 : 0, height: 30)
        .background(Color.white.opacity(isSearchVisible ? 0.72 : 0))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .opacity(isSearchVisible ? 1 : 0)
        .allowsHitTesting(isSearchVisible)
        .animation(.easeOut(duration: 0.16), value: isSearchVisible)
        .animation(.easeOut(duration: 0.12), value: searchText.isEmpty)
    }

    private var moreMenu: some View {
        Menu {
            Button("新建文本") {
                appMenuController.createTextItem()
                showStatus("已新建文本")
            }

            Divider()

            Button("帮助") {
                appMenuController.showHelp()
            }

            Button("设置") {
                appMenuController.showSettings()
            }

            retentionSettingsMenu

            Divider()

            Menu("暂停 轻贴") {
                pauseMenu
            }

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

    @ViewBuilder
    private var pauseMenu: some View {
            Button(recordingController.pauseMenuPrimaryTitle()) {
                togglePauseFromMenu()
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
        if previewState.isVisible {
            showPreview(nextID)
        }
    }

    private func selectVisibleCard(number: Int) {
        let index = number - 1
        guard filteredItems.indices.contains(index) else {
            return
        }

        selectedItemID = filteredItems[index].id
        if previewState.isVisible {
            showPreview(selectedItemID)
        }
        showStatus("已选中第 \(number) 张")
    }

    private func shortcutNumber(for id: HistoryPreviewItem.ID) -> Int? {
        guard let index = filteredItems.prefix(9).firstIndex(where: { $0.id == id }) else {
            return nil
        }

        return filteredItems.distance(from: filteredItems.startIndex, to: index) + 1
    }

    private func copyItem(_ id: ClipboardItem.ID?) {
        guard let item = store.item(with: id) else {
            return
        }

        pasteExecutor.copyToPasteboard(item)
        showStatus("已复制")
    }

    private func copyPlainTextItem(_ id: ClipboardItem.ID?) {
        guard let item = store.item(with: id) else {
            return
        }

        pasteExecutor.copyPlainTextToPasteboard(item)
        showStatus("已复制纯文本")
    }

    private func pastePlainTextItem(_ id: ClipboardItem.ID?) {
        guard let item = store.item(with: id) else {
            return
        }

        canAutoPaste = pasteExecutor.canAutoPaste
        switch pasteExecutor.pastePlainTextToFrontmostApp(item) {
        case .copiedOnly:
            showStatus("已复制纯文本")
        case .pasted:
            showStatus("已粘贴纯文本")
        }
    }

    private func copyMarkdownLink(_ id: ClipboardItem.ID?) {
        guard let item = store.item(with: id),
              item.type == .link else {
            return
        }

        let title = (item.linkTitle?.isEmpty == false ? item.linkTitle : nil)
            ?? item.url?.host(percentEncoded: false)
            ?? item.text
        let markdown = "[\(title)](\(item.text))"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(markdown, forType: .string)
        store.skipNextClipboardText(markdown)
        showStatus("已复制 Markdown 链接")
    }

    private func copyLinkURL(_ id: ClipboardItem.ID?) {
        guard let item = store.item(with: id),
              item.type == .link else {
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.text, forType: .string)
        store.skipNextClipboardText(item.text)
        showStatus("已复制链接地址")
    }

    private func openLink(_ id: ClipboardItem.ID?) {
        guard let item = store.item(with: id),
              item.type == .link,
              let url = item.url else {
            showStatus("无法打开链接")
            return
        }

        NSWorkspace.shared.open(url)
        showStatus("已打开链接")
    }

    private func copyColorHex(_ id: ClipboardItem.ID?) {
        guard let item = store.item(with: id),
              item.type == .color else {
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.text, forType: .string)
        store.skipNextClipboardText(item.text)
        showStatus("已复制 HEX")
    }

    private func copyColorRGB(_ id: ClipboardItem.ID?) {
        guard let item = store.item(with: id),
              item.type == .color,
              let rgb = rgbString(from: item.text) else {
            showStatus("无法转换 RGB")
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(rgb, forType: .string)
        store.skipNextClipboardText(rgb)
        showStatus("已复制 RGB")
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

    private func showPreview(_ id: ClipboardItem.ID?) {
        guard let item = store.item(with: id) else {
            return
        }

        previewState.open(item.id)
        onPreview(item, cardFrames[item.id] ?? CGRect(x: 28, y: 60, width: 250, height: 270))
    }

    private func togglePreviewForSelectedItem() {
        guard let selectedItemID else {
            return
        }

        if previewState.itemID == selectedItemID {
            closePreview()
            return
        }

        showPreview(selectedItemID)
    }

    private func deleteItem(_ id: ClipboardItem.ID?) {
        let nextID = nextSelectionID(afterDeleting: id)
        store.deleteItem(with: id)
        selectedItemID = nextID
        if previewState.itemID == id {
            closePreview()
        }
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

    private func ignoreSourceApp(_ id: ClipboardItem.ID?) {
        guard let item = store.item(with: id),
              item.sourceBundleID != nil else {
            showStatus("无法识别来源 App")
            return
        }

        appMenuController.ignoreSourceApp(for: item)
        showStatus("已忽略 \(item.sourceAppName)")
    }

    private func copySourceAppName(_ id: ClipboardItem.ID?) {
        guard let item = store.item(with: id) else {
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.sourceAppName, forType: .string)
        store.skipNextClipboardText(item.sourceAppName)
        showStatus("已复制来源名称")
    }

    private func copySourceBundleID(_ id: ClipboardItem.ID?) {
        guard let item = store.item(with: id),
              let bundleID = item.sourceBundleID else {
            showStatus("无来源 Bundle ID")
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(bundleID, forType: .string)
        store.skipNextClipboardText(bundleID)
        showStatus("已复制 Bundle ID")
    }

    private func revealImageInFinder(_ id: ClipboardItem.ID?) {
        guard let item = store.item(with: id),
              let imageURL = store.imageFileURL(for: item) else {
            showStatus("未找到图片文件")
            return
        }

        NSWorkspace.shared.activateFileViewerSelecting([imageURL])
        showStatus("已在 Finder 中显示")
    }

    private func openImage(_ id: ClipboardItem.ID?) {
        guard let item = store.item(with: id),
              let imageURL = store.imageFileURL(for: item) else {
            showStatus("未找到图片文件")
            return
        }

        NSWorkspace.shared.open(imageURL)
        showStatus("已打开图片")
    }

    private func copyImagePath(_ id: ClipboardItem.ID?) {
        guard let item = store.item(with: id),
              let imageURL = store.imageFileURL(for: item) else {
            showStatus("未找到图片文件")
            return
        }

        let path = imageURL.path
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
        store.skipNextClipboardText(path)
        showStatus("已复制图片路径")
    }

    private func rgbString(from hex: String) -> String? {
        let normalized = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard normalized.count == 6,
              let value = Int(normalized, radix: 16) else {
            return nil
        }

        let red = (value >> 16) & 0xFF
        let green = (value >> 8) & 0xFF
        let blue = value & 0xFF
        return "rgb(\(red), \(green), \(blue))"
    }

    private func immediateSelectionGesture(for item: HistoryPreviewItem) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                if previewState.isVisible, previewState.itemID != item.id {
                    closePreview()
                }

                if selectedItemID != item.id {
                    selectedItemID = item.id
                }
            }
    }

    private func closePreview() {
        previewState.close()
        onClosePreview()
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
            withAnimation(.easeOut(duration: 0.16)) {
                clearSearch()
            }
        } else {
            openSearch()
        }
    }

    private func clearSearch() {
        withAnimation(.easeOut(duration: 0.16)) {
            searchText = ""
            isSearchVisible = false
            isSearchFocused = false
        }
    }

    private func togglePinnedFilter() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            filter = filter == .pinned ? .all : .pinned
        }
        showStatus(filter == .pinned ? "只看置顶" : "显示全部")
    }

    private func openSearch() {
        withAnimation(.easeOut(duration: 0.16)) {
            isSearchVisible = true
        }
        Task { @MainActor in
            isSearchFocused = true
        }
    }

    private func ensureSelectionInFilteredItems() {
        if let selectedItemID,
           filteredItems.contains(where: { $0.id == selectedItemID }) {
            return
        }

        selectedItemID = filteredItems.first?.id
    }

    private func nextSelectionID(afterDeleting id: ClipboardItem.ID?) -> ClipboardItem.ID? {
        guard let id,
              let index = filteredItems.firstIndex(where: { $0.id == id }) else {
            return filteredItems.first?.id
        }

        let remainingItems = filteredItems.filter { $0.id != id }
        guard !remainingItems.isEmpty else {
            return nil
        }

        return remainingItems[min(index, remainingItems.count - 1)].id
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

    private func togglePauseFromMenu() {
        if recordingController.isPaused {
            appMenuController.resumeRecording()
            showStatus("已恢复记录")
        } else {
            pauseRecording()
        }
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

private struct NumberShortcutHandler: NSViewRepresentable {
    let onCommandStateChange: (Bool) -> Void
    let onNumber: (Int) -> Void

    func makeNSView(context: Context) -> ShortcutNSView {
        let view = ShortcutNSView()
        view.onCommandStateChange = onCommandStateChange
        view.onNumber = onNumber
        return view
    }

    func updateNSView(_ nsView: ShortcutNSView, context: Context) {
        nsView.onCommandStateChange = onCommandStateChange
        nsView.onNumber = onNumber
    }

    final class ShortcutNSView: NSView {
        var onCommandStateChange: ((Bool) -> Void)?
        var onNumber: ((Int) -> Void)?
        private var monitor: Any?
        private var flagsMonitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil {
                removeMonitors()
            } else {
                installMonitors()
            }
        }

        private func installMonitors() {
            if monitor == nil {
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                    guard let self,
                          self.window?.isKeyWindow == true,
                          !Self.isTextInputActive(),
                          event.modifierFlags.contains(.command),
                          let characters = event.charactersIgnoringModifiers,
                          characters.count == 1,
                          let number = Int(characters),
                          (1...9).contains(number) else {
                        return event
                    }

                    self.onNumber?(number)
                    return nil
                }
            }

            if flagsMonitor == nil {
                flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
                    guard let self,
                          self.window?.isKeyWindow == true else {
                        self?.onCommandStateChange?(false)
                        return event
                    }

                    self.onCommandStateChange?(event.modifierFlags.contains(.command))
                    return event
                }
            }
        }

        private func removeMonitors() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }

            if let flagsMonitor {
                NSEvent.removeMonitor(flagsMonitor)
                self.flagsMonitor = nil
            }

            onCommandStateChange?(false)
        }

        private static func isTextInputActive() -> Bool {
            guard let responder = NSApp.keyWindow?.firstResponder else {
                return false
            }

            return responder is NSTextView
        }
    }
}

private struct CardFramePreferenceKey: PreferenceKey {
    static let defaultValue: [ClipboardItem.ID: CGRect] = [:]

    static func reduce(value: inout [ClipboardItem.ID: CGRect], nextValue: () -> [ClipboardItem.ID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, newValue in newValue })
    }
}
