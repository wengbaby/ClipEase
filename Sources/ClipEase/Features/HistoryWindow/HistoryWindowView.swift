import SwiftUI
import AppKit
import QuartzCore

struct HistoryWindowView: View {
    @ObservedObject var store: ClipboardHistoryStore
    @ObservedObject var previewState: HistoryPreviewState
    @ObservedObject var renderState: HistoryWindowRenderState
    @ObservedObject var inputState: HistoryWindowInputState
    @ObservedObject var recordingController: RecordingController
    @ObservedObject var accessibilityPermissionState: AccessibilityPermissionState
    let appMenuController: AppMenuController
    let pasteExecutor: PasteExecutor
    let onClose: () -> Void
    let onPreview: (ClipboardItem, CGRect) -> Void
    let onMovePreview: (CGRect) -> Void
    let onClosePreview: () -> Void
    let onCreateText: (ClipboardGroup.ID?) -> Void

    @State private var selectedItemID: HistoryPreviewItem.ID?
    @State private var statusText: String?
    @State private var statusGeneration: UInt64 = 0
    @State private var hostWindow: NSWindow?
    @State private var searchText = ""
    @State private var searchCriteria = HistorySearchCriteria()
    @State private var selectedSearchTokenKind: HistorySearchTokenKind?
    @State private var isSearchVisible = false
    @State private var isSearchFilterPanelPresented = false
    @State private var selectedGroup: HistoryGroupSelection = .all
    @State private var isClearConfirmationPresented = false
    @State private var groupPendingDeletion: ClipboardGroup?
    @State private var groupRenameTargetID: ClipboardGroup.ID?
    @State private var groupRenameText = ""
    @State private var groupRenameOriginalText = ""
    @State private var isGroupRenameCancelPending = false
    @State private var groupRenameFocusRequestID = 0
    @State private var groupRenameInputScreenFrame: CGRect?
    @State private var groupAppearanceTarget: ClipboardGroup?
    @State private var systemGroupAppearanceTarget: SystemHistoryGroup?
    @State private var groupAppearanceColor = Color(red: 0.18, green: 0.55, blue: 1.0)
    @State private var groupAppearanceOriginalColor = Color(red: 0.18, green: 0.55, blue: 1.0)
    @State private var groupAppearanceIconName = "tray.full"
    @State private var groupAppearanceOriginalIconName = "tray.full"
    @State private var groupIconSearchText = ""
    @State private var isGroupIconSearchFocused = false
    @State private var moveToGroupMenuSnapshot: [MoveToGroupMenuEntry] = []
    @State private var moveToGroupPickerTarget: MoveToGroupPickerTarget?
    @State private var pendingGroupTrackScrollID: String?
    @State private var isCommandKeyPressed = false
    @State private var isSearchFocused = false
    @State private var isSearchTextComposing = false
    @State private var searchFocusRequestID = 0
    @State private var authorizationPulse = false
    @State private var allPreviewItems: [HistoryPreviewItem] = []
    @State private var filteredPreviewItems: [HistoryPreviewItem] = []
    @State private var previewBuildTask: Task<Void, Never>?
    @State private var previewBuildGeneration: UInt64 = 0
    @State private var previewItemsSourceSignature: [HistoryPreviewSourceSignature] = []
    @State private var previewItemCache: [ClipboardItem.ID: CachedHistoryPreviewItem] = [:]
    @State private var searchTask: Task<Void, Never>?
    @State private var searchGeneration: UInt64 = 0
    @State private var lastSearchRequestSignature: HistorySearchRequestSignature?
    @State private var preheatTask: Task<Void, Never>?
    @State private var previewFollowTask: Task<Void, Never>?
    @State private var rememberSelectedItemTask: Task<Void, Never>?
    @State private var pendingPreviewFollowItemID: ClipboardItem.ID?
    @State private var windowWidth: CGFloat = 0
    @State private var latestPresentedItemID: ClipboardItem.ID?
    @State private var latestPresentedItemTimestamp: Date = .distantPast
    @State private var lastObservedNewestItemID: ClipboardItem.ID?
    @State private var observedItemIDs: Set<ClipboardItem.ID> = []
    @State private var observedItemTimestamps: [ClipboardItem.ID: Date] = [:]
    @State private var pendingNewestItemIDForNextShow: ClipboardItem.ID?
    @State private var pendingLatestFocusItemID: ClipboardItem.ID?
    @State private var pendingLatestFocusTimestamp: Date?
    @State private var pendingLatestFocusReason: ClipboardItemFocusRequest.Reason?
    @State private var pendingLatestFocusLockID: ClipboardItem.ID?
    @State private var latestClipboardFocusGeneration: UInt64 = 0
    @State private var pendingProgrammaticJumpItemID: ClipboardItem.ID?
    @State private var pendingItemScrollID: HistoryPreviewItem.ID?
    @State private var pendingItemScrollRetryCount = 0
    @State private var shouldResetHorizontalOffsetForPendingItemScroll = false
    @State private var shouldAnimatePendingItemScroll = false
    @State private var isPreparingPendingItemScrollMeasurement = false
    @State private var didRestoreRememberedViewport = false
    @State private var itemScrollRequestID = UUID()
    @State private var searchInteractionFrames: [CGRect] = []
    @State private var searchControlScreenFrame: CGRect?
    @State private var searchInteractionScreenFrames: [CGRect] = []
    @State private var cardRailTopInWindow: CGFloat = 68
    @AppStorage("history.systemGroup.pinned.iconName") private var pinnedGroupIconName = "pin.fill"
    @AppStorage("history.systemGroup.pinned.colorHex") private var pinnedGroupColorHex = "#2E8CFF"
    @AppStorage("history.lastSelectedGroup") private var rememberedSelectedGroup = HistoryGroupSelection.all.storageValue
    @AppStorage("history.lastSelectedItemID") private var rememberedSelectedItemID = ""
    @AppStorage("history.savedScrollOffsetsByScope") private var rememberedScrollOffsetsByScopeData = "{}"
    @FocusState private var focusedRenameGroupID: ClipboardGroup.ID?

    private let backgroundColor = Color(red: 0.78, green: 0.82, blue: 0.92)
    private let allHistoryGroupColor = Color(red: 0.18, green: 0.55, blue: 1.0)
    private let groupAppearancePopoverWidth: CGFloat = 304
    private let groupAppearanceIconGridHeight: CGFloat = 178
    private let selectedCardTopContentInset: CGFloat = 14
    private let horizontalContentPadding: CGFloat = 28
    private let horizontalCardSpacing: CGFloat = 20
    private let historyCardWidth: CGFloat = 250
    private let pendingItemScrollMaxRetryCount = 6

    private var items: [HistoryPreviewItem] {
        allPreviewItems
    }

    private var filteredItems: [HistoryPreviewItem] {
        filteredPreviewItems
    }

    private var renderedItems: [HistoryPreviewItem] {
        filteredItems
    }

    private var filteredGroupIcons: [String] {
        let query = groupIconSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return ClipboardGroup.defaultIcons
        }

