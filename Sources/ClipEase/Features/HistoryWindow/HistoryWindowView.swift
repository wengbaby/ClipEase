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
    @ObservedObject private var appearanceSettings = AppearanceSettings.shared
    @ObservedObject private var languageSettings = AppLanguageSettings.shared
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var searchCoordinator = HistorySearchCoordinator()
    @StateObject private var previewCoordinator = HistoryPreviewCoordinator()
    @StateObject private var viewportStore = HistoryViewportStore()
    @StateObject private var groupAppearanceCoordinator = GroupAppearanceCoordinator()
    @StateObject private var groupMouseMonitorRegistry = HistoryGroupMouseMonitorRegistry()
    @StateObject private var assetPreheater = PreviewAssetPreheater()
    private let inputFocusCoordinator = HistoryInputFocusCoordinator()
    let appMenuController: AppMenuController
    let pasteExecutor: PasteExecutor
    let onClose: () -> Void
    let onPreview: (ClipboardItem, CGRect) -> Void
    let onMovePreview: (CGRect) -> Void
    let onClosePreview: () -> Void
    let onCreateText: (ClipboardGroup.ID?) -> Void

    @State private var cardInteractionState = HistoryWindowCardInteractionState()
    @State private var statusState = HistoryWindowStatusState()
    @State private var hostWindow: NSWindow?
    @State private var searchUIState = HistoryWindowSearchUIState()
    @State private var groupUIState = HistoryWindowGroupUIState()
    @State private var isCommandKeyPressed = false
    @State private var isSearchFocused = false
    @State private var isSearchTextComposing = false
    @State private var searchLeadingContentWidth: CGFloat = 0
    @State private var searchTextInsertionIndex = Int.max
    @State private var searchFocusRequestID = 0
    @State private var pendingComposedSearchInputEvent: HistoryKeyboardPendingTextInputEvent?
    @State private var previewItemsState = HistoryWindowPreviewItemsState()
    @State private var previewBuildTask: Task<Void, Never>?
    @State private var previewBuildGeneration: UInt64 = 0
    @State private var deferredStartupTask: Task<Void, Never>?
    @State private var searchVisibilityTask: Task<Void, Never>?
    @State private var rememberSelectedItemTask: Task<Void, Never>?
    @State private var latestFocusRetryTask: Task<Void, Never>?
    @State private var hiddenResourceCheckpointTask: Task<Void, Never>?
    @State private var lastHiddenResourceCheckpointAt: CFAbsoluteTime = 0
    @State private var viewportState = HistoryWindowViewportState()
    @State private var focusState = HistoryWindowFocusState()
    @State private var pendingKeyboardFocusClearTask: Task<Void, Never>?
    @State private var glassEnvironmentRevision = 0
    @AppStorage("history.systemGroup.pinned.iconName") private var pinnedGroupIconName = "pin.fill"
    @AppStorage("history.systemGroup.pinned.colorHex") private var pinnedGroupColorHex = "#2E8CFF"
    @AppStorage("history.lastSelectedGroup") private var rememberedSelectedGroup = HistoryGroupSelection.all.storageValue
    @AppStorage("history.lastSelectedItemID") private var rememberedSelectedItemID = ""
    @AppStorage("history.savedScrollOffsetsByScope") private var rememberedScrollOffsetsByScopeData = "{}"
    @FocusState private var focusedRenameGroupID: ClipboardGroup.ID?

    private let allHistoryGroupColor = Color(red: 0.18, green: 0.55, blue: 1.0)
    private let groupAppearancePopoverWidth: CGFloat = 304
    private let groupAppearanceIconGridHeight: CGFloat = 178
    private let selectedCardTopContentInset: CGFloat = HistoryWindowPanelMetrics.selectedCardTopContentInset

    private var toolbarPrimaryForeground: Color {
        let opacity = 0.68 + glassEnvironment.toolbarTextContrast * 0.32
        return colorScheme == .dark ? .white.opacity(opacity) : .black.opacity(opacity)
    }

    private var toolbarSecondaryForeground: Color {
        let opacity = 0.42 + glassEnvironment.toolbarTextContrast * 0.48
        return colorScheme == .dark ? .white.opacity(opacity) : .black.opacity(opacity)
    }

    private var toolbarPrimaryNSColor: NSColor {
        let alpha = 0.68 + glassEnvironment.toolbarTextContrast * 0.32
        return (colorScheme == .dark ? NSColor.white : NSColor.black).withAlphaComponent(alpha)
    }

    private func selectedGroupFill(_ color: Color) -> Color {
        color.opacity(max(0.12, glassEnvironment.groupColorIntensity))
    }

    private var titleTypography: AppearanceTypography { appearanceSettings.typography(for: .windowTitle) }
    private var searchTypography: AppearanceTypography { appearanceSettings.typography(for: .search) }
    private var groupTypography: AppearanceTypography { appearanceSettings.typography(for: .group) }
    private var toolbarButtonTypography: AppearanceTypography { appearanceSettings.typography(for: .toolbarButton) }
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
    private let hiddenHistoryPanelHeight: CGFloat = HistoryWindowPanelMetrics.height
    private let latestInsertedCardLeadingInset: CGFloat = 28

    private var glassEnvironment: HistoryGlassEnvironment {
        _ = glassEnvironmentRevision
        return HistoryGlassEnvironment(
            supportsNativeGlass: HistoryGlassRuntime.supportsNativeGlass,
            reduceTransparency: NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency,
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
            increaseContrast: NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast,
            isDarkMode: colorScheme == .dark,
            isWindowActive: hostWindow?.isKeyWindow ?? true,
            prefersLiquidGlass: appearanceSettings.usesLiquidGlass,
            prefersGlassMotion: appearanceSettings.glassMotionEnabled,
            materialTheme: appearanceSettings.materialTheme,
            windowEffectOpacity: appearanceSettings.windowEffectOpacity,
            cardEffectOpacity: appearanceSettings.cardEffectOpacity,
            cardHeaderColorIntensity: appearanceSettings.cardHeaderColorIntensity,
            groupColorIntensity: appearanceSettings.groupColorIntensity,
            toolbarTextContrast: appearanceSettings.toolbarTextContrast,
            cardTypography: appearanceSettings.typography(for: .card)
        )
    }

    private var panelGlassPlan: HistoryGlassRenderPlan {
        HistoryGlassPolicy.resolve(role: .panel, environment: glassEnvironment)
    }

    private var controlsGlassPlan: HistoryGlassRenderPlan {
        HistoryGlassPolicy.resolve(role: .controls, environment: glassEnvironment)
    }

    private var searchGlassSurfaceStyle: HistoryGlassSearchSurfaceStyle {
        HistoryGlassSearchSurfacePolicy.resolve(
            plan: controlsGlassPlan,
            environment: glassEnvironment
        )
    }

    private var toolbarGlassLayout: HistoryGlassToolbarLayoutStyle {
        HistoryGlassToolbarLayoutPolicy.style
    }

    private var toolbarGlassControlStyle: HistoryGlassToolbarControlStyle {
        HistoryGlassToolbarControlPolicy.style
    }

    private var selectedItemID: HistoryPreviewItem.ID? {
        get { cardInteractionState.selectedItemID }
        nonmutating set { cardInteractionState.select(newValue) }
    }

    private var trackedCardGeometryIDs: Set<HistoryPreviewItem.ID> {
        HistoryCardGeometryCollectionPolicy.trackedIDs(
            previewedID: previewState.isVisible ? previewState.itemID : nil,
            selectedID: selectedItemID,
            pendingScrollID: viewportState.pendingItemScrollID,
            pendingProgrammaticJumpID: focusState.pendingProgrammaticJumpItemID
        )
    }

    private var enteringItemIDs: Set<ClipboardItem.ID> {
        get { cardInteractionState.enteringItemIDs }
        nonmutating set { cardInteractionState.enteringItemIDs = newValue }
    }

    private var enteringItemClearTask: Task<Void, Never>? {
        get { cardInteractionState.enteringItemClearTask }
        nonmutating set { cardInteractionState.enteringItemClearTask = newValue }
    }

    private var entranceSheenItemIDs: Set<ClipboardItem.ID> {
        get { cardInteractionState.entranceSheenItemIDs }
        nonmutating set { cardInteractionState.entranceSheenItemIDs = newValue }
    }

    private var entranceSheenStartTime: CFTimeInterval? {
        get { cardInteractionState.entranceSheenStartTime }
        nonmutating set { cardInteractionState.entranceSheenStartTime = newValue }
    }

    private var entranceSheenClearTask: Task<Void, Never>? {
        get { cardInteractionState.entranceSheenClearTask }
        nonmutating set { cardInteractionState.entranceSheenClearTask = newValue }
    }

    private var hoveredCardID: HistoryPreviewItem.ID? {
        get { cardInteractionState.hoveredCardID }
        nonmutating set { cardInteractionState.hoveredCardID = newValue }
    }

    private var pressedCardID: HistoryPreviewItem.ID? {
        get { cardInteractionState.pressedCardID }
        nonmutating set { cardInteractionState.pressedCardID = newValue }
    }

    private var items: [HistoryPreviewItem] {
        previewItemsState.allItems
    }

    private var filteredItems: [HistoryPreviewItem] {
        previewItemsState.visibleItems
    }

    private var renderedItems: [HistoryPreviewItem] {
        filteredItems
    }

    private func applyFilteredPreviewResult(_ result: HistorySearchFilterResult) {
        previewItemsState.applyFilteredResult(result)
    }

    private func applyUnfilteredPreviewResult() {
        previewItemsState.applyUnfilteredResult()
    }

    private func containsFilteredItem(_ id: HistoryPreviewItem.ID?) -> Bool {
        previewItemsState.containsFilteredItem(id) { store.cachedItemIndex(with: $0) != nil }
    }

    private func filteredItemIndex(for id: HistoryPreviewItem.ID?) -> Int? {
        previewItemsState.filteredItemIndex(for: id) { store.cachedItemIndex(with: $0) }
    }

    private func filteredItem(for id: HistoryPreviewItem.ID?) -> HistoryPreviewItem? {
        previewItemsState.filteredItem(for: id) { store.cachedItemIndex(with: $0) }
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
            pendingLatestFocusItemID: focusState.pendingLatestFocusItemID ?? focusState.pendingKeyboardFocusItemID,
            pendingProgrammaticJumpItemID: focusState.pendingProgrammaticJumpItemID,
            pendingItemScrollID: viewportState.pendingItemScrollID,
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
        if previewItemsState.isUsingUnfilteredResult {
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
        groupUIState.selectedGroupID
    }

    private var searchTokens: [HistorySearchToken] {
        HistorySearchToken.tokens(
            criteria: searchUIState.criteria,
            groups: store.groups
        )
    }

    private var isSearchActive: Bool {
        searchUIState.isActive
    }

    private var isSearchControlExpanded: Bool {
        searchUIState.shouldShowField
    }

    private var hasSearchContent: Bool {
        searchUIState.hasContent || !searchTokens.isEmpty
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

    private var isShortcutOverlayVisible: Bool {
        HistoryShortcutOverlayPolicy.isVisible(
            isCommandKeyPressed: isCommandKeyPressed,
            isInputCommandKeyPressed: inputState.isCommandKeyPressed,
            isTextInputActive: isTextInputActiveForEditShortcut || inputState.isHistoryTextInputActiveSnapshot,
            isPreviewContentActive: inputState.isPreviewContentActive
        )
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
            groupUIState.isIconSearchFocused ||
            searchUIState.isFilterPanelPresented ||
            groupUIState.renameTargetID != nil ||
            groupAppearanceCoordinator.regularGroupTarget != nil ||
            groupAppearanceCoordinator.systemGroupTarget != nil ||
            groupUIState.moveToGroupPickerTarget != nil ||
            NSApp.keyWindow?.firstResponder is NSTextView
    }

    private func scheduleCardRailTopUpdate(_ top: CGFloat) {
        DispatchQueue.main.async { [self] in
            guard viewportState.cardRailTopInWindow != top else {
                return
            }
            viewportState.cardRailTopInWindow = top
        }
    }

    private func scheduleWindowWidthUpdate(_ width: CGFloat) {
        DispatchQueue.main.async { [self] in
            guard viewportState.windowWidth != width else {
                return
            }
            viewportState.windowWidth = width
        }
    }

    private func scheduleSearchInteractionFramesUpdate(_ frames: [CGRect]) {
        DispatchQueue.main.async { [self] in
            guard viewportState.searchInteractionFrames != frames else {
                return
            }
            viewportState.searchInteractionFrames = frames
        }
    }

    private func scheduleCardViewportFramesUpdate(_ frames: [HistoryPreviewItem.ID: CGRect]) {
        let backingScaleFactor = hostWindow?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1
        DispatchQueue.main.async { [self] in
            guard HistoryCardGeometryCollectionPolicy.shouldPublish(
                current: viewportState.cardViewportFrames,
                incoming: frames,
                backingScaleFactor: backingScaleFactor
            ) else {
                return
            }
            viewportState.cardViewportFrames = frames
            followPreviewForCurrentScroll()
        }
    }

    var body: some View {
        ZStack {
            AdaptiveGlassPanelBackground(plan: panelGlassPlan)

            if !inputState.isPreviewContentActive {
                shortcutButtons
            }

            NumberShortcutHandler(
                inputState: inputState,
                isEnabled: inputState.isWindowVisible
            ) { isPressed in
                isCommandKeyPressed = isPressed
            } onNumber: { number in
                selectVisibleCard(number: number)
            }
            .frame(width: 0, height: 0)

            VStack(alignment: .leading, spacing: HistoryWindowPanelMetrics.toolbarRailSpacing) {
                toolbar

                if items.isEmpty && store.items.isEmpty {
                    HistoryAllEmptyStateView()
                } else if items.isEmpty {
                    HistoryLoadingContentStateView()
                } else if filteredItems.isEmpty {
                    HistoryEmptyContentStateView(
                        isSearchActive: isSearchActive,
                        isSelectedGroupPinned: groupUIState.selectedGroup == .pinned,
                        selectedGroupIDIsNotNil: selectedGroupID != nil,
                        pinnedSystemGroupColor: systemGroupColor(.pinned)
                    )
                } else {
                    ScrollViewReader { proxy in
                        historyRail
                        .background(
                            GeometryReader { proxy in
                                Color.clear
                                    .onAppear {
                                        scheduleCardRailTopUpdate(
                                            proxy.frame(in: .named("historyWindow")).minY
                                        )
                                    }
                                    .onChange(of: proxy.frame(in: .named("historyWindow")).minY) { minY in
                                        scheduleCardRailTopUpdate(minY)
                                    }
                            }
                        )
                        .onChange(of: viewportState.itemScrollRequestID) { _ in
                            guard let pendingItemScrollID = viewportState.pendingItemScrollID else {
                                return
                            }

                            if applyPendingItemScrollIfMeasured(pendingItemScrollID) {
                                viewportState.clearPendingItemScroll(resetHorizontalOffset: true)
                                return
                            }

                            guard !viewportState.isPreparingPendingItemScrollMeasurement,
                                  viewportState.pendingItemScrollRetryCount < pendingItemScrollMaxRetryCount else {
                                return
                            }

                            if let targetOffset = programmaticJumpTargetOffset(for: pendingItemScrollID) {
                                _ = viewportState.beginPendingItemScrollMeasurement(maxRetryCount: pendingItemScrollMaxRetryCount)
                                viewportStore.resetForLatestFocus(
                                    offsetX: targetOffset,
                                    width: viewportStore.visibleRect.width,
                                    height: viewportStore.visibleRect.height
                                )

                                Task { @MainActor in
                                    await Task.yield()
                                    guard self.viewportState.pendingItemScrollID == pendingItemScrollID else {
                                        return
                                    }
                                    self.viewportState.finishPendingItemScrollMeasurement()
                                    self.viewportState.itemScrollRequestID = UUID()
                                }
                            }
                        }
                        .background(HorizontalScrollWheelRedirector(
                            scope: .cardRail,
                            isEnabled: inputState.isWindowVisible
                        ))
                    }
                }
            }
            .padding(.top, HistoryWindowPanelMetrics.topPadding)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            SearchOutsideWindowMouseDownObserver(
                isEnabled: HistoryWindowMonitorVisibilityPolicy.isEnabled(
                    isWindowVisible: inputState.isWindowVisible,
                    isFeatureActive: searchUIState.isVisible
                ),
                hostWindow: hostWindow,
                excludedFrames: viewportState.searchInteractionScreenFrames,
                onMouseDown: closeSearchFromOutsideClick
            )
        )
        .background(
            GroupRenameOutsideMouseDownObserver(
                isEnabled: HistoryWindowMonitorVisibilityPolicy.isEnabled(
                    isWindowVisible: inputState.isWindowVisible,
                    isFeatureActive: groupUIState.renameTargetID != nil
                ),
                hostWindow: hostWindow,
                excludedScreenFrame: groupUIState.renameInputScreenFrame,
                onMouseDown: commitPendingRenameIfNeeded
            )
        )
        .background(
            GroupAppearanceOutsideMouseDownObserver(
                isEnabled: HistoryWindowMonitorVisibilityPolicy.isEnabled(
                    isWindowVisible: inputState.isWindowVisible,
                    isFeatureActive: groupAppearanceCoordinator.regularGroupTarget != nil ||
                        groupAppearanceCoordinator.systemGroupTarget != nil
                ),
                hostWindow: hostWindow,
                popoverWindow: groupAppearanceCoordinator.popoverWindow,
                onMouseDown: closeGroupAppearanceLayer
            )
        )
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear {
                        scheduleWindowWidthUpdate(proxy.size.width)
                    }
                    .onChange(of: proxy.size.width) { width in
                        scheduleWindowWidthUpdate(width)
                    }
            }
        )
        .background(HistoryWindowHostWindowReader(window: $hostWindow))
        .preferredColorScheme(appearanceSettings.preferredColorScheme)
        .onReceive(
            NSWorkspace.shared.notificationCenter.publisher(
                for: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification
            )
        ) { _ in
            glassEnvironmentRevision &+= 1
        }
        .coordinateSpace(name: "historyWindow")
        .onPreferenceChange(SearchInteractionFramePreferenceKey.self) { frames in
            scheduleSearchInteractionFramesUpdate(frames)
        }
        .onPreferenceChange(CardViewportFramePreferenceKey.self) { frames in
            scheduleCardViewportFramesUpdate(frames)
        }
        .onChange(of: viewportState.searchInteractionFrames) { _ in
            refreshSearchInteractionScreenFrames()
        }
        .onChange(of: viewportState.searchControlScreenFrame) { _ in
            refreshSearchInteractionScreenFrames()
        }
        .onChange(of: searchUIState.isFilterPanelPresented) { _ in
            refreshSearchInteractionScreenFrames()
        }
        .onChange(of: hostWindow) { _ in
            refreshSearchInteractionScreenFrames()
        }
        .transaction { transaction in
            transaction.animation = nil
        }
        .onAppear {
            scheduleInitialAppearanceWork()
        }
        .onDisappear {
            cancelPendingGroupRename()
            closeInactiveSearchBeforeHiding()
            cancelPresentationWorkForHide()
            searchCoordinator.cancelAll()
            searchVisibilityTask?.cancel()
            assetPreheater.setEnabled(false)
            previewCoordinator.cancelFollow()
            rememberSelectedItemTask?.cancel()
            latestFocusRetryTask?.cancel()
            pendingKeyboardFocusClearTask?.cancel()
            hiddenResourceCheckpointTask?.cancel()
            cardInteractionState.clearTransientState()
            focusState.pendingDefaultFocusOnShow = false
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
            assetPreheater.setEnabled(isVisible)
            if isVisible {
                viewportState.didRestoreRememberedViewport = false
                focusRecentlyAddedItemOnShowIfNeeded(sourceItems: store.items)
                syncLatestItemFocusIfNeeded(sourceItems: store.items)
                restoreRememberedViewportIfNeeded()
                rebuildPreviewItemsIfNeededForVisibleWindow()
                warmPreviewItemsForPreloadedHiddenWindowIfNeeded()
                schedulePreheatVisibleAssets()
            } else {
                noteHistoryWindowHidden()
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: HistoryWindowInputState.windowPresentedDidChangeNotification,
                object: inputState
            )
        ) { _ in
            guard inputState.isWindowPresentedSnapshot else {
                return
            }

            scheduleDeferredStartupWork(
                delayNanoseconds: HistoryWindowLifecycleScheduler.presentedStartupDelayNanoseconds
            )
        }
        .onChange(of: store.groups) { _ in
            refreshMoveToGroupMenuSnapshot()
            groupUIState.repairSelectedGroupIfNeeded(groups: store.groups)
            searchUIState.criteria.groups = searchUIState.criteria.groups.filter { group in
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
        .onChange(of: searchUIState.text) { _ in
            searchUIState.selectedTokenKind = nil
            scheduleSearchUpdate(debounceNanoseconds: isSearchTextComposing ? 300_000_000 : 160_000_000)
        }
        .onChange(of: isSearchTextComposing) { isComposing in
            if !isComposing {
                scheduleSearchUpdate(debounceNanoseconds: 60_000_000)
            }
        }
        .onChange(of: searchUIState.criteria) { _ in
            if !searchTokens.contains(where: { $0.kind == searchUIState.selectedTokenKind }) {
                searchUIState.selectedTokenKind = nil
            }
            scheduleSearchUpdate(immediate: true)
        }
        .onChange(of: groupUIState.selectedGroup) { _ in
            rememberSelectedGroup()
            HistoryScrollCoordinator.shared.setScope(groupUIState.selectedGroup.storageValue)
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
            cancelPresentationWorkForHide()
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
            viewportState.cardViewportFrames = viewportState.cardViewportFrames.filter { visibleIDs.contains($0.key) }
            schedulePreheatVisibleAssets()
        }
        .onChange(of: isSearchFocused) { isFocused in
            inputState.setTextInputFocused(isFocused)
        }
        .onChange(of: searchUIState.hasHandedOffFocusToCard) { hasHandedOff in
            inputState.setSearchHasHandedOffFocusToCard(hasHandedOff)
        }
        .onChange(of: groupUIState.isIconSearchFocused) { isFocused in
            inputState.setTextInputFocused(isFocused || groupUIState.renameTargetID != nil)
        }
        .onChange(of: groupUIState.renameTargetID) { targetID in
            inputState.setTextInputFocused(targetID != nil || groupUIState.isIconSearchFocused)
        }
        .onChange(of: searchUIState.isVisible) { isVisible in
            if !isVisible {
                searchUIState.isFilterPanelPresented = false
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
        .sheet(item: $groupUIState.moveToGroupPickerTarget) { target in
            moveToGroupPicker(for: target)
        }
    }

    private func scheduleInitialAppearanceWork() {
        DispatchQueue.main.async { [self] in
            assetPreheater.setEnabled(inputState.isWindowVisibleSnapshot)
            renderState.mark("swiftui-appear")
            HistoryWindowLifecycleDiagnostics.record(
                .openFirstFrame,
                itemCount: store.items.count,
                wasVisible: inputState.isWindowVisibleSnapshot,
                shouldAnimate: false,
                hasPendingFocus: focusState.pendingLatestFocusItemID != nil || focusState.pendingDefaultFocusOnShow,
                visibleItemCount: renderedWindowItems.count,
                previewItemCount: previewItemsState.allItems.count
            )
            HistoryWindowInputState.currentForTextEditing = inputState
            restoreRememberedGroupSelection()
            HistoryScrollCoordinator.shared.loadSavedOffsets(from: rememberedScrollOffsetsByScopeData)
            HistoryScrollCoordinator.shared.setScope(groupUIState.selectedGroup.storageValue)
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
            warmPreviewItemsForPreloadedHiddenWindowIfNeeded()
            scheduleDeferredStartupWork()
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
            .frame(width: historyRailContentWidth, height: HistoryWindowPanelMetrics.railFrameHeight, alignment: .topLeading)
            .padding(.top, selectedCardTopContentInset)
            .padding(.bottom, 8)
            .padding(.bottom, HistoryWindowPanelMetrics.railBottomPadding - 8)
        }
    }

    @ViewBuilder
    private func historyCard(_ item: HistoryPreviewItem) -> some View {
        let isSelected = selectedItemID == item.id
        let isCardFocused = isSelected && HistoryCardFocusPolicy.isCardFocusActive(
            selectedItemID: selectedItemID,
            isSearchFieldFocused: isSearchFocused || inputState.isTextInputFocusedSnapshot,
            searchHasHandedOffFocusToCard: searchUIState.hasHandedOffFocusToCard
        )
        let isHovered = hoveredCardID == item.id
        let isPressed = pressedCardID == item.id
        let isEnteringLatestItem = enteringItemIDs.contains(item.id)
        let visualState = HistoryCardVisualState(
            isSelected: isSelected,
            isKeyboardFocused: isCardFocused,
            isHovered: isHovered,
            isPressed: isPressed,
            isEnteringLatestItem: isEnteringLatestItem,
            isShortcutOverlayVisible: isShortcutOverlayVisible,
            environment: glassEnvironment,
            renderPlan: HistoryGlassPolicy.resolve(
                role: isSelected ? .selectedCard : .card,
                environment: glassEnvironment
            ),
            cardStyle: appearanceSettings.cardStyle
        )
        let presentation = HistoryCardPresentationPolicy.resolve(visualState)
        let isShowingEntranceSheen = entranceSheenItemIDs.contains(item.id) && presentation.showsEntranceSheen
        let cardScale = CGFloat(presentation.scale)

        HistoryCardView(
            item: item,
            searchQuery: searchUIState.text,
            shortcutNumber: shortcutNumber(for: item.id),
            isShortcutOverlayVisible: isShortcutOverlayVisible,
            isHovered: isHovered,
            isPressed: isPressed,
            isEnteringLatestItem: isEnteringLatestItem,
            isSelected: isSelected,
            visualState: visualState,
            onClick: {
                selectCardForPrimaryClick(item)
            },
            onDoubleClick: {
                blurSearchFieldForCardInteraction()
                pasteItem(item.id)
            },
            onPreview: {
                showPreview(item.id)
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
        .background {
            if trackedCardGeometryIDs.contains(item.id) {
                CardViewportFrameReader(itemID: item.id)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(
                    visualState.isKeyboardFocused ? Color(red: 0.08, green: 0.38, blue: 0.90) : (isSelected ? Color(red: 0.18, green: 0.55, blue: 1.0).opacity(0.92) : Color.black.opacity(0.08)),
                    lineWidth: presentation.borderWidth
                )
                .allowsHitTesting(false)
        }
        .overlay {
            if presentation.focusRingWidth > 0 {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color(red: 0.08, green: 0.38, blue: 0.90), lineWidth: presentation.focusRingWidth)
                    .padding(-4)
                    .overlay {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(Color.white.opacity(0.92), lineWidth: 1)
                            .padding(2)
                    }
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
        .animation(.easeOut(duration: visualState.environment.reduceMotion ? 0.12 : 0.18), value: isCardFocused)
        .animation(.easeOut(duration: visualState.environment.reduceMotion ? 0.12 : 0.22), value: isEnteringLatestItem)
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
        cardInteractionState.setHover(id, isHovered: isHovered)
    }

    private func setCardPress(_ id: HistoryPreviewItem.ID, isPressed: Bool) {
        cardInteractionState.setPress(id, isPressed: isPressed)
    }

    private func playEntranceAnimationSoon(for id: ClipboardItem.ID) {
        playEntranceAnimation(for: id)
    }

    private func playEntranceAnimation(for id: ClipboardItem.ID) {
        cardInteractionState.startEntranceAnimation(for: id, startTime: Date().timeIntervalSinceReferenceDate)
        cardInteractionState.entranceSheenClearTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(latestItemEntranceSheenDuration * 1_000_000_000))
            guard !Task.isCancelled else {
                return
            }

            cardInteractionState.finishEntranceSheen(for: id)
        }
        cardInteractionState.enteringItemClearTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(latestItemEntranceDuration * 1_000_000_000))
            guard !Task.isCancelled else {
                return
            }

            withAnimation(.easeOut(duration: 0.20)) {
                cardInteractionState.finishEntering(for: id)
            }
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
                .foregroundStyle(toolbarSecondaryForeground)

                HStack(spacing: 7) {
                    Image(nsImage: ClipEaseAppIcon.roundedImage(ClipEaseAppIcon.image(size: NSSize(width: 18, height: 18)), size: NSSize(width: 18, height: 18)))
                        .resizable()
                        .frame(width: 18, height: 18)

                    Text(L("轻贴"))
                        .font(titleTypography.swiftUIFont)
                        .foregroundStyle(toolbarPrimaryForeground)
                }

                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            topTrack
                .frame(maxWidth: .infinity)

            HStack(spacing: 12) {
                Button(action: toggleWindowPinnedOpen) {
                    Image(systemName: inputState.isWindowPinnedOpen ? "pin.fill" : "pin")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(inputState.isWindowPinnedOpen ? Color(red: 0.18, green: 0.55, blue: 1.0) : toolbarSecondaryForeground)
                }
                .buttonStyle(.plain)
                .help(inputState.isWindowPinnedOpen ? L("取消钉住主窗口") : L("钉住主窗口"))

                if !accessibilityPermissionState.isTrusted {
                    authorizationButton
                }

                moreMenu
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 22)
        .frame(height: HistoryWindowPanelMetrics.toolbarHeight)
    }

    private var topTrack: some View {
        GeometryReader { proxy in
            let widthPlan = HistoryGlassToolbarWidthPolicy.resolve(
                availableWidth: proxy.size.width,
                isSearchExpanded: searchUIState.shouldShowField
            )

            ScrollViewReader { scrollProxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        searchField
                            .frame(width: widthPlan.searchWidth, alignment: .leading)
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
                    .frame(minWidth: widthPlan.trackWidth, alignment: .center)
                    .padding(.vertical, 1)
                    .animation(.easeOut(duration: 0.16), value: searchUIState.shouldShowField)
                }
                .background(HorizontalScrollWheelRedirector(
                    scope: .auxiliaryRail,
                    isEnabled: inputState.isWindowVisible
                ))
                .onChange(of: groupUIState.pendingGroupTrackScrollID) { scrollID in
                    guard let scrollID else {
                        return
                    }

                    withAnimation(.easeOut(duration: 0.18)) {
                        scrollProxy.scrollTo(scrollID, anchor: .trailing)
                    }
                    groupUIState.pendingGroupTrackScrollID = nil
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: 30)
        .confirmationDialog(
            L("删除分组？"),
            isPresented: Binding(
                get: { groupUIState.groupPendingDeletion != nil },
                set: { isPresented in
                    if !isPresented {
                        groupUIState.groupPendingDeletion = nil
                    }
                }
            ),
            titleVisibility: .visible,
            presenting: groupUIState.groupPendingDeletion
        ) { group in
            Button(L("删除分组和内容"), role: .destructive) {
                deleteGroup(group)
            }

            Button(L("取消"), role: .cancel) {}
        } message: { group in
            Text(L("会删除“\(group.name)”中的 \(store.itemCount(inGroup: group.id)) 条内容，无法恢复。"))
        }
    }

    private var allHistoryGroupButton: some View {
        let isSelected = groupUIState.selectedGroup == .all

        return Button(action: selectAllGroups) {
            HStack(spacing: 6) {
                Image(systemName: "tray.full")
                    .font(.system(size: 12, weight: .semibold))
                if !isSearchControlExpanded {
                    Text(L("全部剪切板"))
                        .font(groupTypography.swiftUIFont)
                        .lineLimit(1)
                }
            }
            .foregroundStyle(isSelected ? Color.white : toolbarPrimaryForeground)
            .padding(.horizontal, isSearchControlExpanded ? 8 : 10)
            .frame(height: 28)
            .background(
                isSelected
                    ? selectedGroupFill(allHistoryGroupColor)
                    : Color.white.opacity(toolbarGlassControlStyle.idleFillOpacity)
            )
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .fixedSize()
        .historyRailControlStyle()
        .background(
            GroupMouseDownObserver(
                registry: groupMouseMonitorRegistry,
                isEnabled: inputState.isWindowVisible,
                onMouseDown: closeSearchForGroupNavigation
            )
                .onRightMouseDown(selectAllGroupsForContextMenu)
        )
        .help(L("显示全部历史"))
    }

    private var searchToggleButton: some View {
        Button(action: toggleSearch) {
            HStack(spacing: 5) {
                Image(systemName: searchUIState.isVisible ? "xmark" : "magnifyingglass")
                    .font(.system(size: 12, weight: .semibold))

                Text(L("搜索"))
                    .font(toolbarButtonTypography.swiftUIFont)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.white.opacity(toolbarGlassControlStyle.idleFillOpacity))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(toolbarPrimaryForeground)
        .fixedSize()
        .historyRailControlStyle()
        .background(
            SearchInteractionLiveRegion(
                isActive: searchUIState.isVisible,
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
                .background(Color.white.opacity(toolbarGlassControlStyle.idleFillOpacity))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color(red: 0.18, green: 0.55, blue: 1.0).opacity(0.70 + glassEnvironment.toolbarTextContrast * 0.30))
        .fixedSize()
        .historyRailControlStyle()
        .help(L("新建分组"))
    }

    private func systemGroupButton(_ group: SystemHistoryGroup) -> some View {
        let isSelected = groupUIState.selectedGroup == group.selection
        let color = systemGroupColor(group)

        return Button(action: { selectSystemGroup(group) }) {
            HStack(spacing: 6) {
                Image(systemName: systemGroupIconName(group))
                    .font(.system(size: 12, weight: .semibold))
                if !isSearchControlExpanded {
                    Text(group.title)
                        .font(groupTypography.swiftUIFont)
                        .lineLimit(1)
                }
            }
            .foregroundStyle(isSelected ? Color.white : toolbarPrimaryForeground)
            .padding(.horizontal, isSearchControlExpanded ? 8 : 10)
            .frame(height: 28)
            .background(
                isSelected
                    ? selectedGroupFill(color)
                    : Color.white.opacity(toolbarGlassControlStyle.idleFillOpacity)
            )
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .fixedSize()
        .historyRailControlStyle()
        .background(GroupMouseDownObserver(
            registry: groupMouseMonitorRegistry,
            isEnabled: inputState.isWindowVisible,
            onMouseDown: closeSearchForGroupNavigation,
            onRightMouseDown: { selectSystemGroupForContextMenu(group) }
        ))
        .contextMenu {
            Button(L("颜色与图标")) {
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
                Text(L("颜色与图标"))
                    .font(.system(size: 14, weight: .semibold))

                Spacer()

                Button(L("关闭")) {
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
                isFocused: $groupUIState.isIconSearchFocused,
                placeholder: L("搜索图标"),
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

            Button(L("确认")) {
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
                Text(L("颜色与图标"))
                    .font(.system(size: 14, weight: .semibold))

                Spacer()

                Button(L("关闭")) {
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
                isFocused: $groupUIState.isIconSearchFocused,
                placeholder: L("搜索图标"),
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

            Button(L("确认")) {
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
        .help(L("选择颜色"))
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
        let isSelected = groupUIState.selectedGroup == .group(group.id)
        let isRenaming = groupUIState.renameTargetID == group.id

        return Group {
            if isRenaming {
                HStack(spacing: 6) {
                    Image(systemName: group.iconName)
                        .font(.system(size: 12, weight: .semibold))

                    GroupInlineTextField(
                        text: $groupUIState.renameText,
                        isFocused: Binding(
                            get: { groupUIState.renameTargetID == group.id },
                            set: { _ in }
                        ),
                        placeholder: L("分组名称"),
                        font: .systemFont(ofSize: 12, weight: .semibold),
                        textColor: .white,
                        drawsBackground: false,
                        isGroupRenameField: true,
                        focusRequestID: groupUIState.renameFocusRequestID,
                        onEscape: handleRenameEscape,
                        onSubmit: { commitRenameGroup(group) }
                    )
                    .frame(width: 84, height: 20)
                    .background(
                        GroupRenameInputFrameReader { frame in
                            groupUIState.renameInputScreenFrame = frame
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
                    if groupUIState.renameTargetID == nil {
                        groupUIState.renameOriginalText = group.name
                        groupUIState.renameText = group.name
                        groupUIState.isRenameCancelPending = false
                    }
                    focusedRenameGroupID = group.id
                }
                .onChange(of: focusedRenameGroupID) { focusedID in
                    if focusedID != group.id, groupUIState.renameTargetID == group.id {
                        commitPendingRenameIfNeeded()
                    }
                }
                .onDisappear {
                    if groupUIState.renameTargetID == group.id {
                        groupUIState.renameInputScreenFrame = nil
                    }
                }
            } else {
                Button(action: { selectGroup(group.id) }) {
                    HStack(spacing: 6) {
                        Image(systemName: group.iconName)
                            .font(.system(size: 12, weight: .semibold))
                        if !compact {
                            Text(group.name)
                                .font(groupTypography.swiftUIFont)
                                .lineLimit(1)
                        }
                    }
                    .foregroundStyle(isSelected ? Color.white : toolbarPrimaryForeground)
                    .padding(.horizontal, compact ? 8 : 10)
                    .frame(height: 28)
                    .background(
                        isSelected
                            ? selectedGroupFill(Color.clipeaseHex(group.colorHex))
                            : Color.white.opacity(toolbarGlassControlStyle.idleFillOpacity)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)
                .fixedSize()
                .historyRailControlStyle()
                .background(GroupMouseDownObserver(
                    registry: groupMouseMonitorRegistry,
                    isEnabled: inputState.isWindowVisible,
                    onMouseDown: handleGroupRowOutsideClick,
                    onRightMouseDown: { selectGroupForContextMenu(group) },
                    onDoubleMouseDown: { beginRenameGroupAfterCurrentMouseEvent(group) }
                ))
                .contextMenu {
                    Button(L("重命名")) {
                        beginRenameGroup(group)
                    }

                    Button(L("颜色与图标")) {
                        beginEditGroupAppearance(group)
                    }

                    Divider()

                    Button(L("删除分组"), role: .destructive) {
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
                .help(L("\(group.name)：\(store.itemCount(inGroup: group.id)) 条"))
            }
        }
    }

    private var resultCountBadge: some View {
        Text("\(filteredItems.count) / \(items.count)")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(toolbarSecondaryForeground)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.45))
            .clipShape(Capsule())
            .help(L("当前筛选结果数量 / 全部数量"))
    }

    private var authorizationButton: some View {
        Button(action: openAccessibilitySettingsIfNeeded) {
            HStack(spacing: 5) {
                Image(systemName: "exclamationmark.lock")
                    .font(.system(size: 12, weight: .semibold))

                Text(L("请授权"))
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
        .help(L("点击打开辅助功能权限设置"))
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            GeometryReader { availableSpace in
                let insertionIndex = min(
                    max(0, searchTextInsertionIndex),
                    searchTokens.count
                )
                let inputWidth = max(
                    24,
                    availableSpace.size.width - searchLeadingContentWidth - 3
                )

                ScrollViewReader { scrollProxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 0) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(toolbarSecondaryForeground)
                                .frame(width: 14, height: 20)

                            ForEach(Array(searchTokens.enumerated()), id: \.element.id) { index, token in
                                if index > 0 {
                                    searchTokenInsertionGap(at: index)
                                }

                                if insertionIndex == index {
                                    searchTextInput(
                                        scrollProxy: scrollProxy,
                                        width: inputWidth
                                    )
                                }

                                searchTokenView(token)
                                    .id(token.id)
                            }

                            if !searchTokens.isEmpty {
                                searchTokenInsertionGap(at: searchTokens.count)
                            }

                            if insertionIndex == searchTokens.count {
                                searchTextInput(
                                    scrollProxy: scrollProxy,
                                    width: inputWidth
                                )
                            }
                        }
                        .id("search-leading-content")
                        .frame(minWidth: availableSpace.size.width, alignment: .leading)
                    }
                    .background(HorizontalScrollWheelRedirector(
                        scope: .auxiliaryRail,
                        isEnabled: inputState.isWindowVisible
                    ))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        focusSearchField()
                    }
                    .onChange(of: searchTokens) { _ in
                        searchTextInsertionIndex = searchTokens.count
                        scrollProxy.scrollTo("search-text-field", anchor: .trailing)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .background(searchTokenWidthMeasurer)

            if isSearchActive {
                Button(action: clearSearchTextAndFilters) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(toolbarSecondaryForeground)
                .help(L("清空搜索"))
            }

            Button(action: toggleSearchFilterPanel) {
                Image(systemName: searchUIState.criteria.hasActiveFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    .font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(searchUIState.criteria.hasActiveFilters ? Color(red: 0.18, green: 0.55, blue: 1.0) : toolbarSecondaryForeground)
            .help(L("搜索筛选"))
            .popover(isPresented: $searchUIState.isFilterPanelPresented, arrowEdge: .bottom) {
                searchFilterPanel
                    .fixedSize()
                    .background(SearchPanelWindowReader(onWindowChange: { _ in
                        refreshSearchInteractionScreenFrames()
                    }))
            }
        }
        .onPreferenceChange(SearchLeadingContentWidthPreferenceKey.self) { width in
            guard abs(searchLeadingContentWidth - width) > 0.5 else {
                return
            }
            searchLeadingContentWidth = width
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 30, maxHeight: 30)
        .background {
            RoundedRectangle(cornerRadius: searchGlassSurfaceStyle.cornerRadius, style: .continuous)
                .fill(Color.white.opacity(
                    searchUIState.isFieldVisualVisible ? searchGlassSurfaceStyle.fillOpacity : 0
                ))
                .overlay {
                    RoundedRectangle(cornerRadius: searchGlassSurfaceStyle.cornerRadius, style: .continuous)
                        .strokeBorder(
                            Color.white.opacity(searchGlassSurfaceStyle.boundaryOpacity),
                            lineWidth: 1
                        )
                }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            focusSearchField()
        }
        .background(
            SearchInteractionLiveRegion(
                isActive: searchUIState.isVisible,
                onRegister: { view in
                    SearchInteractionRegionRegistry.shared.register(view)
                },
                onUnregister: { view in
                    SearchInteractionRegionRegistry.shared.unregister(view)
                }
            )
        )
        .background(
            SearchInteractionScreenFrameReader(isActive: searchUIState.isVisible) { frame in
                if viewportState.searchControlScreenFrame != frame {
                    viewportState.searchControlScreenFrame = frame
                }
            }
        )
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: SearchInteractionFramePreferenceKey.self,
                    value: searchUIState.isVisible ? [proxy.frame(in: .named("historyWindow")).insetBy(dx: -8, dy: -8)] : []
                )
            }
        )
        .opacity(searchUIState.isFieldVisualVisible ? 1 : 0)
        .foregroundStyle(toolbarPrimaryForeground)
        .scaleEffect(searchUIState.isFieldVisualVisible ? 1 : 1, anchor: .center)
        .allowsHitTesting(searchUIState.isVisible)
        .animation(.easeOut(duration: 0.12), value: searchUIState.isFieldVisualVisible)
    }

    private var searchTokenWidthMeasurer: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 14, height: 20)

            ForEach(searchTokens) { token in
                searchTokenView(token)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .hidden()
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: SearchLeadingContentWidthPreferenceKey.self,
                    value: proxy.size.width
                )
            }
        )
    }

    @ViewBuilder
    private func searchTextInput(
        scrollProxy: ScrollViewProxy,
        width: CGFloat
    ) -> some View {
        SearchTextField(
            text: $searchUIState.text,
            isFocused: $isSearchFocused,
            isComposing: $isSearchTextComposing,
            pendingComposedInputEvent: $pendingComposedSearchInputEvent,
            focusRequestID: searchFocusRequestID,
            searchHasHandedOffFocusToCard: searchUIState.hasHandedOffFocusToCard,
            hasSearchResult: !filteredItems.isEmpty,
            hasSearchTokens: !searchTokens.isEmpty,
            textColor: toolbarPrimaryNSColor,
            font: searchTypography.nsFont,
            onFocusChanged: synchronizeSearchTextFieldFocus,
            onEnterFirstResult: enterFirstSearchResultFromSearchField,
            onDeleteLastToken: handleSearchTokenBackspace,
            onCancel: handleSearchCancel,
            onReachLeadingContent: {
                withAnimation(.easeOut(duration: 0.12)) {
                    scrollProxy.scrollTo("search-leading-content", anchor: .leading)
                }
            },
            onReachTrailingContent: {
                withAnimation(.easeOut(duration: 0.12)) {
                    scrollProxy.scrollTo("search-text-field", anchor: .trailing)
                }
            }
        )
        .font(searchTypography.swiftUIFont)
        .frame(width: width)
        .id("search-text-field")
    }

    private func searchTokenInsertionGap(at index: Int) -> some View {
        Color.clear
            .frame(width: 6, height: 20)
            .contentShape(Rectangle())
            .onTapGesture {
                searchTextInsertionIndex = index
                focusSearchField()
            }
    }

    private func searchTokenView(_ token: HistorySearchToken) -> some View {
        let isSelected = searchUIState.selectedTokenKind == token.kind
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
            .help(L("移除\(token.title)"))
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
            if searchUIState.selectedTokenKind == token.kind {
                searchUIState.selectedTokenKind = nil
            } else {
                searchUIState.selectedTokenKind = token.kind
            }
        }
    }

    private var searchFilterPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L("搜索筛选"))
                    .font(.system(size: 14, weight: .semibold))

                Spacer()

                Button(L("清空")) {
                    searchUIState.criteria = HistorySearchCriteria()
                }
                .disabled(!searchUIState.criteria.hasActiveFilters)

                Button(L("关闭")) {
                    searchUIState.isFilterPanelPresented = false
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
                                    isSelected: searchUIState.criteria.types.contains(type),
                                    action: { toggleSearchType(type) }
                                )
                            }
                        }
                    }

                    searchFilterSection("App") {
                        if previewItemsState.sourceAppFilterOptions.isEmpty {
                            Text(L("暂无来源"))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                        } else {
                            filterChipGrid {
                                ForEach(previewItemsState.sourceAppFilterOptions) { option in
                                    let appName = option.name
                                    searchFilterChip(
                                        title: appName,
                                        iconFileName: option.iconFileName,
                                        fallbackSystemImage: "app.fill",
                                        isSelected: searchUIState.criteria.sourceAppNames.contains(appName),
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
                                    isSelected: searchUIState.criteria.dateRanges.contains(range),
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
                                    isSelected: searchUIState.criteria.groups.contains(group.searchGroup),
                                    action: { toggleSearchGroup(group.searchGroup) }
                                )
                            }

                            ForEach(store.groups) { group in
                                searchFilterChip(
                                    title: group.name,
                                    systemImage: group.iconName,
                                    isSelected: searchUIState.criteria.groups.contains(.group(group.id)),
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

        Button(item.isPinned ? L("取消置顶") : L("置顶")) {
            togglePinned(item.id)
        }

        Divider()

        typeSpecificContextMenu(for: item)

        if !groupUIState.moveToGroupMenuSnapshot.isEmpty {
            Button(item.groupID == nil ? L("加入分组...") : L("移动到分组...")) {
                presentMoveToGroupPicker(for: item)
            }
        }

        if item.groupID != nil {
            Button(L("移出分组")) {
                removeItemFromGroup(item.id)
            }
        }

        Button(L("删除"), role: .destructive) {
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

            Button(L("复制来源 App 名称")) {
                copySourceAppName(item.id)
            }

            Button(L("复制来源 Bundle ID")) {
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

        addMenuItem(item.isPinned ? L("取消置顶") : L("置顶"), to: menu) { togglePinned(item.id) }
        menu.addItem(.separator())

        addTypeSpecificMenuItems(for: item, to: menu)

        if !groupUIState.moveToGroupMenuSnapshot.isEmpty {
            addMenuItem(item.groupID == nil ? L("加入分组...") : L("移动到分组..."), to: menu) {
                presentMoveToGroupPicker(for: item)
            }
        }

        if item.groupID != nil {
            addMenuItem(L("移出分组"), to: menu) { removeItemFromGroup(item.id) }
        }

        addMenuItem(L("删除"), to: menu) { deleteItem(item.id) }

        if let sourceItem = store.item(with: item.id),
           sourceItem.sourceBundleID != nil {
            menu.addItem(.separator())
            if !sourceItem.isFromClipEase {
                addMenuItem(sourceAppIgnoreMenuTitle(for: sourceItem), to: menu) { toggleSourceAppIgnored(item.id) }
            }
            addMenuItem(L("复制来源 App 名称"), to: menu) { copySourceAppName(item.id) }
            addMenuItem(L("复制来源 Bundle ID"), to: menu) { copySourceBundleID(item.id) }
        }

        return menu
    }

    private func addTypeSpecificMenuItems(for item: HistoryPreviewItem, to menu: NSMenu) {
        switch item.type {
        case .link:
            addMenuItem(L("打开链接"), to: menu) { openLink(item.id) }
            addMenuItem(L("复制链接地址"), to: menu) { copyLinkURL(item.id) }
            addMenuItem(L("复制为 Markdown 链接"), to: menu) { copyMarkdownLink(item.id) }
            menu.addItem(.separator())
        case .color:
            addMenuItem(L("复制 HEX"), to: menu) { copyColorHex(item.id) }
            addMenuItem(L("复制 RGB"), to: menu) { copyColorRGB(item.id) }
            menu.addItem(.separator())
        case .image:
            addMenuItem(L("打开图片"), to: menu) { openImage(item.id) }
            addMenuItem(L("复制图像"), to: menu) { copyImage(item.id) }
            addMenuItem(L("复制图片路径"), to: menu) { copyImagePath(item.id) }
            addMenuItem(L("在 Finder 中显示"), to: menu) { revealImageInFinder(item.id) }
            menu.addItem(.separator())
        case .file:
            addMenuItem(L("打开文件"), to: menu) { openFile(item.id) }
            addMenuItem(L("复制文件"), to: menu) { copyFile(item.id) }
            addMenuItem(L("复制路径"), to: menu) { copyFilePaths(item.id) }
            addMenuItem(L("在 Finder 中显示"), to: menu) { revealFilesInFinder(item.id) }
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
            Button(L("打开链接")) {
                openLink(item.id)
            }

            Button(L("复制链接地址")) {
                copyLinkURL(item.id)
            }

            Button(L("复制为 Markdown 链接")) {
                copyMarkdownLink(item.id)
            }

            Divider()
        case .color:
            Button(L("复制 HEX")) {
                copyColorHex(item.id)
            }

            Button(L("复制 RGB")) {
                copyColorRGB(item.id)
            }

            Divider()
        case .image:
            Button(L("打开图片")) {
                openImage(item.id)
            }

            Button(L("复制图像")) {
                copyImage(item.id)
            }

            Button(L("复制图片路径")) {
                copyImagePath(item.id)
            }

            Button(L("在 Finder 中显示")) {
                revealImageInFinder(item.id)
            }

            Divider()
        case .file:
            Button(L("打开文件")) {
                openFile(item.id)
            }

            Button(L("复制文件")) {
                copyFile(item.id)
            }

            Button(L("复制路径")) {
                copyFilePaths(item.id)
            }

            Button(L("在 Finder 中显示")) {
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
        groupUIState.refreshMoveToGroupMenuSnapshot(groups: store.groups)
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
        let sourceItems = store.items
        let sourceGeneration = store.itemsMutationGeneration
        PerformanceDiagnosticsService.shared.record(
            "history.hidden.keepWarm",
            category: "history",
            durationMS: 0,
            itemCount: sourceItems.count,
            resultCount: previewItemsState.allItems.count,
            metadata: [
                "reason": "window.hidden",
                "cacheStored": "\(previewItemsState.previewItemCache.count)"
            ]
        )
        if HistoryWindowLifecycleScheduler.shouldWarmPreviewAfterHide(
            hasSourceItems: !sourceItems.isEmpty,
            canSkipPreviewRebuild: canSkipPreviewRebuild(
                sourceItems: sourceItems,
                sourceGeneration: sourceGeneration
            )
        ) {
            schedulePreviewItemsRebuild(from: sourceItems)
        }

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

    private func warmPreviewItemsForPreloadedHiddenWindowIfNeeded() {
        guard previewBuildTask == nil else {
            return
        }

        let sourceItems = store.items
        let sourceGeneration = store.itemsMutationGeneration
        guard HistoryWindowLifecycleScheduler.shouldWarmPreviewForPreloadedHiddenWindow(
            isWindowVisible: inputState.isWindowVisibleSnapshot,
            isWindowPresented: inputState.isWindowPresentedSnapshot,
            isOpenAnimationActive: inputState.isOpenAnimationActiveSnapshot,
            hasSourceItems: !sourceItems.isEmpty,
            canSkipPreviewRebuild: canSkipPreviewRebuild(
                sourceItems: sourceItems,
                sourceGeneration: sourceGeneration
            )
        ) else {
            return
        }

        PerformanceDiagnosticsService.shared.record(
            "history.preload.previewWarm",
            category: "history",
            durationMS: 0,
            itemCount: sourceItems.count,
            resultCount: previewItemsState.allItems.count,
            metadata: [
                "reason": "preloaded.hidden",
                "cacheStored": "\(previewItemsState.previewItemCache.count)"
            ]
        )
        schedulePreviewItemsRebuild(from: sourceItems)
    }

    private func rebuildPreviewItemsIfNeededForVisibleWindow() {
        guard HistoryWindowLifecycleScheduler.shouldScheduleVisibleRebuild(
                isWindowVisible: inputState.isWindowVisibleSnapshot,
                isWindowPresented: inputState.isWindowPresentedSnapshot,
                isOpenAnimationActive: inputState.isOpenAnimationActiveSnapshot
              ),
              !store.items.isEmpty else {
            return
        }

        if previewItemsState.allItems.isEmpty || previewItemsState.filteredItems.isEmpty {
            scheduleDeferredStartupWork(delayNanoseconds: previewItemsState.allItems.isEmpty ? 0 : 32_000_000)
        }
    }

    private func cancelPresentationWorkForHide() {
        deferredStartupTask?.cancel()
        deferredStartupTask = nil
        guard HistoryWindowLifecycleScheduler.shouldCancelPreviewBuildForHide(
            hasPendingPreviewBuild: previewBuildTask != nil
        ) else {
            return
        }

        previewBuildTask?.cancel()
        previewBuildTask = nil
        previewBuildGeneration = HistoryWindowLifecycleScheduler.previewGenerationAfterHideCleanup(
            currentGeneration: previewBuildGeneration,
            hasPendingPreviewBuild: true
        )
    }

    private func scheduleDeferredStartupWork() {
        scheduleDeferredStartupWork(delayNanoseconds: 32_000_000)
    }

    private func scheduleDeferredStartupWork(delayNanoseconds: UInt64) {
        deferredStartupTask?.cancel()
        let wasOpenAnimationActive = inputState.isOpenAnimationActiveSnapshot
        guard let startupDelayNanoseconds = HistoryWindowLifecycleScheduler.startupDelayNanoseconds(
            requestedDelayNanoseconds: delayNanoseconds,
            isWindowVisible: inputState.isWindowVisibleSnapshot,
            isWindowPresented: inputState.isWindowPresentedSnapshot,
            isOpenAnimationActive: wasOpenAnimationActive
        ) else {
            deferredStartupTask = nil
            return
        }

        deferredStartupTask = Task { @MainActor in
            if startupDelayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: startupDelayNanoseconds)
            }
            guard !Task.isCancelled,
                  inputState.isWindowVisibleSnapshot,
                  inputState.isWindowPresentedSnapshot else {
                return
            }

            HistoryWindowLifecycleDiagnostics.record(
                .openDeferredStartup,
                itemCount: store.items.count,
                wasVisible: true,
                shouldAnimate: wasOpenAnimationActive,
                hasPendingFocus: focusState.pendingLatestFocusItemID != nil || focusState.pendingDefaultFocusOnShow,
                visibleItemCount: renderedWindowItems.count,
                previewItemCount: previewItemsState.allItems.count
            )
            schedulePreviewItemsRebuild(from: store.items)
            refreshAccessibilityStateAfterFirstFrame()
            deferredStartupTask = nil
        }
    }

    private func moveToGroupPicker(for target: MoveToGroupPickerTarget) -> some View {
        let groupEntries = groupUIState.moveToGroupMenuSnapshot

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(target.currentGroupID == nil ? L("加入分组") : L("移动到分组"))
                        .font(.system(size: 15, weight: .semibold))

                    Text(L("选择一个目标分组"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(L("取消")) {
                    groupUIState.moveToGroupPickerTarget = nil
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
                    groupUIState.moveToGroupPickerTarget = nil
                } label: {
                    Label(L("移出分组"), systemImage: "tray.and.arrow.up")
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
            groupUIState.moveToGroupPickerTarget = nil
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
            L("清空全部历史？"),
            isPresented: $groupUIState.isClearConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button(L("清空历史"), role: .destructive) {
                clearAllItems()
            }

            Button(L("取消"), role: .cancel) {}
        } message: {
            Text(L("此操作会删除所有普通和置顶记录，以及已保存的图片文件。"))
        }
        .help(L("更多操作"))
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

        let pauseItem = NSMenuItem(title: L("暂停 轻贴"), action: nil, keyEquivalent: "")
        pauseItem.submenu = makePauseNSMenu()
        menu.addItem(pauseItem)

        menu.addItem(.separator())

        let clearItem = NSMenuItem(title: L("清空历史"), action: nil, keyEquivalent: "")
        let clearTarget = ClosureMenuItemTarget {
            groupUIState.isClearConfirmationPresented = true
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
        addMenuItem(L("暂停 15 分钟"), to: menu) {
            pauseRecording(for: 15 * 60, message: L("已暂停 15 分钟"))
        }
        addMenuItem(L("暂停 30 分钟"), to: menu) {
            pauseRecording(for: 30 * 60, message: L("已暂停 30 分钟"))
        }
        addMenuItem(L("暂停 1 小时"), to: menu) {
            pauseRecording(for: 60 * 60, message: L("已暂停 1 小时"))
        }
        addMenuItem(L("暂停 3 小时"), to: menu) {
            pauseRecording(for: 3 * 60 * 60, message: L("已暂停 3 小时"))
        }
        addMenuItem(L("暂停 6 小时"), to: menu) {
            pauseRecording(for: 6 * 60 * 60, message: L("已暂停 6 小时"))
        }
        addMenuItem(L("截止到今日"), to: menu) {
            appMenuController.pauseUntilEndOfToday()
        }

        return menu
    }

    private var retentionSettingsMenu: some View {
        Menu(L("保存期限")) {
            ForEach(HistoryRetentionPolicy.allCases) { policy in
                Button {
                    store.retentionPolicy = policy
                    showStatus(L("保存期限：\(policy.shortTitle)"))
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

            Button(L("暂停 15 分钟")) {
                pauseRecording(for: 15 * 60, message: L("已暂停 15 分钟"))
            }

            Button(L("暂停 30 分钟")) {
                pauseRecording(for: 30 * 60, message: L("已暂停 30 分钟"))
            }

            Button(L("暂停 1 小时")) {
                pauseRecording(for: 60 * 60, message: L("已暂停 1 小时"))
            }

            Button(L("暂停 3 小时")) {
                pauseRecording(for: 3 * 60 * 60, message: L("已暂停 3 小时"))
            }

            Button(L("暂停 6 小时")) {
                pauseRecording(for: 6 * 60 * 60, message: L("已暂停 6 小时"))
            }

            Button(L("截止到今日")) {
                appMenuController.pauseUntilEndOfToday()
            }
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
        focusState.pendingKeyboardFocusItemID = id
        pendingKeyboardFocusClearTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled,
                  focusState.pendingKeyboardFocusItemID == id else {
                return
            }
            focusState.pendingKeyboardFocusItemID = nil
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
            showStatus(L("已复制纯文本"))
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
            showStatus(L("已复制纯文本，需授权后自动粘贴"))
            closeAfterPasteIfNeeded()
        case .pasted, .pastedFallbackText:
            store.markUsed(item.id)
            scheduleProgrammaticJump(to: item.id)
            showStatus(L("已粘贴纯文本到当前 App"))
        case .failed(let reason):
            focusState.pendingPastedItemFocusOnNextShow = nil
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
            showStatus(L("无法写入剪贴板"))
            return
        }
        ClipEaseSoundPlayer.shared.playCopyFeedback()
        showStatus(L("已复制 Markdown 链接"))
        closeAfterContextMenuCommand()
    }

    private func copyLinkURL(_ id: ClipboardItem.ID?) {
        guard let item = store.item(with: id),
              item.type == .link else {
            return
        }

        guard case .copied = pasteExecutor.copyTextToPasteboard(item.text) else {
            showStatus(L("无法写入剪贴板"))
            return
        }
        ClipEaseSoundPlayer.shared.playCopyFeedback()
        showStatus(L("已复制链接地址"))
        closeAfterContextMenuCommand()
    }

    private func openLink(_ id: ClipboardItem.ID?) {
        guard let item = store.item(with: id),
              item.type == .link,
              let url = item.url else {
            showStatus(L("无法打开链接"))
            return
        }

        NSWorkspace.shared.open(url)
        showStatus(L("已打开链接"))
        closeAfterContextMenuCommand()
    }

    private func copyColorHex(_ id: ClipboardItem.ID?) {
        guard let item = store.item(with: id),
              item.type == .color else {
            return
        }

        guard case .copied = pasteExecutor.copyTextToPasteboard(item.text) else {
            showStatus(L("无法写入剪贴板"))
            return
        }
        ClipEaseSoundPlayer.shared.playCopyFeedback()
        showStatus(L("已复制 HEX"))
        closeAfterContextMenuCommand()
    }

    private func copyColorRGB(_ id: ClipboardItem.ID?) {
        guard let item = store.item(with: id),
              item.type == .color,
              let rgb = rgbString(from: item.text) else {
            showStatus(L("无法转换 RGB"))
            return
        }

        guard case .copied = pasteExecutor.copyTextToPasteboard(rgb) else {
            showStatus(L("无法写入剪贴板"))
            return
        }
        ClipEaseSoundPlayer.shared.playCopyFeedback()
        showStatus(L("已复制 RGB"))
        closeAfterContextMenuCommand()
    }

    private func pasteItem(_ id: ClipboardItem.ID?) {
        let startedAt = CFAbsoluteTimeGetCurrent()
        guard containsFilteredItem(id),
              let item = store.item(with: id) else {
            if searchUIState.isVisible {
                showStatus(L("没有可粘贴的搜索结果"))
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
            focusState.pendingPastedItemFocusOnNextShow = nil
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
        focusState.pendingPastedItemFocusOnNextShow = id
        selectedItemID = id
        persistSelectedItem()
        HistoryScrollCoordinator.shared.discardSavedOffset(for: HistoryGroupSelection.all.storageValue)
        HistoryScrollCoordinator.shared.discardSavedOffset(for: groupUIState.selectedGroup.storageValue)
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
        focusState.pendingLatestFocusItemID = nil
        focusState.pendingLatestFocusTimestamp = nil
        focusState.pendingLatestFocusReason = nil
        focusState.pendingLatestFocusLockID = nil
        focusState.pendingProgrammaticJumpItemID = nil
        viewportState.pendingItemScrollID = nil
        viewportState.pendingItemScrollRetryCount = 0
        focusState.pendingKeyboardFocusItemID = nil
        pendingKeyboardFocusClearTask?.cancel()
        pendingKeyboardFocusClearTask = nil
        latestFocusRetryTask?.cancel()
        latestFocusRetryTask = nil
        viewportState.shouldResetHorizontalOffsetForPendingItemScroll = false
        viewportState.shouldAnimatePendingItemScroll = false
        viewportState.isPreparingPendingItemScrollMeasurement = false
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
            showStatus(L("此内容暂不支持编辑"))
            return
        }

        closePreview()
        onClose()
        appMenuController.editItem(item) { updatedItem in
            selectedItemID = updatedItem.id
            if updatedItem.type == .link {
                _ = pasteExecutor.copyTextToPasteboard(updatedItem.text)
                ClipEaseSoundPlayer.shared.playCopyFeedback()
                showStatus(L("已保存并复制新链接"))
            } else {
                showStatus(L("已保存"))
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
        showStatus(L("已删除"))
    }

    private func clearAllItems() {
        store.clearAllItems()
        selectedItemID = nil
        groupUIState.selectedGroup = .all
        rememberSelectedGroup()
        showStatus(L("已清空"))
    }

    private func restoreRememberedGroupSelection() {
        groupUIState.restoreSelectedGroup(from: rememberedSelectedGroup, groups: store.groups)
        if groupUIState.selectedGroup.storageValue != rememberedSelectedGroup {
            rememberSelectedGroup()
            return
        }

        HistoryScrollCoordinator.shared.setScope(groupUIState.selectedGroup.storageValue)
    }

    private func rememberSelectedGroup() {
        if case .group(let groupID) = groupUIState.selectedGroup,
           !store.groups.contains(where: { $0.id == groupID }) {
            rememberedSelectedGroup = HistoryGroupSelection.all.storageValue
            return
        }

        rememberedSelectedGroup = groupUIState.selectedGroup.storageValue
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
        if let pendingPastedItemFocusOnNextShow = focusState.pendingPastedItemFocusOnNextShow,
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
        groupUIState.selectedGroup = .all
        showStatus(L("全部剪切板"))
    }

    private func selectAllGroupsForContextMenu() {
        commitPendingRenameIfNeeded()
        closeSearchForGroupNavigation()
        guard groupUIState.selectedGroup != .all else {
            return
        }

        groupUIState.selectedGroup = .all
        showStatus(L("全部剪切板"))
    }

    private func selectGroup(_ id: ClipboardGroup.ID) {
        commitPendingRenameIfNeeded()
        closeSearchForGroupNavigation()
        groupUIState.selectedGroup = .group(id)
        let groupName = store.group(with: id)?.name ?? L("分组")
        showStatus(groupName)
    }

    private func selectSystemGroup(_ group: SystemHistoryGroup) {
        commitPendingRenameIfNeeded()
        closeSearchForGroupNavigation()
        groupUIState.selectedGroup = groupUIState.selectedGroup == group.selection ? .all : group.selection
        showStatus(groupUIState.selectedGroup == group.selection ? group.selectedStatus : L("全部剪切板"))
    }

    private func selectSystemGroupForContextMenu(_ group: SystemHistoryGroup) {
        commitPendingRenameIfNeeded()
        closeSearchForGroupNavigation()
        guard groupUIState.selectedGroup != group.selection else {
            return
        }

        groupUIState.selectedGroup = group.selection
        showStatus(group.selectedStatus)
    }

    private func selectGroupForContextMenu(_ group: ClipboardGroup) {
        selectGroup(group.id)
    }

    private func createGroup() {
        let group = store.createGroup()
        beginRenameGroup(group)
        groupUIState.pendingGroupTrackScrollID = HistoryGroupSelection.group(group.id).scrollID
        showStatus(L("已新建分组"))
    }

    private func beginRenameGroup(_ group: ClipboardGroup) {
        closeSearchForGroupNavigation()
        commitPendingRenameIfNeeded()
        groupUIState.beginRename(group)
        inputState.setTextInputFocused(true)
        Task { @MainActor in
            await Task.yield()
            focusedRenameGroupID = group.id
            groupUIState.requestRenameFocus()
        }
    }

    private func beginRenameGroupAfterCurrentMouseEvent(_ group: ClipboardGroup) {
        DispatchQueue.main.async {
            beginRenameGroup(group)
        }
    }

    private func commitRenameGroup(_ group: ClipboardGroup) {
        guard groupUIState.renameTargetID == group.id else {
            return
        }

        let trimmedName = groupUIState.renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty {
            switch store.renameGroup(group.id, name: trimmedName) {
            case .renamed:
                showStatus(L("已重命名分组"))
            case .duplicate:
                showStatus(L("已有同名分组"))
            case .empty:
                showStatus(L("分组名称不能为空"))
            case .unchanged:
                break
            case .notFound:
                showStatus(L("分组不存在"))
            }
        } else if !groupUIState.isRenameCancelPending {
            showStatus(L("分组名称不能为空"))
        }

        focusedRenameGroupID = nil
        groupUIState.finishRename()
        inputState.setTextInputFocused(false)
    }

    private func cancelRenameGroup() {
        focusedRenameGroupID = nil
        groupUIState.cancelRename()
        inputState.setTextInputFocused(false)
    }

    private func handleRenameEscape() {
        groupUIState.markRenameCancelPending()
        cancelRenameGroup()
    }

    private func beginEditGroupAppearance(_ group: ClipboardGroup) {
        closeSearchForGroupNavigation()
        commitPendingRenameIfNeeded()
        closeGroupColorPanel()
        groupUIState.isIconSearchFocused = false
        groupAppearanceCoordinator.beginEditing(group)
        inputState.setPresentedInputLayerActive(true)
    }

    private func beginEditSystemGroupAppearance(_ group: SystemHistoryGroup) {
        closeSearchForGroupNavigation()
        commitPendingRenameIfNeeded()
        closeGroupColorPanel()
        groupUIState.isIconSearchFocused = false
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
        groupUIState.isIconSearchFocused = false
        closeGroupColorPanel()
        inputState.setTextInputFocused(false)
        inputState.setPresentedInputLayerActive(false)
    }

    private func closeSystemGroupAppearancePopover() {
        groupAppearanceCoordinator.closeSystemPopover()
        groupUIState.isIconSearchFocused = false
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
            groupUIState.isIconSearchFocused = false
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
            groupUIState.groupPendingDeletion = group
        }
    }

    private func commitPendingRenameIfNeeded() {
        guard let group = store.group(with: groupUIState.renameTargetID) else {
            return
        }

        commitRenameGroup(group)
    }

    private func handleGroupRowOutsideClick() {
        if groupUIState.renameTargetID != nil {
            commitPendingRenameIfNeeded()
        }

        closeSearchForGroupNavigation()
    }

    private func cancelPendingGroupRename() {
        guard groupUIState.renameTargetID != nil else {
            return
        }

        groupUIState.markRenameCancelPending()
        cancelRenameGroup()
    }

    private func deleteGroup(_ group: ClipboardGroup) {
        let removedCount = store.deleteGroup(group.id)
        if groupUIState.selectedGroup == .group(group.id) {
            groupUIState.selectedGroup = .all
        }
        showStatus(removedCount > 0 ? L("已删除分组和 \(removedCount) 条内容") : L("已删除分组"))
    }

    private func presentMoveToGroupPicker(for item: HistoryPreviewItem) {
        groupUIState.presentMoveToGroupPicker(for: item)
    }

    private func addItem(_ id: ClipboardItem.ID?, toGroup groupID: ClipboardGroup.ID, named groupName: String? = nil) {
        store.addItem(id, toGroup: groupID)
        if let groupName {
            showStatus(L("已移动到“\(groupName)”"))
        } else {
            showStatus(L("已加入分组"))
        }
    }

    private func removeItemFromGroup(_ id: ClipboardItem.ID?) {
        store.removeItemFromGroup(id)
        showStatus(L("已移出分组"))
    }

    private func togglePinned(_ id: ClipboardItem.ID?) {
        guard let item = store.item(with: id) else {
            return
        }

        store.togglePinned(for: id)
        showStatus(item.isPinned ? L("已取消置顶") : L("已置顶"))
    }

    private func sourceAppIgnoreMenuTitle(for item: ClipboardItem) -> String {
        let prefix = appMenuController.isSourceAppIgnored(for: item) ? L("取消忽略") : L("忽略")
        return "\(prefix) \(item.sourceAppName)"
    }

    private func toggleSourceAppIgnored(_ id: ClipboardItem.ID?) {
        guard let item = store.item(with: id),
              item.sourceBundleID != nil else {
            showStatus(L("无法识别来源 App"))
            return
        }

        guard !item.isFromClipEase else {
            showStatus(L("轻贴自身内容不能忽略"))
            return
        }

        if appMenuController.isSourceAppIgnored(for: item) {
            appMenuController.unignoreSourceApp(for: item)
            showStatus(L("已取消忽略 \(item.sourceAppName)"))
            return
        }

        appMenuController.ignoreSourceApp(for: item)
        showStatus(L("已忽略 \(item.sourceAppName)"))
    }

    private func copySourceAppName(_ id: ClipboardItem.ID?) {
        guard let item = store.item(with: id) else {
            return
        }

        guard case .copied = pasteExecutor.copyTextToPasteboard(item.sourceAppName) else {
            showStatus(L("无法写入剪贴板"))
            return
        }
        showStatus(L("已复制来源名称"))
        closeAfterContextMenuCommand()
    }

    private func copySourceBundleID(_ id: ClipboardItem.ID?) {
        guard let item = store.item(with: id),
              let bundleID = item.sourceBundleID else {
            showStatus(L("无来源 Bundle ID"))
            return
        }

        guard case .copied = pasteExecutor.copyTextToPasteboard(bundleID) else {
            showStatus(L("无法写入剪贴板"))
            return
        }
        showStatus(L("已复制 Bundle ID"))
        closeAfterContextMenuCommand()
    }

    private func revealImageInFinder(_ id: ClipboardItem.ID?) {
        guard let item = store.item(with: id),
              let imageURL = store.imageFileURL(for: item) else {
            showStatus(L("未找到图片文件"))
            return
        }

        NSWorkspace.shared.activateFileViewerSelecting([imageURL])
        showStatus(L("已在 Finder 中显示"))
        closeAfterContextMenuCommand()
    }

    private func openImage(_ id: ClipboardItem.ID?) {
        guard let item = store.item(with: id),
              let imageURL = store.imageFileURL(for: item) else {
            showStatus(L("未找到图片文件"))
            return
        }

        NSWorkspace.shared.open(imageURL)
        showStatus(L("已打开图片"))
        closeAfterContextMenuCommand()
    }

    private func copyImage(_ id: ClipboardItem.ID?) {
        guard let item = store.item(with: id),
              let imageURL = store.imageFileURL(for: item),
              let image = NSImage(contentsOf: imageURL) else {
            showStatus(L("未找到图片文件"))
            return
        }

        guard case .copied = pasteExecutor.copyImageToPasteboard(
            image,
            skipText: item.preview.isEmpty ? imageURL.lastPathComponent : item.preview
        ) else {
            showStatus(L("无法写入图片到剪贴板"))
            return
        }
        ClipEaseSoundPlayer.shared.playCopyFeedback()
        showStatus(L("已复制图像"))
        closeAfterContextMenuCommand()
    }

    private func copyImagePath(_ id: ClipboardItem.ID?) {
        guard let item = store.item(with: id),
              let imageURL = store.imageFileURL(for: item) else {
            showStatus(L("未找到图片文件"))
            return
        }

        let path = imageURL.path
        guard case .copied = pasteExecutor.copyTextToPasteboard(path) else {
            showStatus(L("无法写入剪贴板"))
            return
        }
        ClipEaseSoundPlayer.shared.playCopyFeedback()
        showStatus(L("已复制图片路径"))
        closeAfterContextMenuCommand()
    }

    private func copyFilePaths(_ id: ClipboardItem.ID?) {
        guard let item = store.item(with: id),
              item.type == .file else {
            showStatus(L("未找到文件"))
            return
        }

        let paths = item.fileReferences
            .map(\.path)
            .filter { !$0.isEmpty }

        guard !paths.isEmpty else {
            showStatus(L("未找到文件"))
            return
        }

        let pathsText = paths.joined(separator: "\n")
        guard case .copied = pasteExecutor.copyTextToPasteboard(pathsText) else {
            showStatus(L("无法写入剪贴板"))
            return
        }
        ClipEaseSoundPlayer.shared.playCopyFeedback()
        showStatus(paths.count > 1 ? L("已复制 \(paths.count) 个文件路径") : L("已复制文件路径"))
        closeAfterContextMenuCommand()
    }

    private func copyFile(_ id: ClipboardItem.ID?) {
        guard let item = store.item(with: id),
              item.type == .file else {
            showStatus(L("未找到文件"))
            return
        }

        let urls = existingFileURLs(for: item)
        guard let firstURL = urls.first else {
            showStatus(L("未找到文件"))
            return
        }

        guard case .copied = pasteExecutor.copyFileURLToPasteboard(firstURL) else {
            showStatus(L("无法写入文件引用到剪贴板"))
            return
        }
        ClipEaseSoundPlayer.shared.playCopyFeedback()
        showStatus(L("已复制文件"))
        closeAfterContextMenuCommand()
    }

    private func openFile(_ id: ClipboardItem.ID?) {
        guard let item = store.item(with: id),
              item.type == .file else {
            showStatus(L("未找到文件"))
            return
        }

        let urls = existingFileURLs(for: item)
        guard let firstURL = urls.first else {
            showStatus(L("未找到文件"))
            return
        }

        NSWorkspace.shared.open(firstURL)
        showStatus(L("已打开文件"))
        closeAfterContextMenuCommand()
    }

    private func revealFilesInFinder(_ id: ClipboardItem.ID?) {
        guard let item = store.item(with: id),
              item.type == .file else {
            showStatus(L("未找到文件"))
            return
        }

        let urls = existingFileURLs(for: item)
        guard !urls.isEmpty else {
            showStatus(L("未找到文件"))
            return
        }

        NSWorkspace.shared.activateFileViewerSelecting(urls)
        showStatus(L("已在 Finder 中显示"))
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
        if focusState.pendingLatestFocusLockID == id,
           let targetOffset = latestClipboardFocusTargetOffset(for: id) {
            HistoryScrollCoordinator.shared.scrollToOffset(
                targetOffset,
                animated: viewportState.shouldAnimatePendingItemScroll,
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
                focusState.pendingProgrammaticJumpItemID = nil
                viewportState.pendingItemScrollID = nil
                viewportState.pendingItemScrollRetryCount = 0
                viewportState.shouldAnimatePendingItemScroll = false
                viewportState.isPreparingPendingItemScrollMeasurement = false
                finishLatestFocusIfNeeded(id)
                return true
            }
            return false
        }

        HistoryScrollCoordinator.shared.scrollToOffset(
            targetOffset,
            animated: viewportState.shouldAnimatePendingItemScroll,
            suppressUserOffsetSave: focusState.pendingLatestFocusLockID == id
        )
        if viewportState.shouldResetHorizontalOffsetForPendingItemScroll,
           targetOffset <= 0.5 {
            HistoryScrollCoordinator.shared.saveOffset(0)
        }
        scheduleSecondPendingItemScrollIfNeeded(id, targetOffset: targetOffset)
        if !viewportState.shouldResetHorizontalOffsetForPendingItemScroll,
           focusState.pendingLatestFocusItemID == id {
            focusState.pendingLatestFocusItemID = nil
            focusState.pendingLatestFocusTimestamp = nil
            focusState.pendingLatestFocusReason = nil
            focusState.pendingLatestFocusLockID = nil
        }
        return true
    }

    private func applyPendingProgrammaticJumpIfPossible() {
        guard let id = focusState.pendingProgrammaticJumpItemID,
              selectedItemID == id,
              containsFilteredItem(id) else {
            return
        }

        if focusState.pendingLatestFocusLockID == id,
           let targetOffset = latestClipboardFocusTargetOffset(for: id) {
            HistoryScrollCoordinator.shared.scrollToOffset(
                targetOffset,
                animated: viewportState.shouldAnimatePendingItemScroll,
                suppressUserOffsetSave: true
            )
            if targetOffset <= 0.5 {
                HistoryScrollCoordinator.shared.saveOffset(0)
            }
            focusState.pendingProgrammaticJumpItemID = nil
            viewportState.pendingItemScrollID = nil
            viewportState.pendingItemScrollRetryCount = 0
            viewportState.shouldResetHorizontalOffsetForPendingItemScroll = false
            viewportState.shouldAnimatePendingItemScroll = false
            viewportState.isPreparingPendingItemScrollMeasurement = false
            finishLatestFocusIfSettled(id, targetOffset: targetOffset)
            return
        }

        guard let targetOffset = programmaticJumpTargetOffset(for: id) else {
            if let frame = cardDocumentFrame(for: id),
               isFrameFullyVisible(frame) {
                focusState.pendingProgrammaticJumpItemID = nil
                viewportState.pendingItemScrollID = nil
                viewportState.pendingItemScrollRetryCount = 0
                viewportState.shouldAnimatePendingItemScroll = false
                viewportState.isPreparingPendingItemScrollMeasurement = false
                finishLatestFocusIfNeeded(id)
            }
            return
        }

        if let visibleRect = HistoryScrollCoordinator.shared.visibleDocumentRect,
           abs(visibleRect.minX - targetOffset) <= 0.5 {
            focusState.pendingProgrammaticJumpItemID = nil
            viewportState.pendingItemScrollID = nil
            viewportState.pendingItemScrollRetryCount = 0
            viewportState.shouldResetHorizontalOffsetForPendingItemScroll = false
            viewportState.shouldAnimatePendingItemScroll = false
            viewportState.isPreparingPendingItemScrollMeasurement = false
            if focusState.pendingLatestFocusItemID == id {
                focusState.pendingLatestFocusItemID = nil
                focusState.pendingLatestFocusTimestamp = nil
                focusState.pendingLatestFocusReason = nil
                focusState.pendingLatestFocusLockID = nil
            }
            return
        }

        HistoryScrollCoordinator.shared.scrollToOffset(
            targetOffset,
            animated: false,
            suppressUserOffsetSave: focusState.pendingLatestFocusLockID == id
        )
        focusState.pendingProgrammaticJumpItemID = nil
        viewportState.pendingItemScrollID = nil
        viewportState.pendingItemScrollRetryCount = 0
        viewportState.shouldAnimatePendingItemScroll = false
        viewportState.isPreparingPendingItemScrollMeasurement = false
        if focusState.pendingLatestFocusItemID == id,
           !viewportState.shouldResetHorizontalOffsetForPendingItemScroll {
            focusState.pendingLatestFocusItemID = nil
            focusState.pendingLatestFocusTimestamp = nil
            focusState.pendingLatestFocusReason = nil
            focusState.pendingLatestFocusLockID = nil
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
            measuredFrame: viewportState.cardViewportFrames[id],
            documentFrame: cardDocumentFrame(for: id),
            currentOffset: HistoryScrollCoordinator.shared.currentOffset,
            cardRailTopInWindow: viewportState.cardRailTopInWindow,
            selectedCardTopContentInset: selectedCardTopContentInset
        )
    }

    private func focusedItemLeadingX(
        for id: HistoryPreviewItem.ID,
        frame: CGRect,
        forceEdgePeekAlignment: Bool? = nil
    ) -> CGFloat {
        if forceEdgePeekAlignment ?? viewportState.shouldResetHorizontalOffsetForPendingItemScroll {
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
        if let pendingLatestFocusItemID = focusState.pendingLatestFocusItemID {
            retainedIDs.insert(pendingLatestFocusItemID)
        }
        if let pendingProgrammaticJumpItemID = focusState.pendingProgrammaticJumpItemID {
            retainedIDs.insert(pendingProgrammaticJumpItemID)
        }
        if let pendingItemScrollID = viewportState.pendingItemScrollID {
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
        let generation = statusState.show(text)
        GlobalStatusToastController.shared.show(text, relativeTo: hostWindow)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            _ = statusState.clearIfCurrent(generation: generation)
        }
    }

    private func copyStatus(for item: ClipboardItem) -> String {
        switch item.type {
        case .text:
            item.richTextFileName == nil ? L("已复制文本") : L("已复制富文本")
        case .link:
            L("已复制链接")
        case .image:
            L("已复制图片")
        case .color:
            L("已复制颜色")
        case .file:
            L("已复制文件引用")
        }
    }

    private func copyFallbackTextStatus(for item: ClipboardItem) -> String {
        switch item.type {
        case .file:
            L("文件不可用，已复制文件路径")
        default:
            copyStatus(for: item)
        }
    }

    private func copiedOnlyStatus(for item: ClipboardItem) -> String {
        switch item.type {
        case .text:
            item.richTextFileName == nil ? L("已复制文本，需授权后自动粘贴") : L("已复制富文本，需授权后自动粘贴")
        case .link:
            L("已复制链接，需授权后自动粘贴")
        case .image:
            L("已复制图片，需授权后自动粘贴")
        case .color:
            L("已复制颜色，需授权后自动粘贴")
        case .file:
            L("已复制文件引用，需授权后自动粘贴")
        }
    }

    private func copiedOnlyFallbackTextStatus(for item: ClipboardItem) -> String {
        switch item.type {
        case .file:
            L("文件不可用，已复制文件路径，需授权后自动粘贴")
        default:
            copiedOnlyStatus(for: item)
        }
    }

    private func pastedStatus(for item: ClipboardItem) -> String {
        switch item.type {
        case .text:
            item.richTextFileName == nil ? L("已粘贴文本到当前 App") : L("已粘贴富文本到当前 App")
        case .link:
            L("已粘贴链接到当前 App")
        case .image:
            L("已粘贴图片到当前 App")
        case .color:
            L("已粘贴颜色到当前 App")
        case .file:
            L("已粘贴文件引用到当前 App")
        }
    }

    private func pastedFallbackTextStatus(for item: ClipboardItem) -> String {
        switch item.type {
        case .file:
            L("文件不可用，已粘贴文件路径到当前 App")
        default:
            pastedStatus(for: item)
        }
    }

    private func toggleSearch() {
        if searchUIState.isVisible {
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
        let shouldFocusTextInput = searchUIState.clearText()
        isSearchFocused = shouldFocusTextInput
        inputState.setTextInputFocused(shouldFocusTextInput)
        restoreSelectionAfterClearingSearch(preferredID: fallbackID)
    }

    private func clearSearchTextAndFilters() {
        let startedAt = CFAbsoluteTimeGetCurrent()
        let fallbackID = selectedItemID
        let shouldFocusTextInput = searchUIState.clearTextAndFilters(trigger: "search.clearButton")
        isSearchFocused = shouldFocusTextInput
        inputState.setTextInputFocused(shouldFocusTextInput)
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
        searchUIState.close()
        inputState.setSearchVisible(false)
    }

    private func updateSearchFieldPresentation(isVisible: Bool) {
        searchVisibilityTask?.cancel()

        if isVisible {
            searchUIState.setFieldPresentationVisible(true)
            searchVisibilityTask = Task { @MainActor in
                await Task.yield()
                guard !Task.isCancelled, searchUIState.isVisible else {
                    return
                }
                searchUIState.finishFieldPresentationShow()
            }
        } else {
            searchUIState.setFieldPresentationVisible(false)
            searchVisibilityTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 120_000_000)
                guard !Task.isCancelled, !searchUIState.isVisible else {
                    return
                }
                searchUIState.finishFieldPresentationHide()
            }
        }
    }

    private func closeSearchFromOutsideClick() {
        guard searchUIState.isVisible else {
            return
        }

        guard !hasSearchContent else {
            return
        }

        closeSearch()
    }

    private func refreshSearchInteractionScreenFrames() {
        guard searchUIState.isVisible,
              let hostWindow else {
            viewportState.searchInteractionScreenFrames = []
            return
        }

        var frames: [CGRect] = []
        if let searchControlScreenFrame = viewportState.searchControlScreenFrame {
            frames.append(searchControlScreenFrame.standardized.insetBy(dx: -6, dy: -6))
        }

        for window in NSApp.windows where window.isVisible && window !== hostWindow {
            let className = String(describing: type(of: window))
            let isSearchRelatedPanel = className.contains("Popover") || window.level.rawValue >= NSWindow.Level.popUpMenu.rawValue
            if searchUIState.isFilterPanelPresented && isSearchRelatedPanel {
                frames.append(window.frame.insetBy(dx: -8, dy: -8))
            }
        }

        viewportState.searchInteractionScreenFrames = frames
    }

    private func clearAndCloseSearch() {
        let fallbackID = selectedItemID
        searchUIState.clearAndClose()
        restoreSelectionAfterClearingSearch(preferredID: fallbackID)
        closeSearch()
    }

    private func closeSearchForGroupNavigation() {
        guard searchUIState.isVisible || isSearchActive else {
            return
        }

        clearAndCloseSearch()
    }

    private func closeInactiveSearchBeforeHiding() {
        guard searchUIState.isVisible, !isSearchActive else {
            return
        }

        closeSearch()
    }

    private func openSearch() {
        let startedAt = CFAbsoluteTimeGetCurrent()
        groupUIState.selectedGroup = .all
        searchUIState.open(trigger: "search.toggleButton.open")
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
        searchUIState.pendingTrigger = "search.commandF"
        if !searchUIState.isVisible {
            openSearch()
        } else if searchUIState.isFilterPanelPresented {
            searchUIState.isFilterPanelPresented = false
            focusSearchField()
        } else {
            searchUIState.isFilterPanelPresented = true
        }
    }

    private func toggleSearchFilterPanel() {
        let startedAt = CFAbsoluteTimeGetCurrent()
        let willOpen = searchUIState.toggleFilterPanel(
            openTrigger: "filter.button.open",
            closeTrigger: "filter.button.close"
        )
        if searchUIState.isFilterPanelPresented {
            isSearchFocused = false
            inputState.setTextInputFocused(false)
        } else {
            focusSearchField()
        }
        recordHistoryInteraction(
            willOpen ? "filter.button.open" : "filter.button.close",
            startedAt: startedAt,
            metadata: [
                "hasFilters": "\(searchUIState.criteria.hasActiveFilters)",
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
        nextMetadata["searchVisible"] = "\(searchUIState.isVisible)"
        nextMetadata["filterPanelVisible"] = "\(searchUIState.isFilterPanelPresented)"
        nextMetadata["hasFilters"] = "\(searchUIState.criteria.hasActiveFilters)"
        nextMetadata["queryLength"] = "\(searchUIState.text.count)"
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
        previewItemsState.sourceAppIconFileNameByName[appName]
    }

    private func toggleSearchType(_ type: HistorySearchItemType) {
        let startedAt = CFAbsoluteTimeGetCurrent()
        searchUIState.toggleType(type)
        recordHistoryInteraction("filter.type.toggle", startedAt: startedAt, metadata: ["type": "\(type)"])
    }

    private func toggleSearchSourceApp(_ appName: String) {
        let startedAt = CFAbsoluteTimeGetCurrent()
        searchUIState.toggleSourceApp(appName)
        recordHistoryInteraction("filter.sourceApp.toggle", startedAt: startedAt, metadata: ["appName": appName])
    }

    private func toggleSearchDateRange(_ range: HistorySearchDateRange) {
        let startedAt = CFAbsoluteTimeGetCurrent()
        searchUIState.toggleDateRange(range)
        recordHistoryInteraction("filter.date.toggle", startedAt: startedAt, metadata: ["range": "\(range)"])
    }

    private func toggleSearchGroup(_ group: HistorySearchGroup) {
        let startedAt = CFAbsoluteTimeGetCurrent()
        searchUIState.toggleGroup(group)
        recordHistoryInteraction("filter.group.toggle", startedAt: startedAt, metadata: ["group": "\(group)"])
    }

    private func removeSearchToken(_ token: HistorySearchToken) {
        let startedAt = CFAbsoluteTimeGetCurrent()
        searchUIState.removeToken(token.kind)
        focusSearchField()
        recordHistoryInteraction("search.token.remove", startedAt: startedAt, metadata: ["token": token.title])
    }

    private func appendSearchTokenOrder(_ kind: HistorySearchTokenKind) {
        searchUIState.appendTokenOrder(kind)
    }

    private func removeSearchTokenOrder(_ kind: HistorySearchTokenKind) {
        searchUIState.removeTokenOrder(kind)
    }

    private func pruneSearchTokenOrder() {
        let activeKinds = Set(searchTokens.map(\.kind))
        searchUIState.pruneTokenOrder(activeKinds: activeKinds)
    }

    private func handleSearchTokenBackspace() {
        if let selectedSearchTokenKind = searchUIState.selectedTokenKind,
           let selectedToken = searchTokens.first(where: { $0.kind == selectedSearchTokenKind }) {
            removeSearchToken(selectedToken)
            return
        }

        guard let token = searchTokens.last else {
            return
        }

        searchUIState.selectedTokenKind = token.kind
        focusSearchField()
    }

    private func schedulePreviewItemsRebuild(from sourceItems: [ClipboardItem]) {
        let signatureStartedAt = CFAbsoluteTimeGetCurrent()
        let currentSourceSignature = previewItemsState.previewItemsSourceSignature
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
                resultCount: previewItemsState.allItems.count,
                metadata: [
                    "reason": "sourceGenerationUnchanged",
                    "cacheStored": "\(previewItemsState.previewItemCache.count)"
                ]
            )
            scheduleSearchUpdate(sourceItems: previewItemsState.allItems, immediate: true)
            convergeLatestClipboardFocusIfNeeded()
            HistoryWindowLifecycleDiagnostics.record(
                .openPreviewReady,
                itemCount: store.items.count,
                wasVisible: inputState.isWindowVisibleSnapshot,
                shouldAnimate: false,
                hasPendingFocus: focusState.pendingLatestFocusItemID != nil || focusState.pendingDefaultFocusOnShow,
                visibleItemCount: renderedWindowItems.count,
                previewItemCount: previewItemsState.allItems.count
            )
            return
        }

        previewBuildTask?.cancel()
        previewBuildGeneration &+= 1
        let generation = previewBuildGeneration
        let currentSelectedID = selectedItemID ?? rememberedSelectedItemUUID()
        let currentPreviewedItemID = previewState.itemID
        let currentLatestClipboardFocusGeneration = focusState.latestClipboardFocusGeneration
        let currentPreviewItemCache = previewItemsState.previewItemCache
        let currentPreviewItems = previewItemsState.allItems
        let retainedCacheIDs = retainedPreviewCacheIDs(for: sourceItems)

        previewBuildTask = Task {
            PerformanceDiagnosticsService.shared.recordResourceCheckpoint("preview.rebuild.start")
            let signatureTask = Task.detached(priority: .userInitiated) {
                try HistoryPreviewBuildCoordinator.previewSignatureUpdateCheckingCancellation(
                    sourceItems: sourceItems,
                    currentSourceSignature: currentSourceSignature
                )
            }
            let signatureUpdate: HistoryPreviewBuildCoordinator.PreviewSignatureUpdate
            do {
                signatureUpdate = try await withTaskCancellationHandler {
                    try await signatureTask.value
                } onCancel: {
                    signatureTask.cancel()
                }
            } catch {
                return
            }

            guard !Task.isCancelled else {
                return
            }
            guard signatureUpdate.hasChanges else {
                await MainActor.run {
                    guard HistoryPreviewBuildCoordinator.shouldApplyResult(
                        isTaskCancelled: Task.isCancelled,
                        generation: generation,
                        currentGeneration: previewBuildGeneration
                    ) else {
                        return
                    }
                    PerformanceDiagnosticsService.shared.record(
                        "preview.rebuild.skip",
                        category: "history",
                        durationMS: (CFAbsoluteTimeGetCurrent() - signatureStartedAt) * 1_000,
                        itemCount: sourceItems.count,
                        resultCount: previewItemsState.allItems.count,
                        metadata: [
                            "reason": "sourceSignatureUnchanged",
                            "cacheStored": "\(previewItemsState.previewItemCache.count)"
                        ]
                    )
                    scheduleSearchUpdate(sourceItems: previewItemsState.allItems, immediate: true)
                    convergeLatestClipboardFocusIfNeeded()
                    HistoryWindowLifecycleDiagnostics.record(
                        .openPreviewReady,
                        itemCount: store.items.count,
                        wasVisible: inputState.isWindowVisibleSnapshot,
                        shouldAnimate: false,
                        hasPendingFocus: focusState.pendingLatestFocusItemID != nil || focusState.pendingDefaultFocusOnShow,
                        visibleItemCount: renderedWindowItems.count,
                        previewItemCount: previewItemsState.allItems.count
                    )
                }
                return
            }

            let sourceSignature = signatureUpdate.sourceSignature
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

            let previewApplyDelayNanoseconds = await MainActor.run {
                HistoryWindowLifecycleScheduler.previewApplyDelayNanoseconds(
                    isOpenAnimationActive: inputState.isOpenAnimationActiveSnapshot
                )
            }
            if previewApplyDelayNanoseconds > 0 {
                await MainActor.run {
                    renderState.mark("preview-apply-deferred-for-open-animation")
                }
                try? await Task.sleep(nanoseconds: previewApplyDelayNanoseconds)
                guard !Task.isCancelled else {
                    return
                }
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
                let applySummary = HistoryWindowPreviewItemsState.rebuildApplySummary(
                    rebuildResult,
                    existingItemCount: currentPreviewItems.count
                )
                PerformanceDiagnosticsService.shared.record(
                    "preview.rebuild.background",
                    category: "history",
                    durationMS: applySummary.buildDurationMS,
                    itemCount: sourceItems.count,
                    resultCount: applySummary.resultCount,
                    metadata: [
                        "cacheHits": "\(applySummary.cacheHitCount)",
                        "cacheMisses": "\(applySummary.cacheMisses)",
                        "cacheStored": "\(applySummary.cacheStored)",
                        "mode": applySummary.mode.diagnosticsValue
                    ]
                )
                var transaction = Transaction()
                let shouldAnimateRebuild = inputState.isWindowPresentedSnapshot && shouldAnimateHistoryRailChange(
                    sourceItemCount: sourceItems.count,
                    renderedItemCount: applySummary.resultCount
                )
                if shouldAnimateRebuild {
                    transaction.animation = .easeOut(duration: focusState.pendingLatestFocusItemID != nil ? 0.30 : 0.18)
                } else {
                    transaction.disablesAnimations = true
                }
                let insertedEntranceID: ClipboardItem.ID?
                switch rebuildResult {
                case .prepend(let insertedItems, _, _, _, _)
                    where inputState.isWindowPresentedSnapshot && shouldAnimateRebuild:
                    insertedEntranceID = insertedItems.first?.id
                default:
                    insertedEntranceID = nil
                }

                withTransaction(transaction) {
                    previewItemsState.applyRebuildItems(rebuildResult)
                }
                if let insertedEntranceID {
                    playEntranceAnimation(for: insertedEntranceID)
                }
                let previewItemsForSearch = previewItemsState.allItems
                previewItemsState.applyRebuildMetadata(
                    applySummary,
                    sourceSignature: sourceSignature,
                    sourceGeneration: sourceGeneration
                )
                PerformanceDiagnosticsService.shared.record(
                    "preview.rebuild.apply",
                    category: "history",
                    durationMS: (CFAbsoluteTimeGetCurrent() - applyStartedAt) * 1_000,
                    itemCount: sourceItems.count,
                    resultCount: previewItemsForSearch.count,
                    metadata: [
                        "animated": "\(shouldAnimateRebuild)",
                        "cacheHits": "\(applySummary.cacheHitCount)",
                        "cacheStored": "\(applySummary.cacheStored)",
                        "mode": applySummary.mode.diagnosticsValue
                    ]
                )
                renderState.mark("preview-items-ready count=\(previewItemsForSearch.count)")
                HistoryWindowLifecycleDiagnostics.record(
                    .openPreviewReady,
                    itemCount: sourceItems.count,
                    wasVisible: inputState.isWindowVisibleSnapshot,
                    shouldAnimate: shouldAnimateRebuild,
                    hasPendingFocus: focusState.pendingLatestFocusItemID != nil || focusState.pendingDefaultFocusOnShow,
                    visibleItemCount: renderedWindowItems.count,
                    previewItemCount: previewItemsForSearch.count
                )
                normalizeHiddenWindowFrameAfterPreviewWarmIfNeeded()

                scheduleSearchUpdate(sourceItems: previewItemsForSearch, immediate: true)
                if focusState.pendingLatestFocusItemID == nil,
                   currentLatestClipboardFocusGeneration == focusState.latestClipboardFocusGeneration {
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
        previewItemsState.canSkipPreviewRebuild(sourceItems: sourceItems, sourceGeneration: sourceGeneration)
    }

    private func normalizeHiddenWindowFrameAfterPreviewWarmIfNeeded() {
        guard !inputState.isWindowVisibleSnapshot,
              let hostWindow else {
            return
        }

        let normalizedFrame = HistoryWindowHiddenFrameNormalizer.normalizedFrame(
            currentFrame: hostWindow.frame,
            targetHeight: hiddenHistoryPanelHeight
        )
        guard normalizedFrame != hostWindow.frame else {
            return
        }

        hostWindow.setFrame(normalizedFrame, display: false)
        renderState.mark("hidden-frame-normalized")
    }

    private func scheduleSearchUpdate(
        immediate: Bool = false,
        debounceNanoseconds: UInt64 = 90_000_000
    ) {
        scheduleSearchUpdate(
            sourceItems: previewItemsState.allItems,
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
        let currentSearchTrigger = searchUIState.pendingTrigger
        searchUIState.pendingTrigger = "stateChange"
        guard let request = searchCoordinator.prepareSearch(
            sourceItems: sourceItems,
            selectedGroup: groupUIState.selectedGroup,
            isSearchVisible: searchUIState.isVisible,
            searchText: searchUIState.text,
            criteria: searchUIState.criteria,
            trigger: currentSearchTrigger,
            pageSize: searchResultPageSize,
            targetResultCount: historyRailRenderedItemLimit
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
                hasPendingLatestFocus: focusState.pendingLatestFocusItemID != nil,
                hasPendingDefaultFocus: focusState.pendingDefaultFocusOnShow,
                hasPendingPastedFocus: focusState.pendingPastedItemFocusOnNextShow != nil
            ) {
                applySearchSelectionAndViewport(isSearchActive: request.isSearchActive)
            }
            PerformanceDiagnosticsService.shared.record(
                "search.applyResults",
                category: "search",
                durationMS: (CFAbsoluteTimeGetCurrent() - applyStartedAt) * 1_000,
                itemCount: sourceItems.count,
                resultCount: previewItemsState.allItems.count,
                metadata: [
                    "queryLength": "\(request.searchText.count)",
                    "hasFilters": "\(request.criteria.hasActiveFilters)",
                    "mode": "unfilteredSource",
                    "trigger": request.trigger
                ]
            )
            renderState.markAndFinish("filtered-items-ready count=\(previewItemsState.allItems.count)")
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
                resultCount: previewItemsState.allItems.count,
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
                    transaction.animation = .easeOut(duration: focusState.pendingLatestFocusItemID != nil ? 0.30 : 0.16)
                } else {
                    transaction.disablesAnimations = true
                }
                withTransaction(transaction) {
                    applyFilteredPreviewResult(result)
                    if HistoryOrdinarySelectionRestorePolicy.canRestore(
                        hasPendingLatestFocus: focusState.pendingLatestFocusItemID != nil,
                        hasPendingDefaultFocus: focusState.pendingDefaultFocusOnShow,
                        hasPendingPastedFocus: focusState.pendingPastedItemFocusOnNextShow != nil
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
            existingItems: previewItemsState.filteredItems,
            selectedGroup: groupUIState.selectedGroup,
            isSearchVisible: searchUIState.isVisible,
            searchText: searchUIState.text,
            criteria: searchUIState.criteria,
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
        focusState.pendingKeyboardFocusItemID = nil
        focusState.pendingProgrammaticJumpItemID = nil
        viewportState.pendingItemScrollID = nil
        viewportState.pendingItemScrollRetryCount = 0
        viewportState.shouldResetHorizontalOffsetForPendingItemScroll = false
        viewportState.shouldAnimatePendingItemScroll = false
        viewportState.isPreparingPendingItemScrollMeasurement = false
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
        let previousObservation = focusState.latestObservation
        let currentObservation = latestItemObservation(sourceItems: sourceItems)
        let changedItem = LatestItemObservation.changedItem(
            previous: previousObservation,
            current: currentObservation,
            sourceItems: sourceItems
        )
        let focusCandidateID = changedItem?.id ?? focusState.pendingNewestItemIDForNextShow
        let focusCandidateTimestamp = changedItem?.createdAt ?? focusCandidateID.flatMap { id in
            sourceItems.first(where: { $0.id == id })?.createdAt
        }
        let focusReason = changedItem?.reason ?? .refreshed
        defer {
            focusState.latestPresentedItemTimestamp = newestTimestamp
            focusState.latestObservation = currentObservation
        }

        guard let focusCandidateID else {
            return
        }

        focusState.pendingNewestItemIDForNextShow = nil
        resetFiltersForLatestItemFocus()
        focusState.latestClipboardFocusGeneration &+= 1
        selectedItemID = focusCandidateID
        focusState.pendingLatestFocusItemID = focusCandidateID
        focusState.pendingLatestFocusTimestamp = focusCandidateTimestamp
        focusState.pendingLatestFocusReason = focusReason
        focusState.pendingLatestFocusLockID = focusCandidateID
        viewportState.shouldResetHorizontalOffsetForPendingItemScroll = true
        HistoryScrollCoordinator.shared.discardSavedOffset(for: HistoryGroupSelection.all.storageValue)
        resetVisibleRailWindowForLatestFocus(focusCandidateID)
        fulfillPendingLatestFocusIfPossible()
        if focusReason == .inserted {
            playEntranceAnimationSoon(for: focusCandidateID)
        }
    }

    private func focusRecentlyAddedItemOnShowIfNeeded(sourceItems: [ClipboardItem]) {
        guard inputState.isWindowPresentedSnapshot,
              focusState.pendingLatestFocusItemID == nil,
              let newestChangedItem = latestPresentationCandidate(from: sourceItems),
              newestChangedItem.createdAt > focusState.latestPresentedItemTimestamp.addingTimeInterval(0.001) else {
            return
        }

        resetFiltersForLatestItemFocus()
        focusState.latestClipboardFocusGeneration &+= 1
        selectedItemID = newestChangedItem.id
        focusState.pendingLatestFocusItemID = newestChangedItem.id
        focusState.pendingLatestFocusTimestamp = newestChangedItem.createdAt
        focusState.pendingLatestFocusReason = focusState.latestObservation?.id == newestChangedItem.id ? .refreshed : .inserted
        focusState.pendingLatestFocusLockID = newestChangedItem.id
        viewportState.shouldResetHorizontalOffsetForPendingItemScroll = true
        HistoryScrollCoordinator.shared.discardSavedOffset(for: HistoryGroupSelection.all.storageValue)
        resetVisibleRailWindowForLatestFocus(newestChangedItem.id)
        fulfillPendingLatestFocusIfPossible()
        playEntranceAnimationSoon(for: newestChangedItem.id)
    }

    private func convergeLatestClipboardFocusIfNeeded() {
        guard focusState.pendingLatestFocusItemID != nil,
              let newestChangedItem = latestChangedFocusItemCandidate() else {
            return
        }

        if focusState.pendingLatestFocusItemID != newestChangedItem.id,
           containsFilteredItem(newestChangedItem.id) {
            focusState.pendingLatestFocusItemID = newestChangedItem.id
            focusState.pendingLatestFocusTimestamp = newestChangedItem.createdAt
            focusState.pendingLatestFocusReason = .refreshed
            focusState.pendingLatestFocusLockID = newestChangedItem.id
            viewportState.shouldResetHorizontalOffsetForPendingItemScroll = true
            resetVisibleRailWindowForLatestFocus(newestChangedItem.id)
        }

        fulfillPendingLatestFocusIfPossible()
    }

    private func latestChangedFocusItemCandidate() -> ClipboardItem? {
        let newestByTimestamp = latestPresentationCandidate(from: store.items)

        guard let pendingLatestFocusTimestamp = focusState.pendingLatestFocusTimestamp,
              let newestByTimestamp,
              newestByTimestamp.createdAt > pendingLatestFocusTimestamp.addingTimeInterval(0.001) else {
            return focusState.pendingLatestFocusItemID.flatMap { store.item(with: $0) } ?? newestByTimestamp
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
        guard let pendingLatestFocusItemID = focusState.pendingLatestFocusItemID,
              containsFilteredItem(focusState.pendingLatestFocusItemID) else {
            return
        }

        selectedItemID = focusState.pendingLatestFocusItemID
        focusState.latestPresentedItemID = focusState.pendingLatestFocusItemID
        focusState.latestPresentedItemTimestamp = filteredItem(for: focusState.pendingLatestFocusItemID)?.createdAt ?? focusState.latestPresentedItemTimestamp

        if previewState.isVisible {
            showPreview(focusState.pendingLatestFocusItemID)
        }

        scheduleLatestProgrammaticTransition(
            to: pendingLatestFocusItemID,
            reason: focusState.pendingLatestFocusReason,
            resetToAll: viewportState.shouldResetHorizontalOffsetForPendingItemScroll,
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
        focusState.scheduleProgrammaticJump(to: id, reason: reason)
        viewportState.shouldResetHorizontalOffsetForPendingItemScroll = resetToAll
        viewportState.shouldAnimatePendingItemScroll = animateWhenPresented && inputState.isWindowPresentedSnapshot
        if resetToAll {
            HistoryScrollCoordinator.shared.discardSavedOffset(for: HistoryGroupSelection.all.storageValue)
        }
        resetVisibleRailWindowForLatestFocus(id)
        scrollToItemWhenRendered(id, animated: viewportState.shouldAnimatePendingItemScroll)
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
                      focusState.pendingLatestFocusItemID == id,
                      selectedItemID == id,
                      containsFilteredItem(id) else {
                    return
                }

                HistoryScrollCoordinator.shared.forceLayout()
                focusState.pendingProgrammaticJumpItemID = id
                scrollToItemWhenRendered(id, animated: false)
                attemptsRemaining -= 1
            }

            latestFocusRetryTask = nil
        }
    }

    private func finishLatestFocusIfNeeded(_ id: HistoryPreviewItem.ID) {
        guard focusState.finishLatestFocusIfNeeded(id) else {
            return
        }

        viewportState.shouldResetHorizontalOffsetForPendingItemScroll = false
        latestFocusRetryTask?.cancel()
        latestFocusRetryTask = nil
    }

    private func finishLatestFocusIfSettled(_ id: HistoryPreviewItem.ID, targetOffset: CGFloat) {
        guard let visibleRect = HistoryScrollCoordinator.shared.visibleDocumentRect,
              abs(visibleRect.minX - targetOffset) <= 0.5 else {
            focusState.pendingProgrammaticJumpItemID = id
            scrollToItemWhenRendered(id, animated: false)
            retryPendingLatestFocusJumpIfNeeded(id, remainingAttempts: 4)
            return
        }

        finishLatestFocusIfNeeded(id)
    }

    private func primeLatestItemPresentationGuard(sourceItems: [ClipboardItem]) {
        let observation = latestItemObservation(sourceItems: sourceItems)
        focusState.primeLatestPresentationGuard(
            observation: observation,
            timestamp: sourceItems.first?.createdAt
        )
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
        guard focusState.pendingLatestFocusItemID == nil else {
            return
        }

        if isSearchFocused || inputState.isTextInputFocusedSnapshot {
            isSearchFocused = false
            inputState.setTextInputFocused(false)
        }
        searchUIState.hasHandedOffFocusToCard = false
        inputState.setSearchHasHandedOffFocusToCard(false)

        clearPendingHistoryRailJumpState()
        focusState.pendingDefaultFocusOnShow = true
        if request.resetToFirst {
            viewportState.didRestoreRememberedViewport = true
            HistoryScrollCoordinator.shared.discardSavedOffset(for: groupUIState.selectedGroup.storageValue)
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
        guard focusState.pendingDefaultFocusOnShow,
              focusState.pendingLatestFocusItemID == nil else {
            return
        }

        if let pastedID = focusState.pendingPastedItemFocusOnNextShow {
            guard containsFilteredItem(pastedID) else {
                return
            }

            selectedItemID = pastedID
            if filteredItems.first?.id == pastedID {
                focusState.pendingPastedItemFocusOnNextShow = nil
                focusState.pendingDefaultFocusOnShow = false
            }
            return
        }

        guard let targetID = filteredItems.first?.id else {
            selectedItemID = nil
            return
        }

        selectedItemID = targetID
        focusState.pendingDefaultFocusOnShow = false
    }

    private func prepareLatestItemFocus(
        itemID: ClipboardItem.ID,
        timestamp: Date?,
        reason: ClipboardItemFocusRequest.Reason?,
        resetToAll: Bool
    ) {
        if resetToAll, groupUIState.selectedGroup != .all {
            groupUIState.selectedGroup = .all
            rememberSelectedGroup()
            HistoryScrollCoordinator.shared.setScope(groupUIState.selectedGroup.storageValue)
        }
        if resetToAll, searchUIState.isVisible || isSearchActive {
            searchUIState.text = ""
            searchUIState.criteria = HistorySearchCriteria()
            searchUIState.selectedTokenKind = nil
            searchUIState.isVisible = false
            isSearchFocused = false
            inputState.setSearchVisible(false)
            inputState.setTextInputFocused(false)
        }

        selectedItemID = itemID
        focusState.prepareLatestFocus(itemID: itemID, timestamp: timestamp, reason: reason)
        viewportState.shouldResetHorizontalOffsetForPendingItemScroll = resetToAll
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
        viewportState.pendingItemScrollID = id
        viewportState.pendingItemScrollRetryCount = 0
        viewportState.shouldAnimatePendingItemScroll = focusState.pendingProgrammaticJumpItemID == id ? animated : (animated || id == focusState.pendingLatestFocusItemID)

        Task { @MainActor in
            await Task.yield()
            guard viewportState.pendingItemScrollID == id,
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
            viewportState.itemScrollRequestID = UUID()
        }
    }

    private func scheduleSecondPendingItemScrollIfNeeded(_ id: HistoryPreviewItem.ID, targetOffset: CGFloat) {
        guard viewportState.shouldResetHorizontalOffsetForPendingItemScroll else {
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
                    suppressUserOffsetSave: focusState.pendingLatestFocusLockID == id
                )
                if refreshedTargetOffset <= 0.5 {
                    HistoryScrollCoordinator.shared.saveOffset(0)
                }
            }

            if focusState.pendingLatestFocusItemID == id,
               viewportState.pendingItemScrollID == nil {
                focusState.pendingLatestFocusItemID = nil
                focusState.pendingLatestFocusTimestamp = nil
                focusState.pendingLatestFocusReason = nil
                focusState.pendingLatestFocusLockID = nil
                viewportState.shouldResetHorizontalOffsetForPendingItemScroll = false
            }
        }
    }

    private func resetFiltersForLatestItemFocus() {
        if groupUIState.selectedGroup != .all {
            groupUIState.selectedGroup = .all
            rememberSelectedGroup()
        }

        guard searchUIState.isVisible || isSearchActive else {
            return
        }

        searchUIState.text = ""
        searchUIState.criteria = HistorySearchCriteria()
        searchUIState.selectedTokenKind = nil
        searchUIState.isVisible = false
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
            pendingPastedID: focusState.pendingPastedItemFocusOnNextShow,
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
                didRestoreRememberedViewport: viewportState.didRestoreRememberedViewport,
                hasPendingLatestFocus: focusState.pendingLatestFocusItemID != nil,
                hasPendingDefaultFocus: focusState.pendingDefaultFocusOnShow,
                hasPendingPastedFocus: focusState.pendingPastedItemFocusOnNextShow != nil,
                hasRememberedSelection: true
              ),
              containsFilteredItem(rememberedID) else {
            return
        }

        viewportState.didRestoreRememberedViewport = true
        selectedItemID = rememberedID
        HistoryScrollCoordinator.shared.restoreSavedOffset()
    }

    private func schedulePreheatVisibleAssets() {
        assetPreheater.schedule(
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
            showStatus(L("自动粘贴已启用"))
            return
        }

        accessibilityPermissionState.openSystemSettings()
        accessibilityPermissionState.refresh(promptIfNeeded: true)
        showStatus(L("请授权轻贴"))
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
        showStatus(inputState.isWindowPinnedOpen ? L("主窗口已钉住") : L("主窗口已取消钉住"))
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
        if groupUIState.renameTargetID != nil {
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
            return groupUIState.isIconSearchFocused
        case .appendSearchText, .beginComposedSearchInput, .copy, .copyPlainText, .paste, .pastePlainText, .togglePinned, .edit, .createText, .openSearch, .showSettings, .closeWindow, .toggleRecording:
            return true
        case .moveLeft, .moveRight, .togglePreview, .selectVisibleCard, .enterFirstSearchResult, .focusFirstSearchResult:
            return groupUIState.isIconSearchFocused
        }
    }

    private func appendSearchText(_ text: String) {
        if previewState.isVisible {
            closePreview()
        }

        if !searchUIState.isVisible {
            groupUIState.selectedGroup = .all
            searchUIState.isVisible = true
            inputState.setSearchVisible(true)
        }

        searchUIState.text += text
        focusSearchField()
    }

    private func beginComposedSearchInput(_ pendingEvent: HistoryKeyboardPendingTextInputEvent) {
        if previewState.isVisible {
            closePreview()
        }

        if !searchUIState.isVisible {
            groupUIState.selectedGroup = .all
            searchUIState.isVisible = true
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
                isSearchVisible: searchUIState.isVisible
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
                isSearchVisible: searchUIState.isVisible
            )
            return
        }

        if HistorySearchTextFirstResponderHandoffPolicy.shouldClearTextFirstResponder(
            isSearchFocused: isSearchFocused,
            isTextInputFocused: inputState.isTextInputFocusedSnapshot,
            hasSearchResult: true
        ) {
            hostWindow?.makeFirstResponder(nil)
        }

        selectedItemID = firstID
        applySearchFocusTransition(
            .focusFirstResult,
            hasSearchResult: true,
            isSearchVisible: searchUIState.isVisible
        )
        if previewState.isVisible {
            showPreview(firstID)
        }
    }

    private func focusSearchField() {
        searchUIState.hasHandedOffFocusToCard = false
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
        searchUIState.hasHandedOffFocusToCard = transition.searchHasHandedOffFocusToCard
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

        if searchUIState.isVisible {
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

        if searchUIState.isFilterPanelPresented {
            searchUIState.isFilterPanelPresented = false
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

        if groupUIState.groupPendingDeletion != nil {
            groupUIState.groupPendingDeletion = nil
            didClose = true
        }

        if groupUIState.isClearConfirmationPresented {
            groupUIState.isClearConfirmationPresented = false
            didClose = true
        }

        if groupUIState.renameTargetID != nil {
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

private struct SearchTextField: NSViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    @Binding var isComposing: Bool
    @Binding var pendingComposedInputEvent: HistoryKeyboardPendingTextInputEvent?
    let focusRequestID: Int
    let searchHasHandedOffFocusToCard: Bool
    let hasSearchResult: Bool
    let hasSearchTokens: Bool
    let textColor: NSColor
    let font: NSFont
    let onFocusChanged: (Bool) -> Void
    let onEnterFirstResult: () -> Void
    let onDeleteLastToken: () -> Void
    let onCancel: () -> Void
    let onReachLeadingContent: () -> Void
    let onReachTrailingContent: () -> Void

    func makeNSView(context: Context) -> SearchNSTextField {
        let textField = SearchNSTextField()
        textField.delegate = context.coordinator
        textField.coordinator = context.coordinator
        textField.isBordered = false
        textField.isBezeled = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.font = font
        textField.textColor = textColor
        textField.placeholderString = L("搜索")
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
        nsView.placeholderString = hasSearchTokens ? nil : L("搜索")

        if nsView.font != font {
            nsView.font = font
        }
        nsView.textColor = textColor

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
            case #selector(NSResponder.moveLeft(_:)):
                if textView.selectedRange().location == 0 {
                    DispatchQueue.main.async { [parent] in
                        parent.onReachLeadingContent()
                    }
                }
                return false
            case #selector(NSResponder.moveRight(_:)):
                let selection = textView.selectedRange()
                if selection.location + selection.length == (textView.string as NSString).length {
                    DispatchQueue.main.async { [parent] in
                        parent.onReachTrailingContent()
                    }
                }
                return false
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

    }
}

private struct GroupMouseDownObserver: NSViewRepresentable {
    let registry: HistoryGroupMouseMonitorRegistry
    let isEnabled: Bool
    let onMouseDown: () -> Void
    var onRightMouseDown: (() -> Void)?
    var onDoubleMouseDown: (() -> Void)?

    init(
        registry: HistoryGroupMouseMonitorRegistry,
        isEnabled: Bool,
        onMouseDown: @escaping () -> Void
    ) {
        self.registry = registry
        self.isEnabled = isEnabled
        self.onMouseDown = onMouseDown
        onRightMouseDown = nil
        onDoubleMouseDown = nil
    }

    init(
        registry: HistoryGroupMouseMonitorRegistry,
        isEnabled: Bool,
        onMouseDown: @escaping () -> Void,
        onRightMouseDown: (() -> Void)?,
        onDoubleMouseDown: (() -> Void)? = nil
    ) {
        self.registry = registry
        self.isEnabled = isEnabled
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
        context.coordinator.update(
            registry: registry,
            view: view,
            isEnabled: isEnabled,
            onMouseDown: onMouseDown,
            onRightMouseDown: onRightMouseDown,
            onDoubleMouseDown: onDoubleMouseDown
        )
        return view
    }

    func updateNSView(_ nsView: ObservingView, context: Context) {
        nsView.coordinator = context.coordinator
        context.coordinator.update(
            registry: registry,
            view: nsView,
            isEnabled: isEnabled,
            onMouseDown: onMouseDown,
            onRightMouseDown: onRightMouseDown,
            onDoubleMouseDown: onDoubleMouseDown
        )
    }

    static func dismantleNSView(_ nsView: ObservingView, coordinator: Coordinator) {
        coordinator.dismantle()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    @MainActor
    final class Coordinator {
        private let regionID = UUID()
        private weak var registry: HistoryGroupMouseMonitorRegistry?
        private var isDismantled = false

        func update(
            registry: HistoryGroupMouseMonitorRegistry,
            view: ObservingView,
            isEnabled: Bool,
            onMouseDown: @escaping () -> Void,
            onRightMouseDown: (() -> Void)?,
            onDoubleMouseDown: (() -> Void)?
        ) {
            guard !isDismantled else {
                return
            }

            if self.registry !== registry {
                self.registry?.unregister(id: regionID)
                self.registry = registry
            }
            registry.register(
                id: regionID,
                view: view,
                isEnabled: isEnabled,
                onMouseDown: onMouseDown,
                onRightMouseDown: onRightMouseDown,
                onDoubleMouseDown: onDoubleMouseDown
            )
        }

        func dismantle() {
            guard !isDismantled else {
                return
            }
            isDismantled = true
            registry?.unregister(id: regionID)
            registry = nil
        }
    }

    final class ObservingView: NSView {
        weak var coordinator: Coordinator?

        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }
    }
}

struct GroupRenameOutsideMouseDownObserver: NSViewRepresentable {
    let isEnabled: Bool
    let hostWindow: NSWindow?
    let excludedScreenFrame: CGRect?
    let onMouseDown: () -> Void

    func makeNSView(context: Context) -> ObservingView {
        let view = ObservingView()
        view.coordinator = context.coordinator
        context.coordinator.view = view
        context.coordinator.hostWindow = hostWindow
        context.coordinator.excludedScreenFrame = excludedScreenFrame
        context.coordinator.onMouseDown = onMouseDown
        context.coordinator.setEnabled(isEnabled)
        return view
    }

    func updateNSView(_ nsView: ObservingView, context: Context) {
        nsView.coordinator = context.coordinator
        context.coordinator.view = nsView
        context.coordinator.hostWindow = hostWindow
        context.coordinator.excludedScreenFrame = excludedScreenFrame
        context.coordinator.onMouseDown = onMouseDown
        context.coordinator.setEnabled(isEnabled)
    }

    static func dismantleNSView(_ nsView: ObservingView, coordinator: Coordinator) {
        coordinator.dismantle()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    @MainActor
    final class Coordinator {
        weak var view: ObservingView?
        private(set) var isEnabled = false
        weak var hostWindow: NSWindow?
        var excludedScreenFrame: CGRect?
        var onMouseDown: (() -> Void)?
        private let injectedMonitorLifecycle: HistoryEventMonitorLifecycle?
        private var isDismantled = false
        private lazy var monitorLifecycle = injectedMonitorLifecycle ?? HistoryEventMonitorLifecycle(
            install: { [weak self] in
                guard let self,
                      let monitor = NSEvent.addLocalMonitorForEvents(
                          matching: [.leftMouseDown, .rightMouseDown],
                          handler: { [weak self] event in
                              self?.handle(event)
                              return event
                          }
                      ) else {
                    return []
                }
                return [monitor]
            },
            remove: { monitor in
                NSEvent.removeMonitor(monitor)
            }
        )

        init(monitorLifecycle: HistoryEventMonitorLifecycle? = nil) {
            injectedMonitorLifecycle = monitorLifecycle
        }

        func setEnabled(_ enabled: Bool) {
            guard !isDismantled else {
                return
            }
            isEnabled = enabled
            monitorLifecycle.setEnabled(enabled)
        }

        func dismantle() {
            guard !isDismantled else {
                return
            }
            isDismantled = true
            isEnabled = false
            onMouseDown = nil
            excludedScreenFrame = nil
            hostWindow = nil
            view = nil
            monitorLifecycle.dismantle()
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

struct GroupAppearanceOutsideMouseDownObserver: NSViewRepresentable {
    let isEnabled: Bool
    let hostWindow: NSWindow?
    let popoverWindow: NSWindow?
    let onMouseDown: () -> Void

    func makeNSView(context: Context) -> ObservingView {
        let view = ObservingView()
        view.coordinator = context.coordinator
        context.coordinator.view = view
        context.coordinator.hostWindow = hostWindow
        context.coordinator.popoverWindow = popoverWindow
        context.coordinator.onMouseDown = onMouseDown
        context.coordinator.setEnabled(isEnabled)
        return view
    }

    func updateNSView(_ nsView: ObservingView, context: Context) {
        nsView.coordinator = context.coordinator
        context.coordinator.view = nsView
        context.coordinator.hostWindow = hostWindow
        context.coordinator.popoverWindow = popoverWindow
        context.coordinator.onMouseDown = onMouseDown
        context.coordinator.setEnabled(isEnabled)
    }

    static func dismantleNSView(_ nsView: ObservingView, coordinator: Coordinator) {
        coordinator.dismantle()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    @MainActor
    final class Coordinator {
        weak var view: ObservingView?
        private(set) var isEnabled = false
        weak var hostWindow: NSWindow?
        weak var popoverWindow: NSWindow?
        var onMouseDown: (() -> Void)?
        private let injectedMonitorLifecycle: HistoryEventMonitorLifecycle?
        private var isDismantled = false
        private lazy var monitorLifecycle = injectedMonitorLifecycle ?? HistoryEventMonitorLifecycle(
            requiredTokenCount: 2,
            install: { [weak self] in
                guard let self else {
                    return []
                }
                var monitors: [Any] = []
                if let localMonitor = NSEvent.addLocalMonitorForEvents(
                    matching: [.leftMouseDown, .rightMouseDown],
                    handler: { [weak self] event in
                        self?.handle(event)
                        return event
                    }
                ) {
                    monitors.append(localMonitor)
                }
                if let globalMonitor = NSEvent.addGlobalMonitorForEvents(
                    matching: [.leftMouseDown, .rightMouseDown],
                    handler: { [weak self] event in
                        Task { @MainActor [weak self] in
                            self?.handle(event)
                        }
                    }
                ) {
                    monitors.append(globalMonitor)
                }
                return monitors
            },
            remove: { monitor in
                NSEvent.removeMonitor(monitor)
            }
        )

        init(monitorLifecycle: HistoryEventMonitorLifecycle? = nil) {
            injectedMonitorLifecycle = monitorLifecycle
        }

        func setEnabled(_ enabled: Bool) {
            guard !isDismantled else {
                return
            }
            isEnabled = enabled
            monitorLifecycle.setEnabled(enabled)
        }

        func dismantle() {
            guard !isDismantled else {
                return
            }
            isDismantled = true
            isEnabled = false
            onMouseDown = nil
            popoverWindow = nil
            hostWindow = nil
            view = nil
            monitorLifecycle.dismantle()
        }

        @MainActor
        private func handle(_ event: NSEvent) {
            let role = eventWindowRole(for: event)
            handle(eventWindowRole: role)
        }

        func handle(eventWindowRole role: HistoryGroupAppearanceEventWindowRole) {
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

private struct HistoryRailControlButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HistoryRailControlButtonBody(configuration: configuration)
    }
}

private struct HistoryRailControlButtonBody: View {
    let configuration: HistoryRailControlButtonStyle.Configuration
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    var body: some View {
        let style = HistoryGlassToolbarControlPolicy.style
        let showsInteractiveMotion = !reduceMotion

        configuration.label
            .scaleEffect(
                showsInteractiveMotion
                    ? (configuration.isPressed ? style.pressedScale : (isHovered ? 1.01 : 1))
                    : 1
            )
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

struct MoreMenuButton: NSViewRepresentable {
    typealias MenuPresenter = @MainActor (NSMenu, NSButton) -> Void

    let menuProvider: () -> NSMenu

    func makeCoordinator() -> Coordinator {
        Coordinator(menuProvider: menuProvider)
    }

    func makeNSView(context: Context) -> NSButton {
        Self.makeButton(coordinator: context.coordinator)
    }

    static func makeButton(coordinator: Coordinator) -> NSButton {
        let button = NSButton(title: "", target: coordinator, action: #selector(Coordinator.openMenu(_:)))
        configure(button)
        coordinator.button = button
        return button
    }

    static func configure(_ button: NSButton) {
        button.title = ""
        button.image = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: L("更多操作"))
        button.imagePosition = .imageOnly
        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.font = .systemFont(ofSize: 14, weight: .semibold)
        button.alignment = .center
        button.focusRingType = .default
        button.refusesFirstResponder = false
        button.setButtonType(.momentaryChange)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.toolTip = L("更多操作")
        button.setAccessibilityLabel(L("更多操作"))
        button.setAccessibilityRole(.menuButton)
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.menuProvider = menuProvider
        Self.configure(button)
    }

    @MainActor
    final class Coordinator: NSObject {
        var menuProvider: () -> NSMenu
        let menuPresenter: MenuPresenter
        weak var button: NSButton?

        init(
            menuProvider: @escaping () -> NSMenu,
            menuPresenter: @escaping MenuPresenter = { menu, button in
                let point = NSPoint(x: 0, y: button.bounds.minY - 4)
                menu.popUp(positioning: nil, at: point, in: button)
            }
        ) {
            self.menuProvider = menuProvider
            self.menuPresenter = menuPresenter
        }

        @objc func openMenu(_ sender: NSButton) {
            let menu = menuProvider()
            menuPresenter(menu, sender)
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

struct NumberShortcutHandler: NSViewRepresentable {
    let inputState: HistoryWindowInputState
    let isEnabled: Bool
    let onCommandStateChange: (Bool) -> Void
    let onNumber: (Int) -> Void

    func makeNSView(context: Context) -> ShortcutNSView {
        let view = ShortcutNSView()
        view.inputState = inputState
        view.onCommandStateChange = onCommandStateChange
        view.onNumber = onNumber
        view.setEnabled(isEnabled)
        return view
    }

    func updateNSView(_ nsView: ShortcutNSView, context: Context) {
        nsView.inputState = inputState
        nsView.onCommandStateChange = onCommandStateChange
        nsView.onNumber = onNumber
        nsView.setEnabled(isEnabled)
    }

    static func dismantleNSView(_ nsView: ShortcutNSView, coordinator: ()) {
        nsView.dismantle()
    }

    final class ShortcutNSView: NSView {
        weak var inputState: HistoryWindowInputState?
        var onCommandStateChange: ((Bool) -> Void)?
        var onNumber: ((Int) -> Void)?
        private let injectedMonitorLifecycle: HistoryEventMonitorLifecycle?
        private var requestedEnabled = false
        private var isDismantled = false
        private lazy var monitorLifecycle = injectedMonitorLifecycle ?? HistoryEventMonitorLifecycle(
            requiredTokenCount: 2,
            install: { [weak self] in
                guard let self else {
                    return []
                }
                var monitors: [Any] = []
                if let keyMonitor = NSEvent.addLocalMonitorForEvents(
                    matching: .keyDown,
                    handler: { [weak self] event in
                        guard let self,
                              !self.isPreviewContentActive(),
                              self.window?.isKeyWindow == true,
                              !self.isHistoryTextInputActive(),
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
                ) {
                    monitors.append(keyMonitor)
                }
                if let flagsMonitor = NSEvent.addLocalMonitorForEvents(
                    matching: .flagsChanged,
                    handler: { [weak self] event in
                        guard let self,
                              !self.isPreviewContentActive(),
                              self.window?.isKeyWindow == true else {
                            self?.onCommandStateChange?(false)
                            return event
                        }

                        let isTextInputActive = self.isHistoryTextInputActive()
                        self.onCommandStateChange?(
                            event.modifierFlags.contains(.command) && !isTextInputActive
                        )
                        return event
                    }
                ) {
                    monitors.append(flagsMonitor)
                }
                return monitors
            },
            remove: { monitor in
                NSEvent.removeMonitor(monitor)
            }
        )

        init(monitorLifecycle: HistoryEventMonitorLifecycle? = nil) {
            injectedMonitorLifecycle = monitorLifecycle
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            nil
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            synchronizeMonitorLifecycle()
        }

        func setEnabled(_ enabled: Bool) {
            guard !isDismantled else {
                return
            }
            requestedEnabled = enabled
            synchronizeMonitorLifecycle()
        }

        func dismantle() {
            guard !isDismantled else {
                return
            }
            isDismantled = true
            requestedEnabled = false
            monitorLifecycle.dismantle()
            reportCommandStateChange(false, asynchronously: true)
            onCommandStateChange = nil
            onNumber = nil
            inputState = nil
        }

        private func synchronizeMonitorLifecycle() {
            let shouldEnable = requestedEnabled && window != nil && !isDismantled
            monitorLifecycle.setEnabled(shouldEnable)
            if !shouldEnable {
                reportCommandStateChange(false, asynchronously: true)
            }
        }

        private func reportCommandStateChange(_ isPressed: Bool, asynchronously: Bool) {
            guard asynchronously else {
                onCommandStateChange?(isPressed)
                return
            }

            let handler = onCommandStateChange
            DispatchQueue.main.async {
                handler?(isPressed)
            }
        }

        private func isPreviewContentActive() -> Bool {
            inputState?.isPreviewActiveSnapshot == true
        }

        private func isHistoryTextInputActive() -> Bool {
            inputState?.isHistoryTextInputActiveSnapshot == true || Self.isTextInputActive()
        }

        private static func isTextInputActive() -> Bool {
            guard let responder = NSApp.keyWindow?.firstResponder else {
                return false
            }

            return responder is NSTextView
        }
    }
}

struct CardRailScrollViewBinder: NSViewRepresentable {
    let onBind: () -> Void

    func makeNSView(context: Context) -> BindingView {
        let view = BindingView()
        view.onBind = onBind
        view.bindScrollViewSoon()
        return view
    }

    func updateNSView(_ nsView: BindingView, context: Context) {
        nsView.onBind = onBind
        nsView.bindScrollViewSoon()
    }

    final class BindingView: NSView {
        var onBind: (() -> Void)?
        private var isBindScheduled = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            bindScrollViewSoon()
        }

        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            bindScrollViewSoon()
        }

        override func layout() {
            super.layout()
            bindScrollViewSoon()
        }

        func bindScrollViewSoon() {
            guard !isBindScheduled else {
                return
            }

            isBindScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else {
                    return
                }

                self.isBindScheduled = false
                self.bindScrollViewIfNeeded()
            }
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
                MainActor.assumeIsolated {
                    scrollView.reflectScrolledClipView(clipView)
                    self.saveOffset(preserveSavedOffset ?? nextX)
                    if suppressUserOffsetSave {
                        self.pendingOffsetForNextBinding = nil
                    }
                    self.isProgrammaticScroll = false
                }
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

private struct SearchLeadingContentWidthPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct SearchInteractionFramePreferenceKey: PreferenceKey {
    static let defaultValue: [CGRect] = []

    static func reduce(value: inout [CGRect], nextValue: () -> [CGRect]) {
        value.append(contentsOf: nextValue())
    }
}

enum HistoryCardGeometryCollectionPolicy {
    static func trackedIDs(
        previewedID: HistoryPreviewItem.ID?,
        selectedID: HistoryPreviewItem.ID?,
        pendingScrollID: HistoryPreviewItem.ID?,
        pendingProgrammaticJumpID: HistoryPreviewItem.ID?
    ) -> Set<HistoryPreviewItem.ID> {
        Set([
            previewedID,
            selectedID,
            pendingScrollID,
            pendingProgrammaticJumpID
        ].compactMap { $0 })
    }

    static func shouldPublish(
        current: [HistoryPreviewItem.ID: CGRect],
        incoming: [HistoryPreviewItem.ID: CGRect],
        backingScaleFactor: CGFloat
    ) -> Bool {
        guard Set(current.keys) == Set(incoming.keys) else {
            return true
        }

        let onePhysicalPixel = 1 / max(abs(backingScaleFactor), 1)
        return incoming.contains { id, incomingFrame in
            guard let currentFrame = current[id] else {
                return true
            }

            return [
                abs(currentFrame.minX - incomingFrame.minX),
                abs(currentFrame.minY - incomingFrame.minY),
                abs(currentFrame.width - incomingFrame.width),
                abs(currentFrame.height - incomingFrame.height)
            ].contains { $0 >= onePhysicalPixel }
        }
    }
}

private struct CardViewportFrameReader: View {
    let itemID: HistoryPreviewItem.ID

    var body: some View {
        GeometryReader { proxy in
            Color.clear
                .preference(
                    key: CardViewportFramePreferenceKey.self,
                    value: [itemID: proxy.frame(in: .named("historyWindow"))]
                )
        }
    }
}

private struct CardViewportFramePreferenceKey: PreferenceKey {
    static let defaultValue: [HistoryPreviewItem.ID: CGRect] = [:]

    static func reduce(value: inout [HistoryPreviewItem.ID: CGRect], nextValue: () -> [HistoryPreviewItem.ID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
