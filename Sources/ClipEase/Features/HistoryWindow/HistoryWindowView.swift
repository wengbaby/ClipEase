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
    @StateObject private var searchCoordinator = HistorySearchCoordinator()
    @StateObject private var previewCoordinator = HistoryPreviewCoordinator()
    @StateObject private var viewportStore = HistoryViewportStore()
    @StateObject private var groupAppearanceCoordinator = GroupAppearanceCoordinator()
    private let inputFocusCoordinator = HistoryInputFocusCoordinator()
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
    @State private var isSearchFieldLayoutVisible = false
    @State private var isSearchFieldVisualVisible = false
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
    @State private var isGroupIconSearchFocused = false
    @State private var moveToGroupMenuSnapshot: [MoveToGroupMenuEntry] = []
    @State private var moveToGroupPickerTarget: MoveToGroupPickerTarget?
    @State private var pendingGroupTrackScrollID: String?
    @State private var isCommandKeyPressed = false
    @State private var isSearchFocused = false
    @State private var isSearchTextComposing = false
    @State private var searchFocusRequestID = 0
    @State private var pendingComposedSearchInputEvent: HistoryKeyboardPendingTextInputEvent?
    @State private var allPreviewItems: [HistoryPreviewItem] = []
    @State private var filteredPreviewItems: [HistoryPreviewItem] = []
    @State private var filteredPreviewItemIDs: Set<HistoryPreviewItem.ID> = []
    @State private var filteredPreviewItemIndexByID: [HistoryPreviewItem.ID: Int] = [:]
    @State private var isUsingUnfilteredPreviewResult = true
    @State private var sourceAppFilterOptions: [HistorySourceAppFilterOption] = []
    @State private var sourceAppIconFileNameByName: [String: String] = [:]
    @State private var previewBuildTask: Task<Void, Never>?
    @State private var previewBuildGeneration: UInt64 = 0
    @State private var deferredStartupTask: Task<Void, Never>?
    @State private var previewItemsSourceSignature: [HistoryPreviewSourceSignature] = []
    @State private var appliedPreviewItemsMutationGeneration: UInt64 = 0
    @State private var previewItemCache: [ClipboardItem.ID: CachedHistoryPreviewItem] = [:]
    @State private var searchVisibilityTask: Task<Void, Never>?
    @State private var pendingSearchTrigger = "unknown"
    @State private var searchHasHandedOffFocusToCard = false
    @State private var preheatTask: Task<Void, Never>?
    @State private var rememberSelectedItemTask: Task<Void, Never>?
    @State private var latestFocusRetryTask: Task<Void, Never>?
    @State private var hiddenResourceCheckpointTask: Task<Void, Never>?
    @State private var lastHiddenResourceCheckpointAt: CFAbsoluteTime = 0
    @State private var windowWidth: CGFloat = 0
    @State private var latestPresentedItemID: ClipboardItem.ID?
    @State private var latestPresentedItemTimestamp: Date = .distantPast
    @State private var latestObservation: LatestItemObservation?
    @State private var pendingNewestItemIDForNextShow: ClipboardItem.ID?
    @State private var pendingLatestFocusItemID: ClipboardItem.ID?
    @State private var pendingLatestFocusTimestamp: Date?
    @State private var pendingLatestFocusReason: ClipboardItemFocusRequest.Reason?
    @State private var pendingLatestFocusLockID: ClipboardItem.ID?
    @State private var pendingKeyboardFocusItemID: ClipboardItem.ID?
    @State private var pendingKeyboardFocusClearTask: Task<Void, Never>?
    @State private var latestClipboardFocusGeneration: UInt64 = 0
    @State private var pendingProgrammaticJumpItemID: ClipboardItem.ID?
    @State private var pendingPastedItemFocusOnNextShow: ClipboardItem.ID?
    @State private var pendingDefaultFocusOnShow = false
    @State private var pendingItemScrollID: HistoryPreviewItem.ID?
    @State private var pendingItemScrollRetryCount = 0
    @State private var shouldResetHorizontalOffsetForPendingItemScroll = false
    @State private var shouldAnimatePendingItemScroll = false
    @State private var isPreparingPendingItemScrollMeasurement = false
    @State private var enteringItemIDs: Set<ClipboardItem.ID> = []
    @State private var enteringItemClearTask: Task<Void, Never>?
    @State private var entranceSheenItemIDs: Set<ClipboardItem.ID> = []
    @State private var entranceSheenStartTime: CFTimeInterval?
    @State private var entranceSheenClearTask: Task<Void, Never>?
    @State private var didRestoreRememberedViewport = false
    @State private var itemScrollRequestID = UUID()
    @State private var hoveredCardID: HistoryPreviewItem.ID?
    @State private var pressedCardID: HistoryPreviewItem.ID?
    @State private var cardViewportFrames: [HistoryPreviewItem.ID: CGRect] = [:]
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
    private let selectedCardTopContentInset: CGFloat = 6
    private let horizontalContentPadding: CGFloat = 28
    private let horizontalCardSpacing: CGFloat = 20
    private let historyCardWidth: CGFloat = 250
    private let latestItemEntranceDuration: TimeInterval = 1.15
    private let latestItemEntranceSheenDuration: TimeInterval = 1.8
    private let pendingItemScrollMaxRetryCount = 6
    private let largeHistoryAnimationThreshold = 2_000
    private let historyRailWindowBufferItemCount = 6
    private let historyRailRenderedItemLimit = 20
    private let previewItemCacheRetainedItemCount = 20
    private let searchResultPageSize = 50
    private let hiddenResourceCheckpointMinimumInterval: CFTimeInterval = 10
    private let latestInsertedCardLeadingInset: CGFloat = 28

    private var items: [HistoryPreviewItem] {
        allPreviewItems
    }

    private var filteredItems: [HistoryPreviewItem] {
        isUsingUnfilteredPreviewResult ? allPreviewItems : filteredPreviewItems
    }

    private var renderedItems: [HistoryPreviewItem] {
        filteredItems
    }

    private func applyFilteredPreviewResult(_ result: HistorySearchFilterResult) {
        guard isUsingUnfilteredPreviewResult || filteredPreviewItems != result.items else {
            return
        }

        isUsingUnfilteredPreviewResult = false
        filteredPreviewItems = result.items
        filteredPreviewItemIDs = result.itemIDs
        filteredPreviewItemIndexByID = result.itemIndexByID
    }

    private func applyUnfilteredPreviewResult() {
        guard !isUsingUnfilteredPreviewResult else {
            return
        }

        isUsingUnfilteredPreviewResult = true
        filteredPreviewItems.removeAll(keepingCapacity: false)
        filteredPreviewItemIDs.removeAll(keepingCapacity: true)
        filteredPreviewItemIndexByID.removeAll(keepingCapacity: true)
    }

    private func containsFilteredItem(_ id: HistoryPreviewItem.ID?) -> Bool {
        guard let id else {
            return false
        }

        if isUsingUnfilteredPreviewResult {
            return store.cachedItemIndex(with: id) != nil
        }

        return filteredPreviewItemIDs.contains(id)
    }

    private func filteredItemIndex(for id: HistoryPreviewItem.ID?) -> Int? {
        guard let id else {
            return nil
        }

        if isUsingUnfilteredPreviewResult {
            return store.cachedItemIndex(with: id)
        }

        return filteredPreviewItemIndexByID[id]
    }

    private func filteredItem(for id: HistoryPreviewItem.ID?) -> HistoryPreviewItem? {
        guard let index = filteredItemIndex(for: id),
              filteredItems.indices.contains(index) else {
            return nil
        }

        return filteredItems[index]
    }

    private var itemStride: CGFloat {
        historyCardWidth + horizontalCardSpacing
    }

    private var historyRailContentWidth: CGFloat {
        RenderWindowCoordinator.contentWidth(
            itemCount: renderedItems.count,
            cardWidth: historyCardWidth,
            cardSpacing: horizontalCardSpacing,
            horizontalPadding: horizontalContentPadding
        )
    }

    private var historyRailVisibleWindow: Range<Int> {
        historyRailViewportContext.visibleWindow(focusedIndex: focusedHistoryRailIndex)
    }

    private var focusedHistoryRailIndex: Int? {
        guard let focusedID = HistoryRailRenderWindowPolicy.focusedID(
            pendingLatestFocusItemID: pendingLatestFocusItemID ?? pendingKeyboardFocusItemID,
            pendingProgrammaticJumpItemID: pendingProgrammaticJumpItemID,
            pendingItemScrollID: pendingItemScrollID,
            selectedItemID: selectedItemID,
            visibleRect: viewportStore.visibleRect
        ),
              let focusedIndex = filteredItemIndex(for: focusedID) else {
            return nil
        }

        return focusedIndex
    }

    private var historyRailViewportContext: HistoryRailViewportContext {
        RenderWindowCoordinator.viewportContext(
            itemCount: renderedItems.count,
            visibleRect: viewportStore.visibleRect,
            hasReliableVisibleRect: HistoryScrollCoordinator.shared.hasBoundScrollView,
            itemStride: itemStride,
            horizontalContentPadding: horizontalContentPadding,
            bufferItemCount: historyRailWindowBufferItemCount,
            renderedItemLimit: historyRailRenderedItemLimit,
            edgeBufferItemCount: 3,
            mode: viewportStore.mode
        )
    }

    private var renderedWindowItems: ArraySlice<HistoryPreviewItem> {
        RenderWindowCoordinator.renderedWindowItems(
            items: renderedItems,
            visibleWindow: historyRailVisibleWindow
        )
    }

    private func requestNextHistoryPageIfNeeded() {
        if isUsingUnfilteredPreviewResult {
            store.loadMoreItemsIfNeeded(visibleUpperBound: historyRailVisibleWindow.upperBound, preloadMargin: 20)
        } else {
            loadMoreSearchResultsIfNeeded(visibleUpperBound: historyRailVisibleWindow.upperBound)
        }
    }

    private func shouldAnimateHistoryRailChange(sourceItemCount: Int, renderedItemCount: Int) -> Bool {
        sourceItemCount <= largeHistoryAnimationThreshold &&
            renderedItemCount <= largeHistoryAnimationThreshold
    }

    private var filteredGroupIcons: [String] {
        let query = groupAppearanceCoordinator.iconSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
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

    private var groupAppearanceColor: Color {
        get {
            Color.clipeaseHex(groupAppearanceCoordinator.colorHex)
        }
        nonmutating set {
            groupAppearanceCoordinator.colorHex = newValue.clipeaseHexString
        }
    }

    private var groupAppearanceIconName: String {
        get {
            groupAppearanceCoordinator.iconName
        }
        nonmutating set {
            groupAppearanceCoordinator.iconName = newValue
        }
    }

    private var groupIconSearchTextBinding: Binding<String> {
        Binding(
            get: { groupAppearanceCoordinator.iconSearchText },
            set: { groupAppearanceCoordinator.iconSearchText = $0 }
        )
    }

    private var groupAppearancePopoverWindowBinding: Binding<NSWindow?> {
        Binding(
            get: { groupAppearanceCoordinator.popoverWindow },
            set: { groupAppearanceCoordinator.setPopoverWindow($0) }
        )
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

    private var isSearchControlExpanded: Bool {
        isSearchVisible || isSearchFieldLayoutVisible
    }

    private var hasSearchContent: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !searchTokens.isEmpty ||
            searchCriteria.hasActiveFilters
    }

    private var canEditSelectedItemFromShortcut: Bool {
        guard !isTextInputActiveForEditShortcut,
              let selectedItemID,
              containsFilteredItem(selectedItemID),
              let item = store.item(with: selectedItemID) else {
            return false
        }

        return isEditable(item)
    }

    private var shouldSuppressHistoryCommandShortcuts: Bool {
        isTextInputActiveForEditShortcut || inputState.isPreviewContentActive
    }

    private var canPerformDeleteCommand: Bool {
        HistoryKeyboardActionRouter().allowsHistoryCommand(
            .delete,
            isTextInputActive: isTextInputActiveForEditShortcut || inputState.isTextInputFocusedSnapshot,
            isPreviewContentActive: inputState.isPreviewContentActive
        )
    }

    private var isTextInputActiveForEditShortcut: Bool {
        isSearchFocused ||
            isGroupIconSearchFocused ||
            isSearchFilterPanelPresented ||
            groupRenameTargetID != nil ||
            groupAppearanceCoordinator.regularGroupTarget != nil ||
            groupAppearanceCoordinator.systemGroupTarget != nil ||
            moveToGroupPickerTarget != nil ||
            NSApp.keyWindow?.firstResponder is NSTextView
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

                if items.isEmpty && store.items.isEmpty {
                    allEmptyState
                } else if items.isEmpty {
                    loadingContentState
                } else if filteredItems.isEmpty {
                    emptyContentState
                } else {
                    ScrollViewReader { proxy in
                        historyRail
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

                            if let targetOffset = programmaticJumpTargetOffset(for: pendingItemScrollID) {
                                isPreparingPendingItemScrollMeasurement = true
                                pendingItemScrollRetryCount += 1
                                viewportStore.resetForLatestFocus(
                                    offsetX: targetOffset,
                                    width: viewportStore.visibleRect.width,
                                    height: viewportStore.visibleRect.height
                                )

                                Task { @MainActor in
                                    await Task.yield()
                                    guard self.pendingItemScrollID == pendingItemScrollID else {
                                        return
                                    }
                                    self.isPreparingPendingItemScrollMeasurement = false
                                    self.itemScrollRequestID = UUID()
                                }
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
            GroupAppearanceOutsideMouseDownObserver(
                isEnabled: groupAppearanceCoordinator.regularGroupTarget != nil || groupAppearanceCoordinator.systemGroupTarget != nil,
                hostWindow: hostWindow,
                popoverWindow: groupAppearanceCoordinator.popoverWindow,
                onMouseDown: closeGroupAppearanceLayer
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
        .onPreferenceChange(CardViewportFramePreferenceKey.self) { frames in
            cardViewportFrames = frames
            followPreviewForCurrentScroll()
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
            HistoryScrollCoordinator.shared.onOffsetChange = { _ in
                Task { @MainActor in
                    updateCardRailVisibleRect()
                    requestNextHistoryPageIfNeeded()
                    followPreviewForCurrentScroll()
                }
            }
            refreshMoveToGroupMenuSnapshot()
            primeLatestItemPresentationGuard(sourceItems: store.items)
            if let request = store.consumeLatestItemFocusRequest() {
                focusRequestedLatestItem(request)
            }
            focusRecentlyAddedItemOnShowIfNeeded(sourceItems: store.items)
            scheduleDeferredStartupWork()
        }
        .onDisappear {
            cancelPendingGroupRename()
            closeInactiveSearchBeforeHiding()
            deferredStartupTask?.cancel()
            previewBuildTask?.cancel()
            previewBuildGeneration &+= 1
            searchCoordinator.cancelAll()
            searchVisibilityTask?.cancel()
            preheatTask?.cancel()
            previewCoordinator.cancelFollow()
            rememberSelectedItemTask?.cancel()
            latestFocusRetryTask?.cancel()
            pendingKeyboardFocusClearTask?.cancel()
            hiddenResourceCheckpointTask?.cancel()
            enteringItemClearTask?.cancel()
            entranceSheenClearTask?.cancel()
            entranceSheenItemIDs.removeAll()
            entranceSheenStartTime = nil
            pendingDefaultFocusOnShow = false
            hoveredCardID = nil
            pressedCardID = nil
            HistoryScrollCoordinator.shared.onOffsetChange = nil
        }
        .onChange(of: store.items) { newItems in
            syncLatestItemFocusIfNeeded(sourceItems: newItems)
            schedulePreviewItemsRebuild(from: newItems)
            requestNextHistoryPageIfNeeded()
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
                rebuildPreviewItemsIfNeededForVisibleWindow()
            } else {
                noteHistoryWindowHidden()
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
            pruneSearchTokenOrder()
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
        .onChange(of: inputState.defaultFocusRequest) { request in
            guard let request else {
                return
            }

            focusDefaultItemOnShow(request)
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
            closeGroupAppearanceLayer()
            closeInactiveSearchBeforeHiding()
        }
        .onChange(of: selectedItemID) { _ in
            rememberSelectedItem()
        }
        .onChange(of: historyRailVisibleWindow) { _ in
            let visibleIDs = Set(renderedWindowItems.map(\.id))
            cardViewportFrames = cardViewportFrames.filter { visibleIDs.contains($0.key) }
        }
        .onChange(of: isSearchFocused) { isFocused in
            inputState.setTextInputFocused(isFocused)
        }
        .onChange(of: searchHasHandedOffFocusToCard) { hasHandedOff in
            inputState.setSearchHasHandedOffFocusToCard(hasHandedOff)
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
            updateSearchFieldPresentation(isVisible: isVisible)
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
    private var historyRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            ZStack(alignment: .topLeading) {
                CardRailScrollViewBinder {
                    updateCardRailVisibleRect()
                    requestNextHistoryPageIfNeeded()
                }
                    .frame(width: 0, height: 0)

                ForEach(renderedWindowItems) { item in
                    historyCard(item)
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.96)
                                .combined(with: .opacity),
                            removal: .scale(scale: 0.985)
                                .combined(with: .opacity)
                        ))
                        .frame(width: historyCardWidth)
                        .offset(x: cardDocumentX(for: item.id))
                }
            }
            .frame(width: historyRailContentWidth, height: 300, alignment: .topLeading)
            .padding(.top, selectedCardTopContentInset)
            .padding(.bottom, 8)
            .padding(.bottom, 22)
        }
    }

    @ViewBuilder
    private func historyCard(_ item: HistoryPreviewItem) -> some View {
        let isSelected = selectedItemID == item.id
        let isCardFocused = isSelected && HistoryCardFocusPolicy.isCardFocusActive(
            selectedItemID: selectedItemID,
            isSearchFieldFocused: isSearchFocused || inputState.isTextInputFocusedSnapshot,
            searchHasHandedOffFocusToCard: searchHasHandedOffFocusToCard
        )
        let isHovered = hoveredCardID == item.id
        let isPressed = pressedCardID == item.id
        let isEnteringLatestItem = enteringItemIDs.contains(item.id)
        let isShowingEntranceSheen = entranceSheenItemIDs.contains(item.id)
        let cardScale: CGFloat = isPressed ? 1.045 : (isHovered ? 1.04 : (isCardFocused ? (isEnteringLatestItem ? 1.012 : 1.025) : 1))

        HistoryCardView(
            item: item,
            searchQuery: searchText,
            shortcutNumber: shortcutNumber(for: item.id),
            isShortcutOverlayVisible: isCommandKeyPressed || inputState.isCommandKeyPressed,
            isHovered: isHovered,
            isPressed: isPressed,
            isEnteringLatestItem: isEnteringLatestItem,
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
            onFileDragStatus: showStatus,
            onHoverChanged: { isHovered in
                setCardHover(item.id, isHovered: isHovered)
            },
            onPressChanged: { isPressed in
                setCardPress(item.id, isPressed: isPressed)
            },
            onMouseExitedWindow: closeWindowForCardDrag
        )
        .equatable()
        .background(
            GeometryReader { proxy in
                Color.clear
                    .preference(
                        key: CardViewportFramePreferenceKey.self,
                        value: [item.id: proxy.frame(in: .named("historyWindow"))]
                    )
            }
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(
                    isCardFocused && !isEnteringLatestItem ? Color(red: 0.18, green: 0.55, blue: 1.0) : (isHovered || isPressed || isEnteringLatestItem ? Color.clear : Color.black.opacity(0.08)),
                    lineWidth: isCardFocused ? 4 : 1
                )
                .allowsHitTesting(false)
        }
        .overlay {
            if isEnteringLatestItem {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color(red: 0.18, green: 0.55, blue: 1.0), lineWidth: 3)
                    .padding(-4)
                    .opacity(0.88)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
        .overlay {
            if isShowingEntranceSheen {
                latestCardEntranceSheen
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .allowsHitTesting(false)
            }
        }
        .shadow(
            color: .black.opacity(0),
            radius: 0,
            x: 0,
            y: 0
        )
        .scaleEffect(cardScale, anchor: .center)
        .animation(.interactiveSpring(response: 0.24, dampingFraction: 0.86), value: isCardFocused)
        .animation(.easeOut(duration: 0.82), value: isEnteringLatestItem)
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .animation(.easeOut(duration: 0.06), value: isPressed)
        .id(item.id)
        .contentShape(Rectangle())
        .zIndex(isPressed ? 4 : (isHovered ? 3 : (isCardFocused ? 2 : 0)))
    }

    private var latestCardEntranceSheen: some View {
        TimelineView(.animation) { timeline in
            GeometryReader { proxy in
                let width = max(proxy.size.width, 1)
                let height = max(proxy.size.height, 1)
                let progress = latestCardEntranceSheenProgress(at: timeline.date)
                let sheenOpacity = latestCardEntranceSheenOpacity(for: progress)
                let sheenTravelProgress = latestCardEntranceSheenTravelProgress(for: progress)
                LinearGradient(
                    colors: [
                        .clear,
                        .white.opacity(0),
                        .white.opacity(0.52),
                        .white.opacity(0),
                        .clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .frame(width: width * 1.55, height: height * 1.28)
                .rotationEffect(.degrees(-10))
                .offset(x: -width * 0.78 + sheenTravelProgress * width * 1.7, y: -height * 0.14)
                .opacity(sheenOpacity)
            }
        }
        .clipped()
    }

    private func latestCardEntranceSheenProgress(at date: Date) -> CGFloat {
        guard let entranceSheenStartTime else {
            return 0
        }

        let elapsed = date.timeIntervalSinceReferenceDate - entranceSheenStartTime
        return min(1, max(0, CGFloat(elapsed / latestItemEntranceSheenDuration)))
    }

    private func latestCardEntranceSheenOpacity(for progress: CGFloat) -> CGFloat {
        if progress <= 0 {
            return 0
        }

        if progress < 0.18 {
            return progress / 0.18
        }

        if progress <= 0.82 {
            return 1
        }

        return max(0, 1 - ((progress - 0.82) / 0.18))
    }

    private func latestCardEntranceSheenTravelProgress(for progress: CGFloat) -> CGFloat {
        guard progress > 0 else {
            return 0
        }

        guard progress < 0.82 else {
            return 1
        }

        return min(1, progress / 0.82)
    }

    private func setCardHover(_ id: HistoryPreviewItem.ID, isHovered: Bool) {
        if isHovered {
            hoveredCardID = id
        } else if hoveredCardID == id {
            hoveredCardID = nil
        }
    }

    private func setCardPress(_ id: HistoryPreviewItem.ID, isPressed: Bool) {
        if isPressed {
            pressedCardID = id
        } else if pressedCardID == id {
            pressedCardID = nil
        }
    }

    private func playEntranceAnimationSoon(for id: ClipboardItem.ID) {
        playEntranceAnimation(for: id)
    }

    private func playEntranceAnimation(for id: ClipboardItem.ID) {
        enteringItemClearTask?.cancel()
        entranceSheenClearTask?.cancel()
        enteringItemIDs = [id]
        entranceSheenItemIDs = [id]
        entranceSheenStartTime = Date().timeIntervalSinceReferenceDate
        entranceSheenClearTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(latestItemEntranceSheenDuration * 1_000_000_000))
            guard !Task.isCancelled else {
                return
            }

            entranceSheenItemIDs.remove(id)
            entranceSheenStartTime = nil
            entranceSheenClearTask = nil
        }
        enteringItemClearTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(latestItemEntranceDuration * 1_000_000_000))
            guard !Task.isCancelled else {
                return
            }

            withAnimation(.easeOut(duration: 0.20)) {
                _ = enteringItemIDs.remove(id)
            }
            enteringItemClearTask = nil
        }
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

                        Group {
                            searchToggleButton
                                .id("search-toggle")

                            allHistoryGroupButton
                                .id(HistoryGroupSelection.all.scrollID)

                            systemGroupButton(.pinned)
                                .id(HistoryGroupSelection.pinned.scrollID)

                            ForEach(store.groups) { group in
                                groupButton(group, compact: isSearchControlExpanded)
                                    .id(HistoryGroupSelection.group(group.id).scrollID)
                            }

                            if !isSearchControlExpanded {
                                newGroupButton
                                    .id("new-group")
                            }

                            if isSearchControlExpanded || isSearchActive {
                                resultCountBadge
                                    .id("result-count")
                            }
                        }
                        .animation(.easeOut(duration: 0.10), value: isSearchControlExpanded)
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
                if !isSearchControlExpanded {
                    Text("全部剪切板")
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, isSearchControlExpanded ? 8 : 10)
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
        .historyRailControlStyle()
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
        .historyRailControlStyle()
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
        .historyRailControlStyle()
        .help("新建分组")
    }

    private func systemGroupButton(_ group: SystemHistoryGroup) -> some View {
        let isSelected = selectedGroup == group.selection
        let color = systemGroupColor(group)

        return Button(action: { selectSystemGroup(group) }) {
            HStack(spacing: 6) {
                Image(systemName: systemGroupIconName(group))
                    .font(.system(size: 12, weight: .semibold))
                if !isSearchControlExpanded {
                    Text(group.title)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, isSearchControlExpanded ? 8 : 10)
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
        .historyRailControlStyle()
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
                    get: { groupAppearanceCoordinator.systemGroupTarget == group },
                    set: { isPresented in
                        if !isPresented, groupAppearanceCoordinator.systemGroupTarget == group {
                            closeSystemGroupAppearancePopover()
                        }
                    }
                ),
                arrowEdge: .bottom,
                onDismiss: closeSystemGroupAppearancePopover
            ) {
                systemGroupAppearancePopover(group)
                    .background(GroupAppearancePopoverWindowReader(window: groupAppearancePopoverWindowBinding))
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
                text: groupIconSearchTextBinding,
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
                text: groupIconSearchTextBinding,
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
                .historyRailControlStyle()
                .background(GroupMouseDownObserver(
                    onMouseDown: handleGroupRowOutsideClick,
                    onRightMouseDown: { selectGroupForContextMenu(group) },
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
                            get: { groupAppearanceCoordinator.regularGroupTarget?.id == group.id },
                            set: { isPresented in
                                if !isPresented, groupAppearanceCoordinator.regularGroupTarget?.id == group.id {
                                    closeGroupAppearancePopover()
                                }
                            }
                        ),
                        arrowEdge: .bottom,
                        onDismiss: closeGroupAppearancePopover
                    ) {
                        groupAppearancePopover(group)
                            .background(GroupAppearancePopoverWindowReader(window: groupAppearancePopoverWindowBinding))
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
            .background(Color.white.opacity(0.76))
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .stroke(
                        Color(red: 0.78, green: 0.36, blue: 0.08).opacity(0.55),
                        lineWidth: 1
                    )
            }
        }
        .buttonStyle(.plain)
        .historyRailControlStyle()
        .help("点击打开辅助功能权限设置")
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
                            pendingComposedInputEvent: $pendingComposedSearchInputEvent,
                            focusRequestID: searchFocusRequestID,
                            searchHasHandedOffFocusToCard: searchHasHandedOffFocusToCard,
                            hasSearchResult: !filteredItems.isEmpty,
                            hasSearchTokens: !searchTokens.isEmpty,
                            onFocusChanged: synchronizeSearchTextFieldFocus,
                            onEnterFirstResult: enterFirstSearchResultFromSearchField,
                            onDeleteLastToken: handleSearchTokenBackspace,
                            onCancel: handleSearchCancel
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
        .frame(width: isSearchFieldLayoutVisible ? 520 : 0, height: 30)
        .background(Color.white.opacity(isSearchFieldVisualVisible ? 0.72 : 0))
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
        .opacity(isSearchFieldVisualVisible ? 1 : 0)
        .scaleEffect(isSearchFieldVisualVisible ? 1 : 0.985, anchor: .leading)
        .allowsHitTesting(isSearchVisible)
        .animation(.easeOut(duration: 0.12), value: isSearchFieldVisualVisible)
    }

    private func searchTokenView(_ token: HistorySearchToken) -> some View {
        let isSelected = selectedSearchTokenKind == token.kind
        let selectedBackground = Color(red: 0.18, green: 0.55, blue: 1.0)
        let addedBackground = Color(red: 0.82, green: 0.91, blue: 1.0)
        let addedStroke = Color(red: 0.45, green: 0.68, blue: 0.92)

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
        .foregroundStyle(isSelected ? .white : Color(red: 0.08, green: 0.22, blue: 0.38))
        .background(isSelected ? selectedBackground : addedBackground)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(isSelected ? selectedBackground : addedStroke.opacity(0.7), lineWidth: 1)
        }
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
                        if sourceAppFilterOptions.isEmpty {
                            Text("暂无来源")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                        } else {
                            filterChipGrid {
                                ForEach(sourceAppFilterOptions) { option in
                                    let appName = option.name
                                    searchFilterChip(
                                        title: appName,
                                        iconFileName: option.iconFileName,
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
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard inputState.isWindowVisibleSnapshot else {
                return
            }

            accessibilityPermissionState.refresh()
        }
    }

    private func noteHistoryWindowHidden() {
        PerformanceDiagnosticsService.shared.record(
            "history.hidden.keepWarm",
            category: "history",
            durationMS: 0,
            itemCount: store.items.count,
            resultCount: allPreviewItems.count,
            metadata: [
                "reason": "window.hidden",
                "cacheStored": "\(previewItemCache.count)"
            ]
        )
        let now = CFAbsoluteTimeGetCurrent()
        if now - lastHiddenResourceCheckpointAt >= hiddenResourceCheckpointMinimumInterval {
            lastHiddenResourceCheckpointAt = now
            hiddenResourceCheckpointTask?.cancel()
            hiddenResourceCheckpointTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 750_000_000)
                guard !Task.isCancelled,
                      !inputState.isWindowPresentedSnapshot else {
                    return
                }

                PerformanceDiagnosticsService.shared.recordResourceCheckpoint("history.hidden.keepWarm.deferred")
                hiddenResourceCheckpointTask = nil
            }
        }
    }

    private func rebuildPreviewItemsIfNeededForVisibleWindow() {
        guard inputState.isWindowVisibleSnapshot,
              !store.items.isEmpty else {
            return
        }

        if allPreviewItems.isEmpty || filteredPreviewItems.isEmpty {
            scheduleDeferredStartupWork(delayNanoseconds: allPreviewItems.isEmpty ? 0 : 32_000_000)
        }
    }

    private func scheduleDeferredStartupWork() {
        scheduleDeferredStartupWork(delayNanoseconds: 32_000_000)
    }

    private func scheduleDeferredStartupWork(delayNanoseconds: UInt64) {
        deferredStartupTask?.cancel()
        deferredStartupTask = Task { @MainActor in
            if delayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: 32_000_000)
                try? await Task.sleep(nanoseconds: delayNanoseconds)
            }
            guard !Task.isCancelled else {
                return
            }

            schedulePreviewItemsRebuild(from: store.items)
            refreshAccessibilityStateAfterFirstFrame()
            deferredStartupTask = nil
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
            .historyRailControlStyle()
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

    private var loadingContentState: some View {
        VStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)

            Text("正在加载历史")
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
              let selectedIndex = filteredItemIndex(for: currentSelectedID) else {
            self.selectedItemID = rememberedSelectionFallbackID() ?? filteredItems.first?.id
            if let selectedItemID {
                scrollToItemWhenRendered(selectedItemID, animated: true)
            }
            return
        }

        let nextID: HistoryPreviewItem.ID
        switch direction {
        case .left:
            guard selectedIndex > 0 else { return }
            nextID = filteredItems[selectedIndex - 1].id
        case .right:
            guard selectedIndex < filteredItems.count - 1 else { return }
            nextID = filteredItems[selectedIndex + 1].id
        default:
            return
        }

        selectedItemID = nextID
        keepKeyboardFocusedItemRendered(nextID)
        revealPartiallyVisibleCardIfNeeded(nextID, animated: false)
        if previewState.isVisible {
            previewCoordinator.markNeedsFollow(nextID)
            showPreview(nextID)
            Task { @MainActor in
                await Task.yield()
                followPreviewForCurrentScroll()
            }
        }
    }

    private func keepKeyboardFocusedItemRendered(_ id: ClipboardItem.ID) {
        pendingKeyboardFocusClearTask?.cancel()
        pendingKeyboardFocusItemID = id
        pendingKeyboardFocusClearTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled,
                  pendingKeyboardFocusItemID == id else {
                return
            }
            pendingKeyboardFocusItemID = nil
            pendingKeyboardFocusClearTask = nil
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
            ClipEaseSoundPlayer.shared.playCopyFeedback()
            showStatus(copyStatus(for: item))
        case .copiedFallbackText:
            store.markUsed(item.id)
            ClipEaseSoundPlayer.shared.playCopyFeedback()
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
            ClipEaseSoundPlayer.shared.playCopyFeedback()
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
        preparePastedItemFocus(item.id)
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
            pendingPastedItemFocusOnNextShow = nil
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
        guard case .copied = pasteExecutor.copyTextToPasteboard(markdown) else {
            showStatus("无法写入剪贴板")
            return
        }
        ClipEaseSoundPlayer.shared.playCopyFeedback()
        showStatus("已复制 Markdown 链接")
        closeAfterContextMenuCommand()
    }

    private func copyLinkURL(_ id: ClipboardItem.ID?) {
        guard let item = store.item(with: id),
              item.type == .link else {
            return
        }

        guard case .copied = pasteExecutor.copyTextToPasteboard(item.text) else {
            showStatus("无法写入剪贴板")
            return
        }
        ClipEaseSoundPlayer.shared.playCopyFeedback()
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

        guard case .copied = pasteExecutor.copyTextToPasteboard(item.text) else {
            showStatus("无法写入剪贴板")
            return
        }
        ClipEaseSoundPlayer.shared.playCopyFeedback()
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

        guard case .copied = pasteExecutor.copyTextToPasteboard(rgb) else {
            showStatus("无法写入剪贴板")
            return
        }
        ClipEaseSoundPlayer.shared.playCopyFeedback()
        showStatus("已复制 RGB")
        closeAfterContextMenuCommand()
    }

    private func pasteItem(_ id: ClipboardItem.ID?) {
        let startedAt = CFAbsoluteTimeGetCurrent()
        guard containsFilteredItem(id),
              let item = store.item(with: id) else {
            if isSearchVisible {
                showStatus("没有可粘贴的搜索结果")
            }
            return
        }

        accessibilityPermissionState.refresh()
        preparePastedItemFocus(item.id)
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
            pendingPastedItemFocusOnNextShow = nil
            showStatus(reason)
        }
        PerformanceDiagnosticsService.shared.record(
            "paste.item",
            category: "interaction",
            durationMS: (CFAbsoluteTimeGetCurrent() - startedAt) * 1_000,
            itemCount: filteredItems.count,
            metadata: ["itemType": "\(item.type)"]
        )
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

    private func preparePastedItemFocus(_ id: ClipboardItem.ID) {
        pendingPastedItemFocusOnNextShow = id
        selectedItemID = id
        persistSelectedItem()
        HistoryScrollCoordinator.shared.discardSavedOffset(for: HistoryGroupSelection.all.storageValue)
        HistoryScrollCoordinator.shared.discardSavedOffset(for: selectedGroup.storageValue)
    }

    private func scheduleProgrammaticJump(to id: ClipboardItem.ID) {
        preparePastedItemFocus(id)
        guard inputState.isWindowPresentedSnapshot else {
            clearPendingHistoryRailJumpState()
            return
        }

        resetFiltersForLatestItemFocus()
        scheduleLatestProgrammaticTransition(
            to: id,
            reason: .refreshed,
            resetToAll: true,
            animateWhenPresented: false
        )
    }

    private func clearPendingHistoryRailJumpState() {
        pendingLatestFocusItemID = nil
        pendingLatestFocusTimestamp = nil
        pendingLatestFocusReason = nil
        pendingLatestFocusLockID = nil
        pendingProgrammaticJumpItemID = nil
        pendingItemScrollID = nil
        pendingItemScrollRetryCount = 0
        pendingKeyboardFocusItemID = nil
        pendingKeyboardFocusClearTask?.cancel()
        pendingKeyboardFocusClearTask = nil
        latestFocusRetryTask?.cancel()
        latestFocusRetryTask = nil
        shouldResetHorizontalOffsetForPendingItemScroll = false
        shouldAnimatePendingItemScroll = false
        isPreparingPendingItemScrollMeasurement = false
        viewportStore.mode = .automatic
    }

    private func showPreview(_ id: ClipboardItem.ID?) {
        let startedAt = CFAbsoluteTimeGetCurrent()
        guard let item = store.item(with: id) else {
            return
        }

        guard let cardFrame = cardViewportFrame(for: item.id) else {
            previewCoordinator.markNeedsFollow(item.id)
            keepKeyboardFocusedItemRendered(item.id)
            scrollToItemWhenRendered(item.id, animated: false)
            followPreviewForCurrentScroll()
            return
        }

        onPreview(item, cardFrame)
        PerformanceDiagnosticsService.shared.record(
            "preview.show",
            category: "preview",
            durationMS: (CFAbsoluteTimeGetCurrent() - startedAt) * 1_000,
            itemCount: renderedItems.count,
            metadata: ["itemType": "\(item.type)"]
        )
    }

    private func followPreviewForCurrentScroll() {
        guard previewState.isVisible,
              let previewedID = previewState.itemID else {
            return
        }

        previewCoordinator.scheduleFollow(
            itemID: previewedID,
            isPreviewVisible: { previewState.isVisible },
            currentPreviewItemID: { previewState.itemID },
            frameForItem: { id in cardViewportFrame(for: id) },
            onMovePreview: { frame in
                onMovePreview(frame)
            }
        )
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
                _ = pasteExecutor.copyTextToPasteboard(updatedItem.text)
                ClipEaseSoundPlayer.shared.playCopyFeedback()
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
        guard !inputState.isAnyTextInputActiveSnapshot,
              canPerformDeleteCommand else {
            return
        }

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
        guard inputState.isWindowPresentedSnapshot || immediate else { return }
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
        let itemIDToPersist: ClipboardItem.ID?
        if let pendingPastedItemFocusOnNextShow,
           selectedItemID == nil || selectedItemID == pendingPastedItemFocusOnNextShow {
            itemIDToPersist = pendingPastedItemFocusOnNextShow
        } else {
            itemIDToPersist = selectedItemID
        }

        guard let itemIDToPersist else {
            rememberedSelectedItemID = ""
            UserDefaults.standard.set("", forKey: "history.lastSelectedItemID")
            return
        }

        rememberedSelectedItemID = itemIDToPersist.uuidString
        UserDefaults.standard.set(itemIDToPersist.uuidString, forKey: "history.lastSelectedItemID")
    }

    private func rememberedSelectedItemUUID() -> ClipboardItem.ID? {
        UUID(uuidString: rememberedSelectedItemID)
    }

    private func rememberedSelectionFallbackID() -> HistoryPreviewItem.ID? {
        guard let rememberedID = rememberedSelectedItemUUID(),
              containsFilteredItem(rememberedID) else {
            return nil
        }

        return rememberedID
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

    private func selectGroupForContextMenu(_ group: ClipboardGroup) {
        selectGroup(group.id)
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
        groupAppearanceCoordinator.beginEditing(group)
        inputState.setPresentedInputLayerActive(true)
    }

    private func beginEditSystemGroupAppearance(_ group: SystemHistoryGroup) {
        closeSearchForGroupNavigation()
        commitPendingRenameIfNeeded()
        closeGroupColorPanel()
        isGroupIconSearchFocused = false
        groupAppearanceCoordinator.beginEditingSystemGroup(
            group,
            colorHex: systemGroupColor(group).clipeaseHexString,
            iconName: systemGroupIconName(group)
        )
        inputState.setPresentedInputLayerActive(true)
    }

    private func systemGroupIconName(_ group: SystemHistoryGroup) -> String {
        switch group {
        case .pinned:
            pinnedGroupIconName
        }
    }

    private func closeGroupAppearancePopover() {
        groupAppearanceCoordinator.closeRegularPopover()
        isGroupIconSearchFocused = false
        closeGroupColorPanel()
        inputState.setTextInputFocused(false)
        inputState.setPresentedInputLayerActive(false)
    }

    private func closeSystemGroupAppearancePopover() {
        groupAppearanceCoordinator.closeSystemPopover()
        isGroupIconSearchFocused = false
        closeGroupColorPanel()
        inputState.setTextInputFocused(false)
        inputState.setPresentedInputLayerActive(false)
    }

    private func commitGroupAppearancePopover(_ group: ClipboardGroup) {
        store.updateGroupAppearance(
            group.id,
            colorHex: groupAppearanceCoordinator.colorHex,
            iconName: groupAppearanceCoordinator.iconName
        )
        closeGroupAppearancePopover()
    }

    private func commitSystemGroupAppearancePopover(_ group: SystemHistoryGroup) {
        updateSystemGroupAppearance(
            group,
            colorHex: groupAppearanceCoordinator.colorHex,
            iconName: groupAppearanceCoordinator.iconName
        )
        closeSystemGroupAppearancePopover()
    }

    private func handleGroupIconSearchEscape() {
        switch groupAppearanceCoordinator.handleIconSearchEscape() {
        case .clearedSearch, .none:
            return
        case .closedPopover:
            isGroupIconSearchFocused = false
            closeGroupColorPanel()
            inputState.setTextInputFocused(false)
            inputState.setPresentedInputLayerActive(false)
        }
    }

    private func closeGroupAppearanceLayer() {
        let hadRegularTarget = groupAppearanceCoordinator.regularGroupTarget != nil
        let hadSystemTarget = groupAppearanceCoordinator.systemGroupTarget != nil
        groupAppearanceCoordinator.closeLayer()
        if hadRegularTarget {
            closeGroupAppearancePopover()
        }

        if hadSystemTarget {
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

        guard case .copied = pasteExecutor.copyTextToPasteboard(item.sourceAppName) else {
            showStatus("无法写入剪贴板")
            return
        }
        showStatus("已复制来源名称")
        closeAfterContextMenuCommand()
    }

    private func copySourceBundleID(_ id: ClipboardItem.ID?) {
        guard let item = store.item(with: id),
              let bundleID = item.sourceBundleID else {
            showStatus("无来源 Bundle ID")
            return
        }

        guard case .copied = pasteExecutor.copyTextToPasteboard(bundleID) else {
            showStatus("无法写入剪贴板")
            return
        }
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

        guard case .copied = pasteExecutor.copyImageToPasteboard(
            image,
            skipText: item.preview.isEmpty ? imageURL.lastPathComponent : item.preview
        ) else {
            showStatus("无法写入图片到剪贴板")
            return
        }
        ClipEaseSoundPlayer.shared.playCopyFeedback()
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
        guard case .copied = pasteExecutor.copyTextToPasteboard(path) else {
            showStatus("无法写入剪贴板")
            return
        }
        ClipEaseSoundPlayer.shared.playCopyFeedback()
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
        guard case .copied = pasteExecutor.copyTextToPasteboard(pathsText) else {
            showStatus("无法写入剪贴板")
            return
        }
        ClipEaseSoundPlayer.shared.playCopyFeedback()
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

        guard case .copied = pasteExecutor.copyFileURLToPasteboard(firstURL) else {
            showStatus("无法写入文件引用到剪贴板")
            return
        }
        ClipEaseSoundPlayer.shared.playCopyFeedback()
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
        let startedAt = CFAbsoluteTimeGetCurrent()
        blurSearchFieldForCardInteraction()

        if previewState.isVisible {
            closePreview()
        }

        if selectedItemID != item.id {
            selectedItemID = item.id
        }

        if !revealPartiallyVisibleCardIfNeeded(item.id) {
            scrollToItemWhenRendered(item.id, animated: true)
        }
        PerformanceDiagnosticsService.shared.record(
            "card.click",
            category: "interaction",
            durationMS: (CFAbsoluteTimeGetCurrent() - startedAt) * 1_000,
            itemCount: renderedItems.count,
            metadata: ["itemType": "\(item.type)"]
        )
    }

    private func selectCardForContextMenu(_ item: HistoryPreviewItem) {
        let startedAt = CFAbsoluteTimeGetCurrent()
        blurSearchFieldForCardInteraction()

        if previewState.isVisible {
            closePreview()
        }

        if selectedItemID != item.id {
            selectedItemID = item.id
        }

        if !revealPartiallyVisibleCardIfNeeded(item.id) {
            scrollToItemWhenRendered(item.id, animated: true)
        }
        PerformanceDiagnosticsService.shared.record(
            "card.contextMenuSelect",
            category: "interaction",
            durationMS: (CFAbsoluteTimeGetCurrent() - startedAt) * 1_000,
            itemCount: renderedItems.count,
            metadata: ["itemType": "\(item.type)"]
        )
    }

    private func blurSearchFieldForCardInteraction() {
        guard isSearchFocused || inputState.isTextInputFocusedSnapshot else {
            return
        }

        isSearchFocused = false
        inputState.setTextInputFocused(false)
        hostWindow?.makeFirstResponder(nil)
    }

    @discardableResult
    private func revealPartiallyVisibleCardIfNeeded(_ id: ClipboardItem.ID) -> Bool {
        revealPartiallyVisibleCardIfNeeded(id, animated: true)
    }

    @discardableResult
    private func revealPartiallyVisibleCardIfNeeded(_ id: ClipboardItem.ID, animated: Bool) -> Bool {
        if let frame = cardDocumentFrame(for: id),
           isFrameFullyVisible(frame) {
            return true
        }

        guard let targetOffset = partialRevealTargetOffset(for: id) else {
            return false
        }

        HistoryScrollCoordinator.shared.scrollToOffset(targetOffset, animated: animated)
        return true
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
              containsFilteredItem(id) else {
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
        programmaticJumpTargetOffset(for: id)
    }

    private func programmaticJumpTargetOffset(for id: HistoryPreviewItem.ID) -> CGFloat? {
        guard let itemIndex = filteredItemIndex(for: id) else {
            return nil
        }

        let frame = cardDocumentFrame(for: id) ?? CGRect(
            x: horizontalContentPadding + CGFloat(itemIndex) * (historyCardWidth + horizontalCardSpacing),
            y: 0,
            width: historyCardWidth,
            height: 270
        )
        let preferredOffset = latestInsertedCardPreferredOffset(frame: frame)
        return targetScrollOffsetForFocusedFrame(
            id: id,
            frame: frame,
            visibleWidth: HistoryScrollCoordinator.shared.visibleDocumentRect?.width,
            preferredOffset: preferredOffset
        )
    }

    private func latestInsertedCardPreferredOffset(frame: CGRect) -> CGFloat {
        max(0, frame.minX - latestInsertedCardLeadingInset)
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
        guard let itemIndex = renderedItemIndex(for: id) else {
            return nil
        }

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
            return max(0, preferredOffset)
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

    private func cardDocumentX(for id: HistoryPreviewItem.ID) -> CGFloat {
        guard let itemIndex = renderedItemIndex(for: id) else {
            return horizontalContentPadding
        }

        return cardDocumentFrame(forRenderedIndex: itemIndex).minX
    }

    private func cardViewportFrame(for id: HistoryPreviewItem.ID) -> CGRect? {
        HistoryPreviewFramePolicy.viewportFrame(
            measuredFrame: cardViewportFrames[id],
            documentFrame: cardDocumentFrame(for: id),
            currentOffset: HistoryScrollCoordinator.shared.currentOffset,
            cardRailTopInWindow: cardRailTopInWindow,
            selectedCardTopContentInset: selectedCardTopContentInset
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
        filteredItemIndex(for: id)
    }

    private func cardDocumentFrame(forRenderedIndex itemIndex: Int) -> CGRect {
        RenderWindowCoordinator.documentFrame(
            itemIndex: itemIndex,
            horizontalPadding: horizontalContentPadding,
            itemStride: itemStride,
            cardWidth: historyCardWidth
        )
    }

    private func adjacentRenderedItemID(before id: HistoryPreviewItem.ID) -> HistoryPreviewItem.ID? {
        guard let index = filteredItemIndex(for: id),
              index > filteredItems.startIndex else {
            return nil
        }

        return filteredItems[index - 1].id
    }

    private func adjacentRenderedItemID(after id: HistoryPreviewItem.ID) -> HistoryPreviewItem.ID? {
        guard let index = filteredItemIndex(for: id) else {
            return nil
        }

        let nextIndex = index + 1
        guard nextIndex < filteredItems.endIndex else {
            return nil
        }

        return filteredItems[nextIndex].id
    }

    private func closePreview() {
        previewState.close()
        inputState.setPreviewActive(false)
        onClosePreview()
    }

    private func updateCardRailVisibleRect() {
        guard let visibleRect = HistoryScrollCoordinator.shared.visibleDocumentRect else {
            return
        }

        if viewportStore.updateVisibleRectIfNeeded(visibleRect, itemStride: itemStride) {
            requestNextHistoryPageIfNeeded()
        }
    }

    private func resetVisibleRailWindowForLatestFocus(_ id: HistoryPreviewItem.ID) {
        guard programmaticJumpTargetOffset(for: id) != nil else {
            return
        }

        let focusedIndex = filteredItemIndex(for: id) ?? 0
        viewportStore.resetForLatestFocus(
            offsetX: latestInsertedCardPreferredOffset(frame: CGRect(
                x: horizontalContentPadding + CGFloat(focusedIndex) * itemStride,
                y: 0,
                width: historyCardWidth,
                height: 270
            )),
            width: viewportStore.visibleRect.width,
            height: viewportStore.visibleRect.height
        )
    }

    private func retainedPreviewCacheIDs(for sourceItems: [ClipboardItem]) -> Set<ClipboardItem.ID> {
        var retainedIDs = Set<ClipboardItem.ID>()
        if let selectedItemID {
            retainedIDs.insert(selectedItemID)
        }
        if let previewedID = previewState.itemID {
            retainedIDs.insert(previewedID)
        }
        if let pendingLatestFocusItemID {
            retainedIDs.insert(pendingLatestFocusItemID)
        }
        if let pendingProgrammaticJumpItemID {
            retainedIDs.insert(pendingProgrammaticJumpItemID)
        }
        if let pendingItemScrollID {
            retainedIDs.insert(pendingItemScrollID)
        }

        let visibleRange = HistoryPreviewCacheRetentionPolicy.retainedWindow(
            itemCount: sourceItems.count,
            visibleRect: viewportStore.visibleRect,
            hasReliableVisibleRect: HistoryScrollCoordinator.shared.hasBoundScrollView,
            itemStride: itemStride,
            horizontalContentPadding: horizontalContentPadding,
            retainedItemCount: previewItemCacheRetainedItemCount,
            renderedItemLimit: historyRailRenderedItemLimit
        )

        if !visibleRange.isEmpty {
            for item in sourceItems[visibleRange] {
                retainedIDs.insert(item.id)
            }
        }

        if retainedIDs.count < previewItemCacheRetainedItemCount {
            for item in sourceItems.prefix(previewItemCacheRetainedItemCount) {
                retainedIDs.insert(item.id)
                if retainedIDs.count >= previewItemCacheRetainedItemCount {
                    break
                }
            }
        }

        return retainedIDs
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
            clearAndCloseSearch()
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
        searchHasHandedOffFocusToCard = false
        searchText = ""
        selectedSearchTokenKind = nil
        isSearchFocused = isSearchVisible
        inputState.setTextInputFocused(isSearchVisible)
        restoreSelectionAfterClearingSearch(preferredID: fallbackID)
    }

    private func clearSearchTextAndFilters() {
        let startedAt = CFAbsoluteTimeGetCurrent()
        pendingSearchTrigger = "search.clearButton"
        let fallbackID = selectedItemID
        searchHasHandedOffFocusToCard = false
        searchText = ""
        searchCriteria = HistorySearchCriteria()
        selectedSearchTokenKind = nil
        isSearchFocused = isSearchVisible
        inputState.setTextInputFocused(isSearchVisible)
        restoreSelectionAfterClearingSearch(preferredID: fallbackID)
        recordHistoryInteraction(
            "search.clearButton",
            startedAt: startedAt,
            metadata: ["wasActive": "\(isSearchActive)"]
        )
    }

    private func closeSearch() {
        applySearchFocusTransition(
            .searchClosed,
            hasSearchResult: filteredItems.first != nil,
            isSearchVisible: false
        )
        isSearchVisible = false
        inputState.setSearchVisible(false)
    }

    private func updateSearchFieldPresentation(isVisible: Bool) {
        searchVisibilityTask?.cancel()

        if isVisible {
            isSearchFieldLayoutVisible = true
            searchVisibilityTask = Task { @MainActor in
                await Task.yield()
                guard !Task.isCancelled, isSearchVisible else {
                    return
                }
                isSearchFieldVisualVisible = true
            }
        } else {
            isSearchFieldVisualVisible = false
            searchVisibilityTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 120_000_000)
                guard !Task.isCancelled, !isSearchVisible else {
                    return
                }
                isSearchFieldLayoutVisible = false
            }
        }
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
        let startedAt = CFAbsoluteTimeGetCurrent()
        pendingSearchTrigger = "search.toggleButton.open"
        selectedGroup = .all
        isSearchVisible = true
        inputState.setSearchVisible(true)
        recordHistoryInteraction(
            "search.toggleButton.open",
            startedAt: startedAt,
            metadata: [
                "itemCount": "\(items.count)",
                "filteredCount": "\(filteredItems.count)"
            ]
        )
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 20_000_000)
            focusSearchField()
        }
    }

    private func handleCommandFSearch() {
        pendingSearchTrigger = "search.commandF"
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
        let startedAt = CFAbsoluteTimeGetCurrent()
        let willOpen = !isSearchFilterPanelPresented
        pendingSearchTrigger = willOpen ? "filter.button.open" : "filter.button.close"
        isSearchFilterPanelPresented.toggle()
        if isSearchFilterPanelPresented {
            isSearchFocused = false
            inputState.setTextInputFocused(false)
        } else {
            focusSearchField()
        }
        recordHistoryInteraction(
            willOpen ? "filter.button.open" : "filter.button.close",
            startedAt: startedAt,
            metadata: [
                "hasFilters": "\(searchCriteria.hasActiveFilters)",
                "tokenCount": "\(searchTokens.count)",
                "itemCount": "\(items.count)",
                "filteredCount": "\(filteredItems.count)"
            ]
        )
    }

    private func recordHistoryInteraction(
        _ name: String,
        startedAt: CFAbsoluteTime,
        metadata: [String: String] = [:]
    ) {
        var nextMetadata = metadata
        nextMetadata["searchVisible"] = "\(isSearchVisible)"
        nextMetadata["filterPanelVisible"] = "\(isSearchFilterPanelPresented)"
        nextMetadata["hasFilters"] = "\(searchCriteria.hasActiveFilters)"
        nextMetadata["queryLength"] = "\(searchText.count)"
        PerformanceDiagnosticsService.shared.record(
            name,
            category: "interaction",
            durationMS: (CFAbsoluteTimeGetCurrent() - startedAt) * 1_000,
            itemCount: items.count,
            resultCount: filteredItems.count,
            metadata: nextMetadata
        )
    }

    private func sourceAppIconFileName(_ appName: String) -> String? {
        sourceAppIconFileNameByName[appName]
    }

    private func toggleSearchType(_ type: HistorySearchItemType) {
        let startedAt = CFAbsoluteTimeGetCurrent()
        pendingSearchTrigger = "filter.type.toggle"
        if searchCriteria.types.contains(type) {
            searchCriteria.types.remove(type)
            removeSearchTokenOrder(.type(type))
        } else {
            searchCriteria.types.insert(type)
            appendSearchTokenOrder(.type(type))
        }
        recordHistoryInteraction("filter.type.toggle", startedAt: startedAt, metadata: ["type": "\(type)"])
    }

    private func toggleSearchSourceApp(_ appName: String) {
        let startedAt = CFAbsoluteTimeGetCurrent()
        pendingSearchTrigger = "filter.sourceApp.toggle"
        if searchCriteria.sourceAppNames.contains(appName) {
            searchCriteria.sourceAppNames.remove(appName)
            removeSearchTokenOrder(.sourceApp(appName))
        } else {
            searchCriteria.sourceAppNames.insert(appName)
            appendSearchTokenOrder(.sourceApp(appName))
        }
        recordHistoryInteraction("filter.sourceApp.toggle", startedAt: startedAt, metadata: ["appName": appName])
    }

    private func toggleSearchDateRange(_ range: HistorySearchDateRange) {
        let startedAt = CFAbsoluteTimeGetCurrent()
        pendingSearchTrigger = "filter.date.toggle"
        if searchCriteria.dateRanges.contains(range) {
            searchCriteria.dateRanges.remove(range)
            removeSearchTokenOrder(.date(range))
        } else {
            searchCriteria.dateRanges.insert(range)
            appendSearchTokenOrder(.date(range))
        }
        recordHistoryInteraction("filter.date.toggle", startedAt: startedAt, metadata: ["range": "\(range)"])
    }

    private func toggleSearchGroup(_ group: HistorySearchGroup) {
        let startedAt = CFAbsoluteTimeGetCurrent()
        pendingSearchTrigger = "filter.group.toggle"
        if searchCriteria.groups.contains(group) {
            searchCriteria.groups.remove(group)
            removeSearchTokenOrder(.group(group))
        } else {
            searchCriteria.groups.insert(group)
            appendSearchTokenOrder(.group(group))
        }
        recordHistoryInteraction("filter.group.toggle", startedAt: startedAt, metadata: ["group": "\(group)"])
    }

    private func removeSearchToken(_ token: HistorySearchToken) {
        let startedAt = CFAbsoluteTimeGetCurrent()
        pendingSearchTrigger = "search.token.remove"
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
        removeSearchTokenOrder(token.kind)

        selectedSearchTokenKind = nil
        focusSearchField()
        recordHistoryInteraction("search.token.remove", startedAt: startedAt, metadata: ["token": token.title])
    }

    private func appendSearchTokenOrder(_ kind: HistorySearchTokenKind) {
        guard !searchCriteria.tokenOrder.contains(kind) else {
            return
        }

        searchCriteria.tokenOrder.append(kind)
    }

    private func removeSearchTokenOrder(_ kind: HistorySearchTokenKind) {
        searchCriteria.tokenOrder.removeAll { $0 == kind }
    }

    private func pruneSearchTokenOrder() {
        let activeKinds = Set(searchTokens.map(\.kind))
        searchCriteria.tokenOrder.removeAll { !activeKinds.contains($0) }
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
        let signatureStartedAt = CFAbsoluteTimeGetCurrent()
        let currentSourceSignature = previewItemsSourceSignature
        let sourceGeneration = store.itemsMutationGeneration
        if canSkipPreviewRebuild(
            sourceItems: sourceItems,
            sourceGeneration: sourceGeneration
        ) {
            PerformanceDiagnosticsService.shared.record(
                "preview.rebuild.skip",
                category: "history",
                durationMS: (CFAbsoluteTimeGetCurrent() - signatureStartedAt) * 1_000,
                itemCount: sourceItems.count,
                resultCount: allPreviewItems.count,
                metadata: [
                    "reason": "sourceGenerationUnchanged",
                    "cacheStored": "\(previewItemCache.count)"
                ]
            )
            scheduleSearchUpdate(sourceItems: allPreviewItems, immediate: true)
            convergeLatestClipboardFocusIfNeeded()
            return
        }

        let signatureUpdate = HistoryPreviewBuildCoordinator.previewSignatureUpdate(
            sourceItems: sourceItems,
            currentSourceSignature: currentSourceSignature
        )
        guard signatureUpdate.hasChanges else {
            PerformanceDiagnosticsService.shared.record(
                "preview.rebuild.skip",
                category: "history",
                durationMS: (CFAbsoluteTimeGetCurrent() - signatureStartedAt) * 1_000,
                itemCount: sourceItems.count,
                resultCount: allPreviewItems.count,
                metadata: [
                    "reason": "sourceSignatureUnchanged",
                    "cacheStored": "\(previewItemCache.count)"
                ]
            )
            scheduleSearchUpdate(sourceItems: allPreviewItems, immediate: true)
            convergeLatestClipboardFocusIfNeeded()
            return
        }

        let sourceSignature = signatureUpdate.sourceSignature
        previewBuildTask?.cancel()
        previewBuildGeneration &+= 1
        let generation = previewBuildGeneration
        let currentSelectedID = selectedItemID ?? rememberedSelectedItemUUID()
        let currentPreviewedItemID = previewState.itemID
        let currentLatestClipboardFocusGeneration = latestClipboardFocusGeneration
        let currentPreviewItemCache = previewItemCache
        let currentPreviewItems = allPreviewItems
        let retainedCacheIDs = retainedPreviewCacheIDs(for: sourceItems)

        previewBuildTask = Task {
            PerformanceDiagnosticsService.shared.recordResourceCheckpoint("preview.rebuild.start")
            let buildTask = Task.detached(priority: .userInitiated) {
                try HistoryPreviewBuildCoordinator.rebuild(
                    sourceItems: sourceItems,
                    sourceSignature: sourceSignature,
                    currentPreviewItems: currentPreviewItems,
                    currentSourceSignature: currentSourceSignature,
                    currentPreviewItemCache: currentPreviewItemCache,
                    retainedCacheIDs: retainedCacheIDs
                )
            }

            let rebuildResult: HistoryPreviewBuildCoordinator.RebuildResult
            do {
                rebuildResult = try await withTaskCancellationHandler {
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
                guard HistoryPreviewBuildCoordinator.shouldApplyResult(
                    isTaskCancelled: Task.isCancelled,
                    generation: generation,
                    currentGeneration: previewBuildGeneration
                ) else {
                    return
                }

                let applyStartedAt = CFAbsoluteTimeGetCurrent()
                let resultCount: Int
                let cacheMisses: Int
                let cacheHitCount: Int
                let cacheStored: Int
                let buildDurationMS: Double
                let rebuildMode: String
                switch rebuildResult {
                case .full(let previewItems, let nextCache, _, let hitCount, let durationMS):
                    resultCount = previewItems.count
                    cacheMisses = previewItems.count - hitCount
                    cacheHitCount = hitCount
                    cacheStored = nextCache.count
                    buildDurationMS = durationMS
                    rebuildMode = "full"
                case .prepend(let insertedItems, let nextCache, _, let hitCount, let durationMS):
                    resultCount = currentPreviewItems.count + insertedItems.count
                    cacheMisses = insertedItems.count
                    cacheHitCount = hitCount
                    cacheStored = nextCache.count
                    buildDurationMS = durationMS
                    rebuildMode = "incrementalPrepend"
                }
                PerformanceDiagnosticsService.shared.record(
                    "preview.rebuild.background",
                    category: "history",
                    durationMS: buildDurationMS,
                    itemCount: sourceItems.count,
                    resultCount: resultCount,
                    metadata: [
                        "cacheHits": "\(cacheHitCount)",
                        "cacheMisses": "\(cacheMisses)",
                        "cacheStored": "\(cacheStored)",
                        "mode": rebuildMode
                    ]
                )
                var transaction = Transaction()
                let shouldAnimateRebuild = inputState.isWindowPresentedSnapshot && shouldAnimateHistoryRailChange(
                    sourceItemCount: sourceItems.count,
                    renderedItemCount: resultCount
                )
                if shouldAnimateRebuild {
                    transaction.animation = .easeOut(duration: pendingLatestFocusItemID != nil ? 0.30 : 0.18)
                } else {
                    transaction.disablesAnimations = true
                }
                let previewItemsForSearch: [HistoryPreviewItem]
                let sourceAppSnapshot = rebuildResult.sourceAppSnapshot
                let insertedEntranceID: ClipboardItem.ID?
                switch rebuildResult {
                case .prepend(let insertedItems, _, _, _, _)
                    where inputState.isWindowPresentedSnapshot && shouldAnimateRebuild:
                    insertedEntranceID = insertedItems.first?.id
                default:
                    insertedEntranceID = nil
                }

                withTransaction(transaction) {
                    switch rebuildResult {
                    case .full(let previewItems, let nextCache, _, _, _):
                        previewItemCache = nextCache
                        allPreviewItems = previewItems
                    case .prepend(let insertedItems, let nextCache, _, _, _):
                        previewItemCache = nextCache
                        allPreviewItems.insert(contentsOf: insertedItems, at: 0)
                    }
                }
                if let insertedEntranceID {
                    playEntranceAnimation(for: insertedEntranceID)
                }
                previewItemsForSearch = allPreviewItems
                if sourceAppFilterOptions != sourceAppSnapshot.options {
                    sourceAppFilterOptions = sourceAppSnapshot.options
                }
                if sourceAppIconFileNameByName != sourceAppSnapshot.iconFileNameByName {
                    sourceAppIconFileNameByName = sourceAppSnapshot.iconFileNameByName
                }
                PerformanceDiagnosticsService.shared.record(
                    "preview.rebuild.apply",
                    category: "history",
                    durationMS: (CFAbsoluteTimeGetCurrent() - applyStartedAt) * 1_000,
                    itemCount: sourceItems.count,
                    resultCount: previewItemsForSearch.count,
                    metadata: [
                        "animated": "\(shouldAnimateRebuild)",
                        "cacheHits": "\(cacheHitCount)",
                        "cacheStored": "\(cacheStored)",
                        "mode": rebuildMode
                    ]
                )
                previewItemsSourceSignature = sourceSignature
                appliedPreviewItemsMutationGeneration = sourceGeneration
                renderState.mark("preview-items-ready count=\(previewItemsForSearch.count)")

                scheduleSearchUpdate(sourceItems: previewItemsForSearch, immediate: true)
                if pendingLatestFocusItemID == nil,
                   currentLatestClipboardFocusGeneration == latestClipboardFocusGeneration {
                    restoreSelectionAfterPreviewRebuild(
                        preferredID: currentSelectedID,
                        previewedID: currentPreviewedItemID,
                        sourceItems: sourceItems
                    )
                } else if let currentPreviewedItemID,
                          store.item(with: currentPreviewedItemID) == nil {
                    closePreview()
                }
            }
        }
    }

    private func canSkipPreviewRebuild(
        sourceItems: [ClipboardItem],
        sourceGeneration: UInt64
    ) -> Bool {
        guard appliedPreviewItemsMutationGeneration == sourceGeneration,
              allPreviewItems.count == sourceItems.count else {
            return false
        }

        if sourceItems.isEmpty {
            return allPreviewItems.isEmpty
        }

        return allPreviewItems.first?.id == sourceItems.first?.id &&
            allPreviewItems.last?.id == sourceItems.last?.id
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
        let scheduleStartedAt = CFAbsoluteTimeGetCurrent()
        let currentSearchTrigger = pendingSearchTrigger
        pendingSearchTrigger = "stateChange"
        guard let request = searchCoordinator.prepareSearch(
            sourceItems: sourceItems,
            selectedGroup: selectedGroup,
            isSearchVisible: isSearchVisible,
            searchText: searchText,
            criteria: searchCriteria,
            trigger: currentSearchTrigger,
            pageSize: searchResultPageSize
        ) else {
            return
        }

        let searchStore = store
        PerformanceDiagnosticsService.shared.record(
            "search.schedule",
            category: "search",
            durationMS: (CFAbsoluteTimeGetCurrent() - scheduleStartedAt) * 1_000,
            itemCount: sourceItems.count,
            metadata: [
                "immediate": "\(immediate)",
                "queryLength": "\(request.searchText.count)",
                "hasFilters": "\(request.criteria.hasActiveFilters)",
                "trigger": request.trigger
            ]
        )

        if request.usesUnfilteredSource {
            let applyStartedAt = CFAbsoluteTimeGetCurrent()
            searchCoordinator.markUnfilteredApplied()
            applyUnfilteredPreviewResult()
            if HistoryOrdinarySelectionRestorePolicy.canRestore(
                hasPendingLatestFocus: pendingLatestFocusItemID != nil,
                hasPendingDefaultFocus: pendingDefaultFocusOnShow,
                hasPendingPastedFocus: pendingPastedItemFocusOnNextShow != nil
            ) {
                applySearchSelectionAndViewport(isSearchActive: request.isSearchActive)
            }
            PerformanceDiagnosticsService.shared.record(
                "search.applyResults",
                category: "search",
                durationMS: (CFAbsoluteTimeGetCurrent() - applyStartedAt) * 1_000,
                itemCount: sourceItems.count,
                resultCount: allPreviewItems.count,
                metadata: [
                    "queryLength": "\(request.searchText.count)",
                    "hasFilters": "\(request.criteria.hasActiveFilters)",
                    "mode": "unfilteredSource",
                    "trigger": request.trigger
                ]
            )
            renderState.markAndFinish("filtered-items-ready count=\(allPreviewItems.count)")
            let followupStartedAt = CFAbsoluteTimeGetCurrent()
            restoreRememberedViewportIfNeeded()
            fulfillPendingLatestFocusIfPossible()
            convergeLatestClipboardFocusIfNeeded()
            applyPendingProgrammaticJumpIfPossible()
            applyPendingDefaultFocusOnShowIfNeeded()
            schedulePreheatVisibleAssets()
            PerformanceDiagnosticsService.shared.record(
                "search.postApply",
                category: "search",
                durationMS: (CFAbsoluteTimeGetCurrent() - followupStartedAt) * 1_000,
                itemCount: sourceItems.count,
                resultCount: allPreviewItems.count,
                metadata: [
                    "queryLength": "\(request.searchText.count)",
                    "hasFilters": "\(request.criteria.hasActiveFilters)",
                    "mode": "unfilteredSource",
                    "trigger": request.trigger
                ]
            )
            return
        }

        searchCoordinator.startSearch(
            request: request,
            immediate: immediate,
            debounceNanoseconds: debounceNanoseconds,
            repositorySearch: { query in
                searchStore.searchItems(query)
            },
            onResult: { coordinatorResult in
                let request = coordinatorResult.request
                let result = coordinatorResult.filterResult
                let applyStartedAt = CFAbsoluteTimeGetCurrent()
                var transaction = Transaction()
                let shouldAnimateResults = inputState.isWindowPresentedSnapshot && shouldAnimateHistoryRailChange(
                    sourceItemCount: request.sourceItems.count,
                    renderedItemCount: result.items.count
                )
                if shouldAnimateResults {
                    transaction.animation = .easeOut(duration: pendingLatestFocusItemID != nil ? 0.30 : 0.16)
                } else {
                    transaction.disablesAnimations = true
                }
                withTransaction(transaction) {
                    applyFilteredPreviewResult(result)
                    if HistoryOrdinarySelectionRestorePolicy.canRestore(
                        hasPendingLatestFocus: pendingLatestFocusItemID != nil,
                        hasPendingDefaultFocus: pendingDefaultFocusOnShow,
                        hasPendingPastedFocus: pendingPastedItemFocusOnNextShow != nil
                    ) {
                        applySearchSelectionAndViewport(isSearchActive: request.isSearchActive)
                    }
                }
                PerformanceDiagnosticsService.shared.record(
                    "search.filter",
                    category: "search",
                    durationMS: coordinatorResult.filterDurationMS,
                    itemCount: request.sourceItems.count,
                    resultCount: result.items.count,
                    metadata: [
                        "queryLength": "\(request.searchText.count)",
                        "hasFilters": "\(request.criteria.hasActiveFilters)",
                        "mode": "sqliteFTS",
                        "trigger": request.trigger
                    ]
                )
                PerformanceDiagnosticsService.shared.record(
                    "search.applyResults",
                    category: "search",
                    durationMS: (CFAbsoluteTimeGetCurrent() - applyStartedAt) * 1_000,
                    itemCount: request.sourceItems.count,
                    resultCount: result.items.count,
                    metadata: [
                        "queryLength": "\(request.searchText.count)",
                        "hasFilters": "\(request.criteria.hasActiveFilters)",
                        "mode": "sqliteFTS",
                        "animated": "\(shouldAnimateResults)",
                        "trigger": request.trigger
                    ]
                )
                renderState.markAndFinish("filtered-items-ready count=\(result.items.count)")
                let followupStartedAt = CFAbsoluteTimeGetCurrent()
                restoreRememberedViewportIfNeeded()
                fulfillPendingLatestFocusIfPossible()
                convergeLatestClipboardFocusIfNeeded()
                applyPendingProgrammaticJumpIfPossible()
                applyPendingDefaultFocusOnShowIfNeeded()
                schedulePreheatVisibleAssets()
                if HistorySearchPaginationPolicy.shouldLoadMore(
                    filteredCount: result.items.count,
                    targetCount: historyRailRenderedItemLimit,
                    repositoryResultCount: result.repositoryResultCount,
                    pageSize: searchResultPageSize,
                    canLoadMore: result.canLoadMore
                ) {
                    loadMoreSearchResultsIfNeeded(visibleUpperBound: result.items.count, preloadMargin: historyRailRenderedItemLimit)
                }
                PerformanceDiagnosticsService.shared.record(
                    "search.postApply",
                    category: "search",
                    durationMS: (CFAbsoluteTimeGetCurrent() - followupStartedAt) * 1_000,
                    itemCount: request.sourceItems.count,
                    resultCount: result.items.count,
                    metadata: [
                        "queryLength": "\(request.searchText.count)",
                        "hasFilters": "\(request.criteria.hasActiveFilters)",
                        "trigger": request.trigger
                    ]
                )
                PerformanceDiagnosticsService.shared.recordResourceCheckpoint("search.apply.complete")
            }
        )
    }

    private func loadMoreSearchResultsIfNeeded(visibleUpperBound: Int, preloadMargin: Int = 12) {
        let searchStore = store
        searchCoordinator.loadMoreIfNeeded(
            visibleUpperBound: visibleUpperBound,
            preloadMargin: preloadMargin,
            existingItems: filteredPreviewItems,
            selectedGroup: selectedGroup,
            isSearchVisible: isSearchVisible,
            searchText: searchText,
            criteria: searchCriteria,
            pageSize: searchResultPageSize,
            repositorySearch: { query in
                searchStore.searchItems(query)
            },
            onResult: { result in
                applyFilteredPreviewResult(result)
                schedulePreheatVisibleAssets()
            }
        )
    }

    private func ensureSelectionInFilteredItems() {
        applySearchSelectionAndViewport(isSearchActive: isSearchActive)
    }

    private func applySearchSelectionAndViewport(isSearchActive: Bool) {
        let nextSelectedID = HistorySearchResultSelectionPolicy.selectedID(
            currentSelectedID: selectedItemID,
            resultIDs: filteredItems.map(\.id),
            isSearchActive: isSearchActive
        )
        selectedItemID = nextSelectedID

        if isSearchActive {
            resetSearchResultsViewport()
        }

        guard let nextSelectedID else {
            closePreview()
            return
        }

        if previewState.isVisible,
           previewState.itemID != nextSelectedID {
            showPreview(nextSelectedID)
        }
    }

    private func resetSearchResultsViewport() {
        pendingKeyboardFocusClearTask?.cancel()
        pendingKeyboardFocusItemID = nil
        pendingProgrammaticJumpItemID = nil
        pendingItemScrollID = nil
        pendingItemScrollRetryCount = 0
        shouldResetHorizontalOffsetForPendingItemScroll = false
        shouldAnimatePendingItemScroll = false
        isPreparingPendingItemScrollMeasurement = false
        viewportStore.mode = .firstPage
        let measuredVisibleRect = HistoryScrollCoordinator.shared.visibleDocumentRect
        viewportStore.visibleRect = CGRect(
            x: 0,
            y: measuredVisibleRect?.minY ?? viewportStore.visibleRect.minY,
            width: measuredVisibleRect?.width ?? viewportStore.visibleRect.width,
            height: measuredVisibleRect?.height ?? viewportStore.visibleRect.height
        )
        HistoryScrollCoordinator.shared.scrollToOffset(0, animated: false)
        Task { @MainActor in
            await Task.yield()
            if viewportStore.mode == .firstPage {
                viewportStore.mode = .automatic
            }
        }
    }

    private func syncLatestItemFocusIfNeeded(sourceItems: [ClipboardItem]) {
        let newestTimestamp = sourceItems.first?.createdAt ?? .distantPast
        let previousObservation = latestObservation
        let currentObservation = latestItemObservation(sourceItems: sourceItems)
        let changedItem = LatestItemObservation.changedItem(
            previous: previousObservation,
            current: currentObservation,
            sourceItems: sourceItems
        )
        let focusCandidateID = changedItem?.id ?? pendingNewestItemIDForNextShow
        let focusCandidateTimestamp = changedItem?.createdAt ?? focusCandidateID.flatMap { id in
            sourceItems.first(where: { $0.id == id })?.createdAt
        }
        let focusReason = changedItem?.reason ?? .refreshed
        defer {
            latestPresentedItemTimestamp = newestTimestamp
            latestObservation = currentObservation
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
        pendingLatestFocusReason = focusReason
        pendingLatestFocusLockID = focusCandidateID
        shouldResetHorizontalOffsetForPendingItemScroll = true
        HistoryScrollCoordinator.shared.discardSavedOffset(for: HistoryGroupSelection.all.storageValue)
        resetVisibleRailWindowForLatestFocus(focusCandidateID)
        fulfillPendingLatestFocusIfPossible()
        if focusReason == .inserted {
            playEntranceAnimationSoon(for: focusCandidateID)
        }
    }

    private func focusRecentlyAddedItemOnShowIfNeeded(sourceItems: [ClipboardItem]) {
        guard inputState.isWindowPresentedSnapshot,
              pendingLatestFocusItemID == nil,
              let newestChangedItem = latestPresentationCandidate(from: sourceItems),
              newestChangedItem.createdAt > latestPresentedItemTimestamp.addingTimeInterval(0.001) else {
            return
        }

        resetFiltersForLatestItemFocus()
        latestClipboardFocusGeneration &+= 1
        selectedItemID = newestChangedItem.id
        pendingLatestFocusItemID = newestChangedItem.id
        pendingLatestFocusTimestamp = newestChangedItem.createdAt
        pendingLatestFocusReason = latestObservation?.id == newestChangedItem.id ? .refreshed : .inserted
        pendingLatestFocusLockID = newestChangedItem.id
        shouldResetHorizontalOffsetForPendingItemScroll = true
        HistoryScrollCoordinator.shared.discardSavedOffset(for: HistoryGroupSelection.all.storageValue)
        resetVisibleRailWindowForLatestFocus(newestChangedItem.id)
        fulfillPendingLatestFocusIfPossible()
        playEntranceAnimationSoon(for: newestChangedItem.id)
    }

    private func convergeLatestClipboardFocusIfNeeded() {
        guard pendingLatestFocusItemID != nil,
              let newestChangedItem = latestChangedFocusItemCandidate() else {
            return
        }

        if pendingLatestFocusItemID != newestChangedItem.id,
           containsFilteredItem(newestChangedItem.id) {
            pendingLatestFocusItemID = newestChangedItem.id
            pendingLatestFocusTimestamp = newestChangedItem.createdAt
            pendingLatestFocusReason = .refreshed
            pendingLatestFocusLockID = newestChangedItem.id
            shouldResetHorizontalOffsetForPendingItemScroll = true
            resetVisibleRailWindowForLatestFocus(newestChangedItem.id)
        }

        fulfillPendingLatestFocusIfPossible()
    }

    private func latestChangedFocusItemCandidate() -> ClipboardItem? {
        let newestByTimestamp = latestPresentationCandidate(from: store.items)

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
              containsFilteredItem(pendingLatestFocusItemID) else {
            return
        }

        selectedItemID = pendingLatestFocusItemID
        latestPresentedItemID = pendingLatestFocusItemID
        latestPresentedItemTimestamp = filteredItem(for: pendingLatestFocusItemID)?.createdAt ?? latestPresentedItemTimestamp

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
        resetVisibleRailWindowForLatestFocus(id)
        scrollToItemWhenRendered(id, animated: shouldAnimatePendingItemScroll)
        applyPendingProgrammaticJumpIfPossible()
        retryPendingLatestFocusJumpIfNeeded(id, remainingAttempts: 4)
    }

    private func retryPendingLatestFocusJumpIfNeeded(_ id: HistoryPreviewItem.ID, remainingAttempts: Int) {
        guard remainingAttempts > 0 else {
            return
        }

        latestFocusRetryTask?.cancel()
        latestFocusRetryTask = Task { @MainActor in
            var attemptsRemaining = remainingAttempts
            while attemptsRemaining > 0 {
                try? await Task.sleep(nanoseconds: 16_000_000)
                guard !Task.isCancelled,
                      pendingLatestFocusItemID == id,
                      selectedItemID == id,
                      containsFilteredItem(id) else {
                    return
                }

                HistoryScrollCoordinator.shared.forceLayout()
                pendingProgrammaticJumpItemID = id
                scrollToItemWhenRendered(id, animated: false)
                attemptsRemaining -= 1
            }

            latestFocusRetryTask = nil
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
        latestFocusRetryTask?.cancel()
        latestFocusRetryTask = nil
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
        let observation = latestItemObservation(sourceItems: sourceItems)
        latestObservation = observation
        latestPresentedItemID = observation?.id
        latestPresentedItemTimestamp = sourceItems.first?.createdAt ?? .distantPast
    }

    private func focusRequestedLatestItem(_ request: ClipboardItemFocusRequest) {
        prepareLatestItemFocus(
            itemID: request.itemID,
            timestamp: store.item(with: request.itemID)?.createdAt,
            reason: request.reason,
            resetToAll: true
        )
        fulfillPendingLatestFocusIfPossible()
        if request.reason == .inserted {
            playEntranceAnimationSoon(for: request.itemID)
        }
    }

    private func focusRequestedItem(_ request: HistoryItemFocusRequest) {
        prepareLatestItemFocus(
            itemID: request.itemID,
            timestamp: store.item(with: request.itemID)?.createdAt,
            reason: nil,
            resetToAll: request.resetToAll
        )
        fulfillPendingLatestFocusIfPossible()
        if request.reason == .inserted {
            playEntranceAnimationSoon(for: request.itemID)
        }
    }

    private func focusDefaultItemOnShow(_ request: HistoryDefaultFocusRequest) {
        guard pendingLatestFocusItemID == nil else {
            return
        }

        if isSearchFocused || inputState.isTextInputFocusedSnapshot {
            isSearchFocused = false
            inputState.setTextInputFocused(false)
        }
        searchHasHandedOffFocusToCard = false
        inputState.setSearchHasHandedOffFocusToCard(false)

        clearPendingHistoryRailJumpState()
        pendingDefaultFocusOnShow = true
        if request.resetToFirst {
            didRestoreRememberedViewport = true
            HistoryScrollCoordinator.shared.discardSavedOffset(for: selectedGroup.storageValue)
            HistoryScrollCoordinator.shared.scrollToOffset(0, animated: false)
            viewportStore.mode = .automatic
            viewportStore.visibleRect = CGRect(
                x: 0,
                y: viewportStore.visibleRect.minY,
                width: max(viewportStore.visibleRect.width, 1),
                height: viewportStore.visibleRect.height
            )
        }

        applyPendingDefaultFocusOnShowIfNeeded()
    }

    private func applyPendingDefaultFocusOnShowIfNeeded() {
        guard pendingDefaultFocusOnShow,
              pendingLatestFocusItemID == nil else {
            return
        }

        if let pastedID = pendingPastedItemFocusOnNextShow {
            guard containsFilteredItem(pastedID) else {
                return
            }

            selectedItemID = pastedID
            if filteredItems.first?.id == pastedID {
                pendingPastedItemFocusOnNextShow = nil
                pendingDefaultFocusOnShow = false
            }
            return
        }

        guard let targetID = filteredItems.first?.id else {
            selectedItemID = nil
            return
        }

        selectedItemID = targetID
        pendingDefaultFocusOnShow = false
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
        pendingNewestItemIDForNextShow = nil
        latestPresentedItemID = nil
        if resetToAll {
            HistoryScrollCoordinator.shared.discardSavedOffset(for: HistoryGroupSelection.all.storageValue)
        }
        resetVisibleRailWindowForLatestFocus(itemID)
    }

    private func latestItemObservation(sourceItems: [ClipboardItem]) -> LatestItemObservation? {
        LatestItemObservation(item: latestPresentationCandidate(from: sourceItems))
    }

    private func latestPresentationCandidate(from sourceItems: [ClipboardItem]) -> ClipboardItem? {
        if let requestedItem = store.latestItemFocusRequest.flatMap({ store.item(with: $0.itemID) }) {
            return requestedItem
        }

        return sourceItems.first { !$0.isPinned } ?? sourceItems.first
    }

    private func scrollToItemWhenRendered(_ id: HistoryPreviewItem.ID, animated: Bool = false) {
        pendingItemScrollID = id
        pendingItemScrollRetryCount = 0
        shouldAnimatePendingItemScroll = pendingProgrammaticJumpItemID == id ? animated : (animated || id == pendingLatestFocusItemID)

        Task { @MainActor in
            await Task.yield()
            guard pendingItemScrollID == id,
                  containsFilteredItem(id) else {
                return
            }

            if let targetOffset = programmaticJumpTargetOffset(for: id) {
                viewportStore.resetForLatestFocus(
                    offsetX: targetOffset,
                    width: viewportStore.visibleRect.width,
                    height: viewportStore.visibleRect.height
                )
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
                  containsFilteredItem(id),
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
           containsFilteredItem(preferredID) {
            selectedItemID = preferredID
        } else {
            selectedItemID = rememberedSelectionFallbackID() ?? filteredItems.first?.id
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

        selectedItemID = HistorySelectionRecoveryPolicy.selectedID(
            pendingPastedID: pendingPastedItemFocusOnNextShow,
            preferredID: preferredID,
            rememberedID: rememberedSelectedItemUUID(),
            firstID: firstItem.id,
            containsID: { id in store.item(with: id) != nil }
        )
        rememberSelectedItem()

        if let previewedID,
           store.item(with: previewedID) == nil {
            closePreview()
        }
    }

    private func restoreRememberedViewportIfNeeded() {
        guard let rememberedID = rememberedSelectedItemUUID(),
              HistoryRememberedViewportRestorePolicy.canRestore(
                didRestoreRememberedViewport: didRestoreRememberedViewport,
                hasPendingLatestFocus: pendingLatestFocusItemID != nil,
                hasPendingDefaultFocus: pendingDefaultFocusOnShow,
                hasPendingPastedFocus: pendingPastedItemFocusOnNextShow != nil,
                hasRememberedSelection: true
              ),
              containsFilteredItem(rememberedID) else {
            return
        }

        didRestoreRememberedViewport = true
        selectedItemID = rememberedID
        HistoryScrollCoordinator.shared.restoreSavedOffset()
    }

    private func schedulePreheatVisibleAssets() {
        PreviewAssetPreheater.schedule(
            existingTask: &preheatTask,
            items: filteredItems,
            visibleWindow: historyRailVisibleWindow
        )
    }

    private func nextSelectionID(afterDeleting id: ClipboardItem.ID?) -> ClipboardItem.ID? {
        guard let id,
              let index = filteredItemIndex(for: id) else {
            return filteredItems.first?.id
        }

        let remainingCount = filteredItems.count - 1
        guard remainingCount > 0 else {
            return nil
        }

        let nextIndex = min(index, remainingCount - 1)
        if nextIndex >= index {
            return filteredItems[nextIndex + 1].id
        }

        return filteredItems[nextIndex].id
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
        case .beginComposedSearchInput(let pendingEvent):
            beginComposedSearchInput(pendingEvent)
        case .enterFirstSearchResult:
            enterFirstSearchResultFromSearchField()
        case .focusFirstSearchResult:
            focusFirstSearchResultCard()
        }
    }

    private func handleGroupEditingKeyboardAction(_ action: HistoryKeyboardAction) -> Bool {
        if groupRenameTargetID != nil {
            switch HistoryGroupRenameActionPolicy.action(for: action) {
            case .submit:
                commitPendingRenameIfNeeded()
                return true
            case .cancel:
                handleRenameEscape()
                return true
            case .consume:
                return true
            }
        }

        guard groupAppearanceCoordinator.regularGroupTarget != nil || groupAppearanceCoordinator.systemGroupTarget != nil else {
            return false
        }

        switch action {
        case .close:
            handleGroupIconSearchEscape()
            return true
        case .delete:
            return isGroupIconSearchFocused
        case .appendSearchText, .beginComposedSearchInput, .copy, .copyPlainText, .paste, .pastePlainText, .togglePinned, .edit, .createText, .openSearch, .showSettings, .closeWindow, .toggleRecording:
            return true
        case .moveLeft, .moveRight, .togglePreview, .selectVisibleCard, .enterFirstSearchResult, .focusFirstSearchResult:
            return isGroupIconSearchFocused
        }
    }

    private func appendSearchText(_ text: String) {
        if previewState.isVisible {
            closePreview()
        }

        if !isSearchVisible {
            selectedGroup = .all
            isSearchVisible = true
            inputState.setSearchVisible(true)
        }

        searchText += text
        focusSearchField()
    }

    private func beginComposedSearchInput(_ pendingEvent: HistoryKeyboardPendingTextInputEvent) {
        if previewState.isVisible {
            closePreview()
        }

        if !isSearchVisible {
            selectedGroup = .all
            isSearchVisible = true
            inputState.setSearchVisible(true)
        }

        pendingComposedSearchInputEvent = pendingEvent
        focusSearchField()
    }

    private func handleSearchCancel() {
        switch HistorySearchCancelPolicy.action(hasSearchContent: hasSearchContent) {
        case .clearSearch:
            clearSearchTextAndFilters()
            focusSearchField()
        case .closeSearchAndFocusFirstResult:
            closeSearch()
            focusFirstSearchResultCard()
        }
    }

    private func enterFirstSearchResultFromSearchField() {
        focusFirstSearchResultCard()
    }

    private func synchronizeSearchTextFieldFocus(_ isFocused: Bool) {
        if isFocused {
            applySearchFocusTransition(
                .searchFieldFocused,
                hasSearchResult: filteredItems.first != nil,
                isSearchVisible: isSearchVisible
            )
        } else {
            isSearchFocused = false
            inputState.setTextInputFocused(false)
        }
    }

    private func focusFirstSearchResultCard() {
        guard let firstID = filteredItems.first?.id else {
            applySearchFocusTransition(
                .focusFirstResult,
                hasSearchResult: false,
                isSearchVisible: isSearchVisible
            )
            return
        }

        selectedItemID = firstID
        applySearchFocusTransition(
            .focusFirstResult,
            hasSearchResult: true,
            isSearchVisible: isSearchVisible
        )
        if previewState.isVisible {
            showPreview(firstID)
        }
    }

    private func focusSearchField() {
        searchHasHandedOffFocusToCard = false
        isSearchFocused = true
        searchFocusRequestID += 1
        inputState.setTextInputFocused(true)
    }

    private func applySearchFocusTransition(
        _ event: HistorySearchFocusTransitionEvent,
        hasSearchResult: Bool,
        isSearchVisible: Bool
    ) {
        let transition: HistorySearchFocusTransition
        switch event {
        case .searchFieldFocused:
            transition = inputFocusCoordinator.searchFieldFocused(
                hasSearchResult: hasSearchResult,
                isSearchVisible: isSearchVisible
            )
        case .focusFirstResult:
            transition = inputFocusCoordinator.focusFirstSearchResult(
                hasSearchResult: hasSearchResult,
                isSearchVisible: isSearchVisible
            )
        case .searchClosed:
            transition = inputFocusCoordinator.searchClosed(
                hasSearchResult: hasSearchResult,
                isSearchVisible: isSearchVisible
            )
        }
        searchHasHandedOffFocusToCard = transition.searchHasHandedOffFocusToCard
        inputState.setSearchHasHandedOffFocusToCard(transition.searchHasHandedOffFocusToCard)
        isSearchFocused = transition.isSearchFocused
        inputState.setTextInputFocused(transition.isTextInputFocused)
        if transition.shouldRefocusSearchField {
            searchFocusRequestID += 1
        }
    }

    private func closeWindowFromShortcut() {
        closePreview()
        cancelPendingGroupRename()
        onClose()
    }

    private func closeWindowForCardDrag() {
        closePreview()
        cancelPendingGroupRename()
        onClose()
    }

    private func handleEscapeClose() {
        if (groupAppearanceCoordinator.regularGroupTarget != nil || groupAppearanceCoordinator.systemGroupTarget != nil),
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

        if groupAppearanceCoordinator.regularGroupTarget != nil {
            closeGroupAppearancePopover()
            didClose = true
        }

        if groupAppearanceCoordinator.systemGroupTarget != nil {
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

private struct LatestItemObservation: Equatable {
    let id: ClipboardItem.ID
    let createdAt: Date

    init?(item: ClipboardItem?) {
        guard let item else {
            return nil
        }

        self.id = item.id
        self.createdAt = item.createdAt
    }

    static func changedItem(
        previous: LatestItemObservation?,
        current: LatestItemObservation?,
        sourceItems: [ClipboardItem]
    ) -> (id: ClipboardItem.ID, createdAt: Date, reason: ClipboardItemFocusRequest.Reason)? {
        guard let previous, let current else {
            return nil
        }

        if current.id != previous.id {
            return (current.id, current.createdAt, .inserted)
        }

        if current.createdAt > previous.createdAt.addingTimeInterval(0.001) {
            return (current.id, current.createdAt, .refreshed)
        }

        return sourceItems.first { item in
            item.createdAt > previous.createdAt.addingTimeInterval(0.001)
        }.map { item in
            (item.id, item.createdAt, .refreshed)
        }
    }
}

private struct SearchTextField: NSViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    @Binding var isComposing: Bool
    @Binding var pendingComposedInputEvent: HistoryKeyboardPendingTextInputEvent?
    let focusRequestID: Int
    let searchHasHandedOffFocusToCard: Bool
    let hasSearchResult: Bool
    let hasSearchTokens: Bool
    let onFocusChanged: (Bool) -> Void
    let onEnterFirstResult: () -> Void
    let onDeleteLastToken: () -> Void
    let onCancel: () -> Void

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

        if searchHasHandedOffFocusToCard {
            if nsView.window?.firstResponder === nsView.currentEditor() {
                nsView.window?.makeFirstResponder(nil)
            }
        } else if isFocused {
            if nsView.window?.firstResponder !== nsView.currentEditor() {
                nsView.window?.makeFirstResponder(nsView)
            }
            context.coordinator.configureEditor(in: nsView)
            if !hasMarkedText, context.coordinator.handledFocusRequestID != focusRequestID {
                context.coordinator.handledFocusRequestID = focusRequestID
                context.coordinator.moveInsertionPointToEndSoon(in: nsView)
            }
            context.coordinator.consumePendingComposedInputEventSoon(in: nsView)
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

        override func keyDown(with event: NSEvent) {
            guard HistoryInputFocusCoordinator().shouldRestoreSearchTextFieldFocus(
                searchHasHandedOffFocusToCard: coordinator?.parent.searchHasHandedOffFocusToCard ?? false
            ) else {
                if event.keyCode == KeyCode.space {
                    HistoryWindowInputState.currentForTextEditing?.dispatch(.togglePreview)
                    return
                }
                super.keyDown(with: event)
                return
            }

            coordinator?.parent.onFocusChanged(true)
            super.keyDown(with: event)
        }

        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            guard HistoryInputFocusCoordinator().shouldRestoreSearchTextFieldFocus(
                searchHasHandedOffFocusToCard: coordinator?.parent.searchHasHandedOffFocusToCard ?? false
            ) else {
                return super.performKeyEquivalent(with: event)
            }

            coordinator?.parent.onFocusChanged(true)

            guard event.modifierFlags.contains(.command),
                  let characters = event.charactersIgnoringModifiers?.lowercased(),
                  characters.count == 1,
                  let editor = currentEditor() as? NSTextView else {
                return super.performKeyEquivalent(with: event)
            }

            switch characters {
            case "a":
                editor.selectAll(nil)
                editor.setNeedsDisplay(editor.visibleRect)
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
                return true
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
            parent.onFocusChanged(true)
            if let textField = notification.object as? NSTextField {
                configureEditor(in: textField)
            }
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            parent.isComposing = false
            parent.onFocusChanged(false)
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.insertNewline(_:)):
                if parent.hasSearchResult {
                    parent.onEnterFirstResult()
                }
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                parent.onCancel()
                return true
            case #selector(NSResponder.insertTab(_:)):
                if parent.hasSearchResult {
                    parent.onEnterFirstResult()
                }
                return true
            case #selector(NSResponder.moveDown(_:)):
                if parent.hasSearchResult {
                    parent.onEnterFirstResult()
                }
                return true
            case #selector(NSResponder.moveRight(_:)):
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

        func moveInsertionPointToEnd(in textField: NSTextField) {
            guard let editor = textField.currentEditor() else {
                return
            }

            let endLocation = (textField.stringValue as NSString).length
            if editor.selectedRange.location != endLocation || editor.selectedRange.length != 0 {
                editor.selectedRange = NSRange(location: endLocation, length: 0)
            }
        }

        func configureEditor(in textField: NSTextField) {
            guard let editor = textField.currentEditor() as? NSTextView else {
                return
            }

            editor.insertionPointColor = .labelColor
            editor.selectedTextAttributes = [
                .backgroundColor: NSColor.selectedTextBackgroundColor,
                .foregroundColor: NSColor.selectedTextColor
            ]
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

        func consumePendingComposedInputEventSoon(in textField: SearchNSTextField) {
            guard parent.pendingComposedInputEvent != nil else {
                return
            }

            DispatchQueue.main.async { [weak self, weak textField] in
                guard let self,
                      let textField,
                      let event = self.parent.pendingComposedInputEvent else {
                    return
                }

                if textField.window?.firstResponder !== textField.currentEditor() {
                    textField.window?.makeFirstResponder(textField)
                }

                guard let editor = textField.currentEditor() as? NSTextView,
                      let nsEvent = NSEvent.keyEvent(
                        with: .keyDown,
                        location: .zero,
                        modifierFlags: NSEvent.ModifierFlags(rawValue: event.modifierFlags),
                        timestamp: ProcessInfo.processInfo.systemUptime,
                        windowNumber: textField.window?.windowNumber ?? 0,
                        context: nil,
                        characters: event.characters,
                        charactersIgnoringModifiers: event.characters,
                        isARepeat: false,
                        keyCode: event.keyCode
                      ) else {
                    return
                }

                self.parent.pendingComposedInputEvent = nil
                editor.keyDown(with: nsEvent)
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

private struct GroupAppearanceOutsideMouseDownObserver: NSViewRepresentable {
    let isEnabled: Bool
    let hostWindow: NSWindow?
    let popoverWindow: NSWindow?
    let onMouseDown: () -> Void

    func makeNSView(context: Context) -> ObservingView {
        let view = ObservingView()
        view.coordinator = context.coordinator
        context.coordinator.view = view
        context.coordinator.isEnabled = isEnabled
        context.coordinator.hostWindow = hostWindow
        context.coordinator.popoverWindow = popoverWindow
        context.coordinator.onMouseDown = onMouseDown
        context.coordinator.installMonitor()
        return view
    }

    func updateNSView(_ nsView: ObservingView, context: Context) {
        nsView.coordinator = context.coordinator
        context.coordinator.view = nsView
        context.coordinator.isEnabled = isEnabled
        context.coordinator.hostWindow = hostWindow
        context.coordinator.popoverWindow = popoverWindow
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
        weak var popoverWindow: NSWindow?
        var onMouseDown: (() -> Void)?
        private var localMonitor: Any?
        private var globalMonitor: Any?

        func installMonitor() {
            removeMonitor()
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                self?.handle(event)
                return event
            }
            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                Task { @MainActor in
                    self?.handle(event)
                }
            }
        }

        func installMonitorIfNeeded() {
            guard localMonitor == nil || globalMonitor == nil else {
                return
            }

            installMonitor()
        }

        func removeMonitor() {
            if let localMonitor {
                NSEvent.removeMonitor(localMonitor)
                self.localMonitor = nil
            }
            if let globalMonitor {
                NSEvent.removeMonitor(globalMonitor)
                self.globalMonitor = nil
            }
        }

        @MainActor
        private func handle(_ event: NSEvent) {
            let role = eventWindowRole(for: event)
            guard HistoryGroupAppearanceOutsideClickPolicy.shouldClose(
                isEnabled: isEnabled,
                eventWindowRole: role
            ) else {
                return
            }

            onMouseDown?()
        }

        private func eventWindowRole(for event: NSEvent) -> HistoryGroupAppearanceEventWindowRole {
            guard let eventWindow = event.window else {
                return .outsideApp
            }

            if let hostWindow = hostWindow ?? view?.window,
               eventWindow === hostWindow {
                return .hostWindow
            }

            if eventWindow === NSColorPanel.shared {
                return .colorPanel
            }

            if let popoverWindow,
               eventWindow === popoverWindow {
                return .popover
            }

            return .outsideApp
        }
    }

    final class ObservingView: NSView {
        weak var coordinator: Coordinator?

        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }
    }
}

private struct GroupAppearancePopoverWindowReader: NSViewRepresentable {
    @Binding var window: NSWindow?

    func makeNSView(context: Context) -> WindowReaderView {
        let view = WindowReaderView()
        view.onWindowChange = { newWindow in
            if window !== newWindow {
                window = newWindow
            }
        }
        return view
    }

    func updateNSView(_ nsView: WindowReaderView, context: Context) {
        nsView.onWindowChange = { newWindow in
            if window !== newWindow {
                window = newWindow
            }
        }
        nsView.reportWindowSoon()
    }

    static func dismantleNSView(_ nsView: WindowReaderView, coordinator: ()) {
        nsView.reportWindow(nil)
    }

    final class WindowReaderView: NSView {
        var onWindowChange: ((NSWindow?) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            reportWindowSoon()
        }

        func reportWindowSoon() {
            DispatchQueue.main.async { [weak self] in
                guard let self else {
                    return
                }

                self.reportWindow(self.window)
            }
        }

        func reportWindow(_ window: NSWindow?) {
            DispatchQueue.main.async { [weak self] in
                self?.onWindowChange?(window)
            }
        }

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
            switch HistoryGroupRenameKeyPolicy.action(for: event.keyCode) {
            case .submit:
                coordinator?.parent.onSubmit?()
                return
            case .cancel:
                coordinator?.parent.onEscape()
                return
            case nil:
                break
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

private struct HistoryRailControlButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HistoryRailControlButtonBody(configuration: configuration)
    }
}

private struct HistoryRailControlButtonBody: View {
    let configuration: HistoryRailControlButtonStyle.Configuration
    @State private var isHovered = false

    var body: some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : (isHovered ? 1.01 : 1))
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.14 : (isHovered ? 0.08 : 0)))
                    .allowsHitTesting(false)
            }
            .onHover { hovering in
                isHovered = hovering
            }
            .animation(.easeOut(duration: 0.10), value: isHovered)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

private extension View {
    func historyRailControlStyle() -> some View {
        buttonStyle(HistoryRailControlButtonStyle())
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
    let onBind: () -> Void

    func makeNSView(context: Context) -> BindingView {
        let view = BindingView()
        view.onBind = onBind
        DispatchQueue.main.async {
            view.bindScrollViewIfNeeded()
        }
        return view
    }

    func updateNSView(_ nsView: BindingView, context: Context) {
        nsView.onBind = onBind
        DispatchQueue.main.async {
            nsView.bindScrollViewIfNeeded()
        }
    }

    final class BindingView: NSView {
        var onBind: (() -> Void)?

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
            guard let scrollView = enclosingScrollView else {
                return
            }

            HistoryScrollCoordinator.shared.update(scrollView: scrollView)
            onBind?()
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

    var hasBoundScrollView: Bool {
        scrollView?.window != nil
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

private struct CardViewportFramePreferenceKey: PreferenceKey {
    static let defaultValue: [HistoryPreviewItem.ID: CGRect] = [:]

    static func reduce(value: inout [HistoryPreviewItem.ID: CGRect], nextValue: () -> [HistoryPreviewItem.ID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