        let normalizedQuery = query.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        return ClipboardGroup.defaultIcons.filter { iconName in
            iconName
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                .contains(normalizedQuery)
        }
    }

    private var selectedGroupID: ClipboardGroup.ID? {
        selectedGroup.groupID
    }

    private var searchTokens: [HistorySearchToken] {
        HistorySearchToken.tokens(
            criteria: searchCriteria,
            groups: store.groups
        )
    }

    private var isSearchActive: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || searchCriteria.hasActiveFilters
    }

    private var hasSearchContent: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !searchTokens.isEmpty ||
            searchCriteria.hasActiveFilters
    }

    private var canEditSelectedItemFromShortcut: Bool {
        guard !isTextInputActiveForEditShortcut,
              let selectedItemID,
              filteredItems.contains(where: { $0.id == selectedItemID }),
              let item = store.item(with: selectedItemID) else {
            return false
        }

        return isEditable(item)
    }

    private var shouldSuppressHistoryCommandShortcuts: Bool {
        isTextInputActiveForEditShortcut || inputState.isPreviewContentActive
    }

    private var isTextInputActiveForEditShortcut: Bool {
        isSearchFocused ||
            isGroupIconSearchFocused ||
            isSearchFilterPanelPresented ||
            groupRenameTargetID != nil ||
            groupAppearanceTarget != nil ||
            systemGroupAppearanceTarget != nil ||
            moveToGroupPickerTarget != nil ||
            NSApp.keyWindow?.firstResponder is NSTextView
    }

    private var sourceAppOptions: [String] {
        var seen = Set<String>()
        var options: [String] = []

        for item in allPreviewItems {
            let name = item.sourceAppName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, !seen.contains(name) else {
                continue
            }

            seen.insert(name)
            options.append(name)
        }

        return options
    }

    private var sourceAppIconFileNames: [String: String] {
        var result: [String: String] = [:]
        for item in allPreviewItems {
            guard let iconFileName = item.iconFileName,
                  result[item.sourceAppName] == nil else {
                continue
            }
            result[item.sourceAppName] = iconFileName
        }
        return result
    }

    var body: some View {
        ZStack {
            backgroundColor
            .ignoresSafeArea()

            if !inputState.isPreviewContentActive {
                shortcutButtons
            }

            NumberShortcutHandler(inputState: inputState) { isPressed in
                isCommandKeyPressed = isPressed
            } onNumber: { number in
                selectVisibleCard(number: number)
            }
            .frame(width: 0, height: 0)

            VStack(alignment: .leading, spacing: 14) {
                toolbar

                if items.isEmpty {
                    allEmptyState
                } else if filteredItems.isEmpty {
                    emptyContentState
                } else {
                    ScrollViewReader { proxy in
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(spacing: horizontalCardSpacing) {
                                CardRailScrollViewBinder()
                                    .frame(width: 0, height: 0)

                                ForEach(renderedItems) { item in
                                    historyCard(item)
                                }
                            }
                            .padding(.horizontal, horizontalContentPadding)
                            .padding(.top, selectedCardTopContentInset)
                            .padding(.bottom, 8)
                            .padding(.bottom, 22)
                        }
                        .background(
                            GeometryReader { proxy in
                                Color.clear
                                    .onAppear {
                                        cardRailTopInWindow = proxy.frame(in: .named("historyWindow")).minY
                                    }
                                    .onChange(of: proxy.frame(in: .named("historyWindow")).minY) { minY in
                                        cardRailTopInWindow = minY
                                    }
                            }
                        )
                        .onChange(of: itemScrollRequestID) { _ in
                            guard let pendingItemScrollID else {
                                return
                            }

                            if applyPendingItemScrollIfMeasured(pendingItemScrollID) {
                                self.pendingItemScrollID = nil
                                pendingItemScrollRetryCount = 0
                                shouldResetHorizontalOffsetForPendingItemScroll = false
                                shouldAnimatePendingItemScroll = false
                                isPreparingPendingItemScrollMeasurement = false
                                return
                            }

                            guard !isPreparingPendingItemScrollMeasurement,
                                  pendingItemScrollRetryCount < pendingItemScrollMaxRetryCount else {
                                return
                            }

                            isPreparingPendingItemScrollMeasurement = true
                            pendingItemScrollRetryCount += 1
                            var transaction = Transaction()
                            transaction.disablesAnimations = true
                            withTransaction(transaction) {
                                proxy.scrollTo(pendingItemScrollID, anchor: .center)
                            }

                            Task { @MainActor in
                                await Task.yield()
                                guard self.pendingItemScrollID == pendingItemScrollID else {
                                    return
                                }
                                self.isPreparingPendingItemScrollMeasurement = false
                                self.itemScrollRequestID = UUID()
                            }
                        }
                        .background(HorizontalScrollWheelRedirector(scope: .cardRail))
                    }
                }
            }
            .padding(.top, 18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            SearchOutsideWindowMouseDownObserver(
                isEnabled: isSearchVisible,
                hostWindow: hostWindow,
                excludedFrames: searchInteractionScreenFrames,
                onMouseDown: closeSearchFromOutsideClick
            )
        )
        .background(
            GroupRenameOutsideMouseDownObserver(
                isEnabled: groupRenameTargetID != nil,
                hostWindow: hostWindow,
                excludedScreenFrame: groupRenameInputScreenFrame,
                onMouseDown: commitPendingRenameIfNeeded
            )
        )
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear {
                        windowWidth = proxy.size.width
                    }
                    .onChange(of: proxy.size.width) { width in
                        windowWidth = width
                    }
            }
        )
        .background(HistoryWindowHostWindowReader(window: $hostWindow))
        .coordinateSpace(name: "historyWindow")
        .onPreferenceChange(SearchInteractionFramePreferenceKey.self) { frames in
            searchInteractionFrames = frames
        }
        .onChange(of: searchInteractionFrames) { _ in
            refreshSearchInteractionScreenFrames()
        }
        .onChange(of: searchControlScreenFrame) { _ in
            refreshSearchInteractionScreenFrames()
        }
        .onChange(of: isSearchFilterPanelPresented) { _ in
            refreshSearchInteractionScreenFrames()
        }
        .onChange(of: hostWindow) { _ in
            refreshSearchInteractionScreenFrames()
        }
        .transaction { transaction in
            transaction.animation = nil
        }
        .onAppear {
            renderState.mark("swiftui-appear")
            HistoryWindowInputState.currentForTextEditing = inputState
            restoreRememberedGroupSelection()
            HistoryScrollCoordinator.shared.loadSavedOffsets(from: rememberedScrollOffsetsByScopeData)
            HistoryScrollCoordinator.shared.setScope(selectedGroup.storageValue)
            HistoryScrollCoordinator.shared.onOffsetChange = { [weak inputState] _ in
                guard inputState?.isWindowPresentedSnapshot == true else {
                    return
                }

                Task { @MainActor in
                    followPreviewForCurrentScroll()
                }
            }
            refreshMoveToGroupMenuSnapshot()
            primeLatestItemPresentationGuard(sourceItems: store.items)
            if let request = store.latestItemFocusRequest {
                focusRequestedLatestItem(request)
            }
            focusRecentlyAddedItemOnShowIfNeeded(sourceItems: store.items)
            schedulePreviewItemsRebuild(from: store.items)
            refreshAccessibilityStateAfterFirstFrame()
            authorizationPulse = false
        }
        .onDisappear {
            cancelPendingGroupRename()
            closeInactiveSearchBeforeHiding()
            previewBuildTask?.cancel()
            previewBuildGeneration &+= 1
            searchTask?.cancel()
            preheatTask?.cancel()
            previewFollowTask?.cancel()
            rememberSelectedItemTask?.cancel()
            HistoryScrollCoordinator.shared.onOffsetChange = nil
        }
        .onChange(of: store.items) { newItems in
            syncLatestItemFocusIfNeeded(sourceItems: newItems)
            schedulePreviewItemsRebuild(from: newItems)
            if previewState.isVisible {
                showPreview(previewState.itemID)
            }
        }
        .onChange(of: inputState.isWindowVisible) { isVisible in
            if isVisible {
                didRestoreRememberedViewport = false
                focusRecentlyAddedItemOnShowIfNeeded(sourceItems: store.items)
                syncLatestItemFocusIfNeeded(sourceItems: store.items)
                restoreRememberedViewportIfNeeded()
            }
        }
        .onChange(of: store.groups) { _ in
            refreshMoveToGroupMenuSnapshot()
            if let selectedGroupID,
               !store.groups.contains(where: { $0.id == selectedGroupID }) {
                selectedGroup = .all
            }
            searchCriteria.groups = searchCriteria.groups.filter { group in
                switch group {
                case .pinned:
                    return true
                case .group(let groupID):
                    return store.groups.contains(where: { $0.id == groupID })
                }
            }
            rememberSelectedGroup()
            scheduleSearchUpdate(immediate: true)
        }
        .onChange(of: searchText) { _ in
            selectedSearchTokenKind = nil
            scheduleSearchUpdate(debounceNanoseconds: isSearchTextComposing ? 300_000_000 : 160_000_000)
        }
        .onChange(of: isSearchTextComposing) { isComposing in
            if !isComposing {
                scheduleSearchUpdate(debounceNanoseconds: 60_000_000)
            }
        }
        .onChange(of: searchCriteria) { _ in
            if !searchTokens.contains(where: { $0.kind == selectedSearchTokenKind }) {
                selectedSearchTokenKind = nil
            }
            scheduleSearchUpdate(immediate: true)
        }
        .onChange(of: selectedGroup) { _ in
            rememberSelectedGroup()
            HistoryScrollCoordinator.shared.setScope(selectedGroup.storageValue)
            scheduleSearchUpdate(immediate: true)
        }
        .onChange(of: inputState.request) { request in
            guard let request else {
                return
            }

            handleKeyboardAction(request.action)
        }
        .onChange(of: inputState.itemFocusRequest) { request in
            guard let request else {
                return
            }

            focusRequestedItem(request)
        }
        .onChange(of: store.latestItemFocusRequest) { request in
            guard let request else {
                return
            }

            focusRequestedLatestItem(request)
        }
        .onChange(of: inputState.windowHideRequestID) { _ in
            HistoryScrollCoordinator.shared.captureCurrentOffset()
            rememberedScrollOffsetsByScopeData = HistoryScrollCoordinator.shared.savedOffsetsStorageValue()
            rememberSelectedItem(immediate: true)
            cancelPendingGroupRename()
            closeInactiveSearchBeforeHiding()
        }
        .onChange(of: selectedItemID) { _ in
            rememberSelectedItem()
        }
        .onChange(of: isSearchFocused) { isFocused in
            inputState.setTextInputFocused(isFocused)
        }
        .onChange(of: isGroupIconSearchFocused) { isFocused in
            inputState.setTextInputFocused(isFocused || groupRenameTargetID != nil)
        }
        .onChange(of: groupRenameTargetID) { targetID in
            inputState.setTextInputFocused(targetID != nil || isGroupIconSearchFocused)
        }
        .onChange(of: isSearchVisible) { isVisible in
            if !isVisible {
                isSearchFilterPanelPresented = false
            }
            inputState.setSearchVisible(isVisible)
            refreshSearchInteractionScreenFrames()
        }
        .onChange(of: shouldSuppressHistoryCommandShortcuts) { isActive in
            inputState.setPresentedInputLayerActive(isActive)
        }
        .onMoveCommand { direction in
            moveSelection(direction)
        }
        .onExitCommand {
            handleEscapeClose()
        }
        .sheet(item: $moveToGroupPickerTarget) { target in
            moveToGroupPicker(for: target)
        }
    }

    @ViewBuilder
    private func historyCard(_ item: HistoryPreviewItem) -> some View {
        let isSelected = selectedItemID == item.id

        HistoryCardView(
            item: item,
            searchQuery: searchText,
            shortcutNumber: shortcutNumber(for: item.id),
            isShortcutOverlayVisible: isCommandKeyPressed || inputState.isCommandKeyPressed,
            entranceOffset: 0,
            onClick: {
                selectCardForPrimaryClick(item)
            },
            onDoubleClick: {
                blurSearchFieldForCardInteraction()
                pasteItem(item.id)
            },
            onRightMouseDown: {
                selectCardForContextMenu(item)
            },
            onMenu: {
                cardMenu(for: item)
            },
            onFileDragStatus: showStatus
        )
        .equatable()
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(
                    isSelected ? Color(red: 0.18, green: 0.55, blue: 1.0) : Color.black.opacity(0.08),
                    lineWidth: isSelected ? 4 : 1
                )
                .allowsHitTesting(false)
        }
        .shadow(
            color: .black.opacity(isSelected ? 0.14 : 0),
            radius: isSelected ? 12 : 0,
            x: 0,
            y: isSelected ? 5 : 0
        )
        .scaleEffect(isSelected ? 1.015 : 1)
        .animation(.interactiveSpring(response: 0.24, dampingFraction: 0.86), value: isSelected)
        .id(item.id)
        .contentShape(Rectangle())
        .zIndex(isSelected ? 1 : 0)
    }

    @ViewBuilder
    private var shortcutButtons: some View {
        Group {
            Button(action: { pasteItem(selectedItemID) }) {
                EmptyView()
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.return, modifiers: [])
            .disabled(shouldSuppressHistoryCommandShortcuts)
            .frame(width: 0, height: 0)
            .opacity(0)

            Button(action: { pastePlainTextItem(selectedItemID) }) {
                EmptyView()
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.return, modifiers: [.shift])
            .disabled(shouldSuppressHistoryCommandShortcuts)
            .frame(width: 0, height: 0)
            .opacity(0)

            Button(action: togglePreviewForSelectedItem) {
                EmptyView()
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.space, modifiers: [])
            .disabled(shouldSuppressHistoryCommandShortcuts)
            .frame(width: 0, height: 0)
            .opacity(0)

            Button(action: handleCommandFSearch) {
                EmptyView()
            }
            .buttonStyle(.plain)
            .keyboardShortcut("f", modifiers: [.command])
            .disabled(shouldSuppressHistoryCommandShortcuts)
            .frame(width: 0, height: 0)
            .opacity(0)

            Button(action: { copyItem(selectedItemID) }) {
                EmptyView()
            }
            .buttonStyle(.plain)
            .keyboardShortcut("c", modifiers: [.command])
            .disabled(shouldSuppressHistoryCommandShortcuts)
            .frame(width: 0, height: 0)
            .opacity(0)

            Button(action: { copyPlainTextItem(selectedItemID) }) {
                EmptyView()
            }
            .buttonStyle(.plain)
            .keyboardShortcut("c", modifiers: [.shift, .command])
            .disabled(shouldSuppressHistoryCommandShortcuts)
            .frame(width: 0, height: 0)
            .opacity(0)

            Button(action: { deleteItem(selectedItemID) }) {
                EmptyView()
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.delete, modifiers: [])
            .disabled(shouldSuppressHistoryCommandShortcuts)
            .frame(width: 0, height: 0)
            .opacity(0)

            Button(action: handleEditShortcut) {
                EmptyView()
            }
            .buttonStyle(.plain)
            .keyboardShortcut("e", modifiers: [.command])
            .disabled(!canEditSelectedItemFromShortcut)
            .frame(width: 0, height: 0)
            .opacity(0)

            Button(action: { togglePinned(selectedItemID) }) {
                EmptyView()
            }
            .buttonStyle(.plain)
            .keyboardShortcut("p", modifiers: [.command])
            .disabled(shouldSuppressHistoryCommandShortcuts)
            .frame(width: 0, height: 0)
            .opacity(0)

            Button(action: appMenuController.showSettings) {
                EmptyView()
            }
            .buttonStyle(.plain)
            .keyboardShortcut(",", modifiers: [.command])
            .disabled(shouldSuppressHistoryCommandShortcuts)
            .frame(width: 0, height: 0)
            .opacity(0)

            Button(action: closeWindowFromShortcut) {
                EmptyView()
            }
            .buttonStyle(.plain)
            .keyboardShortcut("w", modifiers: [.command])
            .disabled(shouldSuppressHistoryCommandShortcuts)
            .frame(width: 0, height: 0)
            .opacity(0)

            Button(action: createTextFromShortcut) {
                EmptyView()
            }
            .buttonStyle(.plain)
            .keyboardShortcut("n", modifiers: [.command])
            .disabled(shouldSuppressHistoryCommandShortcuts)
            .frame(width: 0, height: 0)
            .opacity(0)

            Button(action: toggleRecordingFromShortcut) {
                EmptyView()
            }
            .buttonStyle(.plain)
            .keyboardShortcut("t", modifiers: [.command])
            .disabled(shouldSuppressHistoryCommandShortcuts)
            .frame(width: 0, height: 0)
            .opacity(0)
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

                HStack(spacing: 7) {
                    Image(nsImage: ClipEaseAppIcon.roundedImage(ClipEaseAppIcon.image(size: NSSize(width: 18, height: 18)), size: NSSize(width: 18, height: 18)))
                        .resizable()
                        .frame(width: 18, height: 18)

                    Text("轻贴")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                }

                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            topTrack
                .padding(.horizontal, 132)

            HStack(spacing: 12) {
                Button(action: toggleWindowPinnedOpen) {
                    Image(systemName: inputState.isWindowPinnedOpen ? "pin.fill" : "pin")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(inputState.isWindowPinnedOpen ? Color(red: 0.18, green: 0.55, blue: 1.0) : .secondary)
                }
                .buttonStyle(.plain)
                .help(inputState.isWindowPinnedOpen ? "取消钉住主窗口" : "钉住主窗口")

                if !accessibilityPermissionState.isTrusted {
                    authorizationButton
                        .onAppear {
                            authorizationPulse = true
                        }
                        .onDisappear {
                            authorizationPulse = false
                        }
                }

                moreMenu
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 22)
        .frame(height: 36)
    }

    private var topTrack: some View {
        GeometryReader { proxy in
            ScrollViewReader { scrollProxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        searchField
                            .id("search-field")

                        searchToggleButton
                            .id("search-toggle")

                        allHistoryGroupButton
                            .id(HistoryGroupSelection.all.scrollID)

                        systemGroupButton(.pinned)
                            .id(HistoryGroupSelection.pinned.scrollID)

                        ForEach(store.groups) { group in
                            groupButton(group, compact: isSearchVisible)
                                .id(HistoryGroupSelection.group(group.id).scrollID)
                        }

                        if !isSearchVisible {
                            newGroupButton
                                .id("new-group")
                        }

                        if isSearchVisible || isSearchActive {
                            resultCountBadge
                                .id("result-count")
                        }
                    }
                    .frame(minWidth: proxy.size.width, alignment: .center)
                    .padding(.vertical, 1)
                }
                .background(HorizontalScrollWheelRedirector(scope: .auxiliaryRail))
                .onChange(of: pendingGroupTrackScrollID) { scrollID in
                    guard let scrollID else {
                        return
                    }

                    withAnimation(.easeOut(duration: 0.18)) {
                        scrollProxy.scrollTo(scrollID, anchor: .trailing)
                    }
                    pendingGroupTrackScrollID = nil
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: 30)
        .confirmationDialog(
            "删除分组？",
            isPresented: Binding(
                get: { groupPendingDeletion != nil },
                set: { isPresented in
                    if !isPresented {
                        groupPendingDeletion = nil
                    }
                }
            ),
            titleVisibility: .visible,
            presenting: groupPendingDeletion
        ) { group in
            Button("删除分组和内容", role: .destructive) {
                deleteGroup(group)
            }

            Button("取消", role: .cancel) {}
        } message: { group in
            Text("会删除“\(group.name)”中的 \(store.itemCount(inGroup: group.id)) 条内容，无法恢复。")
        }
    }

    private var allHistoryGroupButton: some View {
        let isSelected = selectedGroup == .all

        return Button(action: selectAllGroups) {
            HStack(spacing: 6) {
                Image(systemName: "tray.full")
                    .font(.system(size: 12, weight: .semibold))
                if !isSearchVisible {
                    Text("全部剪切板")
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, isSearchVisible ? 8 : 10)
            .frame(height: 28)
            .background(allHistoryGroupColor.opacity(isSelected ? 1 : 0.78))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(isSelected ? Color.white.opacity(0.9) : Color.clear, lineWidth: 2)
            }
        }
        .buttonStyle(.plain)
        .fixedSize()
        .background(
            GroupMouseDownObserver(onMouseDown: closeSearchForGroupNavigation)
                .onRightMouseDown(selectAllGroupsForContextMenu)
        )
        .help("显示全部历史")
    }

    private var searchToggleButton: some View {
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
        .fixedSize()
    }

    private var newGroupButton: some View {
        Button(action: createGroup) {
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .bold))
                .frame(width: 28, height: 28)
                .background(Color.white.opacity(0.55))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color(red: 0.18, green: 0.55, blue: 1.0))
        .fixedSize()
        .help("新建分组")
    }

    private func systemGroupButton(_ group: SystemHistoryGroup) -> some View {
        let isSelected = selectedGroup == group.selection
        let color = systemGroupColor(group)

        return Button(action: { selectSystemGroup(group) }) {
            HStack(spacing: 6) {
                Image(systemName: systemGroupIconName(group))
                    .font(.system(size: 12, weight: .semibold))
                if !isSearchVisible {
                    Text(group.title)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, isSearchVisible ? 8 : 10)
            .frame(height: 28)
            .background(color.opacity(isSelected ? 1 : 0.78))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(isSelected ? Color.white.opacity(0.9) : Color.clear, lineWidth: 2)
            }
        }
        .buttonStyle(.plain)
        .fixedSize()
        .background(GroupMouseDownObserver(
            onMouseDown: closeSearchForGroupNavigation,
            onRightMouseDown: { selectSystemGroupForContextMenu(group) }
        ))
        .contextMenu {
            Button("颜色与图标") {
                beginEditSystemGroupAppearance(group)
            }
        }
        .background(
            PersistentPopoverPresenter(
                isPresented: Binding(
                    get: { systemGroupAppearanceTarget == group },
                    set: { isPresented in
                        if !isPresented, systemGroupAppearanceTarget == group {
                            closeSystemGroupAppearancePopover()
                        }
                    }
                ),
                arrowEdge: .bottom,
                onDismiss: closeSystemGroupAppearancePopover
            ) {
                systemGroupAppearancePopover(group)
                    .fixedSize()
            }
        )
        .help(group.help)
    }

    private func groupAppearancePopover(_ group: ClipboardGroup) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("颜色与图标")
                    .font(.system(size: 14, weight: .semibold))

                Spacer()

                Button("关闭") {
                    closeGroupAppearancePopover()
                }
            }

            HStack(spacing: 10) {
                groupColorPanelSquare(
                    color: groupAppearanceColor,
                    iconName: groupAppearanceIconName
                ) { color in
                    groupAppearanceColor = Color(nsColor: color)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(group.name)
                        .font(.system(size: 14, weight: .semibold))
                }
            }

            groupColorSwatches { color in
                groupAppearanceColor = color
            }

            GroupInlineTextField(
                text: $groupIconSearchText,
                isFocused: $isGroupIconSearchFocused,
                placeholder: "搜索图标",
                onEscape: handleGroupIconSearchEscape
            )
            .frame(height: 24)

            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(38), spacing: 8), count: 6), spacing: 8) {
                    ForEach(filteredGroupIcons, id: \.self) { iconName in
                        Button {
                            groupAppearanceIconName = iconName
                        } label: {
                            Image(systemName: iconName)
                                .font(.system(size: 15, weight: .semibold))
                                .frame(width: 36, height: 36)
                                .foregroundStyle(groupAppearanceIconName == iconName ? .white : .primary)
                                .background(groupAppearanceIconName == iconName ? Color.accentColor : Color.white.opacity(0.45))
                                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .help(iconName)
                    }
                }
            }
            .frame(width: 268, height: groupAppearanceIconGridHeight)

            Button("确认") {
                commitGroupAppearancePopover(group)
            }
            .keyboardShortcut(.defaultAction)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(18)
        .frame(width: groupAppearancePopoverWidth)
    }

    private func systemGroupAppearancePopover(_ group: SystemHistoryGroup) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("颜色与图标")
                    .font(.system(size: 14, weight: .semibold))

                Spacer()

                Button("关闭") {
                    closeSystemGroupAppearancePopover()
                }
            }

            HStack(spacing: 10) {
                groupColorPanelSquare(
                    color: groupAppearanceColor,
                    iconName: groupAppearanceIconName
                ) { color in
                    groupAppearanceColor = Color(nsColor: color)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(group.title)
                        .font(.system(size: 14, weight: .semibold))
                }
            }

            groupColorSwatches { color in
                groupAppearanceColor = color
            }

            GroupInlineTextField(
                text: $groupIconSearchText,
                isFocused: $isGroupIconSearchFocused,
                placeholder: "搜索图标",
                onEscape: handleGroupIconSearchEscape
            )
            .frame(height: 24)

            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(38), spacing: 8), count: 6), spacing: 8) {
                    ForEach(filteredGroupIcons, id: \.self) { iconName in
                        Button {
                            groupAppearanceIconName = iconName
                        } label: {
                            Image(systemName: iconName)
                                .font(.system(size: 15, weight: .semibold))
                                .frame(width: 36, height: 36)
                                .foregroundStyle(groupAppearanceIconName == iconName ? .white : .primary)
                                .background(groupAppearanceIconName == iconName ? Color.accentColor : Color.white.opacity(0.45))
                                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .help(iconName)
                    }
                }
            }
            .frame(width: 268, height: groupAppearanceIconGridHeight)

            Button("确认") {
                commitSystemGroupAppearancePopover(group)
            }
            .keyboardShortcut(.defaultAction)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(18)
        .frame(width: groupAppearancePopoverWidth)
    }

    private func groupColorPanelSquare(
        color: Color,
        iconName: String,
        onChange: @escaping (NSColor) -> Void
    ) -> some View {
        GroupColorWell(color: NSColor(color), onChange: onChange)
            .frame(width: 42, height: 42)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                Image(systemName: iconName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .allowsHitTesting(false)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.white.opacity(0.35), lineWidth: 1)
                    .allowsHitTesting(false)
            }
        .buttonStyle(.plain)
        .help("选择颜色")
    }

    private func groupColorSwatches(onSelect: @escaping (Color) -> Void) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 18, maximum: 18), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(ClipboardGroup.defaultColors, id: \.self) { hex in
                let color = Color.clipeaseHex(hex)
                Button {
                    onSelect(color)
                } label: {
                    Circle()
                        .fill(color)
                        .frame(width: 18, height: 18)
                        .overlay {
                            Circle()
                                .stroke(
                                    Color.white.opacity(groupAppearanceColor.clipeaseHexString == hex ? 0.95 : 0.45),
                                    lineWidth: groupAppearanceColor.clipeaseHexString == hex ? 2 : 1
                                )
                        }
                }
                .buttonStyle(.plain)
                .help(hex)
            }
        }
    }

    private func groupButton(_ group: ClipboardGroup, compact: Bool = false) -> some View {
        let isSelected = selectedGroup == .group(group.id)
        let isRenaming = groupRenameTargetID == group.id

        return Group {
            if isRenaming {
                HStack(spacing: 6) {
                    Image(systemName: group.iconName)
                        .font(.system(size: 12, weight: .semibold))

                    GroupInlineTextField(
                        text: $groupRenameText,
                        isFocused: Binding(
                            get: { groupRenameTargetID == group.id },
                            set: { _ in }
                        ),
                        placeholder: "分组名称",
                        font: .systemFont(ofSize: 12, weight: .semibold),
                        textColor: .white,
                        drawsBackground: false,
                        isGroupRenameField: true,
                        focusRequestID: groupRenameFocusRequestID,
                        onEscape: handleRenameEscape,
                        onSubmit: { commitRenameGroup(group) }
                    )
                    .frame(width: 84, height: 20)
                    .background(
                        GroupRenameInputFrameReader { frame in
                            groupRenameInputScreenFrame = frame
                        }
                    )
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(Color.clipeaseHex(group.colorHex))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(Color.white.opacity(0.9), lineWidth: 2)
                }
                .onAppear {
                    if groupRenameTargetID == nil {
                        groupRenameOriginalText = group.name
                        groupRenameText = group.name
                        isGroupRenameCancelPending = false
                    }
                    focusedRenameGroupID = group.id
                }
                .onChange(of: focusedRenameGroupID) { focusedID in
                    if focusedID != group.id, groupRenameTargetID == group.id {
                        commitPendingRenameIfNeeded()
                    }
                }
                .onDisappear {
                    if groupRenameTargetID == group.id {
                        groupRenameInputScreenFrame = nil
                    }
                }
            } else {
                Button(action: { selectGroup(group.id) }) {
                    HStack(spacing: 6) {
                        Image(systemName: group.iconName)
                            .font(.system(size: 12, weight: .semibold))
                        if !compact {
                            Text(group.name)
                                .font(.system(size: 12, weight: .semibold))
                                .lineLimit(1)
                        }
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, compact ? 8 : 10)
                    .frame(height: 28)
                    .background(Color.clipeaseHex(group.colorHex).opacity(isSelected ? 1 : 0.78))
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(isSelected ? Color.white.opacity(0.9) : Color.clear, lineWidth: 2)
                    }
                }
                .buttonStyle(.plain)
                .fixedSize()
                .background(GroupMouseDownObserver(
                    onMouseDown: handleGroupRowOutsideClick,
                    onRightMouseDown: { selectGroup(group.id) },
                    onDoubleMouseDown: { beginRenameGroupAfterCurrentMouseEvent(group) }
                ))
                .contextMenu {
                    Button("重命名") {
                        beginRenameGroup(group)
                    }

                    Button("颜色与图标") {
                        beginEditGroupAppearance(group)
                    }

                    Divider()

                    Button("删除分组", role: .destructive) {
                        requestDeleteGroup(group)
                    }
                }
                .background(
                    PersistentPopoverPresenter(
                        isPresented: Binding(
                            get: { groupAppearanceTarget?.id == group.id },
                            set: { isPresented in
                                if !isPresented, groupAppearanceTarget?.id == group.id {
                                    closeGroupAppearancePopover()
                                }
                            }
                        ),
                        arrowEdge: .bottom,
                        onDismiss: closeGroupAppearancePopover
                    ) {
                        groupAppearancePopover(group)
                            .fixedSize()
                    }
                )
                .help("\(group.name)：\(store.itemCount(inGroup: group.id)) 条")
            }
        }
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

    private var authorizationButton: some View {
        Button(action: openAccessibilitySettingsIfNeeded) {
            HStack(spacing: 5) {
                Image(systemName: "exclamationmark.lock")
                    .font(.system(size: 12, weight: .semibold))

                Text("请授权")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(Color(red: 0.78, green: 0.36, blue: 0.08))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Color.white.opacity(authorizationPulse ? 0.92 : 0.45))
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .stroke(
                        Color(red: 0.78, green: 0.36, blue: 0.08).opacity(authorizationPulse ? 0.9 : 0.25),
                        lineWidth: 1
                    )
            }
        }
        .buttonStyle(.plain)
        .help("点击打开辅助功能权限设置")
        .animation(
            accessibilityPermissionState.isTrusted ? nil : .easeInOut(duration: 0.9).repeatForever(autoreverses: true),
            value: authorizationPulse
        )
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            ScrollViewReader { scrollProxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 3) {
                        ForEach(searchTokens) { token in
                            searchTokenView(token)
                                .id(token.id)
                        }

                        SearchTextField(
                            text: $searchText,
                            isFocused: $isSearchFocused,
                            isComposing: $isSearchTextComposing,
                            focusRequestID: searchFocusRequestID,
                            hasSearchResult: !filteredItems.isEmpty,
                            hasSearchTokens: !searchTokens.isEmpty,
                            onEnterFirstResult: enterFirstSearchResultFromSearchField,
                            onReplaceSearch: replaceSearchText,
                            onDeleteLastToken: handleSearchTokenBackspace,
                            onCancel: handleSearchCancel,
                            onSubmit: {
                                pasteItem(selectedItemID)
                            }
                        )
                        .font(.system(size: 13, weight: .medium))
                        .frame(minWidth: 160)
                        .id("search-text-field")
                    }
                }
                .frame(maxWidth: .infinity)
                .background(HorizontalScrollWheelRedirector(scope: .auxiliaryRail))
                .contentShape(Rectangle())
                .onTapGesture {
                    focusSearchField()
                }
                .onChange(of: searchTokens) { _ in
                    scrollProxy.scrollTo("search-text-field", anchor: .trailing)
                }
            }

            if isSearchActive {
                Button(action: clearSearchTextAndFilters) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("清空搜索")
            }

            Button(action: toggleSearchFilterPanel) {
                Image(systemName: searchCriteria.hasActiveFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    .font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(searchCriteria.hasActiveFilters ? Color(red: 0.18, green: 0.55, blue: 1.0) : .secondary)
            .help("搜索筛选")
            .popover(isPresented: $isSearchFilterPanelPresented, arrowEdge: .bottom) {
                searchFilterPanel
                    .fixedSize()
                    .background(SearchPanelWindowReader(onWindowChange: { _ in
                        refreshSearchInteractionScreenFrames()
                    }))
            }
        }
        .padding(.horizontal, 10)
        .frame(width: isSearchVisible ? 520 : 0, height: 30)
        .background(Color.white.opacity(isSearchVisible ? 0.72 : 0))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture {
            focusSearchField()
        }
        .background(
            SearchInteractionLiveRegion(
                isActive: isSearchVisible,
                onRegister: { view in
                    SearchInteractionRegionRegistry.shared.register(view)
                },
                onUnregister: { view in
                    SearchInteractionRegionRegistry.shared.unregister(view)
                }
            )
        )
        .background(
            SearchInteractionScreenFrameReader(isActive: isSearchVisible) { frame in
                if searchControlScreenFrame != frame {
                    searchControlScreenFrame = frame
                }
            }
        )
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: SearchInteractionFramePreferenceKey.self,
                    value: isSearchVisible ? [proxy.frame(in: .named("historyWindow")).insetBy(dx: -8, dy: -8)] : []
                )
            }
        )
        .opacity(isSearchVisible ? 1 : 0)
        .allowsHitTesting(isSearchVisible)
        .animation(.easeOut(duration: 0.14), value: isSearchVisible)
    }

    private func searchTokenView(_ token: HistorySearchToken) -> some View {
        let isSelected = selectedSearchTokenKind == token.kind

        return HStack(spacing: 4) {
            Text(token.title)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)

            Button {
                removeSearchToken(token)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("移除\(token.title)")
        }
        .padding(.leading, 7)
        .padding(.trailing, 5)
        .frame(height: 20)
        .foregroundStyle(isSelected ? .white : .primary)
        .background(isSelected ? Color(red: 0.18, green: 0.55, blue: 1.0) : Color.white.opacity(0.75))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .fixedSize()
        .contentShape(Rectangle())
        .onTapGesture {
            selectedSearchTokenKind = token.kind
            focusSearchField()
        }
    }

    private var searchFilterPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("搜索筛选")
                    .font(.system(size: 14, weight: .semibold))

                Spacer()

                Button("清空") {
                    searchCriteria = HistorySearchCriteria()
                }
                .disabled(!searchCriteria.hasActiveFilters)

                Button("关闭") {
                    isSearchFilterPanelPresented = false
                    focusSearchField()
                }
            }

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 14) {
                    searchFilterSection("Type") {
                        filterChipGrid {
                            ForEach(HistorySearchItemType.allCases) { type in
                                searchFilterChip(
                                    title: type.title,
                                    systemImage: type.iconName,
                                    isSelected: searchCriteria.types.contains(type),
                                    action: { toggleSearchType(type) }
                                )
                            }
                        }
                    }

                    searchFilterSection("App") {
                        if sourceAppOptions.isEmpty {
                            Text("暂无来源")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                        } else {
                            filterChipGrid {
                                ForEach(sourceAppOptions, id: \.self) { appName in
                                    searchFilterChip(
                                        title: appName,
                                        iconFileName: sourceAppIconFileName(appName),
                                        fallbackSystemImage: "app.fill",
                                        isSelected: searchCriteria.sourceAppNames.contains(appName),
                                        action: { toggleSearchSourceApp(appName) }
                                    )
                                }
                            }
                        }
                    }

                    searchFilterSection("Date") {
                        filterChipGrid {
                            ForEach(HistorySearchDateRange.allCases) { range in
                                searchFilterChip(
                                    title: range.title,
                                    systemImage: "calendar",
                                    isSelected: searchCriteria.dateRanges.contains(range),
                                    action: { toggleSearchDateRange(range) }
                                )
                            }
                        }
                    }

                    searchFilterSection("Group") {
                        filterChipGrid {
                            ForEach(SystemHistoryGroup.allCases) { group in
                                searchFilterChip(
                                    title: group.title,
                                    systemImage: systemGroupIconName(group),
                                    isSelected: searchCriteria.groups.contains(group.searchGroup),
                                    action: { toggleSearchGroup(group.searchGroup) }
                                )
                            }

                            ForEach(store.groups) { group in
                                searchFilterChip(
                                    title: group.name,
                                    systemImage: group.iconName,
                                    isSelected: searchCriteria.groups.contains(.group(group.id)),
                                    action: { toggleSearchGroup(.group(group.id)) }
                                )
                            }
                        }
                    }
                }
                .padding(.trailing, 6)
            }
            .frame(width: 420, height: 260)
        }
        .padding(16)
        .frame(width: 440, height: 320)
    }

    private func searchFilterSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                content()
            }
        }
    }

    private func filterChipGrid<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(minimum: 118), spacing: 8), count: 3),
            alignment: .leading,
            spacing: 8
        ) {
            content()
        }
    }

    private func searchFilterChip(
        title: String,
        systemImage: String? = nil,
        iconFileName: String? = nil,
        fallbackSystemImage: String = "circle",
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                searchFilterChipIcon(
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

    @ViewBuilder
    private func cardContextMenu(for item: HistoryPreviewItem) -> some View {
        commandButton(.paste) {
            pasteItem(item.id)
        }

        if item.type == .text || item.type == .link || item.type == .color {
            commandButton(.pastePlainText) {
                pastePlainTextItem(item.id)
            }
        }

        commandButton(.preview) {
            showPreview(item.id)
        }

        if isEditable(item) {
            commandButton(.edit) {
                beginEditItem(item.id)
            }
        }

        Button(item.isPinned ? "取消置顶" : "置顶") {
            togglePinned(item.id)
        }

        Divider()

        typeSpecificContextMenu(for: item)

        if !moveToGroupMenuSnapshot.isEmpty {
            Button(item.groupID == nil ? "加入分组..." : "移动到分组...") {
                presentMoveToGroupPicker(for: item)
            }
        }

        if item.groupID != nil {
            Button("移出分组") {
                removeItemFromGroup(item.id)
            }
        }

        Button("删除", role: .destructive) {
            deleteItem(item.id)
        }

        if let sourceItem = store.item(with: item.id),
           sourceItem.sourceBundleID != nil {
            Divider()

            if !sourceItem.isFromClipEase {
                Button(sourceAppIgnoreMenuTitle(for: sourceItem)) {
                    toggleSourceAppIgnored(item.id)
                }
            }

            Button("复制来源 App 名称") {
                copySourceAppName(item.id)
            }

            Button("复制来源 Bundle ID") {
                copySourceBundleID(item.id)
            }
        }
    }

    private func cardMenu(for item: HistoryPreviewItem) -> NSMenu {
        let menu = NSMenu()

        addMenuItem(HistoryCommand.paste.title, to: menu) { pasteItem(item.id) }

        if item.type == .text || item.type == .link || item.type == .color {
            addMenuItem(HistoryCommand.pastePlainText.title, to: menu) { pastePlainTextItem(item.id) }
        }

        addMenuItem(HistoryCommand.preview.title, to: menu) { showPreview(item.id) }

        if isEditable(item) {
            addMenuItem(HistoryCommand.edit.title, to: menu) { beginEditItem(item.id) }
        }

        addMenuItem(item.isPinned ? "取消置顶" : "置顶", to: menu) { togglePinned(item.id) }
        menu.addItem(.separator())

        addTypeSpecificMenuItems(for: item, to: menu)

        if !moveToGroupMenuSnapshot.isEmpty {
            addMenuItem(item.groupID == nil ? "加入分组..." : "移动到分组...", to: menu) {
                presentMoveToGroupPicker(for: item)
            }
        }

        if item.groupID != nil {
            addMenuItem("移出分组", to: menu) { removeItemFromGroup(item.id) }
        }

        addMenuItem("删除", to: menu) { deleteItem(item.id) }

        if let sourceItem = store.item(with: item.id),
           sourceItem.sourceBundleID != nil {
            menu.addItem(.separator())
            if !sourceItem.isFromClipEase {
                addMenuItem(sourceAppIgnoreMenuTitle(for: sourceItem), to: menu) { toggleSourceAppIgnored(item.id) }
            }
            addMenuItem("复制来源 App 名称", to: menu) { copySourceAppName(item.id) }
            addMenuItem("复制来源 Bundle ID", to: menu) { copySourceBundleID(item.id) }
        }

        return menu
    }

    private func addTypeSpecificMenuItems(for item: HistoryPreviewItem, to menu: NSMenu) {
        switch item.type {
        case .link:
            addMenuItem("打开链接", to: menu) { openLink(item.id) }
            addMenuItem("复制链接地址", to: menu) { copyLinkURL(item.id) }
            addMenuItem("复制为 Markdown 链接", to: menu) { copyMarkdownLink(item.id) }
            menu.addItem(.separator())
        case .color:
            addMenuItem("复制 HEX", to: menu) { copyColorHex(item.id) }
            addMenuItem("复制 RGB", to: menu) { copyColorRGB(item.id) }
            menu.addItem(.separator())
        case .image:
            addMenuItem("打开图片", to: menu) { openImage(item.id) }
            addMenuItem("复制图像", to: menu) { copyImage(item.id) }
            addMenuItem("复制图片路径", to: menu) { copyImagePath(item.id) }
            addMenuItem("在 Finder 中显示", to: menu) { revealImageInFinder(item.id) }
            menu.addItem(.separator())
        case .file:
            addMenuItem("打开文件", to: menu) { openFile(item.id) }
            addMenuItem("复制文件", to: menu) { copyFile(item.id) }
            addMenuItem("复制路径", to: menu) { copyFilePaths(item.id) }
            addMenuItem("在 Finder 中显示", to: menu) { revealFilesInFinder(item.id) }
            menu.addItem(.separator())
        case .text:
            break
        }
    }

    private func addMenuItem(_ title: String, to menu: NSMenu, action: @escaping () -> Void) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let target = ClosureMenuItemTarget(action)
        item.target = target
        item.representedObject = target
        item.action = #selector(ClosureMenuItemTarget.performAction)
        menu.addItem(item)
    }

    @ViewBuilder
    private func typeSpecificContextMenu(for item: HistoryPreviewItem) -> some View {
        switch item.type {
        case .link:
            Button("打开链接") {
                openLink(item.id)
            }

            Button("复制链接地址") {
                copyLinkURL(item.id)
            }

            Button("复制为 Markdown 链接") {
                copyMarkdownLink(item.id)
            }

            Divider()
        case .color:
            Button("复制 HEX") {
                copyColorHex(item.id)
            }

            Button("复制 RGB") {
                copyColorRGB(item.id)
            }

            Divider()
        case .image:
            Button("打开图片") {
                openImage(item.id)
            }

            Button("复制图像") {
                copyImage(item.id)
            }

            Button("复制图片路径") {
                copyImagePath(item.id)
            }

            Button("在 Finder 中显示") {
                revealImageInFinder(item.id)
            }

            Divider()
        case .file:
            Button("打开文件") {
                openFile(item.id)
            }

            Button("复制文件") {
                copyFile(item.id)
            }

            Button("复制路径") {
                copyFilePaths(item.id)
            }

            Button("在 Finder 中显示") {
                revealFilesInFinder(item.id)
            }

            Divider()
        case .text:
            EmptyView()
        }
    }

    private func commandButton(_ command: HistoryCommand, action: @escaping () -> Void) -> some View {
        Button(command.title, action: action)
            .historyKeyboardShortcut(command)
    }

    private func refreshMoveToGroupMenuSnapshot() {
        let snapshot = store.groups.map { MoveToGroupMenuEntry(group: $0) }
        if moveToGroupMenuSnapshot != snapshot {
            moveToGroupMenuSnapshot = snapshot
        }
    }

    private func refreshAccessibilityStateAfterFirstFrame() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard inputState.isWindowVisibleSnapshot else {
                return
            }

            accessibilityPermissionState.refresh()
        }
    }

    private func moveToGroupPicker(for target: MoveToGroupPickerTarget) -> some View {
        let groupEntries = moveToGroupMenuSnapshot

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(target.currentGroupID == nil ? "加入分组" : "移动到分组")
                        .font(.system(size: 15, weight: .semibold))

                    Text("选择一个目标分组")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("取消") {
                    moveToGroupPickerTarget = nil
                }
                .keyboardShortcut(.cancelAction)
            }

            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(groupEntries, id: \.id) { group in
                        moveToGroupPickerRow(group, target: target)
                    }
                }
                .padding(.trailing, 4)
            }
            .frame(width: 340)
            .frame(maxHeight: 260)

            if target.currentGroupID != nil {
                Divider()

                Button(role: .destructive) {
                    removeItemFromGroup(target.itemID)
                    moveToGroupPickerTarget = nil
                } label: {
                    Label("移出分组", systemImage: "tray.and.arrow.up")
                }
            }
        }
        .padding(18)
        .frame(width: 380)
    }

    private func moveToGroupPickerRow(
        _ group: MoveToGroupMenuEntry,
        target: MoveToGroupPickerTarget
    ) -> some View {
        let isCurrentGroup = group.id == target.currentGroupID

        return Button {
            addItem(target.itemID, toGroup: group.id, named: group.name)
            moveToGroupPickerTarget = nil
        } label: {
            HStack(spacing: 9) {
                Image(systemName: group.iconName)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 18)

                Text(group.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)

                Spacer()

                if isCurrentGroup {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .foregroundStyle(isCurrentGroup ? .secondary : .primary)
            .padding(.horizontal, 10)
            .frame(height: 32)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isCurrentGroup ? Color.black.opacity(0.05) : Color.white.opacity(0.68))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isCurrentGroup)
    }

    @ViewBuilder
    private func searchFilterChipIcon(
        systemImage: String?,
        iconFileName: String?,
        fallbackSystemImage: String
    ) -> some View {
        if let iconFileName,
           let iconURL = try? ClipEaseStoragePaths.appIconFileURL(fileName: iconFileName),
           let nsImage = NSImage(contentsOf: iconURL) {
            Image(nsImage: ClipEaseAppIcon.roundedImage(nsImage, size: NSSize(width: 13, height: 13)))
                .resizable()
                .frame(width: 13, height: 13)
        } else {
            Image(systemName: systemImage ?? fallbackSystemImage)
                .font(.system(size: 12, weight: .medium))
        }
    }

    private var moreMenu: some View {
        MoreMenuButton(menuProvider: makeMoreMenu)
            .frame(width: 28, height: 24)
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

    private func makeMoreMenu() -> NSMenu {
        let menu = NSMenu()

        addMenuItem(HistoryCommand.newText.title, to: menu) {
            createTextFromMenu()
        }

        menu.addItem(.separator())

        addMenuItem(HistoryCommand.help.title, to: menu) {
            appMenuController.showHelp()
        }

        addMenuItem(HistoryCommand.settings.title, to: menu) {
            appMenuController.showSettings()
        }

        let pauseItem = NSMenuItem(title: "暂停 轻贴", action: nil, keyEquivalent: "")
        pauseItem.submenu = makePauseNSMenu()
        menu.addItem(pauseItem)

        menu.addItem(.separator())

        let clearItem = NSMenuItem(title: "清空历史", action: nil, keyEquivalent: "")
        let clearTarget = ClosureMenuItemTarget {
            isClearConfirmationPresented = true
        }
        clearItem.target = clearTarget
        clearItem.representedObject = clearTarget
        clearItem.action = #selector(ClosureMenuItemTarget.performAction)
        clearItem.isEnabled = !store.items.isEmpty
        menu.addItem(clearItem)

        menu.addItem(.separator())

        let debugItem = NSMenuItem(title: "开发测试", action: nil, keyEquivalent: "")
        debugItem.submenu = makeDebugNSMenu()
        menu.addItem(debugItem)

        menu.addItem(.separator())

        addMenuItem(HistoryCommand.quit.title, to: menu) {
            appMenuController.quit()
        }

        addMenuItem(HistoryCommand.about.title, to: menu) {
            appMenuController.showAbout()
        }

        return menu
    }

    private func makePauseNSMenu() -> NSMenu {
        let menu = NSMenu()

        addMenuItem(recordingController.pauseMenuPrimaryTitle(), to: menu) {
            togglePauseFromMenu()
        }
        addMenuItem("暂停 15 分钟", to: menu) {
            pauseRecording(for: 15 * 60, message: "已暂停 15 分钟")
        }
        addMenuItem("暂停 30 分钟", to: menu) {
            pauseRecording(for: 30 * 60, message: "已暂停 30 分钟")
        }
        addMenuItem("暂停 1 小时", to: menu) {
            pauseRecording(for: 60 * 60, message: "已暂停 1 小时")
        }
        addMenuItem("暂停 3 小时", to: menu) {
            pauseRecording(for: 3 * 60 * 60, message: "已暂停 3 小时")
        }
        addMenuItem("暂停 6 小时", to: menu) {
            pauseRecording(for: 6 * 60 * 60, message: "已暂停 6 小时")
        }
        addMenuItem("截止到今日", to: menu) {
            appMenuController.pauseUntilEndOfToday()
        }

        return menu
    }

    private func makeDebugNSMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "测试文本：\(appMenuController.debugTextItemCount) 条", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        addMenuItem("添加 1,000 条文本", to: menu) {
            addDebugTextItems(count: 1_000)
        }
        addMenuItem("添加 10,000 条文本", to: menu) {
            addDebugTextItems(count: 10_000)
        }
        menu.addItem(.separator())
        addMenuItem("清除测试文本", to: menu) {
            clearDebugTextItems()
        }
        return menu
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
            }
    }

    private var allEmptyState: some View {
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

    private var emptyContentState: some View {
        VStack(spacing: 10) {
            Image(systemName: emptyContentIconName)
                .font(.system(size: 38, weight: .regular))
                .foregroundStyle(emptyContentTint)

            Text(emptyContentMessage)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 32)
    }

    private var emptyContentMessage: String {
        if !isSearchActive {
            if selectedGroup == .pinned {
                return "暂无置顶内容"
            }

            if selectedGroupID != nil {
                return "暂无内容"
            }
        }

        return "没有找到匹配的历史"
    }

    private var emptyContentIconName: String {
        if !isSearchActive,
           selectedGroup == .pinned {
            return "pin"
        }

        if !isSearchActive,
           selectedGroupID != nil {
            return "tray"
        }

        return "magnifyingglass"
    }

    private var emptyContentTint: Color {
        if !isSearchActive,
           selectedGroup == .pinned {
            return systemGroupColor(.pinned)
        }

        return Color(red: 0.18, green: 0.55, blue: 1.0)
    }

    private func moveSelection(_ direction: MoveCommandDirection) {
        guard let currentSelectedID = selectedItemID,
              let selectedIndex = filteredItems.firstIndex(where: { $0.id == currentSelectedID }) else {
            self.selectedItemID = filteredItems.first?.id
            if let selectedItemID {
                scrollToItemWhenRendered(selectedItemID, animated: true)
            }
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
        revealPartiallyVisibleCardIfNeeded(nextID, animated: false)
        if previewState.isVisible {
            showPreview(nextID)
            Task { @MainActor in
                await Task.yield()
                followPreviewForCurrentScroll()
            }
        }
    }

    private func selectVisibleCard(number: Int) {
        let index = number - 1
        guard filteredItems.indices.contains(index) else {
            return
        }

        let id = filteredItems[index].id
        pasteItem(id)
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

        switch pasteExecutor.copyToPasteboard(item) {
        case .copied:
            store.markUsed(item.id)
            showStatus(copyStatus(for: item))
        case .copiedFallbackText:
            store.markUsed(item.id)
            showStatus(copyFallbackTextStatus(for: item))
        case .failed(let reason):
            showStatus(reason)
        }
    }

    private func copyPlainTextItem(_ id: ClipboardItem.ID?) {
        guard let item = store.item(with: id) else {
            return
        }

        switch pasteExecutor.copyPlainTextToPasteboard(item) {
        case .copied, .copiedFallbackText:
            store.markUsed(item.id)
            showStatus("已复制纯文本")
        case .failed(let reason):
            showStatus(reason)
        }
    }

    private func pastePlainTextItem(_ id: ClipboardItem.ID?) {
        guard let item = store.item(with: id) else {
            return
        }
        accessibilityPermissionState.refresh()
        switch pasteExecutor.pastePlainTextToFrontmostApp(item) {
        case .copiedOnly, .copiedFallbackTextOnly:
            store.markUsed(item.id)
            showStatus("已复制纯文本，需授权后自动粘贴")
            closeAfterPasteIfNeeded()
        case .pasted, .pastedFallbackText:
            store.markUsed(item.id)
            scheduleProgrammaticJump(to: item.id)
            showStatus("已粘贴纯文本到当前 App")
        case .failed(let reason):
            showStatus(reason)
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
        addClipEaseTextCard(markdown)
        showStatus("已复制 Markdown 链接")
        closeAfterContextMenuCommand()
    }

    private func copyLinkURL(_ id: ClipboardItem.ID?) {
        guard let item = store.item(with: id),
              item.type == .link else {
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.text, forType: .string)
        addClipEaseTextCard(item.text)
        showStatus("已复制链接地址")
        closeAfterContextMenuCommand()
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
        closeAfterContextMenuCommand()
    }

    private func copyColorHex(_ id: ClipboardItem.ID?) {
        guard let item = store.item(with: id),
              item.type == .color else {
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.text, forType: .string)
        addClipEaseTextCard(item.text)
        showStatus("已复制 HEX")
        closeAfterContextMenuCommand()
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
        addClipEaseTextCard(rgb)
        showStatus("已复制 RGB")
        closeAfterContextMenuCommand()
    }

    private func pasteItem(_ id: ClipboardItem.ID?) {
        guard filteredItems.contains(where: { $0.id == id }),
              let item = store.item(with: id) else {
            if isSearchVisible {
                showStatus("没有可粘贴的搜索结果")
            }
            return
        }

        accessibilityPermissionState.refresh()
        switch pasteExecutor.pasteToFrontmostApp(item) {
        case .copiedOnly:
            store.markUsed(item.id)
            showStatus(copiedOnlyStatus(for: item))
            closeAfterPasteIfNeeded()
        case .copiedFallbackTextOnly:
            store.markUsed(item.id)
            showStatus(copiedOnlyFallbackTextStatus(for: item))
            closeAfterPasteIfNeeded()
        case .pasted:
            store.markUsed(item.id)
            scheduleProgrammaticJump(to: item.id)
            showStatus(pastedStatus(for: item))
        case .pastedFallbackText:
            store.markUsed(item.id)
            scheduleProgrammaticJump(to: item.id)
            showStatus(pastedFallbackTextStatus(for: item))
        case .failed(let reason):
            showStatus(reason)
        }
    }

    private func closeAfterPasteIfNeeded() {
        if inputState.isWindowPinnedOpen {
            return
        }

        onClose()
    }

    private func closeAfterContextMenuCommand() {
        onClose()
    }

    private func scheduleProgrammaticJump(to id: ClipboardItem.ID) {
        resetFiltersForLatestItemFocus()
        scheduleLatestProgrammaticTransition(
            to: id,
            reason: .refreshed,
            resetToAll: true,
            animateWhenPresented: false
        )
    }

    private func showPreview(_ id: ClipboardItem.ID?) {
        guard let item = store.item(with: id) else {
            return
        }

        onPreview(item, cardViewportFrame(for: item.id) ?? CGRect(x: 28, y: 60, width: 250, height: 270))
    }

    private func followPreviewForCurrentScroll() {
        guard previewState.isVisible,
              let previewedID = previewState.itemID else {
            return
        }

        pendingPreviewFollowItemID = previewedID
        guard previewFollowTask == nil else {
            return
        }

        previewFollowTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 33_000_000)
            let targetID = pendingPreviewFollowItemID
            pendingPreviewFollowItemID = nil
            previewFollowTask = nil
            guard previewState.isVisible,
                  previewState.itemID == targetID,
                  let targetID,
                  let refreshedFrame = cardViewportFrame(for: targetID) else {
                return
            }

            onMovePreview(refreshedFrame)
        }
    }

    private func isEditable(_ item: HistoryPreviewItem) -> Bool {
        guard let sourceItem = store.item(with: item.id) else {
            return false
        }

        return isEditable(sourceItem)
    }

    private func isEditable(_ item: ClipboardItem) -> Bool {
        switch item.type {
        case .text:
            true
        case .link, .color:
            true
        case .image:
            false
        case .file:
            false
        }
    }

    private func handleEditShortcut() {
        guard canEditSelectedItemFromShortcut else {
            return
        }

        beginEditItem(selectedItemID)
    }

    private func beginEditItem(_ id: ClipboardItem.ID?) {
        guard let item = store.item(with: id),
              isEditable(item) else {
            showStatus("此内容暂不支持编辑")
            return
        }

        closePreview()
        onClose()
        appMenuController.editItem(item) { updatedItem in
            selectedItemID = updatedItem.id
            if updatedItem.type == .link {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(updatedItem.text, forType: .string)
                addClipEaseTextCard(updatedItem.text)
                showStatus("已保存并复制新链接")
            } else {
                showStatus("已保存")
            }
        }
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
        selectedGroup = .all
        rememberSelectedGroup()
        showStatus("已清空")
    }

    private func restoreRememberedGroupSelection() {
        let restoredSelection = HistoryGroupSelection(storageValue: rememberedSelectedGroup)
        if case .group(let groupID) = restoredSelection,
           !store.groups.contains(where: { $0.id == groupID }) {
            selectedGroup = .all
            rememberSelectedGroup()
            return
        }

        selectedGroup = restoredSelection
        HistoryScrollCoordinator.shared.setScope(selectedGroup.storageValue)
    }

    private func rememberSelectedGroup() {
        if case .group(let groupID) = selectedGroup,
           !store.groups.contains(where: { $0.id == groupID }) {
            rememberedSelectedGroup = HistoryGroupSelection.all.storageValue
            return
        }

        rememberedSelectedGroup = selectedGroup.storageValue
    }

    private func rememberSelectedItem(immediate: Bool = false) {
        rememberSelectedItemTask?.cancel()
        if immediate {
            persistSelectedItem()
            return
        }

        let selectedItemID = selectedItemID
        rememberSelectedItemTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled,
                  self.selectedItemID == selectedItemID else {
                return
            }

            persistSelectedItem()
        }
    }

    private func persistSelectedItem() {
        guard let selectedItemID else {
            rememberedSelectedItemID = ""
            UserDefaults.standard.set("", forKey: "history.lastSelectedItemID")
            return
        }

        rememberedSelectedItemID = selectedItemID.uuidString
        UserDefaults.standard.set(selectedItemID.uuidString, forKey: "history.lastSelectedItemID")
    }

    private func rememberedSelectedItemUUID() -> ClipboardItem.ID? {
        UUID(uuidString: rememberedSelectedItemID)
    }

    private func selectAllGroups() {
        commitPendingRenameIfNeeded()
        closeSearchForGroupNavigation()
        selectedGroup = .all
        showStatus("全部剪切板")
    }

    private func selectAllGroupsForContextMenu() {
        commitPendingRenameIfNeeded()
        closeSearchForGroupNavigation()
        guard selectedGroup != .all else {
            return
        }

        selectedGroup = .all
        showStatus("全部剪切板")
    }

    private func selectGroup(_ id: ClipboardGroup.ID) {
        commitPendingRenameIfNeeded()
        closeSearchForGroupNavigation()
        selectedGroup = .group(id)
        let groupName = store.group(with: id)?.name ?? "分组"
        showStatus(groupName)
    }

    private func selectSystemGroup(_ group: SystemHistoryGroup) {
        commitPendingRenameIfNeeded()
        closeSearchForGroupNavigation()
        selectedGroup = selectedGroup == group.selection ? .all : group.selection
        showStatus(selectedGroup == group.selection ? group.selectedStatus : "全部剪切板")
    }

    private func selectSystemGroupForContextMenu(_ group: SystemHistoryGroup) {
        commitPendingRenameIfNeeded()
        closeSearchForGroupNavigation()
        guard selectedGroup != group.selection else {
            return
        }

        selectedGroup = group.selection
        showStatus(group.selectedStatus)
    }

    private func createGroup() {
        let group = store.createGroup()
        beginRenameGroup(group)
        pendingGroupTrackScrollID = HistoryGroupSelection.group(group.id).scrollID
        showStatus("已新建分组")
    }

    private func beginRenameGroup(_ group: ClipboardGroup) {
        closeSearchForGroupNavigation()
        commitPendingRenameIfNeeded()
        groupRenameText = group.name
        groupRenameOriginalText = group.name
        isGroupRenameCancelPending = false
        groupRenameTargetID = group.id
        groupRenameFocusRequestID += 1
        inputState.setTextInputFocused(true)
        Task { @MainActor in
            await Task.yield()
            focusedRenameGroupID = group.id
            groupRenameFocusRequestID += 1
        }
    }

    private func beginRenameGroupAfterCurrentMouseEvent(_ group: ClipboardGroup) {
        DispatchQueue.main.async {
            beginRenameGroup(group)
        }
    }

    private func commitRenameGroup(_ group: ClipboardGroup) {
        guard groupRenameTargetID == group.id else {
            return
        }

        let trimmedName = groupRenameText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty {
            switch store.renameGroup(group.id, name: trimmedName) {
            case .renamed:
                showStatus("已重命名分组")
            case .duplicate:
                showStatus("已有同名分组")
            case .empty:
                showStatus("分组名称不能为空")
            case .unchanged:
                break
            case .notFound:
                showStatus("分组不存在")
            }
        } else if !isGroupRenameCancelPending {
            showStatus("分组名称不能为空")
        }

        focusedRenameGroupID = nil
        groupRenameTargetID = nil
        isGroupRenameCancelPending = false
        groupRenameInputScreenFrame = nil
        inputState.setTextInputFocused(false)
    }

    private func cancelRenameGroup() {
        focusedRenameGroupID = nil
        groupRenameTargetID = nil
        groupRenameText = groupRenameOriginalText
        isGroupRenameCancelPending = false
        groupRenameInputScreenFrame = nil
        inputState.setTextInputFocused(false)
    }

    private func handleRenameEscape() {
        isGroupRenameCancelPending = true
        cancelRenameGroup()
    }

    private func beginEditGroupAppearance(_ group: ClipboardGroup) {
        closeSearchForGroupNavigation()
        commitPendingRenameIfNeeded()
        closeGroupColorPanel()
        isGroupIconSearchFocused = false
        systemGroupAppearanceTarget = nil
        let color = Color.clipeaseHex(group.colorHex)
        groupAppearanceColor = color
        groupAppearanceOriginalColor = color
        groupAppearanceIconName = group.iconName
        groupAppearanceOriginalIconName = group.iconName
        groupIconSearchText = ""
        groupAppearanceTarget = group
        inputState.setPresentedInputLayerActive(true)
    }

    private func beginEditSystemGroupAppearance(_ group: SystemHistoryGroup) {
        closeSearchForGroupNavigation()
        commitPendingRenameIfNeeded()
        closeGroupColorPanel()
        isGroupIconSearchFocused = false
        groupAppearanceTarget = nil
        let color = systemGroupColor(group)
        groupAppearanceColor = color
        groupAppearanceOriginalColor = color
        groupAppearanceIconName = systemGroupIconName(group)
        groupAppearanceOriginalIconName = systemGroupIconName(group)
        groupIconSearchText = ""
        systemGroupAppearanceTarget = group
        inputState.setPresentedInputLayerActive(true)
    }

    private func systemGroupIconName(_ group: SystemHistoryGroup) -> String {
        switch group {
        case .pinned:
            pinnedGroupIconName
        }
    }

    private func closeGroupAppearancePopover() {
        groupAppearanceTarget = nil
        isGroupIconSearchFocused = false
        groupIconSearchText = ""
        closeGroupColorPanel()
        inputState.setTextInputFocused(false)
        inputState.setPresentedInputLayerActive(false)
    }

    private func closeSystemGroupAppearancePopover() {
        systemGroupAppearanceTarget = nil
        isGroupIconSearchFocused = false
        groupIconSearchText = ""
        closeGroupColorPanel()
        inputState.setTextInputFocused(false)
        inputState.setPresentedInputLayerActive(false)
    }

    private func commitGroupAppearancePopover(_ group: ClipboardGroup) {
        store.updateGroupAppearance(
            group.id,
            colorHex: groupAppearanceColor.clipeaseHexString,
            iconName: groupAppearanceIconName
        )
        closeGroupAppearancePopover()
    }

    private func commitSystemGroupAppearancePopover(_ group: SystemHistoryGroup) {
        updateSystemGroupAppearance(
            group,
            colorHex: groupAppearanceColor.clipeaseHexString,
            iconName: groupAppearanceIconName
        )
        closeSystemGroupAppearancePopover()
    }

    private func handleGroupIconSearchEscape() {
        if !groupIconSearchText.isEmpty {
            groupIconSearchText = ""
            return
        }

        if groupAppearanceTarget != nil {
            closeGroupAppearancePopover()
        } else if systemGroupAppearanceTarget != nil {
            closeSystemGroupAppearancePopover()
        }
    }

    private func closeGroupColorPanel() {
        GroupColorPanelController.shared.close()
        GroupColorPanelController.closeSharedColorPanel()
    }

    private func systemGroupColor(_ group: SystemHistoryGroup) -> Color {
        switch group {
        case .pinned:
            Color.clipeaseHex(pinnedGroupColorHex)
        }
    }

    private func updateSystemGroupAppearance(
        _ group: SystemHistoryGroup,
        colorHex: String? = nil,
        iconName: String? = nil
    ) {
        switch group {
        case .pinned:
            if let colorHex {
                pinnedGroupColorHex = colorHex
            }
            if let iconName {
                pinnedGroupIconName = iconName
            }
        }
    }

    private func requestDeleteGroup(_ group: ClipboardGroup) {
        closeSearchForGroupNavigation()
        commitPendingRenameIfNeeded()
        if store.itemCount(inGroup: group.id) == 0 {
            deleteGroup(group)
        } else {
            groupPendingDeletion = group
        }
    }

    private func commitPendingRenameIfNeeded() {
        guard let groupRenameTargetID,
              let group = store.group(with: groupRenameTargetID) else {
            return
        }

        commitRenameGroup(group)
    }

    private func handleGroupRowOutsideClick() {
        if groupRenameTargetID != nil {
            commitPendingRenameIfNeeded()
        }

        closeSearchForGroupNavigation()
    }

    private func cancelPendingGroupRename() {
        guard groupRenameTargetID != nil else {
            return
        }

        isGroupRenameCancelPending = true
        cancelRenameGroup()
    }

    private func deleteGroup(_ group: ClipboardGroup) {
        let removedCount = store.deleteGroup(group.id)
        if selectedGroup == .group(group.id) {
            selectedGroup = .all
        }
        showStatus(removedCount > 0 ? "已删除分组和 \(removedCount) 条内容" : "已删除分组")
    }

    private func presentMoveToGroupPicker(for item: HistoryPreviewItem) {
        moveToGroupPickerTarget = MoveToGroupPickerTarget(itemID: item.id, currentGroupID: item.groupID)
    }

    private func addItem(_ id: ClipboardItem.ID?, toGroup groupID: ClipboardGroup.ID, named groupName: String? = nil) {
        store.addItem(id, toGroup: groupID)
        if let groupName {
            showStatus("已移动到“\(groupName)”")
        } else {
            showStatus("已加入分组")
        }
    }

    private func removeItemFromGroup(_ id: ClipboardItem.ID?) {
        store.removeItemFromGroup(id)
        showStatus("已移出分组")
    }

    private func addDebugTextItems(count: Int) {
        appMenuController.addDebugTextItems(count: count)
        showStatus("正在生成 \(count) 条测试文本")
    }

    private func clearDebugTextItems() {
        let removedCount = appMenuController.clearDebugTextItems()
        showStatus(removedCount > 0 ? "已清除 \(removedCount) 条测试文本" : "没有测试文本")
    }

    private func togglePinned(_ id: ClipboardItem.ID?) {
        guard let item = store.item(with: id) else {
            return
        }

        store.togglePinned(for: id)
        showStatus(item.isPinned ? "已取消置顶" : "已置顶")
    }

    private func sourceAppIgnoreMenuTitle(for item: ClipboardItem) -> String {
        let prefix = appMenuController.isSourceAppIgnored(for: item) ? "取消忽略" : "忽略"
        return "\(prefix) \(item.sourceAppName)"
    }

    private func toggleSourceAppIgnored(_ id: ClipboardItem.ID?) {
        guard let item = store.item(with: id),
              item.sourceBundleID != nil else {
            showStatus("无法识别来源 App")
            return
        }

        guard !item.isFromClipEase else {
            showStatus("轻贴自身内容不能忽略")
            return
        }

        if appMenuController.isSourceAppIgnored(for: item) {
            appMenuController.unignoreSourceApp(for: item)
            showStatus("已取消忽略 \(item.sourceAppName)")
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
        addClipEaseTextCard(item.sourceAppName)
        showStatus("已复制来源名称")
        closeAfterContextMenuCommand()
    }

    private func copySourceBundleID(_ id: ClipboardItem.ID?) {
        guard let item = store.item(with: id),
              let bundleID = item.sourceBundleID else {
            showStatus("无来源 Bundle ID")
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(bundleID, forType: .string)
        addClipEaseTextCard(bundleID)
        showStatus("已复制 Bundle ID")
        closeAfterContextMenuCommand()
    }

    private func revealImageInFinder(_ id: ClipboardItem.ID?) {
        guard let item = store.item(with: id),
              let imageURL = store.imageFileURL(for: item) else {
            showStatus("未找到图片文件")
            return
        }

        NSWorkspace.shared.activateFileViewerSelecting([imageURL])
        showStatus("已在 Finder 中显示")
        closeAfterContextMenuCommand()
    }

    private func openImage(_ id: ClipboardItem.ID?) {
        guard let item = store.item(with: id),
              let imageURL = store.imageFileURL(for: item) else {
            showStatus("未找到图片文件")
            return
        }

        NSWorkspace.shared.open(imageURL)
        showStatus("已打开图片")
        closeAfterContextMenuCommand()
    }

    private func copyImage(_ id: ClipboardItem.ID?) {
        guard let item = store.item(with: id),
              let imageURL = store.imageFileURL(for: item),
              let image = NSImage(contentsOf: imageURL) else {
            showStatus("未找到图片文件")
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
        addClipEaseTextCard(item.preview.isEmpty ? imageURL.lastPathComponent : item.preview)
        showStatus("已复制图像")
        closeAfterContextMenuCommand()
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
        addClipEaseTextCard(path)
        showStatus("已复制图片路径")
        closeAfterContextMenuCommand()
    }

    private func copyFilePaths(_ id: ClipboardItem.ID?) {
        guard let item = store.item(with: id),
              item.type == .file else {
            showStatus("未找到文件")
            return
        }

        let paths = item.fileReferences
            .map(\.path)
            .filter { !$0.isEmpty }

        guard !paths.isEmpty else {
            showStatus("未找到文件")
            return
        }

        let pathsText = paths.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(pathsText, forType: .string)
        addClipEaseTextCard(pathsText)
        showStatus(paths.count > 1 ? "已复制 \(paths.count) 个文件路径" : "已复制文件路径")
        closeAfterContextMenuCommand()
    }

    private func copyFile(_ id: ClipboardItem.ID?) {
        guard let item = store.item(with: id),
              item.type == .file else {
            showStatus("未找到文件")
            return
        }

        let urls = existingFileURLs(for: item)
        guard let firstURL = urls.first else {
            showStatus("未找到文件")
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([firstURL as NSURL])
        addClipEaseTextCard(firstURL.path)
        showStatus("已复制文件")
        closeAfterContextMenuCommand()
    }

    private func openFile(_ id: ClipboardItem.ID?) {
        guard let item = store.item(with: id),
              item.type == .file else {
            showStatus("未找到文件")
            return
        }

        let urls = existingFileURLs(for: item)
        guard let firstURL = urls.first else {
            showStatus("未找到文件")
            return
        }

        NSWorkspace.shared.open(firstURL)
        showStatus("已打开文件")
        closeAfterContextMenuCommand()
    }

    private func revealFilesInFinder(_ id: ClipboardItem.ID?) {
        guard let item = store.item(with: id),
              item.type == .file else {
            showStatus("未找到文件")
            return
        }

        let urls = existingFileURLs(for: item)
        guard !urls.isEmpty else {
            showStatus("未找到文件")
            return
        }

        NSWorkspace.shared.activateFileViewerSelecting(urls)
        showStatus("已在 Finder 中显示")
        closeAfterContextMenuCommand()
    }

    private func existingFileURLs(for item: ClipboardItem) -> [URL] {
        guard item.type == .file else {
            return []
        }

        return item.fileReferences.compactMap { reference in
            guard !reference.path.isEmpty else {
                return nil
            }

            let url = URL(fileURLWithPath: reference.path).standardizedFileURL
            guard FileManager.default.fileExists(atPath: url.path) else {
                return nil
            }

            return url
        }
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

    private func selectCardForPrimaryClick(_ item: HistoryPreviewItem) {
        blurSearchFieldForCardInteraction()

        if previewState.isVisible {
            closePreview()
        }

        if selectedItemID != item.id {
            selectedItemID = item.id
        }

        revealPartiallyVisibleCardIfNeeded(item.id)
    }

    private func selectCardForContextMenu(_ item: HistoryPreviewItem) {
        blurSearchFieldForCardInteraction()

        if previewState.isVisible {
            closePreview()
        }

        if selectedItemID != item.id {
            selectedItemID = item.id
        }

        revealPartiallyVisibleCardIfNeeded(item.id)
    }

    private func blurSearchFieldForCardInteraction() {
        guard isSearchFocused || inputState.isTextInputFocusedSnapshot else {
            return
        }

        isSearchFocused = false
        inputState.setTextInputFocused(false)
        hostWindow?.makeFirstResponder(nil)
    }

    private func revealPartiallyVisibleCardIfNeeded(_ id: ClipboardItem.ID) {
        revealPartiallyVisibleCardIfNeeded(id, animated: true)
    }

    private func revealPartiallyVisibleCardIfNeeded(_ id: ClipboardItem.ID, animated: Bool) {
        guard let targetOffset = partialRevealTargetOffset(for: id) else {
            return
        }

        HistoryScrollCoordinator.shared.scrollToOffset(targetOffset, animated: animated)
    }

    private func partialRevealTargetOffset(for id: ClipboardItem.ID) -> CGFloat? {
        guard let frame = cardDocumentFrame(for: id),
              let visibleRect = HistoryScrollCoordinator.shared.visibleDocumentRect else {
            return nil
        }

        let leftVisibleEdge = visibleRect.minX + horizontalContentPadding
        let rightVisibleEdge = visibleRect.maxX - horizontalContentPadding
        guard visibleRect.width > 0,
              rightVisibleEdge > leftVisibleEdge else {
            return nil
        }

        if isFirstRenderedItem(id), frame.minX < leftVisibleEdge {
            return max(0, frame.minX - horizontalContentPadding)
        }

        if isLastRenderedItem(id), frame.maxX > rightVisibleEdge {
            return frame.maxX + horizontalContentPadding - visibleRect.width
        }

        if frame.minX < leftVisibleEdge {
            let targetOffset = frame.minX - edgeRevealLeadingX(for: id, frame: frame)
            return min(targetOffset, visibleRect.minX)
        }

        if frame.maxX > rightVisibleEdge {
            let targetOffset = frame.maxX + edgeRevealTrailingX(for: id, frame: frame) - visibleRect.width
            return max(targetOffset, visibleRect.minX)
        }

        return nil
    }

    private func applyPendingItemScrollIfMeasured(_ id: HistoryPreviewItem.ID) -> Bool {
        if pendingLatestFocusLockID == id,
           let targetOffset = latestClipboardFocusTargetOffset(for: id) {
            HistoryScrollCoordinator.shared.scrollToOffset(
                targetOffset,
                animated: shouldAnimatePendingItemScroll,
                suppressUserOffsetSave: true
            )
            if targetOffset <= 0.5 {
                HistoryScrollCoordinator.shared.saveOffset(0)
            }
            finishLatestFocusIfSettled(id, targetOffset: targetOffset)
            return true
        }

        guard let targetOffset = targetScrollOffsetForFocusedItem(
            id,
            strategy: .programmaticJump
        ) else {
            if let frame = cardDocumentFrame(for: id),
               isFrameFullyVisible(frame) {
                pendingProgrammaticJumpItemID = nil
                pendingItemScrollID = nil
                pendingItemScrollRetryCount = 0
                shouldAnimatePendingItemScroll = false
                isPreparingPendingItemScrollMeasurement = false
                finishLatestFocusIfNeeded(id)
                return true
            }
            return false
        }

        HistoryScrollCoordinator.shared.scrollToOffset(
            targetOffset,
            animated: shouldAnimatePendingItemScroll,
            suppressUserOffsetSave: pendingLatestFocusLockID == id
        )
        if shouldResetHorizontalOffsetForPendingItemScroll,
           targetOffset <= 0.5 {
            HistoryScrollCoordinator.shared.saveOffset(0)
        }
        scheduleSecondPendingItemScrollIfNeeded(id, targetOffset: targetOffset)
        if !shouldResetHorizontalOffsetForPendingItemScroll,
           pendingLatestFocusItemID == id {
            pendingLatestFocusItemID = nil
            pendingLatestFocusTimestamp = nil
            pendingLatestFocusReason = nil
            pendingLatestFocusLockID = nil
        }
        return true
    }

    private func applyPendingProgrammaticJumpIfPossible() {
        guard let id = pendingProgrammaticJumpItemID,
              selectedItemID == id,
              filteredItems.contains(where: { $0.id == id }) else {
            return
        }

        if pendingLatestFocusLockID == id,
           let targetOffset = latestClipboardFocusTargetOffset(for: id) {
            HistoryScrollCoordinator.shared.scrollToOffset(
                targetOffset,
                animated: shouldAnimatePendingItemScroll,
                suppressUserOffsetSave: true
            )
            if targetOffset <= 0.5 {
                HistoryScrollCoordinator.shared.saveOffset(0)
            }
            pendingProgrammaticJumpItemID = nil
            pendingItemScrollID = nil
            pendingItemScrollRetryCount = 0
            shouldResetHorizontalOffsetForPendingItemScroll = false
            shouldAnimatePendingItemScroll = false
            isPreparingPendingItemScrollMeasurement = false
            finishLatestFocusIfSettled(id, targetOffset: targetOffset)
            return
        }

        guard let targetOffset = programmaticJumpTargetOffset(for: id) else {
            if let frame = cardDocumentFrame(for: id),
               isFrameFullyVisible(frame) {
                pendingProgrammaticJumpItemID = nil
                pendingItemScrollID = nil
                pendingItemScrollRetryCount = 0
                shouldAnimatePendingItemScroll = false
                isPreparingPendingItemScrollMeasurement = false
                finishLatestFocusIfNeeded(id)
            }
            return
        }

        if let visibleRect = HistoryScrollCoordinator.shared.visibleDocumentRect,
           abs(visibleRect.minX - targetOffset) <= 0.5 {
            pendingProgrammaticJumpItemID = nil
            pendingItemScrollID = nil
            pendingItemScrollRetryCount = 0
            shouldResetHorizontalOffsetForPendingItemScroll = false
            shouldAnimatePendingItemScroll = false
            isPreparingPendingItemScrollMeasurement = false
            if pendingLatestFocusItemID == id {
                pendingLatestFocusItemID = nil
                pendingLatestFocusTimestamp = nil
                pendingLatestFocusReason = nil
                pendingLatestFocusLockID = nil
            }
            return
        }

        HistoryScrollCoordinator.shared.scrollToOffset(
            targetOffset,
            animated: false,
            suppressUserOffsetSave: pendingLatestFocusLockID == id
        )
        pendingProgrammaticJumpItemID = nil
        pendingItemScrollID = nil
        pendingItemScrollRetryCount = 0
        shouldAnimatePendingItemScroll = false
        isPreparingPendingItemScrollMeasurement = false
        if pendingLatestFocusItemID == id,
           !shouldResetHorizontalOffsetForPendingItemScroll {
            pendingLatestFocusItemID = nil
            pendingLatestFocusTimestamp = nil
            pendingLatestFocusReason = nil
            pendingLatestFocusLockID = nil
        }
    }

    private func latestClipboardFocusTargetOffset(for id: HistoryPreviewItem.ID) -> CGFloat? {
        guard store.items.contains(where: { $0.id == id }) else {
            return nil
        }

        let sourceIndex = store.items.firstIndex(where: { $0.id == id }) ?? store.items.startIndex
        let itemIndex = store.items.distance(from: store.items.startIndex, to: sourceIndex)
        return CGFloat(itemIndex) * (historyCardWidth + horizontalCardSpacing)
    }

    private func programmaticJumpTargetOffset(for id: HistoryPreviewItem.ID) -> CGFloat? {
        guard let index = filteredItems.firstIndex(where: { $0.id == id }) else {
            return nil
        }

        let itemIndex = filteredItems.distance(from: filteredItems.startIndex, to: index)
        let frame = cardDocumentFrame(for: id) ?? CGRect(
            x: horizontalContentPadding + CGFloat(itemIndex) * (historyCardWidth + horizontalCardSpacing),
            y: 0,
            width: historyCardWidth,
            height: 270
        )
        let preferredOffset = frame.minX - focusedItemLeadingX(
            for: id,
            frame: frame,
            forceEdgePeekAlignment: true
        )
        return targetScrollOffsetForFocusedFrame(
            id: id,
            frame: frame,
            visibleWidth: HistoryScrollCoordinator.shared.visibleDocumentRect?.width,
            preferredOffset: preferredOffset
        )
    }

    private func targetScrollOffsetForFocusedItem(
        _ id: HistoryPreviewItem.ID,
        forceEdgePeekAlignment: Bool? = nil,
        strategy: CardScrollTargetStrategy = .visibleOnlyIfClipped
    ) -> CGFloat? {
        guard let frame = cardDocumentFrame(for: id) else {
            return directScrollOffsetForFocusedItem(
                id,
                forceEdgePeekAlignment: forceEdgePeekAlignment,
                strategy: strategy
            )
        }

        if strategy == .programmaticJump,
           isFrameFullyVisible(frame) {
            return nil
        }

        if isFirstRenderedItem(id) {
            return 0
        }

        if strategy == .visibleOnlyIfClipped,
           let targetOffset = targetScrollOffsetForVisibleCardRun(
            id: id,
            frame: frame,
            visibleRect: HistoryScrollCoordinator.shared.visibleDocumentRect
           ) {
            return targetOffset
        }

        return targetScrollOffsetForFocusedFrame(
            id: id,
            frame: frame,
            visibleWidth: HistoryScrollCoordinator.shared.visibleDocumentRect?.width,
            preferredOffset: frame.minX - focusedItemLeadingX(
                for: id,
                frame: frame,
                forceEdgePeekAlignment: forceEdgePeekAlignment
            )
        )
    }

    private func directScrollOffsetForFocusedItem(
        _ id: HistoryPreviewItem.ID,
        forceEdgePeekAlignment: Bool?,
        strategy: CardScrollTargetStrategy
    ) -> CGFloat? {
        guard let index = renderedItems.firstIndex(where: { $0.id == id }) else {
            return nil
        }

        let itemIndex = renderedItems.distance(from: renderedItems.startIndex, to: index)
        let frame = CGRect(
            x: horizontalContentPadding + CGFloat(itemIndex) * (historyCardWidth + horizontalCardSpacing),
            y: 0,
            width: historyCardWidth,
            height: 270
        )

        if strategy == .programmaticJump,
           isFrameFullyVisible(frame) {
            return nil
        }

        if isFirstRenderedItem(id) {
            return 0
        }

        if strategy == .visibleOnlyIfClipped,
           let targetOffset = targetScrollOffsetForVisibleCardRun(
            id: id,
            frame: frame,
            visibleRect: HistoryScrollCoordinator.shared.visibleDocumentRect
           ) {
            return targetOffset
        }

        return targetScrollOffsetForFocusedFrame(
            id: id,
            frame: frame,
            visibleWidth: HistoryScrollCoordinator.shared.visibleDocumentRect?.width,
            preferredOffset: frame.minX - focusedItemLeadingX(
                for: id,
                frame: frame,
                forceEdgePeekAlignment: forceEdgePeekAlignment
            )
        )
    }

    private func targetScrollOffsetForVisibleCardRun(
        id: HistoryPreviewItem.ID,
        frame: CGRect,
        visibleRect: CGRect?
    ) -> CGFloat? {
        partialRevealTargetOffset(for: id)
    }

    private func isFrameFullyVisible(_ frame: CGRect) -> Bool {
        guard let visibleRect = HistoryScrollCoordinator.shared.visibleDocumentRect else {
            return false
        }

        let leftVisibleEdge = visibleRect.minX + horizontalContentPadding
        let rightVisibleEdge = visibleRect.maxX - horizontalContentPadding
        return frame.minX >= leftVisibleEdge && frame.maxX <= rightVisibleEdge
    }

    private func targetScrollOffsetForFocusedFrame(
        id: HistoryPreviewItem.ID,
        frame: CGRect,
        visibleWidth: CGFloat?,
        preferredOffset: CGFloat
    ) -> CGFloat {
        guard let visibleWidth,
              adjacentRenderedItemID(after: id) != nil,
              visibleWidth > frame.width else {
            return preferredOffset
        }

        if isFirstRenderedItem(id) {
            return 0
        }

        let nextPeekOffset = frame.maxX + edgeRevealTrailingX(for: id, frame: frame) - visibleWidth
        return max(preferredOffset, nextPeekOffset)
    }

    private enum CardScrollTargetStrategy {
        case visibleOnlyIfClipped
        case programmaticJump
    }

    private func cardDocumentFrame(for id: HistoryPreviewItem.ID) -> CGRect? {
        guard let itemIndex = renderedItemIndex(for: id) else {
            return nil
        }

        return cardDocumentFrame(forRenderedIndex: itemIndex)
    }

    private func cardViewportFrame(for id: HistoryPreviewItem.ID) -> CGRect? {
        guard let documentFrame = cardDocumentFrame(for: id) else {
            return nil
        }

        return documentFrame.offsetBy(
            dx: -HistoryScrollCoordinator.shared.currentOffset,
            dy: cardRailTopInWindow + selectedCardTopContentInset
        )
    }

    private func focusedItemLeadingX(
        for id: HistoryPreviewItem.ID,
        frame: CGRect,
        forceEdgePeekAlignment: Bool? = nil
    ) -> CGFloat {
        if forceEdgePeekAlignment ?? shouldResetHorizontalOffsetForPendingItemScroll {
            return edgeRevealLeadingX(for: id, frame: frame)
        }

        let leadingPeek = leadingPeekWidth(for: id, fallback: oneSixthPeekWidth(for: frame))
        let spacingBeforePeek = leadingPeek > 0 ? horizontalCardSpacing : 0
        return horizontalContentPadding + spacingBeforePeek + leadingPeek
    }

    private func edgeRevealLeadingX(for id: HistoryPreviewItem.ID, frame: CGRect) -> CGFloat {
        let leadingPeek = leadingPeekWidth(for: id, fallback: oneSixthPeekWidth(for: frame))
        let spacingBeforePeek = leadingPeek > 0 ? horizontalCardSpacing : 0
        return spacingBeforePeek + leadingPeek
    }

    private func edgeRevealTrailingX(for id: HistoryPreviewItem.ID, frame: CGRect) -> CGFloat {
        let trailingPeek = trailingPeekWidth(for: id, fallback: oneSixthPeekWidth(for: frame))
        let spacingAfterPeek = trailingPeek > 0 ? horizontalCardSpacing : 0
        let trailingContentInset = trailingPeek > 0 ? horizontalContentPadding : 0
        return spacingAfterPeek + trailingPeek + trailingContentInset
    }

    private func isFirstRenderedItem(_ id: HistoryPreviewItem.ID) -> Bool {
        renderedItems.first?.id == id
    }

    private func isLastRenderedItem(_ id: HistoryPreviewItem.ID) -> Bool {
        renderedItems.last?.id == id
    }

    private func leadingPeekWidth(for id: HistoryPreviewItem.ID, fallback: CGFloat) -> CGFloat {
        guard let previousID = adjacentRenderedItemID(before: id),
              let previousIndex = renderedItemIndex(for: previousID) else {
            return 0
        }

        return oneSixthPeekWidth(for: cardDocumentFrame(forRenderedIndex: previousIndex))
    }

    private func trailingPeekWidth(for id: HistoryPreviewItem.ID, fallback: CGFloat) -> CGFloat {
        guard let nextID = adjacentRenderedItemID(after: id),
              let nextIndex = renderedItemIndex(for: nextID) else {
            return fallback
        }

        return oneSixthPeekWidth(for: cardDocumentFrame(forRenderedIndex: nextIndex))
    }

    private func oneSixthPeekWidth(for frame: CGRect) -> CGFloat {
        frame.width / 6
    }

    private func renderedItemIndex(for id: HistoryPreviewItem.ID) -> Int? {
        guard let index = renderedItems.firstIndex(where: { $0.id == id }) else {
            return nil
        }

        return renderedItems.distance(from: renderedItems.startIndex, to: index)
    }

    private func cardDocumentFrame(forRenderedIndex itemIndex: Int) -> CGRect {
        CGRect(
            x: horizontalContentPadding + CGFloat(itemIndex) * (historyCardWidth + horizontalCardSpacing),
            y: 0,
            width: historyCardWidth,
            height: 270
        )
    }

    private func adjacentRenderedItemID(before id: HistoryPreviewItem.ID) -> HistoryPreviewItem.ID? {
        guard let index = renderedItems.firstIndex(where: { $0.id == id }),
              index > renderedItems.startIndex else {
            return nil
        }

        return renderedItems[renderedItems.index(before: index)].id
    }

    private func adjacentRenderedItemID(after id: HistoryPreviewItem.ID) -> HistoryPreviewItem.ID? {
        guard let index = renderedItems.firstIndex(where: { $0.id == id }) else {
            return nil
        }

        let nextIndex = renderedItems.index(after: index)
        guard nextIndex < renderedItems.endIndex else {
            return nil
        }

        return renderedItems[nextIndex].id
    }

    private func closePreview() {
        previewState.close()
        inputState.setPreviewActive(false)
        onClosePreview()
    }

    private func showStatus(_ text: String) {
        statusGeneration &+= 1
        let generation = statusGeneration
        statusText = text
        GlobalStatusToastController.shared.show(text, relativeTo: hostWindow)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            if statusGeneration == generation {
                statusText = nil
            }
        }
    }

    private func copyStatus(for item: ClipboardItem) -> String {
        switch item.type {
        case .text:
            item.richTextFileName == nil ? "已复制文本" : "已复制富文本"
        case .link:
            "已复制链接"
        case .image:
            "已复制图片"
        case .color:
            "已复制颜色"
        case .file:
            "已复制文件引用"
        }
    }

    private func addClipEaseTextCard(_ text: String) {
        store.addText(text, sourceApp: .clipease)
    }

    private func copyFallbackTextStatus(for item: ClipboardItem) -> String {
        switch item.type {
        case .file:
            "文件不可用，已复制文件路径"
        default:
            copyStatus(for: item)
        }
    }

    private func copiedOnlyStatus(for item: ClipboardItem) -> String {
        switch item.type {
        case .text:
            item.richTextFileName == nil ? "已复制文本，需授权后自动粘贴" : "已复制富文本，需授权后自动粘贴"
        case .link:
            "已复制链接，需授权后自动粘贴"
        case .image:
            "已复制图片，需授权后自动粘贴"
        case .color:
            "已复制颜色，需授权后自动粘贴"
        case .file:
            "已复制文件引用，需授权后自动粘贴"
        }
    }

    private func copiedOnlyFallbackTextStatus(for item: ClipboardItem) -> String {
        switch item.type {
        case .file:
            "文件不可用，已复制文件路径，需授权后自动粘贴"
        default:
            copiedOnlyStatus(for: item)
        }
    }

    private func pastedStatus(for item: ClipboardItem) -> String {
        switch item.type {
        case .text:
            item.richTextFileName == nil ? "已粘贴文本到当前 App" : "已粘贴富文本到当前 App"
        case .link:
            "已粘贴链接到当前 App"
        case .image:
            "已粘贴图片到当前 App"
        case .color:
            "已粘贴颜色到当前 App"
        case .file:
            "已粘贴文件引用到当前 App"
        }
    }

    private func pastedFallbackTextStatus(for item: ClipboardItem) -> String {
        switch item.type {
        case .file:
            "文件不可用，已粘贴文件路径到当前 App"
        default:
            pastedStatus(for: item)
        }
    }

    private func toggleSearch() {
        if isSearchVisible {
            withAnimation(.easeOut(duration: 0.12)) {
                clearSearch()
            }
        } else {
            openSearch()
        }
    }

    private func clearSearch() {
        if !isSearchActive {
            closeSearch()
        } else {
            clearSearchTextAndFilters()
        }
    }

    private func clearSearchText() {
        let fallbackID = selectedItemID
        searchText = ""
        selectedSearchTokenKind = nil
        isSearchFocused = isSearchVisible
        inputState.setTextInputFocused(isSearchVisible)
        restoreSelectionAfterClearingSearch(preferredID: fallbackID)
    }

    private func clearSearchTextAndFilters() {
        let fallbackID = selectedItemID
        searchText = ""
        searchCriteria = HistorySearchCriteria()
        selectedSearchTokenKind = nil
        isSearchFocused = isSearchVisible
        inputState.setTextInputFocused(isSearchVisible)
        restoreSelectionAfterClearingSearch(preferredID: fallbackID)
    }

    private func closeSearch() {
        withAnimation(.easeOut(duration: 0.12)) {
            isSearchVisible = false
            isSearchFocused = false
        }
        inputState.setTextInputFocused(false)
        inputState.setSearchVisible(false)
    }

    private func closeSearchFromOutsideClick() {
        guard isSearchVisible else {
            return
        }

        guard !hasSearchContent else {
            return
        }

        closeSearch()
    }

    private func refreshSearchInteractionScreenFrames() {
        guard isSearchVisible,
              let hostWindow else {
            searchInteractionScreenFrames = []
            return
        }

        var frames: [CGRect] = []
        if let searchControlScreenFrame {
            frames.append(searchControlScreenFrame.standardized.insetBy(dx: -6, dy: -6))
        }

        for window in NSApp.windows where window.isVisible && window !== hostWindow {
            let className = String(describing: type(of: window))
            let isSearchRelatedPanel = className.contains("Popover") || window.level.rawValue >= NSWindow.Level.popUpMenu.rawValue
            if isSearchFilterPanelPresented && isSearchRelatedPanel {
                frames.append(window.frame.insetBy(dx: -8, dy: -8))
            }
        }

        searchInteractionScreenFrames = frames
    }

    private func clearAndCloseSearch() {
        let fallbackID = selectedItemID
        searchText = ""
        searchCriteria = HistorySearchCriteria()
        selectedSearchTokenKind = nil
        restoreSelectionAfterClearingSearch(preferredID: fallbackID)
        closeSearch()
    }

    private func closeSearchForGroupNavigation() {
        guard isSearchVisible || isSearchActive else {
            return
        }

        clearAndCloseSearch()
    }

    private func closeInactiveSearchBeforeHiding() {
        guard isSearchVisible, !isSearchActive else {
            return
        }

        closeSearch()
    }

    private func openSearch() {
        selectedGroup = .all
        withAnimation(.easeOut(duration: 0.12)) {
            isSearchVisible = true
        }
        inputState.setSearchVisible(true)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 20_000_000)
            focusSearchField()
        }
    }

    private func handleCommandFSearch() {
        if !isSearchVisible {
            openSearch()
        } else if isSearchFilterPanelPresented {
            isSearchFilterPanelPresented = false
            focusSearchField()
        } else {
            isSearchFilterPanelPresented = true
        }
    }

    private func toggleSearchFilterPanel() {
        isSearchFilterPanelPresented.toggle()
        if isSearchFilterPanelPresented {
            isSearchFocused = false
            inputState.setTextInputFocused(false)
        } else {
            focusSearchField()
        }
    }

    private func sourceAppIconFileName(_ appName: String) -> String? {
        sourceAppIconFileNames[appName]
    }

    private func toggleSearchType(_ type: HistorySearchItemType) {
        if searchCriteria.types.contains(type) {
            searchCriteria.types.remove(type)
        } else {
            searchCriteria.types.insert(type)
        }
    }

    private func toggleSearchSourceApp(_ appName: String) {
        if searchCriteria.sourceAppNames.contains(appName) {
            searchCriteria.sourceAppNames.remove(appName)
        } else {
            searchCriteria.sourceAppNames.insert(appName)
        }
    }

    private func toggleSearchDateRange(_ range: HistorySearchDateRange) {
        if searchCriteria.dateRanges.contains(range) {
            searchCriteria.dateRanges.remove(range)
        } else {
            searchCriteria.dateRanges.insert(range)
        }
    }

    private func toggleSearchGroup(_ group: HistorySearchGroup) {
        if searchCriteria.groups.contains(group) {
            searchCriteria.groups.remove(group)
        } else {
            searchCriteria.groups.insert(group)
        }
    }

    private func removeSearchToken(_ token: HistorySearchToken) {
        switch token.kind {
        case .type(let type):
            searchCriteria.types.remove(type)
        case .sourceApp(let appName):
            searchCriteria.sourceAppNames.remove(appName)
        case .date(let range):
            searchCriteria.dateRanges.remove(range)
        case .group(let group):
            searchCriteria.groups.remove(group)
        }

        selectedSearchTokenKind = nil
        focusSearchField()
    }

    private func handleSearchTokenBackspace() {
        if let selectedSearchTokenKind,
           let selectedToken = searchTokens.first(where: { $0.kind == selectedSearchTokenKind }) {
            removeSearchToken(selectedToken)
            return
        }

        guard let token = searchTokens.last else {
            return
        }

        selectedSearchTokenKind = token.kind
        focusSearchField()
    }

    private func schedulePreviewItemsRebuild(from sourceItems: [ClipboardItem]) {
        let sourceSignature = sourceItems.map(HistoryPreviewSourceSignature.init)
        guard sourceSignature != previewItemsSourceSignature else {
            scheduleSearchUpdate(sourceItems: allPreviewItems, immediate: true)
            convergeLatestClipboardFocusIfNeeded()
            return
        }

        previewItemsSourceSignature = sourceSignature
        previewBuildTask?.cancel()
        previewBuildGeneration &+= 1
        let generation = previewBuildGeneration
        let currentSelectedID = selectedItemID ?? rememberedSelectedItemUUID()
        let currentPreviewedItemID = previewState.itemID
        let currentLatestClipboardFocusGeneration = latestClipboardFocusGeneration
        let currentPreviewItemCache = previewItemCache

        previewBuildTask = Task {
            let buildTask = Task.detached(priority: .userInitiated) {
                var previewItems: [HistoryPreviewItem] = []
                previewItems.reserveCapacity(sourceItems.count)
                var nextCache: [ClipboardItem.ID: CachedHistoryPreviewItem] = [:]
                nextCache.reserveCapacity(sourceItems.count)

                for item in sourceItems {
                    try Task.checkCancellation()
                    let signature = HistoryPreviewSourceSignature(item: item)
                    let previewItem: HistoryPreviewItem
                    if let cachedItem = currentPreviewItemCache[item.id],
                       cachedItem.signature == signature {
                        previewItem = cachedItem.item
                    } else {
                        previewItem = HistoryPreviewItem(item: item)
                    }

                    previewItems.append(previewItem)
                    nextCache[item.id] = CachedHistoryPreviewItem(
                        signature: signature,
                        item: previewItem
                    )
                }

                try Task.checkCancellation()
                return (previewItems, nextCache)
            }

            let previewItems: [HistoryPreviewItem]
            let nextCache: [ClipboardItem.ID: CachedHistoryPreviewItem]
            do {
                (previewItems, nextCache) = try await withTaskCancellationHandler {
                    try await buildTask.value
                } onCancel: {
                    buildTask.cancel()
                }
            } catch is CancellationError {
                return
            } catch {
                return
            }

            guard !Task.isCancelled else {
                return
            }

            await MainActor.run {
                guard !Task.isCancelled, previewBuildGeneration == generation else {
                    return
                }

                var transaction = Transaction()
                let shouldAnimateLatestReorder = pendingLatestFocusItemID != nil && inputState.isWindowPresentedSnapshot
                if shouldAnimateLatestReorder {
                    transaction.animation = .easeOut(duration: pendingLatestFocusReason == .refreshed ? 0.34 : 0.30)
                } else {
                    transaction.disablesAnimations = true
                }
                withTransaction(transaction) {
                    previewItemCache = nextCache
                    allPreviewItems = previewItems
                }
                renderState.mark("preview-items-ready count=\(previewItems.count)")

                scheduleSearchUpdate(sourceItems: previewItems, immediate: true)
                if pendingLatestFocusItemID == nil,
                   currentLatestClipboardFocusGeneration == latestClipboardFocusGeneration {
                    restoreSelectionAfterPreviewRebuild(
                        preferredID: currentSelectedID,
                        previewedID: currentPreviewedItemID,
                        sourceItems: sourceItems
                    )
                } else if let currentPreviewedItemID,
                          !sourceItems.contains(where: { $0.id == currentPreviewedItemID }) {
                    closePreview()
                }
            }
        }
    }

    private func scheduleSearchUpdate(
        immediate: Bool = false,
        debounceNanoseconds: UInt64 = 90_000_000
    ) {
        scheduleSearchUpdate(
            sourceItems: allPreviewItems,
            immediate: immediate,
            debounceNanoseconds: debounceNanoseconds
        )
    }

    private func scheduleSearchUpdate(
        sourceItems: [HistoryPreviewItem],
        immediate: Bool = false,
        debounceNanoseconds: UInt64 = 90_000_000
    ) {
        searchTask?.cancel()
        searchGeneration &+= 1
        let generation = searchGeneration
        let currentGroup: HistoryGroupSelection = isSearchVisible ? .all : selectedGroup
        let currentSearchText = searchText
        let currentSearchCriteria = searchCriteria
        let requestSignature = HistorySearchRequestSignature(
            sourceItems: sourceItems.map(HistorySearchSourceSignature.init),
            selectedGroup: currentGroup.storageValue,
            searchText: currentSearchText,
            criteria: currentSearchCriteria
        )
        guard requestSignature != lastSearchRequestSignature else {
            return
        }
        lastSearchRequestSignature = requestSignature

        searchTask = Task(priority: .userInitiated) {
            if !immediate {
                try? await Task.sleep(nanoseconds: debounceNanoseconds)
            }

            guard !Task.isCancelled else {
                return
            }

            let filterTask = Task.detached(priority: .userInitiated) {
                try Self.filterItems(
                    sourceItems,
                    selectedGroup: currentGroup,
                    searchText: currentSearchText,
                    criteria: currentSearchCriteria,
                    now: Date()
                )
            }

            let result: [HistoryPreviewItem]
            do {
                result = try await withTaskCancellationHandler {
                    try await filterTask.value
                } onCancel: {
                    filterTask.cancel()
                }
            } catch is CancellationError {
                return
            } catch {
                return
            }

            guard !Task.isCancelled else {
                return
            }

            await MainActor.run {
                guard searchGeneration == generation else {
                    return
                }

                var transaction = Transaction()
                let shouldAnimateLatestReorder = pendingLatestFocusItemID != nil && inputState.isWindowPresentedSnapshot
                if shouldAnimateLatestReorder {
                    transaction.animation = .easeOut(duration: pendingLatestFocusReason == .refreshed ? 0.34 : 0.30)
                } else {
                    transaction.disablesAnimations = true
                }
                withTransaction(transaction) {
                    filteredPreviewItems = result
                    if pendingLatestFocusItemID == nil {
                        ensureSelectionInFilteredItems()
                    }
                }
                renderState.mark("filtered-items-ready count=\(result.count)")
                restoreRememberedViewportIfNeeded()
                fulfillPendingLatestFocusIfPossible()
                convergeLatestClipboardFocusIfNeeded()
                applyPendingProgrammaticJumpIfPossible()
                schedulePreheatVisibleAssets()
            }
        }
    }

    nonisolated private static func filterItems(
        _ items: [HistoryPreviewItem],
        selectedGroup: HistoryGroupSelection,
        searchText: String,
        criteria: HistorySearchCriteria,
        now: Date
    ) throws -> [HistoryPreviewItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedQuery = query.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)

        var result: [HistoryPreviewItem] = []
        result.reserveCapacity(items.count)

        for item in items {
            try Task.checkCancellation()

            switch selectedGroup {
            case .all:
                break
            case .pinned:
                if !item.isPinned {
                    continue
                }
            case .group(let selectedGroupID):
                if item.groupID != selectedGroupID {
                    continue
                }
            }

            if !criteria.types.isEmpty,
               !criteria.types.contains(where: { item.type == $0.previewType }) {
                continue
            }

            if !criteria.sourceAppNames.isEmpty,
               !criteria.sourceAppNames.contains(item.sourceAppName) {
                continue
            }

            if !criteria.dateRanges.isEmpty,
               !criteria.dateRanges.contains(where: { $0.contains(item.createdAt, now: now) }) {
                continue
            }

            if !criteria.groups.isEmpty,
               !criteria.groups.contains(where: { itemMatchesSearchGroup(item, group: $0) }) {
                continue
            }

            guard !normalizedQuery.isEmpty else {
                result.append(item)
                continue
            }

            if item.normalizedSearchText.contains(normalizedQuery) {
                result.append(item)
            }
        }

        try Task.checkCancellation()

        if case .group = selectedGroup {
            result.sort(by: {
                ($0.groupedAt ?? .distantPast) > ($1.groupedAt ?? .distantPast)
            })
        }

        try Task.checkCancellation()
        return result
    }

    nonisolated private static func itemMatchesSearchGroup(
        _ item: HistoryPreviewItem,
        group: HistorySearchGroup
    ) -> Bool {
        switch group {
        case .pinned:
            item.isPinned
        case .group(let groupID):
            item.groupID == groupID
        }
    }

    private func ensureSelectionInFilteredItems() {
        if filteredItems.isEmpty {
            selectedItemID = nil
            closePreview()
            return
        }

        if let selectedItemID,
           filteredItems.contains(where: { $0.id == selectedItemID }) {
            if previewState.isVisible,
               previewState.itemID != selectedItemID {
                showPreview(selectedItemID)
            }
            return
        }

        let fallbackID = filteredItems.first?.id
        selectedItemID = fallbackID
        if previewState.isVisible {
            showPreview(fallbackID)
        }
    }

    private func syncLatestItemFocusIfNeeded(sourceItems: [ClipboardItem]) {
        let newestItem = sourceItems.first
        let newestID = newestItem?.id
        let newestTimestamp = newestItem?.createdAt ?? .distantPast
        let previousObservedItemIDs = observedItemIDs
        let previousObservedItemTimestamps = observedItemTimestamps
        let currentObservedItemIDs = Set(sourceItems.map(\.id))
        let currentObservedItemTimestamps = Dictionary(uniqueKeysWithValues: sourceItems.map { ($0.id, $0.createdAt) })
        let newlyInsertedItemID = previousObservedItemIDs.isEmpty
            ? nil
            : sourceItems.first(where: { !previousObservedItemIDs.contains($0.id) })?.id
        let refreshedItemID = sourceItems.first { item in
            guard let previousTimestamp = previousObservedItemTimestamps[item.id] else {
                return false
            }

            return item.createdAt > previousTimestamp.addingTimeInterval(0.001)
        }?.id
        let focusCandidateID = newlyInsertedItemID ?? refreshedItemID ?? pendingNewestItemIDForNextShow
        let focusCandidateTimestamp = focusCandidateID.flatMap { id in
            sourceItems.first(where: { $0.id == id })?.createdAt
        }
        defer {
            lastObservedNewestItemID = newestID
            latestPresentedItemTimestamp = newestTimestamp
            observedItemIDs = currentObservedItemIDs
            observedItemTimestamps = currentObservedItemTimestamps
        }

        guard let focusCandidateID else {
            return
        }

        pendingNewestItemIDForNextShow = nil
        resetFiltersForLatestItemFocus()
        latestClipboardFocusGeneration &+= 1
        selectedItemID = focusCandidateID
        pendingLatestFocusItemID = focusCandidateID
        pendingLatestFocusTimestamp = focusCandidateTimestamp
        pendingLatestFocusReason = newlyInsertedItemID == focusCandidateID ? .inserted : .refreshed
        pendingLatestFocusLockID = focusCandidateID
        shouldResetHorizontalOffsetForPendingItemScroll = true
        HistoryScrollCoordinator.shared.discardSavedOffset(for: HistoryGroupSelection.all.storageValue)
        fulfillPendingLatestFocusIfPossible()
    }

    private func focusRecentlyAddedItemOnShowIfNeeded(sourceItems: [ClipboardItem]) {
        guard inputState.isWindowPresentedSnapshot,
              pendingLatestFocusItemID == nil,
              let newestChangedItem = sourceItems.max(by: latestChangedItemSort),
              newestChangedItem.createdAt > latestPresentedItemTimestamp.addingTimeInterval(0.001) else {
            return
        }

        resetFiltersForLatestItemFocus()
        latestClipboardFocusGeneration &+= 1
        selectedItemID = newestChangedItem.id
        pendingLatestFocusItemID = newestChangedItem.id
        pendingLatestFocusTimestamp = newestChangedItem.createdAt
        pendingLatestFocusReason = observedItemIDs.contains(newestChangedItem.id) ? .refreshed : .inserted
        pendingLatestFocusLockID = newestChangedItem.id
        shouldResetHorizontalOffsetForPendingItemScroll = true
        HistoryScrollCoordinator.shared.discardSavedOffset(for: HistoryGroupSelection.all.storageValue)
        fulfillPendingLatestFocusIfPossible()
    }

    private func convergeLatestClipboardFocusIfNeeded() {
        guard pendingLatestFocusItemID != nil,
              let newestChangedItem = latestChangedFocusItemCandidate() else {
            return
        }

        if pendingLatestFocusItemID != newestChangedItem.id,
           filteredItems.contains(where: { $0.id == newestChangedItem.id }) {
            pendingLatestFocusItemID = newestChangedItem.id
            pendingLatestFocusTimestamp = newestChangedItem.createdAt
            pendingLatestFocusReason = .refreshed
            pendingLatestFocusLockID = newestChangedItem.id
            shouldResetHorizontalOffsetForPendingItemScroll = true
        }

        fulfillPendingLatestFocusIfPossible()
    }

    private func latestChangedFocusItemCandidate() -> ClipboardItem? {
        let newestByTimestamp = store.items.max(by: latestChangedItemSort)

        guard let pendingLatestFocusTimestamp,
              let newestByTimestamp,
              newestByTimestamp.createdAt > pendingLatestFocusTimestamp.addingTimeInterval(0.001) else {
            return pendingLatestFocusItemID.flatMap { store.item(with: $0) } ?? newestByTimestamp
        }

        return newestByTimestamp
    }

    private func latestChangedItemSort(_ left: ClipboardItem, _ right: ClipboardItem) -> Bool {
        if left.createdAt != right.createdAt {
            return left.createdAt < right.createdAt
        }

        return (left.pinnedAt ?? left.createdAt) < (right.pinnedAt ?? right.createdAt)
    }

    private func fulfillPendingLatestFocusIfPossible() {
        guard let pendingLatestFocusItemID,
              filteredItems.contains(where: { $0.id == pendingLatestFocusItemID }) else {
            return
        }

        selectedItemID = pendingLatestFocusItemID
        latestPresentedItemID = pendingLatestFocusItemID
        latestPresentedItemTimestamp = filteredItems.first(where: { $0.id == pendingLatestFocusItemID })?.createdAt ?? latestPresentedItemTimestamp

        if previewState.isVisible {
            showPreview(pendingLatestFocusItemID)
        }

        scheduleLatestProgrammaticTransition(
            to: pendingLatestFocusItemID,
            reason: pendingLatestFocusReason,
            resetToAll: shouldResetHorizontalOffsetForPendingItemScroll,
            animateWhenPresented: inputState.isWindowPresentedSnapshot
        )
    }

    private func scheduleLatestProgrammaticTransition(
        to id: ClipboardItem.ID,
        reason: ClipboardItemFocusRequest.Reason?,
        resetToAll: Bool,
        animateWhenPresented: Bool
    ) {
        selectedItemID = id
        pendingLatestFocusItemID = id
        pendingLatestFocusReason = reason
        pendingLatestFocusLockID = id
        pendingProgrammaticJumpItemID = id
        shouldResetHorizontalOffsetForPendingItemScroll = resetToAll
        shouldAnimatePendingItemScroll = animateWhenPresented && inputState.isWindowPresentedSnapshot
        if resetToAll {
            HistoryScrollCoordinator.shared.discardSavedOffset(for: HistoryGroupSelection.all.storageValue)
        }
        scrollToItemWhenRendered(id, animated: shouldAnimatePendingItemScroll)
        applyPendingProgrammaticJumpIfPossible()
        retryPendingLatestFocusJumpIfNeeded(id, remainingAttempts: 4)
    }

    private func retryPendingLatestFocusJumpIfNeeded(_ id: HistoryPreviewItem.ID, remainingAttempts: Int) {
        guard remainingAttempts > 0 else {
            return
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 16_000_000)
            guard pendingLatestFocusItemID == id,
                  selectedItemID == id,
                  filteredItems.contains(where: { $0.id == id }) else {
                return
            }

            HistoryScrollCoordinator.shared.forceLayout()
            pendingProgrammaticJumpItemID = id
            scrollToItemWhenRendered(id, animated: false)
            retryPendingLatestFocusJumpIfNeeded(id, remainingAttempts: remainingAttempts - 1)
        }
    }

    private func finishLatestFocusIfNeeded(_ id: HistoryPreviewItem.ID) {
        guard pendingLatestFocusItemID == id else {
            return
        }

        pendingLatestFocusItemID = nil
        pendingLatestFocusTimestamp = nil
        pendingLatestFocusReason = nil
        pendingLatestFocusLockID = nil
        shouldResetHorizontalOffsetForPendingItemScroll = false
    }

    private func finishLatestFocusIfSettled(_ id: HistoryPreviewItem.ID, targetOffset: CGFloat) {
        guard let visibleRect = HistoryScrollCoordinator.shared.visibleDocumentRect,
              abs(visibleRect.minX - targetOffset) <= 0.5 else {
            pendingProgrammaticJumpItemID = id
            scrollToItemWhenRendered(id, animated: false)
            retryPendingLatestFocusJumpIfNeeded(id, remainingAttempts: 4)
            return
        }

        finishLatestFocusIfNeeded(id)
    }

    private func primeLatestItemPresentationGuard(sourceItems: [ClipboardItem]) {
        let newestID = sourceItems.first?.id
        lastObservedNewestItemID = newestID
        latestPresentedItemID = newestID
        latestPresentedItemTimestamp = sourceItems.first?.createdAt ?? .distantPast
        observedItemIDs = Set(sourceItems.map(\.id))
        observedItemTimestamps = Dictionary(uniqueKeysWithValues: sourceItems.map { ($0.id, $0.createdAt) })
    }

    private func focusRequestedLatestItem(_ request: ClipboardItemFocusRequest) {
        prepareLatestItemFocus(
            itemID: request.itemID,
            timestamp: store.item(with: request.itemID)?.createdAt,
            reason: request.reason,
            resetToAll: true
        )
        fulfillPendingLatestFocusIfPossible()
    }

    private func focusRequestedItem(_ request: HistoryItemFocusRequest) {
        prepareLatestItemFocus(
            itemID: request.itemID,
            timestamp: store.item(with: request.itemID)?.createdAt,
            reason: nil,
            resetToAll: request.resetToAll
        )
        fulfillPendingLatestFocusIfPossible()
    }

    private func prepareLatestItemFocus(
        itemID: ClipboardItem.ID,
        timestamp: Date?,
        reason: ClipboardItemFocusRequest.Reason?,
        resetToAll: Bool
    ) {
        if resetToAll, selectedGroup != .all {
            selectedGroup = .all
            rememberSelectedGroup()
            HistoryScrollCoordinator.shared.setScope(selectedGroup.storageValue)
        }
        if resetToAll, isSearchVisible || isSearchActive {
            searchText = ""
            searchCriteria = HistorySearchCriteria()
            selectedSearchTokenKind = nil
            isSearchVisible = false
            isSearchFocused = false
            inputState.setSearchVisible(false)
            inputState.setTextInputFocused(false)
        }

        selectedItemID = itemID
        pendingLatestFocusItemID = itemID
        pendingLatestFocusTimestamp = timestamp
        pendingLatestFocusReason = reason
        pendingLatestFocusLockID = itemID
        latestClipboardFocusGeneration &+= 1
        shouldResetHorizontalOffsetForPendingItemScroll = resetToAll
        lastObservedNewestItemID = itemID
        pendingNewestItemIDForNextShow = nil
        latestPresentedItemID = nil
        if resetToAll {
            HistoryScrollCoordinator.shared.discardSavedOffset(for: HistoryGroupSelection.all.storageValue)
        }
    }

    private func scrollToItemWhenRendered(_ id: HistoryPreviewItem.ID, animated: Bool = false) {
        pendingItemScrollID = id
        pendingItemScrollRetryCount = 0
        shouldAnimatePendingItemScroll = pendingProgrammaticJumpItemID == id ? animated : (animated || id == pendingLatestFocusItemID)

        Task { @MainActor in
            await Task.yield()
            guard pendingItemScrollID == id,
                  renderedItems.contains(where: { $0.id == id }) else {
                return
            }

            itemScrollRequestID = UUID()
        }
    }

    private func scheduleSecondPendingItemScrollIfNeeded(_ id: HistoryPreviewItem.ID, targetOffset: CGFloat) {
        guard shouldResetHorizontalOffsetForPendingItemScroll else {
            return
        }

        Task { @MainActor in
            await Task.yield()
            guard selectedItemID == id,
                  filteredItems.contains(where: { $0.id == id }),
                  let refreshedTargetOffset = targetScrollOffsetForFocusedItem(
                    id,
                    forceEdgePeekAlignment: true
                  ) else {
                return
            }

            if abs(refreshedTargetOffset - targetOffset) > 0.5 {
                HistoryScrollCoordinator.shared.scrollToOffset(
                    refreshedTargetOffset,
                    animated: false,
                    suppressUserOffsetSave: pendingLatestFocusLockID == id
                )
                if refreshedTargetOffset <= 0.5 {
                    HistoryScrollCoordinator.shared.saveOffset(0)
                }
            }

            if pendingLatestFocusItemID == id,
               pendingItemScrollID == nil {
                pendingLatestFocusItemID = nil
                pendingLatestFocusTimestamp = nil
                pendingLatestFocusReason = nil
                pendingLatestFocusLockID = nil
                shouldResetHorizontalOffsetForPendingItemScroll = false
            }
        }
    }

    private func resetFiltersForLatestItemFocus() {
        if selectedGroup != .all {
            selectedGroup = .all
            rememberSelectedGroup()
        }

        guard isSearchVisible || isSearchActive else {
            return
        }

        searchText = ""
        searchCriteria = HistorySearchCriteria()
        selectedSearchTokenKind = nil
        isSearchVisible = false
        isSearchFocused = false
        inputState.setSearchVisible(false)
        inputState.setTextInputFocused(false)
    }

    private func restoreSelectionAfterClearingSearch(preferredID: HistoryPreviewItem.ID?) {
        if let preferredID,
           filteredItems.contains(where: { $0.id == preferredID }) {
            selectedItemID = preferredID
        } else {
            selectedItemID = filteredItems.first?.id
        }

        if previewState.isVisible {
            showPreview(selectedItemID)
        }
    }

    private func restoreSelectionAfterPreviewRebuild(
        preferredID: HistoryPreviewItem.ID?,
        previewedID: HistoryPreviewItem.ID?,
        sourceItems: [ClipboardItem]
    ) {
        guard let firstItem = sourceItems.first else {
            selectedItemID = nil
            rememberSelectedItem()
            closePreview()
            return
        }

        if let preferredID,
           sourceItems.contains(where: { $0.id == preferredID }) {
            selectedItemID = preferredID
        } else {
            selectedItemID = firstItem.id
        }
        rememberSelectedItem()

        if let previewedID,
           !sourceItems.contains(where: { $0.id == previewedID }) {
            closePreview()
        }
    }

    private func restoreRememberedViewportIfNeeded() {
        guard !didRestoreRememberedViewport,
              pendingLatestFocusItemID == nil,
              let rememberedID = rememberedSelectedItemUUID(),
              filteredItems.contains(where: { $0.id == rememberedID }) else {
            return
        }

        didRestoreRememberedViewport = true
        selectedItemID = rememberedID
        HistoryScrollCoordinator.shared.restoreSavedOffset()
    }

    private func preheatVisibleAssets() {
        let itemsToPreheat = filteredItems.prefix(HistoryWindowRenderState.preheatItemLimit)
        for item in itemsToPreheat {
            preheatImageThumbnail(for: item)
            preheatSourceIcon(for: item)
        }
    }

    private func schedulePreheatVisibleAssets() {
        preheatTask?.cancel()
        let itemsToPreheat = filteredItems
        guard !itemsToPreheat.isEmpty else {
            preheatTask = nil
            return
        }

        let batchSize = HistoryWindowRenderState.preheatItemLimit
        preheatTask = Task.detached(priority: .utility) {
            try? await Task.sleep(nanoseconds: 160_000_000)
            guard !Task.isCancelled else {
                return
            }

            for batchStart in stride(from: 0, to: itemsToPreheat.count, by: batchSize) {
                guard !Task.isCancelled else {
                    return
                }
                let batchEnd = min(batchStart + batchSize, itemsToPreheat.count)
                for item in itemsToPreheat[batchStart..<batchEnd] {
                    guard !Task.isCancelled else {
                        return
                    }
                    await Self.preheatImageThumbnailInBackground(for: item)
                    await Self.preheatSourceIconInBackground(for: item)
                }
                try? await Task.sleep(nanoseconds: 80_000_000)
            }
        }
    }

    private func preheatImageThumbnail(for item: HistoryPreviewItem) {
        guard let imageFileName = item.imageFileName,
              let thumbnailURL = try? ClipEaseStoragePaths.thumbnailFileURL(fileName: imageFileName),
              let imageURL = try? ClipEaseStoragePaths.imageFileURL(fileName: imageFileName) else {
            return
        }

        ImageMemoryCache.shared.preheatImage(for: "history-thumbnail:\(imageFileName)") {
            if let thumbnail = NSImage(contentsOf: thumbnailURL) {
                return thumbnail
            }

            return NSImage(contentsOf: imageURL)
        }
    }

    private func preheatSourceIcon(for item: HistoryPreviewItem) {
        guard let iconFileName = item.iconFileName,
              let iconURL = try? ClipEaseStoragePaths.appIconFileURL(fileName: iconFileName) else {
            return
        }

        ImageMemoryCache.shared.preheatImage(for: "app-icon:\(iconFileName)") {
            NSImage(contentsOf: iconURL).map {
                ClipEaseAppIcon.roundedImage($0, size: NSSize(width: 24, height: 24))
            }
        }
    }

    nonisolated private static func preheatImageThumbnailInBackground(for item: HistoryPreviewItem) async {
        guard let imageFileName = item.imageFileName,
              let thumbnailURL = try? ClipEaseStoragePaths.thumbnailFileURL(fileName: imageFileName),
              let imageURL = try? ClipEaseStoragePaths.imageFileURL(fileName: imageFileName) else {
            return
        }

        let cacheKey = "history-thumbnail:\(imageFileName)"
        let isCached = await MainActor.run {
            ImageMemoryCache.shared.cachedImage(for: cacheKey) != nil
        }
        guard !isCached else {
            return
        }

        let image = NSImage(contentsOf: thumbnailURL) ?? NSImage(contentsOf: imageURL)
        if let image {
            await MainActor.run {
                ImageMemoryCache.shared.store(image, for: cacheKey)
            }
        }
    }

    nonisolated private static func preheatSourceIconInBackground(for item: HistoryPreviewItem) async {
        guard let iconFileName = item.iconFileName,
              let iconURL = try? ClipEaseStoragePaths.appIconFileURL(fileName: iconFileName) else {
            return
        }

        let cacheKey = "app-icon:\(iconFileName)"
        let isCached = await MainActor.run {
            ImageMemoryCache.shared.cachedImage(for: cacheKey) != nil
        }
        guard !isCached else {
            return
        }

        let image = NSImage(contentsOf: iconURL).map {
            ClipEaseAppIcon.roundedImage($0, size: NSSize(width: 64, height: 64))
        }
        if let image {
            await MainActor.run {
                ImageMemoryCache.shared.store(image, for: cacheKey)
            }
        }
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
        accessibilityPermissionState.refresh()
        guard !accessibilityPermissionState.isTrusted else {
            showStatus("自动粘贴已启用")
            return
        }

        accessibilityPermissionState.openSystemSettings()
        accessibilityPermissionState.refresh(promptIfNeeded: true)
        showStatus("请授权轻贴")
    }

    private func toggleRecording() {
        onClose()
        if recordingController.isPaused {
            appMenuController.resumeRecording()
        } else {
            appMenuController.pauseRecording()
        }
    }

    private func toggleWindowPinnedOpen() {
        inputState.toggleWindowPinnedOpen()
        showStatus(inputState.isWindowPinnedOpen ? "主窗口已钉住" : "主窗口已取消钉住")
    }

    private func pauseRecording() {
        onClose()
        appMenuController.pauseRecording()
    }

    private func togglePauseFromMenu() {
        if recordingController.isPaused {
            onClose()
            appMenuController.resumeRecording()
        } else {
            pauseRecording()
        }
    }

    private func pauseRecording(for interval: TimeInterval, message: String) {
        onClose()
        appMenuController.pauseRecording(for: interval)
    }

    private func handleKeyboardAction(_ action: HistoryKeyboardAction) {
        if handleGroupEditingKeyboardAction(action) {
            return
        }

        switch action {
        case .moveLeft:
            moveSelection(.left)
        case .moveRight:
            moveSelection(.right)
        case .paste:
            pasteItem(selectedItemID)
        case .pastePlainText:
            pastePlainTextItem(selectedItemID)
        case .togglePreview:
            togglePreviewForSelectedItem()
        case .close:
            handleEscapeClose()
        case .selectVisibleCard(let number):
            selectVisibleCard(number: number)
        case .openSearch:
            handleCommandFSearch()
        case .showSettings:
            onClose()
            appMenuController.showSettings()
        case .copy:
            copyItem(selectedItemID)
        case .copyPlainText:
            copyPlainTextItem(selectedItemID)
        case .delete:
            deleteItem(selectedItemID)
        case .togglePinned:
            togglePinned(selectedItemID)
        case .edit:
            handleEditShortcut()
        case .closeWindow:
            closeWindowFromShortcut()
        case .createText:
            createTextFromShortcut()
        case .toggleRecording:
            toggleRecordingFromShortcut()
        case .appendSearchText(let text):
            appendSearchText(text)
        case .enterFirstSearchResult:
            enterFirstSearchResultFromSearchField()
        }
    }

    private func handleGroupEditingKeyboardAction(_ action: HistoryKeyboardAction) -> Bool {
        if groupRenameTargetID != nil {
            switch action {
            case .close:
                handleRenameEscape()
                return true
            case .delete, .appendSearchText, .copy, .copyPlainText, .paste, .pastePlainText, .togglePinned, .edit, .createText, .openSearch, .showSettings, .closeWindow, .toggleRecording, .moveLeft, .moveRight, .togglePreview, .selectVisibleCard, .enterFirstSearchResult:
                return true
            }
        }

        guard groupAppearanceTarget != nil || systemGroupAppearanceTarget != nil else {
            return false
        }

        switch action {
        case .close:
            handleGroupIconSearchEscape()
            return true
        case .delete:
            return isGroupIconSearchFocused
        case .appendSearchText, .copy, .copyPlainText, .paste, .pastePlainText, .togglePinned, .edit, .createText, .openSearch, .showSettings, .closeWindow, .toggleRecording:
            return true
        case .moveLeft, .moveRight, .togglePreview, .selectVisibleCard, .enterFirstSearchResult:
            return isGroupIconSearchFocused
        }
    }

    private func appendSearchText(_ text: String) {
        if previewState.isVisible {
            closePreview()
        }

        if !isSearchVisible {
            selectedGroup = .all
            withAnimation(.easeOut(duration: 0.12)) {
                isSearchVisible = true
            }
            inputState.setSearchVisible(true)
        }

        searchText += text
        focusSearchField()
    }

    private func replaceSearchText(_ text: String) {
        searchText = text
        focusSearchField()
    }

    private func handleSearchCancel() {
        handleEscapeClose()
    }

    private func enterFirstSearchResultFromSearchField() {
        guard let firstID = filteredItems.first?.id else {
            focusSearchField()
            return
        }

        selectedItemID = firstID
        isSearchFocused = false
        inputState.setTextInputFocused(false)
        if previewState.isVisible {
            showPreview(firstID)
        }
    }

    private func focusSearchField() {
        isSearchFocused = true
        searchFocusRequestID += 1
        inputState.setTextInputFocused(true)
    }

    private func closeWindowFromShortcut() {
        closePreview()
        cancelPendingGroupRename()
        onClose()
    }

    private func handleEscapeClose() {
        if (groupAppearanceTarget != nil || systemGroupAppearanceTarget != nil),
           NSColorPanel.shared.isVisible {
            closeGroupColorPanel()
            return
        }

        if closePresentedLayers() {
            return
        }

        if isSearchActive {
            clearSearchTextAndFilters()
            return
        }

        if isSearchVisible {
            closeSearch()
            return
        }

        onClose()
    }

    @discardableResult
    private func closePresentedLayers() -> Bool {
        var didClose = false

        if previewState.isVisible {
            closePreview()
            didClose = true
        }

        if isSearchFilterPanelPresented {
            isSearchFilterPanelPresented = false
            didClose = true
        }

        if groupAppearanceTarget != nil {
            closeGroupAppearancePopover()
            didClose = true
        }

        if systemGroupAppearanceTarget != nil {
            closeSystemGroupAppearancePopover()
            didClose = true
        }

        if groupPendingDeletion != nil {
            groupPendingDeletion = nil
            didClose = true
        }

        if isClearConfirmationPresented {
            isClearConfirmationPresented = false
            didClose = true
        }

        if groupRenameTargetID != nil {
            cancelPendingGroupRename()
            didClose = true
        }

        if didClose {
            isSearchFocused = false
            inputState.setTextInputFocused(false)
        }

        return didClose
    }

    private func createTextFromShortcut() {
        onClose()
        onCreateText(selectedGroupID)
    }

    private func createTextFromMenu() {
        onClose()
        onCreateText(selectedGroupID)
    }

    private func toggleRecordingFromShortcut() {
        toggleRecording()
    }

}

private struct HistorySearchCriteria: Equatable, Sendable {
    var types: Set<HistorySearchItemType> = []
    var sourceAppNames: Set<String> = []
    var dateRanges: Set<HistorySearchDateRange> = []
    var groups: Set<HistorySearchGroup> = []

    var hasActiveFilters: Bool {
        !types.isEmpty || !sourceAppNames.isEmpty || !dateRanges.isEmpty || !groups.isEmpty
    }
}

private enum HistorySearchItemType: String, CaseIterable, Identifiable, Hashable, Sendable {
    case text
    case link
    case image
    case color
    case file

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .text:
            "文字"
        case .link:
            "链接"
        case .image:
            "图片"
        case .color:
            "颜色"
        case .file:
            "文件"
        }
    }

    var iconName: String {
        switch self {
        case .text:
            "text.alignleft"
        case .link:
            "link"
        case .image:
            "photo"
        case .color:
            "paintpalette"
        case .file:
            "doc"
        }
    }

    var previewType: HistoryPreviewType {
        switch self {
        case .text:
            .text
        case .link:
            .link
        case .image:
            .image
        case .color:
            .color
        case .file:
            .file
        }
    }
}

private enum HistorySearchDateRange: String, CaseIterable, Identifiable, Hashable, Sendable {
    case today
    case last7Days
    case last30Days

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .today:
            "今天"
        case .last7Days:
            "最近 7 天"
        case .last30Days:
            "最近 30 天"
        }
    }

    func contains(_ date: Date, now: Date) -> Bool {
        let calendar = Calendar.current
        switch self {
        case .today:
            return calendar.isDate(date, inSameDayAs: now)
        case .last7Days:
            return date >= calendar.date(byAdding: .day, value: -7, to: now) ?? now
        case .last30Days:
            return date >= calendar.date(byAdding: .day, value: -30, to: now) ?? now
        }
    }
}

private struct HistoryPreviewSourceSignature: Equatable {
    let id: ClipboardItem.ID
    let type: ClipboardItemType
    let createdAt: Date
    let sourceAppName: String
    let sourceBundleID: String?
    let iconName: String
    let iconFileName: String?
    let headerColorHex: String
    let linkTitle: String?
    let linkSubtitle: String?
    let isPinned: Bool
    let groupID: ClipboardGroup.ID?
    let groupedAt: Date?
    let richTextFileName: String?
    let imageFileName: String?
    let imageWidth: Int?
    let imageHeight: Int?
    let imageHash: String?
    let fileReferences: [ClipboardFileReference]
    let text: String

    init(item: ClipboardItem) {
        id = item.id
        type = item.type
        createdAt = item.createdAt
        sourceAppName = item.sourceAppName
        sourceBundleID = item.sourceBundleID
        iconName = item.iconName
        iconFileName = item.iconFileName
        headerColorHex = item.headerColorHex
        linkTitle = item.linkTitle
        linkSubtitle = item.linkSubtitle
        isPinned = item.isPinned
        groupID = item.groupID
        groupedAt = item.groupedAt
        richTextFileName = item.richTextFileName
        imageFileName = item.imageFileName
        imageWidth = item.imageWidth
        imageHeight = item.imageHeight
        imageHash = item.imageHash
        fileReferences = item.fileReferences
        text = item.text
    }
}

private struct CachedHistoryPreviewItem: Sendable {
    let signature: HistoryPreviewSourceSignature
    let item: HistoryPreviewItem
}

private struct HistorySearchSourceSignature: Equatable {
    let id: HistoryPreviewItem.ID
    let type: HistoryPreviewType
    let createdAt: Date
    let sourceAppName: String
    let normalizedSearchText: String
    let isPinned: Bool
    let groupID: UUID?
    let groupedAt: Date?

    init(item: HistoryPreviewItem) {
        id = item.id
        type = item.type
        createdAt = item.createdAt
        sourceAppName = item.sourceAppName
        normalizedSearchText = item.normalizedSearchText
        isPinned = item.isPinned
        groupID = item.groupID
        groupedAt = item.groupedAt
    }
}

private struct HistorySearchRequestSignature: Equatable {
    let sourceItems: [HistorySearchSourceSignature]
    let selectedGroup: String
    let searchText: String
    let criteria: HistorySearchCriteria
}

private enum HistorySearchGroup: Hashable, Sendable {
    case pinned
    case group(ClipboardGroup.ID)
}

private enum HistorySearchTokenKind: Hashable, Sendable {
    case type(HistorySearchItemType)
    case sourceApp(String)
    case date(HistorySearchDateRange)
    case group(HistorySearchGroup)
}

private struct HistorySearchToken: Identifiable, Equatable, Sendable {
    let kind: HistorySearchTokenKind
    let title: String

    var id: HistorySearchTokenKind {
        kind
    }

    static func tokens(
        criteria: HistorySearchCriteria,
        groups: [ClipboardGroup]
    ) -> [HistorySearchToken] {
        var tokens: [HistorySearchToken] = []

        for type in HistorySearchItemType.allCases where criteria.types.contains(type) {
            tokens.append(HistorySearchToken(kind: .type(type), title: type.title))
        }

        for sourceAppName in criteria.sourceAppNames.sorted() {
            tokens.append(HistorySearchToken(kind: .sourceApp(sourceAppName), title: sourceAppName))
        }

        for dateRange in HistorySearchDateRange.allCases where criteria.dateRanges.contains(dateRange) {
            tokens.append(HistorySearchToken(kind: .date(dateRange), title: dateRange.title))
        }

        let systemGroups: [HistorySearchGroup] = [.pinned]
        for group in systemGroups where criteria.groups.contains(group) {
            tokens.append(HistorySearchToken(kind: .group(group), title: group.title(groups: groups)))
        }
        for group in groups where criteria.groups.contains(.group(group.id)) {
            let searchGroup = HistorySearchGroup.group(group.id)
            tokens.append(HistorySearchToken(kind: .group(searchGroup), title: searchGroup.title(groups: groups)))
        }

        return tokens
    }
}

private extension HistorySearchGroup {
    func title(groups: [ClipboardGroup]) -> String {
        switch self {
        case .pinned:
            "置顶"
        case .group(let groupID):
            groups.first(where: { $0.id == groupID })?.name ?? "分组"
        }
    }
}

private enum HistoryGroupSelection: Equatable, Sendable {
    case all
    case pinned
    case group(ClipboardGroup.ID)

    var groupID: ClipboardGroup.ID? {
        switch self {
        case .all, .pinned:
            nil
        case .group(let id):
            id
        }
    }

    init(storageValue: String) {
        switch storageValue {
        case Self.pinned.storageValue:
            self = .pinned
        default:
            if storageValue.hasPrefix(Self.groupStoragePrefix),
               let id = ClipboardGroup.ID(uuidString: String(storageValue.dropFirst(Self.groupStoragePrefix.count))) {
                self = .group(id)
            } else {
                self = .all
            }
        }
    }

    var storageValue: String {
        switch self {
        case .all:
            "all"
        case .pinned:
            "pinned"
        case .group(let id):
            "\(Self.groupStoragePrefix)\(id.uuidString)"
        }
    }

    var scrollID: String {
        "group-selection-\(storageValue)"
    }

    private static let groupStoragePrefix = "group:"
}

private enum SystemHistoryGroup: CaseIterable, Identifiable, Equatable, Sendable {
    case pinned

    var id: String {
        title
    }

    var selection: HistoryGroupSelection {
        switch self {
        case .pinned:
            .pinned
        }
    }

    var searchGroup: HistorySearchGroup {
        switch self {
        case .pinned:
            .pinned
        }
    }

    var title: String {
        switch self {
        case .pinned:
            "置顶"
        }
    }

    var selectedStatus: String {
        switch self {
        case .pinned:
            "只看置顶"
        }
    }

    var help: String {
        switch self {
        case .pinned:
            "显示置顶内容"
        }
    }
}

private struct SearchTextField: NSViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    @Binding var isComposing: Bool
    let focusRequestID: Int
    let hasSearchResult: Bool
    let hasSearchTokens: Bool
    let onEnterFirstResult: () -> Void
    let onReplaceSearch: (String) -> Void
    let onDeleteLastToken: () -> Void
    let onCancel: () -> Void
    let onSubmit: () -> Void

    func makeNSView(context: Context) -> SearchNSTextField {
        let textField = SearchNSTextField()
        textField.delegate = context.coordinator
        textField.coordinator = context.coordinator
        textField.isBordered = false
        textField.isBezeled = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.font = .systemFont(ofSize: 13, weight: .medium)
        textField.placeholderString = "搜索"
        textField.lineBreakMode = .byTruncatingTail
        textField.cell?.sendsActionOnEndEditing = false
        return textField
    }

    func updateNSView(_ nsView: SearchNSTextField, context: Context) {
        context.coordinator.parent = self
        nsView.coordinator = context.coordinator
        let editor = nsView.currentEditor() as? NSTextView
        let hasMarkedText = editor?.hasMarkedText() ?? false

        if !hasMarkedText, nsView.stringValue != text {
            nsView.stringValue = text
        }
        nsView.placeholderString = hasSearchTokens ? nil : "搜索"

        if nsView.font?.pointSize != 13 {
            nsView.font = .systemFont(ofSize: 13, weight: .medium)
        }

        if isFocused {
            if nsView.window?.firstResponder !== nsView.currentEditor() {
                nsView.window?.makeFirstResponder(nsView)
            }
            if !hasMarkedText, context.coordinator.handledFocusRequestID != focusRequestID {
                context.coordinator.handledFocusRequestID = focusRequestID
                context.coordinator.moveInsertionPointToEndSoon(in: nsView)
            }
        } else if nsView.window?.firstResponder === nsView.currentEditor() {
            nsView.window?.makeFirstResponder(nil)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    @MainActor
    final class SearchNSTextField: NSTextField {
        weak var coordinator: Coordinator?

        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            guard event.modifierFlags.contains(.command),
                  let characters = event.charactersIgnoringModifiers?.lowercased(),
                  characters.count == 1,
                  let coordinator,
                  let editor = currentEditor() as? NSTextView else {
                return super.performKeyEquivalent(with: event)
            }

            switch characters {
            case "a":
                editor.selectAll(nil)
                return true
            case "c":
                editor.copy(nil)
                return true
            case "x":
                editor.cut(nil)
                return true
            case "v":
                editor.paste(nil)
                return true
            case "z":
                if event.modifierFlags.contains(.shift) {
                    editor.undoManager?.redo()
                } else {
                    editor.undoManager?.undo()
                }
                return true
            case "w":
                coordinator.parent.onCancel()
                return true
            default:
                return super.performKeyEquivalent(with: event)
            }
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: SearchTextField
        var handledFocusRequestID = 0

        init(parent: SearchTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else {
                return
            }

            parent.isComposing = (textField.currentEditor() as? NSTextView)?.hasMarkedText() ?? false
            parent.text = textField.stringValue
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            parent.isFocused = true
            if let inputState = HistoryWindowInputState.currentForTextEditing {
                inputState.setTextInputFocused(true)
            }
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            parent.isComposing = false
            parent.isFocused = false
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.insertNewline(_:)):
                if isCursorAtEnd(in: textView), parent.hasSearchResult {
                    parent.onEnterFirstResult()
                } else {
                    parent.onSubmit()
                }
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                parent.onCancel()
                return true
            case #selector(NSResponder.moveRight(_:)), #selector(NSResponder.moveDown(_:)):
                guard isCursorAtEnd(in: textView), parent.hasSearchResult else {
                    return false
                }

                parent.onEnterFirstResult()
                return true
            case #selector(NSResponder.deleteBackward(_:)):
                guard parent.text.isEmpty, parent.hasSearchTokens else {
                    return false
                }

                parent.onDeleteLastToken()
                return true
            case #selector(NSResponder.selectAll(_:)):
                textView.selectAll(nil)
                return true
            default:
                return false
            }
        }

        func control(_ control: NSControl, textView: NSTextView, shouldChangeCharactersIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
            guard let replacementString,
                  replacementString.isEmpty == false,
                  !textView.hasMarkedText(),
                  isCursorAtEnd(in: textView),
                  parent.hasSearchResult else {
                return true
            }

            parent.onReplaceSearch(replacementString)
            return false
        }

        func moveInsertionPointToEnd(in textField: NSTextField) {
            guard let editor = textField.currentEditor() else {
                return
            }

            let endLocation = (textField.stringValue as NSString).length
            if editor.selectedRange.location != endLocation || editor.selectedRange.length != 0 {
                editor.selectedRange = NSRange(location: endLocation, length: 0)
            }
        }

        func moveInsertionPointToEndSoon(in textField: NSTextField) {
            DispatchQueue.main.async { [weak textField] in
                guard let textField else {
                    return
                }

                if textField.window?.firstResponder !== textField.currentEditor() {
                    textField.window?.makeFirstResponder(textField)
                }
                self.moveInsertionPointToEnd(in: textField)
            }
        }

        private func isCursorAtEnd(in textView: NSTextView) -> Bool {
            let range = textView.selectedRange()
            return range.length == 0 && range.location == (textView.string as NSString).length
        }
    }
}

private struct GroupMouseDownObserver: NSViewRepresentable {
    let onMouseDown: () -> Void
    var onRightMouseDown: (() -> Void)?
    var onDoubleMouseDown: (() -> Void)?

    init(onMouseDown: @escaping () -> Void) {
        self.onMouseDown = onMouseDown
        onRightMouseDown = nil
        onDoubleMouseDown = nil
    }

    init(
        onMouseDown: @escaping () -> Void,
        onRightMouseDown: (() -> Void)?,
        onDoubleMouseDown: (() -> Void)? = nil
    ) {
        self.onMouseDown = onMouseDown
        self.onRightMouseDown = onRightMouseDown
        self.onDoubleMouseDown = onDoubleMouseDown
    }

    func onRightMouseDown(_ action: @escaping () -> Void) -> Self {
        var observer = self
        observer.onRightMouseDown = action
        return observer
    }

    func onDoubleMouseDown(_ action: @escaping () -> Void) -> Self {
        var observer = self
        observer.onDoubleMouseDown = action
        return observer
    }

    func makeNSView(context: Context) -> ObservingView {
        let view = ObservingView()
        view.coordinator = context.coordinator
        context.coordinator.view = view
        context.coordinator.onMouseDown = onMouseDown
        context.coordinator.onRightMouseDown = onRightMouseDown
        context.coordinator.onDoubleMouseDown = onDoubleMouseDown
        context.coordinator.installMonitor()
        return view
    }

    func updateNSView(_ nsView: ObservingView, context: Context) {
        nsView.coordinator = context.coordinator
        context.coordinator.view = nsView
        context.coordinator.onMouseDown = onMouseDown
        context.coordinator.onRightMouseDown = onRightMouseDown
        context.coordinator.onDoubleMouseDown = onDoubleMouseDown
    }

    static func dismantleNSView(_ nsView: ObservingView, coordinator: Coordinator) {
        coordinator.removeMonitor()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    @MainActor
    final class Coordinator {
        weak var view: ObservingView?
        var onMouseDown: (() -> Void)?
        var onRightMouseDown: (() -> Void)?
        var onDoubleMouseDown: (() -> Void)?
        private var monitor: Any?

        func installMonitor() {
            removeMonitor()
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                self?.handle(event)
                return event
            }
        }

        func removeMonitor() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        @MainActor
        private func handle(_ event: NSEvent) {
            guard let view,
                  event.window === view.window else {
                return
            }

            let point = view.convert(event.locationInWindow, from: nil)
            guard view.bounds.contains(point) else {
                return
            }

            switch event.type {
            case .rightMouseDown:
                (onRightMouseDown ?? onMouseDown)?()
            default:
                if event.clickCount >= 2, let onDoubleMouseDown {
                    onDoubleMouseDown()
                } else {
                    onMouseDown?()
                }
            }
        }
    }

    final class ObservingView: NSView {
        weak var coordinator: Coordinator?

        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }
    }
}

private struct GroupRenameOutsideMouseDownObserver: NSViewRepresentable {
    let isEnabled: Bool
    let hostWindow: NSWindow?
    let excludedScreenFrame: CGRect?
    let onMouseDown: () -> Void

    func makeNSView(context: Context) -> ObservingView {
        let view = ObservingView()
        view.coordinator = context.coordinator
        context.coordinator.view = view
        context.coordinator.isEnabled = isEnabled
        context.coordinator.hostWindow = hostWindow
        context.coordinator.excludedScreenFrame = excludedScreenFrame
        context.coordinator.onMouseDown = onMouseDown
        context.coordinator.installMonitor()
        return view
    }

    func updateNSView(_ nsView: ObservingView, context: Context) {
        nsView.coordinator = context.coordinator
        context.coordinator.view = nsView
        context.coordinator.isEnabled = isEnabled
        context.coordinator.hostWindow = hostWindow
        context.coordinator.excludedScreenFrame = excludedScreenFrame
        context.coordinator.onMouseDown = onMouseDown
        context.coordinator.installMonitorIfNeeded()
    }

    static func dismantleNSView(_ nsView: ObservingView, coordinator: Coordinator) {
        coordinator.removeMonitor()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    @MainActor
    final class Coordinator {
        weak var view: ObservingView?
        var isEnabled = false
        weak var hostWindow: NSWindow?
        var excludedScreenFrame: CGRect?
        var onMouseDown: (() -> Void)?
        private var monitor: Any?

        func installMonitor() {
            removeMonitor()
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                self?.handle(event)
                return event
            }
        }

        func installMonitorIfNeeded() {
            guard monitor == nil else {
                return
            }

            installMonitor()
        }

        func removeMonitor() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        @MainActor
        private func handle(_ event: NSEvent) {
            guard isEnabled,
                  let activeHostWindow = hostWindow ?? view?.window,
                  event.window === activeHostWindow else {
                return
            }

            if isExcludedScreenFrameHit(event, in: activeHostWindow) {
                return
            }

            guard !isCurrentRenameTextFieldHit(event) else {
                return
            }

            onMouseDown?()
        }

        private func isExcludedScreenFrameHit(_ event: NSEvent, in window: NSWindow) -> Bool {
            guard let excludedScreenFrame else {
                return false
            }

            let screenPoint = window.convertPoint(toScreen: event.locationInWindow)
            return excludedScreenFrame.insetBy(dx: -4, dy: -4).contains(screenPoint)
        }

        private func isCurrentRenameTextFieldHit(_ event: NSEvent) -> Bool {
            guard let contentView = event.window?.contentView else {
                return false
            }

            let contentPoint = contentView.convert(event.locationInWindow, from: nil)
            var candidate = contentView.hitTest(contentPoint)
            while let view = candidate {
                if let textField = view as? GroupInlineTextField.InlineNSTextField,
                   textField.isGroupRenameField {
                    return true
                }
                candidate = view.superview
            }

            return false
        }
    }

    final class ObservingView: NSView {
        weak var coordinator: Coordinator?

        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }
    }
}

private struct GroupRenameInputFrameReader: NSViewRepresentable {
    let onChange: (CGRect?) -> Void

    func makeNSView(context: Context) -> FrameView {
        let view = FrameView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ nsView: FrameView, context: Context) {
        nsView.onChange = onChange
        DispatchQueue.main.async {
            nsView.reportFrame()
        }
    }

    static func dismantleNSView(_ nsView: FrameView, coordinator: ()) {
        nsView.onChange?(nil)
    }

    final class FrameView: NSView {
        var onChange: ((CGRect?) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            DispatchQueue.main.async { [weak self] in
                self?.reportFrame()
            }
        }

        override func setFrameSize(_ newSize: NSSize) {
            super.setFrameSize(newSize)
            DispatchQueue.main.async { [weak self] in
                self?.reportFrame()
            }
        }

        func reportFrame() {
            guard let window else {
                onChange?(nil)
                return
            }

            let frameInWindow = convert(bounds, to: nil)
            onChange?(window.convertToScreen(frameInWindow))
        }
    }
}

private struct SearchOutsideWindowMouseDownObserver: NSViewRepresentable {
    let isEnabled: Bool
    let hostWindow: NSWindow?
    let excludedFrames: [CGRect]
    let onMouseDown: () -> Void

    func makeNSView(context: Context) -> ObservingView {
        let view = ObservingView()
        view.coordinator = context.coordinator
        context.coordinator.view = view
        context.coordinator.isEnabled = isEnabled
        context.coordinator.hostWindow = hostWindow
        context.coordinator.excludedFrames = excludedFrames
        context.coordinator.onMouseDown = onMouseDown
        context.coordinator.installMonitor()
        return view
    }

    func updateNSView(_ nsView: ObservingView, context: Context) {
        nsView.coordinator = context.coordinator
        context.coordinator.view = nsView
        context.coordinator.isEnabled = isEnabled
        context.coordinator.hostWindow = hostWindow
        context.coordinator.excludedFrames = excludedFrames
        context.coordinator.onMouseDown = onMouseDown
        context.coordinator.installMonitorIfNeeded()
    }

    static func dismantleNSView(_ nsView: ObservingView, coordinator: Coordinator) {
        coordinator.removeMonitor()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    @MainActor
    final class Coordinator {
        weak var view: ObservingView?
        var isEnabled = false
        weak var hostWindow: NSWindow?
        var excludedFrames: [CGRect] = []
        var onMouseDown: (() -> Void)?
        private var monitor: Any?

        func installMonitor() {
            removeMonitor()
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                self?.handle(event)
                return event
            }
        }

        func installMonitorIfNeeded() {
            guard monitor == nil else {
                return
            }

            installMonitor()
        }

        func removeMonitor() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        @MainActor
        private func handle(_ event: NSEvent) {
            guard isEnabled,
                  let view else {
                return
            }

            guard let activeHostWindow = hostWindow ?? view.window else {
                return
            }

            let screenPoint: NSPoint
            if let eventWindow = event.window {
                guard eventWindow === activeHostWindow || !isSearchRelatedPanel(eventWindow) else {
                    return
                }
                screenPoint = eventWindow.convertPoint(toScreen: event.locationInWindow)
            } else {
                screenPoint = NSEvent.mouseLocation
            }

            guard !excludedFrames.contains(where: { $0.contains(screenPoint) }) else {
                return
            }

            guard !SearchInteractionRegionRegistry.shared.contains(screenPoint: screenPoint, in: activeHostWindow) else {
                return
            }

            guard activeHostWindow.frame.contains(screenPoint) else {
                onMouseDown?()
                return
            }

            guard event.window === activeHostWindow else {
                onMouseDown?()
                return
            }

            guard !isInteractiveControlHit(event) else {
                return
            }

            onMouseDown?()
        }

        private func isInteractiveControlHit(_ event: NSEvent) -> Bool {
            guard let contentView = event.window?.contentView else {
                return false
            }

            let contentPoint = contentView.convert(event.locationInWindow, from: nil)
            var candidate = contentView.hitTest(contentPoint)
            while let view = candidate {
                if view is NSControl || view is NSTextView {
                    return true
                }
                candidate = view.superview
            }

            return false
        }

        private func isSearchRelatedPanel(_ window: NSWindow) -> Bool {
            let className = String(describing: type(of: window))
            return className.contains("Popover") || window.level.rawValue >= NSWindow.Level.popUpMenu.rawValue
        }
    }

    final class ObservingView: NSView {
        weak var coordinator: Coordinator?

        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }
    }
}

@MainActor
private final class SearchInteractionRegionRegistry {
    static let shared = SearchInteractionRegionRegistry()
    private let views = NSHashTable<NSView>.weakObjects()

    func register(_ view: NSView) {
        views.add(view)
    }

    func unregister(_ view: NSView) {
        views.remove(view)
    }

    func contains(screenPoint: NSPoint, in hostWindow: NSWindow) -> Bool {
        for view in views.allObjects {
            guard let window = view.window,
                  window === hostWindow,
                  !view.isHidden,
                  view.bounds.width > 0,
                  view.bounds.height > 0 else {
                continue
            }

            let rectInWindow = view.convert(view.bounds, to: nil)
            let origin = window.convertPoint(toScreen: rectInWindow.origin)
            let screenFrame = CGRect(origin: origin, size: rectInWindow.size)
                .standardized
                .insetBy(dx: -8, dy: -8)
            if screenFrame.contains(screenPoint) {
                return true
            }
        }

        return false
    }
}

private struct SearchInteractionLiveRegion: NSViewRepresentable {
    let isActive: Bool
    let onRegister: (NSView) -> Void
    let onUnregister: (NSView) -> Void

    func makeNSView(context: Context) -> RegionView {
        let view = RegionView()
        view.onRegister = onRegister
        view.onUnregister = onUnregister
        view.isActive = isActive
        view.syncRegistration()
        return view
    }

    func updateNSView(_ nsView: RegionView, context: Context) {
        nsView.onRegister = onRegister
        nsView.onUnregister = onUnregister
        nsView.isActive = isActive
        nsView.syncRegistration()
    }

    static func dismantleNSView(_ nsView: RegionView, coordinator: ()) {
        nsView.unregisterIfNeeded()
    }

    final class RegionView: NSView {
        var onRegister: ((NSView) -> Void)?
        var onUnregister: ((NSView) -> Void)?
        var isActive = false
        private var isRegistered = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            syncRegistration()
        }

        func syncRegistration() {
            if isActive, window != nil {
                guard !isRegistered else {
                    return
                }

                isRegistered = true
                onRegister?(self)
            } else {
                unregisterIfNeeded()
            }
        }

        func unregisterIfNeeded() {
            guard isRegistered else {
                return
            }

            isRegistered = false
            onUnregister?(self)
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }
    }
}

private struct SearchInteractionScreenFrameReader: NSViewRepresentable {
    let isActive: Bool
    let onFrameChange: (CGRect?) -> Void

    func makeNSView(context: Context) -> ReadingView {
        let view = ReadingView()
        view.onFrameChange = onFrameChange
        view.isActive = isActive
        return view
    }

    func updateNSView(_ nsView: ReadingView, context: Context) {
        nsView.onFrameChange = onFrameChange
        nsView.isActive = isActive
        DispatchQueue.main.async {
            nsView.reportFrame()
        }
    }

    final class ReadingView: NSView {
        var onFrameChange: ((CGRect?) -> Void)?
        var isActive = false {
            didSet {
                reportFrame()
            }
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            reportFrame()
        }

        override func setFrameSize(_ newSize: NSSize) {
            super.setFrameSize(newSize)
            reportFrame()
        }

        override func setFrameOrigin(_ newOrigin: NSPoint) {
            super.setFrameOrigin(newOrigin)
            reportFrame()
        }

        func reportFrame() {
            guard isActive,
                  let window else {
                onFrameChange?(nil)
                return
            }

            let rectInWindow = convert(bounds, to: nil)
            let origin = window.convertPoint(toScreen: rectInWindow.origin)
            onFrameChange?(CGRect(origin: origin, size: rectInWindow.size))
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }
    }
}

private struct GroupTextInputFocusObserver: NSViewRepresentable {
    @Binding var isFocused: Bool

    func makeNSView(context: Context) -> FocusObserverView {
        let view = FocusObserverView()
        view.onFocusChange = { focused in
            if isFocused != focused {
                isFocused = focused
            }
        }
        return view
    }

    func updateNSView(_ nsView: FocusObserverView, context: Context) {
        nsView.onFocusChange = { focused in
            if isFocused != focused {
                isFocused = focused
            }
        }

        DispatchQueue.main.async {
            nsView.refreshFocus()
        }
    }

    final class FocusObserverView: NSView {
        var onFocusChange: ((Bool) -> Void)?
        private var observedWindow: NSWindow?
        private var isObservedFocused = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            updateWindowObservation()
            refreshFocus()
        }

        deinit {
            if let observedWindow {
                NotificationCenter.default.removeObserver(
                    self,
                    name: NSWindow.didUpdateNotification,
                    object: observedWindow
                )
            }
        }

        func refreshFocus() {
            let focused = isFirstResponderInsideObservedTextField()
            guard focused != isObservedFocused else {
                return
            }

            isObservedFocused = focused
            onFocusChange?(focused)
        }

        private func updateWindowObservation() {
            guard observedWindow !== window else {
                return
            }

            if let observedWindow {
                NotificationCenter.default.removeObserver(
                    self,
                    name: NSWindow.didUpdateNotification,
                    object: observedWindow
                )
            }

            observedWindow = window
            if let window {
                NotificationCenter.default.addObserver(
                    self,
                    selector: #selector(windowDidUpdate),
                    name: NSWindow.didUpdateNotification,
                    object: window
                )
            }
        }

        @objc private func windowDidUpdate() {
            refreshFocus()
        }

        private func isFirstResponderInsideObservedTextField() -> Bool {
            guard let window,
                  let textField = enclosingTextField() else {
                return false
            }

            if window.firstResponder === textField {
                return true
            }

            guard let editor = textField.currentEditor() else {
                return false
            }

            return window.firstResponder === editor
        }

        private func enclosingTextField() -> NSTextField? {
            var candidate = superview
            while let view = candidate {
                if let textField = view as? NSTextField {
                    return textField
                }
                candidate = view.superview
            }
            return nil
        }
    }
}

private struct GroupInlineTextField: NSViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    var placeholder: String
    var font: NSFont = .systemFont(ofSize: 13, weight: .regular)
    var textColor: NSColor = .labelColor
    var drawsBackground = true
    var isGroupRenameField = false
    var focusRequestID = 0
    var onEscape: () -> Void
    var onSubmit: (() -> Void)? = nil

    func makeNSView(context: Context) -> InlineNSTextField {
        let textField = InlineNSTextField()
        textField.delegate = context.coordinator
        textField.coordinator = context.coordinator
        textField.placeholderString = placeholder
        textField.font = font
        textField.textColor = textColor
        textField.isGroupRenameField = isGroupRenameField
        textField.isBordered = drawsBackground
        textField.isBezeled = drawsBackground
        textField.bezelStyle = .roundedBezel
        textField.drawsBackground = drawsBackground
        textField.focusRingType = drawsBackground ? .default : .none
        textField.cell?.sendsActionOnEndEditing = false
        return textField
    }

    func updateNSView(_ textField: InlineNSTextField, context: Context) {
        context.coordinator.parent = self
        textField.coordinator = context.coordinator
        if textField.stringValue != text {
            textField.stringValue = text
        }
        textField.placeholderString = placeholder
        textField.font = font
        textField.textColor = textColor
        textField.isGroupRenameField = isGroupRenameField
        textField.isBordered = drawsBackground
        textField.isBezeled = drawsBackground
        textField.drawsBackground = drawsBackground
        textField.focusRingType = drawsBackground ? .default : .none

        if isFocused {
            context.coordinator.focus(textField)
        } else if textField.window?.firstResponder === textField.currentEditor() {
            textField.window?.makeFirstResponder(nil)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    @MainActor
    final class InlineNSTextField: NSTextField {
        weak var coordinator: Coordinator?
        var isGroupRenameField = false

        override func mouseDown(with event: NSEvent) {
            coordinator?.focus(self)
            super.mouseDown(with: event)
            coordinator?.focus(self)
        }

        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            guard event.modifierFlags.contains(.command),
                  let characters = event.charactersIgnoringModifiers?.lowercased(),
                  characters.count == 1,
                  let editor = currentEditor() as? NSTextView else {
                return super.performKeyEquivalent(with: event)
            }

            switch characters {
            case "a":
                editor.selectAll(nil)
                return true
            case "c":
                editor.copy(nil)
                return true
            case "x":
                editor.cut(nil)
                return true
            case "v":
                editor.paste(nil)
                return true
            case "z":
                if event.modifierFlags.contains(.shift) {
                    editor.undoManager?.redo()
                } else {
                    editor.undoManager?.undo()
                }
                return true
            default:
                return super.performKeyEquivalent(with: event)
            }
        }

        override func keyDown(with event: NSEvent) {
            if event.keyCode == 53 {
                coordinator?.parent.onEscape()
                return
            }

            super.keyDown(with: event)
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: GroupInlineTextField
        private var handledFocusRequestID: Int?

        init(parent: GroupInlineTextField) {
            self.parent = parent
        }

        func focus(_ textField: NSTextField) {
            guard let window = textField.window else {
                requestFocusSoon(in: textField)
                return
            }

            if window.firstResponder !== textField.currentEditor() {
                window.makeFirstResponder(textField)
            }

            if handledFocusRequestID != parent.focusRequestID {
                handledFocusRequestID = parent.focusRequestID
                requestFocusSoon(in: textField)
            }
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            parent.isFocused = true
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else {
                return
            }

            parent.text = textField.stringValue
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            guard parent.isFocused else {
                return
            }

            parent.isFocused = false
            if let inputState = HistoryWindowInputState.currentForTextEditing {
                inputState.setTextInputFocused(false)
            }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.insertNewline(_:)):
                parent.onSubmit?()
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                parent.onEscape()
                return true
            default:
                return false
            }
        }

        private func requestFocusSoon(in textField: NSTextField) {
            DispatchQueue.main.async { [weak textField] in
                guard let textField,
                      let window = textField.window else {
                    return
                }

                if window.firstResponder !== textField.currentEditor() {
                    window.makeFirstResponder(textField)
                }

                guard let editor = textField.currentEditor() else {
                    return
                }

                let endLocation = (textField.stringValue as NSString).length
                editor.selectedRange = NSRange(location: endLocation, length: 0)
            }
        }
    }
}

private struct SearchPanelWindowReader: NSViewRepresentable {
    let onWindowChange: (NSWindow?) -> Void

    func makeNSView(context: Context) -> WindowReaderView {
        let view = WindowReaderView()
        view.onWindowChange = onWindowChange
        return view
    }

    func updateNSView(_ nsView: WindowReaderView, context: Context) {
        nsView.onWindowChange = onWindowChange
        DispatchQueue.main.async {
            nsView.reportWindow()
        }
    }

    final class WindowReaderView: NSView {
        var onWindowChange: ((NSWindow?) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            reportWindow()
        }

        func reportWindow() {
            onWindowChange?(window)
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }
    }
}

private struct MoveToGroupMenuEntry: Identifiable, Equatable {
    let id: ClipboardGroup.ID
    let name: String
    let iconName: String

    init(group: ClipboardGroup) {
        self.id = group.id
        self.name = group.name
        self.iconName = group.iconName
    }
}

private struct MoveToGroupPickerTarget: Identifiable, Equatable {
    let itemID: ClipboardItem.ID
    let currentGroupID: ClipboardGroup.ID?

    var id: ClipboardItem.ID {
        itemID
    }
}

private struct MoreMenuButton: NSViewRepresentable {
    let menuProvider: () -> NSMenu

    func makeCoordinator() -> Coordinator {
        Coordinator(menuProvider: menuProvider)
    }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: "...", target: context.coordinator, action: #selector(Coordinator.openMenu(_:)))
        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.font = .systemFont(ofSize: 14, weight: .semibold)
        button.alignment = .center
        button.focusRingType = .none
        button.refusesFirstResponder = true
        button.setButtonType(.momentaryChange)
        button.translatesAutoresizingMaskIntoConstraints = false
        context.coordinator.button = button
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.menuProvider = menuProvider
        button.title = "..."
    }

    final class Coordinator: NSObject {
        var menuProvider: () -> NSMenu
        weak var button: NSButton?

        init(menuProvider: @escaping () -> NSMenu) {
            self.menuProvider = menuProvider
        }

        @MainActor @objc func openMenu(_ sender: NSButton) {
            let menu = menuProvider()
            let point = NSPoint(x: 0, y: sender.bounds.minY - 4)
            menu.popUp(positioning: nil, at: point, in: sender)
        }
    }
}

private final class ClosureMenuItemTarget: NSObject {
    private let action: () -> Void

    init(_ action: @escaping () -> Void) {
        self.action = action
    }

    @objc func performAction() {
        action()
    }
}

private struct NumberShortcutHandler: NSViewRepresentable {
    let inputState: HistoryWindowInputState
    let onCommandStateChange: (Bool) -> Void
    let onNumber: (Int) -> Void

    func makeNSView(context: Context) -> ShortcutNSView {
        let view = ShortcutNSView()
        view.inputState = inputState
        view.onCommandStateChange = onCommandStateChange
        view.onNumber = onNumber
        return view
    }

    func updateNSView(_ nsView: ShortcutNSView, context: Context) {
        nsView.inputState = inputState
        nsView.onCommandStateChange = onCommandStateChange
        nsView.onNumber = onNumber
    }

    final class ShortcutNSView: NSView {
        weak var inputState: HistoryWindowInputState?
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
                          !self.isPreviewContentActive(),
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
                          !self.isPreviewContentActive(),
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

        private func isPreviewContentActive() -> Bool {
            inputState?.isPreviewActiveSnapshot == true
        }

        private static func isTextInputActive() -> Bool {
            guard let responder = NSApp.keyWindow?.firstResponder else {
                return false
            }

            return responder is NSTextView
        }
    }
}

private struct HorizontalScrollWheelRedirector: NSViewRepresentable {
    enum Scope {
        case cardRail
        case auxiliaryRail
    }

    let scope: Scope

    func makeNSView(context: Context) -> ScrollRedirectView {
        let view = ScrollRedirectView(scope: scope)
        DispatchQueue.main.async {
            view.updateCoordinatorBindingIfNeeded()
            view.installMonitorIfNeeded()
        }
        return view
    }

    func updateNSView(_ nsView: ScrollRedirectView, context: Context) {
        nsView.scope = scope
        DispatchQueue.main.async {
            nsView.updateCoordinatorBindingIfNeeded()
            nsView.installMonitorIfNeeded()
        }
    }

    static func dismantleNSView(_ nsView: ScrollRedirectView, coordinator: ()) {
        nsView.removeMonitor()
    }

    final class ScrollRedirectView: NSView {
        var scope: Scope
        private var localMonitor: Any?

        init(scope: Scope) {
            self.scope = scope
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) {
            self.scope = .auxiliaryRail
            super.init(coder: coder)
        }

        func updateCoordinatorBindingIfNeeded() {
            guard let scrollView = horizontalScrollableEnclosingScrollView() else {
                return
            }

            updateCardRailCoordinatorIfNeeded(scrollView)
        }

        func installMonitorIfNeeded() {
            guard localMonitor == nil else {
                return
            }

            localMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self,
                      self.redirect(event) else {
                    return event
                }

                return nil
            }
        }

        func removeMonitor() {
            if let localMonitor {
                NSEvent.removeMonitor(localMonitor)
                self.localMonitor = nil
            }
        }

        override func scrollWheel(with event: NSEvent) {
            guard redirect(event) else {
                super.scrollWheel(with: event)
                return
            }
        }

        private func redirect(_ event: NSEvent) -> Bool {
            guard abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX),
                  let window,
                  event.window === window,
                  let scrollView = horizontalScrollView(at: event.locationInWindow) else {
                return false
            }

            let clipView = scrollView.contentView
            let documentWidth = scrollView.documentView?.bounds.width ?? 0
            let maxX = max(documentWidth - clipView.bounds.width, 0)
            let multiplier: CGFloat = event.hasPreciseScrollingDeltas ? 5.0 : 18.0
            let delta = -event.scrollingDeltaY * multiplier
            let nextX = min(max(clipView.bounds.minX + delta, 0), maxX)
            clipView.scroll(to: NSPoint(x: nextX, y: clipView.bounds.minY))
            scrollView.reflectScrolledClipView(clipView)
            saveCardRailOffsetIfNeeded(nextX)
            return true
        }

        private func updateCardRailCoordinatorIfNeeded(_ scrollView: NSScrollView) {
            guard scope == .cardRail else {
                return
            }

            HistoryScrollCoordinator.shared.update(scrollView: scrollView)
        }

        private func saveCardRailOffsetIfNeeded(_ nextX: CGFloat) {
            guard scope == .cardRail else {
                return
            }

            HistoryScrollCoordinator.shared.saveOffset(nextX)
        }

        private func horizontalScrollView(at locationInWindow: NSPoint) -> NSScrollView? {
            if let scrollView = horizontalScrollableEnclosingScrollView() {
                let point = scrollView.convert(locationInWindow, from: nil)
                guard scrollView.bounds.contains(point) else {
                    return nil
                }

                return scrollView
            }

            let localPoint = convert(locationInWindow, from: nil)
            guard bounds.contains(localPoint),
                  let contentView = window?.contentView else {
                return nil
            }

            let contentPoint = contentView.convert(locationInWindow, from: nil)
            guard let hitView = contentView.hitTest(contentPoint) else {
                return nil
            }

            var candidate: NSView? = hitView
            while let view = candidate {
                if let scrollView = view as? NSScrollView,
                   isHorizontallyScrollable(scrollView) {
                    return scrollView
                }
                candidate = view.superview
            }

            return nil
        }

        private func horizontalScrollableEnclosingScrollView() -> NSScrollView? {
            var candidate: NSView? = self
            while let view = candidate {
                if let scrollView = view as? NSScrollView,
                   isHorizontallyScrollable(scrollView) {
                    return scrollView
                }
                candidate = view.superview
            }

            return nil
        }

        private func isHorizontallyScrollable(_ scrollView: NSScrollView) -> Bool {
            guard let documentView = scrollView.documentView else {
                return false
            }

            return documentView.bounds.width > scrollView.contentView.bounds.width + 2
        }
    }
}

private struct CardRailScrollViewBinder: NSViewRepresentable {
    func makeNSView(context: Context) -> BindingView {
        let view = BindingView()
        DispatchQueue.main.async {
            view.bindScrollViewIfNeeded()
        }
        return view
    }

    func updateNSView(_ nsView: BindingView, context: Context) {
        DispatchQueue.main.async {
            nsView.bindScrollViewIfNeeded()
        }
    }

    final class BindingView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            DispatchQueue.main.async {
                self.bindScrollViewIfNeeded()
            }
        }

        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            DispatchQueue.main.async {
                self.bindScrollViewIfNeeded()
            }
        }

        override func layout() {
            super.layout()
            bindScrollViewIfNeeded()
        }

        func bindScrollViewIfNeeded() {
            guard let scrollView = enclosingScrollView,
                  let documentView = scrollView.documentView,
                  documentView.bounds.width > scrollView.contentView.bounds.width + 2 else {
                return
            }

            HistoryScrollCoordinator.shared.update(scrollView: scrollView)
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }
    }
}

private struct HistoryWindowHostWindowReader: NSViewRepresentable {
    @Binding var window: NSWindow?

    func makeNSView(context: Context) -> WindowReaderView {
        let view = WindowReaderView()
        view.onWindowChange = { window in
            self.window = window
        }
        return view
    }

    func updateNSView(_ nsView: WindowReaderView, context: Context) {
        nsView.onWindowChange = { window in
            self.window = window
        }

        DispatchQueue.main.async {
            nsView.reportWindow()
        }
    }

    final class WindowReaderView: NSView {
        var onWindowChange: ((NSWindow?) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            reportWindow()
        }

        func reportWindow() {
            onWindowChange?(window)
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }
    }
}

@MainActor
final class HistoryScrollCoordinator {
    static let shared = HistoryScrollCoordinator()
    private static let savedOffsetsStorageKey = "history.savedScrollOffsetsByScope"
    var onOffsetChange: ((CGFloat) -> Void)?
    private weak var scrollView: NSScrollView?
    private var observedClipView: NSClipView?
    private var boundsObserver: ClipViewBoundsObserver?
    private var isProgrammaticScroll = false
    private var lastOffsetNotificationTime: CFTimeInterval = 0
    private var pendingOffsetNotificationTask: Task<Void, Never>?
    private var needsRestoreOnNextBinding = false
    private var pendingOffsetForNextBinding: CGFloat?
    private var coalescedScrollRequest: ScrollRequest?
    private var coalescedScrollTask: Task<Void, Never>?
    private var currentScope = "all"
    private var savedOffsetsByScope: [String: CGFloat] = [:]
    private var persistOffsetsTask: Task<Void, Never>?

    func update(scrollView: NSScrollView) {
        if self.scrollView === scrollView {
            observeClipViewIfNeeded(scrollView.contentView)
            return
        }

        self.scrollView = scrollView
        observeClipViewIfNeeded(scrollView.contentView)
        applyPendingBindingScrollIfNeeded()
    }

    func setScope(_ scope: String) {
        if let scrollView {
            saveOffset(scrollView.contentView.bounds.minX)
        }
        currentScope = scope
        restoreSavedOffset()
    }

    func restoreSavedOffset() {
        guard pendingOffsetForNextBinding == nil else {
            needsRestoreOnNextBinding = false
            return
        }

        guard let scrollView else {
            needsRestoreOnNextBinding = true
            return
        }

        needsRestoreOnNextBinding = false
        let clipView = scrollView.contentView
        let documentWidth = scrollView.documentView?.bounds.width ?? 0
        let maxX = max(documentWidth - clipView.bounds.width, 0)
        let savedOffset = savedOffsetsByScope[currentScope] ?? 0
        let targetX = min(max(savedOffset, 0), maxX)
        guard abs(targetX - clipView.bounds.minX) > 0.5 else {
            return
        }

        scrollToClampedOffset(
            targetX,
            in: scrollView,
            clipView: clipView,
            animated: false,
            preserveSavedOffset: savedOffset > maxX + 0.5 ? savedOffset : nil
        )
    }

    func saveOffset(_ offsetX: CGFloat) {
        let savedOffset = max(0, offsetX)
        let previousOffset = savedOffsetsByScope[currentScope]
        guard previousOffset == nil || abs((previousOffset ?? 0) - savedOffset) > 0.5 else {
            return
        }

        savedOffsetsByScope[currentScope] = savedOffset
        schedulePersistSavedOffsets()
        scheduleOffsetChangeNotification(savedOffset)
    }

    func loadSavedOffsets(from storageValue: String) {
        guard let data = storageValue.data(using: .utf8),
              let decodedOffsets = try? JSONDecoder().decode([String: Double].self, from: data) else {
            return
        }

        savedOffsetsByScope = decodedOffsets.mapValues { CGFloat($0) }
    }

    func savedOffsetsStorageValue() -> String {
        let encodableOffsets = savedOffsetsByScope.mapValues(Double.init)
        guard let data = try? JSONEncoder().encode(encodableOffsets),
              let value = String(data: data, encoding: .utf8) else {
            return "{}"
        }

        return value
    }

    private func schedulePersistSavedOffsets() {
        persistOffsetsTask?.cancel()
        persistOffsetsTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else {
                return
            }

            UserDefaults.standard.set(savedOffsetsStorageValue(), forKey: Self.savedOffsetsStorageKey)
        }
    }

    private func scheduleOffsetChangeNotification(_ offsetX: CGFloat) {
        guard onOffsetChange != nil else {
            return
        }

        let now = CACurrentMediaTime()
        if now - lastOffsetNotificationTime >= 1.0 / 30.0 {
            pendingOffsetNotificationTask?.cancel()
            lastOffsetNotificationTime = now
            onOffsetChange?(offsetX)
            return
        }

        pendingOffsetNotificationTask?.cancel()
        pendingOffsetNotificationTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 33_000_000)
            guard !Task.isCancelled else {
                return
            }

            lastOffsetNotificationTime = CACurrentMediaTime()
            onOffsetChange?(currentOffset)
        }
    }

    func captureCurrentOffset() {
        guard let scrollView else {
            return
        }

        saveOffset(scrollView.contentView.bounds.minX)
        persistOffsetsTask?.cancel()
        UserDefaults.standard.set(savedOffsetsStorageValue(), forKey: Self.savedOffsetsStorageKey)
    }

    func discardSavedOffset(for scope: String) {
        savedOffsetsByScope[scope] = 0
        if currentScope == scope {
            pendingOffsetForNextBinding = nil
            needsRestoreOnNextBinding = false
        }
    }

    func queuePendingOffset(_ offsetX: CGFloat) {
        pendingOffsetForNextBinding = max(0, offsetX)
        needsRestoreOnNextBinding = false
    }

    var hasPendingExplicitOffset: Bool {
        pendingOffsetForNextBinding != nil
    }

    var currentOffset: CGFloat {
        scrollView?.contentView.bounds.minX ?? savedOffsetsByScope[currentScope] ?? 0
    }

    var visibleDocumentRect: CGRect? {
        guard let scrollView else {
            return nil
        }

        return scrollView.contentView.bounds
    }

    func scrollToOffset(_ offsetX: CGFloat, animated: Bool, suppressUserOffsetSave: Bool = false) {
        if scrollView != nil,
           animated {
            coalesceScrollToOffset(offsetX, suppressUserOffsetSave: suppressUserOffsetSave)
            return
        }

        performScrollToOffset(offsetX, animated: animated, suppressUserOffsetSave: suppressUserOffsetSave)
    }

    private func coalesceScrollToOffset(_ offsetX: CGFloat, suppressUserOffsetSave: Bool) {
        coalescedScrollRequest = ScrollRequest(
            offsetX: offsetX,
            animated: true,
            suppressUserOffsetSave: suppressUserOffsetSave
        )
        coalescedScrollTask?.cancel()
        coalescedScrollTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled,
                  let request = coalescedScrollRequest else {
                return
            }

            coalescedScrollRequest = nil
            performScrollToOffset(
                request.offsetX,
                animated: request.animated,
                suppressUserOffsetSave: request.suppressUserOffsetSave
            )
        }
    }

    private func performScrollToOffset(_ offsetX: CGFloat, animated: Bool, suppressUserOffsetSave: Bool = false) {
        guard let scrollView else {
            pendingOffsetForNextBinding = offsetX
            needsRestoreOnNextBinding = false
            if !suppressUserOffsetSave {
                saveOffset(offsetX)
            }
            return
        }

        forceLayout()
        pendingOffsetForNextBinding = nil
        needsRestoreOnNextBinding = false
        let clipView = scrollView.contentView
        scrollToClampedOffset(
            offsetX,
            in: scrollView,
            clipView: clipView,
            animated: animated,
            suppressUserOffsetSave: suppressUserOffsetSave
        )
    }

    func forceLayout() {
        guard let scrollView else {
            return
        }

        scrollView.documentView?.layoutSubtreeIfNeeded()
        scrollView.layoutSubtreeIfNeeded()
    }

    func scrollBy(_ deltaX: CGFloat, animated: Bool) {
        guard let scrollView else {
            return
        }

        let clipView = scrollView.contentView
        scrollToClampedOffset(clipView.bounds.minX + deltaX, in: scrollView, clipView: clipView, animated: animated)
    }

    private func scrollToClampedOffset(
        _ offsetX: CGFloat,
        in scrollView: NSScrollView,
        clipView: NSClipView,
        animated: Bool,
        preserveSavedOffset: CGFloat? = nil,
        suppressUserOffsetSave: Bool = false
    ) {
        let documentWidth = scrollView.documentView?.bounds.width ?? 0
        let maxX = max(documentWidth - clipView.bounds.width, 0)
        let nextX = min(max(offsetX, 0), maxX)

        guard abs(nextX - clipView.bounds.minX) > 0.5 else {
            saveOffset(preserveSavedOffset ?? nextX)
            return
        }

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.26
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)
                self.isProgrammaticScroll = true
                if suppressUserOffsetSave {
                    self.pendingOffsetForNextBinding = nextX
                }
                clipView.animator().setBoundsOrigin(NSPoint(x: nextX, y: clipView.bounds.minY))
            } completionHandler: {
                scrollView.reflectScrolledClipView(clipView)
                self.saveOffset(preserveSavedOffset ?? nextX)
                if suppressUserOffsetSave {
                    self.pendingOffsetForNextBinding = nil
                }
                self.isProgrammaticScroll = false
            }
        } else {
            isProgrammaticScroll = true
            clipView.scroll(to: NSPoint(x: nextX, y: clipView.bounds.minY))
            scrollView.reflectScrolledClipView(clipView)
            saveOffset(preserveSavedOffset ?? nextX)
            isProgrammaticScroll = false
        }
    }

    private func applyPendingBindingScrollIfNeeded() {
        if let pendingOffsetForNextBinding {
            self.pendingOffsetForNextBinding = nil
            performScrollToOffset(pendingOffsetForNextBinding, animated: false)
            return
        }

        if needsRestoreOnNextBinding {
            restoreSavedOffset()
        }
    }

    private func observeClipViewIfNeeded(_ clipView: NSClipView) {
        guard observedClipView !== clipView else {
            return
        }

        observedClipView = clipView
        boundsObserver = ClipViewBoundsObserver(clipView: clipView) { [weak self] clipView in
            self?.clipViewBoundsDidChange(clipView)
        }
    }

    private func clipViewBoundsDidChange(_ clipView: NSClipView) {
        guard !isProgrammaticScroll,
              clipView === observedClipView else {
            return
        }

        if let scrollView,
           let savedOffset = savedOffsetsByScope[currentScope],
           savedOffset > 0 {
            let documentWidth = scrollView.documentView?.bounds.width ?? 0
            let maxX = max(documentWidth - clipView.bounds.width, 0)
            if savedOffset > maxX + 0.5,
               clipView.bounds.minX < savedOffset {
                return
            }
        }

        saveOffset(clipView.bounds.minX)
    }

    deinit {
        persistOffsetsTask?.cancel()
        pendingOffsetNotificationTask?.cancel()
        coalescedScrollTask?.cancel()
    }
}

@MainActor
private struct ScrollRequest {
    let offsetX: CGFloat
    let animated: Bool
    let suppressUserOffsetSave: Bool
}

@MainActor
private final class ClipViewBoundsObserver: NSObject, @unchecked Sendable {
    private weak var clipView: NSClipView?
    private let onBoundsChange: (NSClipView) -> Void

    init(clipView: NSClipView, onBoundsChange: @escaping (NSClipView) -> Void) {
        self.clipView = clipView
        self.onBoundsChange = onBoundsChange
        super.init()

        clipView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(clipViewBoundsDidChange(_:)),
            name: NSView.boundsDidChangeNotification,
            object: clipView,
        )
    }

    @objc private func clipViewBoundsDidChange(_ notification: Notification) {
        guard let clipView = notification.object as? NSClipView,
              clipView === self.clipView else {
            return
        }

        onBoundsChange(clipView)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

private struct SearchInteractionFramePreferenceKey: PreferenceKey {
    static let defaultValue: [CGRect] = []

    static func reduce(value: inout [CGRect], nextValue: () -> [CGRect]) {
        value.append(contentsOf: nextValue())
    }
}
