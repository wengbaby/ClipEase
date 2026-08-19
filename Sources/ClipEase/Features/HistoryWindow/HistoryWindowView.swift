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
    @ObservedObject var appearanceSettings = AppearanceSettings.shared
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
    @State var searchUIState = HistoryWindowSearchUIState()
    @State var groupUIState = HistoryWindowGroupUIState()
    @State private var isCommandKeyPressed = false
    @State var isSearchFocused = false
    @State var isSearchTextComposing = false
    @State private var isSearchTextDrivenUpdate = false
    @State var appliedSearchQuery = ""
    @State var searchLeadingContentWidth: CGFloat = 0
    @State var searchTextInsertionIndex = Int.max
    @State var searchFocusRequestID = 0
    @State var pendingComposedSearchInputEvent: HistoryKeyboardPendingTextInputEvent?
    @State private var previewItemsState = HistoryWindowPreviewItemsState()
    @State private var previewBuildTask: Task<Void, Never>?
    @State private var previewBuildGeneration: UInt64 = 0
    @State private var deferredStartupTask: Task<Void, Never>?
    @State private var searchVisibilityTask: Task<Void, Never>?
    @State private var rememberSelectedItemTask: Task<Void, Never>?
    @State private var latestFocusRetryTask: Task<Void, Never>?
    @State private var hiddenResourceCheckpointTask: Task<Void, Never>?
    @State private var lastHiddenResourceCheckpointAt: CFAbsoluteTime = 0
    @State var viewportState = HistoryWindowViewportState()
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
    let selectedCardTopContentInset: CGFloat = HistoryWindowPanelMetrics.selectedCardTopContentInset

    var toolbarPrimaryForeground: Color {
        let opacity = 0.68 + glassEnvironment.toolbarTextContrast * 0.32
        return colorScheme == .dark ? .white.opacity(opacity) : .black.opacity(opacity)
    }

    var toolbarSecondaryForeground: Color {
        let opacity = 0.42 + glassEnvironment.toolbarTextContrast * 0.48
        return colorScheme == .dark ? .white.opacity(opacity) : .black.opacity(opacity)
    }

    var toolbarPrimaryNSColor: NSColor {
        let alpha = 0.68 + glassEnvironment.toolbarTextContrast * 0.32
        return (colorScheme == .dark ? NSColor.white : NSColor.black).withAlphaComponent(alpha)
    }

    private func selectedGroupFill(_ color: Color) -> Color {
        color.opacity(max(0.12, glassEnvironment.groupColorIntensity))
    }

    var titleTypography: AppearanceTypography { appearanceSettings.typography(for: .windowTitle) }
    var searchTypography: AppearanceTypography { appearanceSettings.typography(for: .search) }
    private var groupTypography: AppearanceTypography { appearanceSettings.typography(for: .group) }
    private var toolbarButtonTypography: AppearanceTypography { appearanceSettings.typography(for: .toolbarButton) }
    private let horizontalContentPadding: CGFloat = 28
    private let horizontalCardSpacing: CGFloat = 20
    let historyCardWidth: CGFloat = 250
    private let latestItemEntranceDuration: TimeInterval = 1.15
    let latestItemEntranceSheenDuration: TimeInterval = 1.8
    private let pendingItemScrollMaxRetryCount = 6
    private let largeHistoryAnimationThreshold = 2_000
    private let historyRailWindowBufferItemCount = 6
    private let historyRailRenderedItemLimit = 20
    private let previewItemCacheRetainedItemCount = 20
    private let searchResultPageSize = 50
    private let hiddenResourceCheckpointMinimumInterval: CFTimeInterval = 10
    private let hiddenHistoryPanelHeight: CGFloat = HistoryWindowPanelMetrics.height
    private let latestInsertedCardLeadingInset: CGFloat = 28

    var glassEnvironment: HistoryGlassEnvironment {
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

    var searchGlassSurfaceStyle: HistoryGlassSearchSurfaceStyle {
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

    var selectedItemID: HistoryPreviewItem.ID? {
        get { cardInteractionState.selectedItemID }
        nonmutating set { cardInteractionState.select(newValue) }
    }

    var trackedCardGeometryIDs: Set<HistoryPreviewItem.ID> {
        HistoryCardGeometryCollectionPolicy.trackedIDs(
            previewedID: previewState.isVisible ? previewState.itemID : nil,
            selectedID: selectedItemID,
            pendingScrollID: viewportState.pendingItemScrollID,
            pendingProgrammaticJumpID: focusState.pendingProgrammaticJumpItemID
        )
    }

    var enteringItemIDs: Set<ClipboardItem.ID> {
        get { cardInteractionState.enteringItemIDs }
        nonmutating set { cardInteractionState.enteringItemIDs = newValue }
    }

    private var enteringItemClearTask: Task<Void, Never>? {
        get { cardInteractionState.enteringItemClearTask }
        nonmutating set { cardInteractionState.enteringItemClearTask = newValue }
    }

    var entranceSheenItemIDs: Set<ClipboardItem.ID> {
        get { cardInteractionState.entranceSheenItemIDs }
        nonmutating set { cardInteractionState.entranceSheenItemIDs = newValue }
    }

    var entranceSheenStartTime: CFTimeInterval? {
        get { cardInteractionState.entranceSheenStartTime }
        nonmutating set { cardInteractionState.entranceSheenStartTime = newValue }
    }

    private var entranceSheenClearTask: Task<Void, Never>? {
        get { cardInteractionState.entranceSheenClearTask }
        nonmutating set { cardInteractionState.entranceSheenClearTask = newValue }
    }

    var hoveredCardID: HistoryPreviewItem.ID? {
        get { cardInteractionState.hoveredCardID }
        nonmutating set { cardInteractionState.hoveredCardID = newValue }
    }

    var pressedCardID: HistoryPreviewItem.ID? {
        get { cardInteractionState.pressedCardID }
        nonmutating set { cardInteractionState.pressedCardID = newValue }
    }

    private var items: [HistoryPreviewItem] {
        previewItemsState.allItems
    }

    var filteredItems: [HistoryPreviewItem] {
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

    var historyRailContentWidth: CGFloat {
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

    var renderedWindowItems: ArraySlice<HistoryPreviewItem> {
        RenderWindowCoordinator.renderedWindowItems(
            items: renderedItems,
            visibleWindow: historyRailVisibleWindow
        )
    }

    func requestNextHistoryPageIfNeeded() {
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

    var searchTokens: [HistorySearchToken] {
        HistorySearchToken.tokens(
            criteria: searchUIState.criteria,
            groups: store.groups
        )
    }

    var isSearchActive: Bool {
        searchUIState.isActive
    }

    var isSearchControlExpanded: Bool {
        searchUIState.shouldShowField
    }

    private var hasSearchContent: Bool {
        searchUIState.hasContent || !searchTokens.isEmpty
    }

    var canEditSelectedItemFromShortcut: Bool {
        guard !isTextInputActiveForEditShortcut,
              let selectedItemID,
              containsFilteredItem(selectedItemID),
              let item = store.item(with: selectedItemID) else {
            return false
        }

        return isEditable(item)
    }

    var shouldSuppressHistoryCommandShortcuts: Bool {
        isTextInputActiveForEditShortcut || inputState.isPreviewContentActive
    }

    var isShortcutOverlayVisible: Bool {
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
            isSearchTextDrivenUpdate = true
            scheduleSearchUpdate(debounceNanoseconds: isSearchTextComposing ? 300_000_000 : 200_000_000)
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

    func setCardHover(_ id: HistoryPreviewItem.ID, isHovered: Bool) {
        cardInteractionState.setHover(id, isHovered: isHovered)
    }

    func setCardPress(_ id: HistoryPreviewItem.ID, isPressed: Bool) {
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

    var allHistoryGroupButton: some View {
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

    var searchToggleButton: some View {
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

    var newGroupButton: some View {
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

    func systemGroupButton(_ group: SystemHistoryGroup) -> some View {
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
        GroupColorPanelSquare(color: color, iconName: iconName, onChange: onChange)
    }

    private func groupColorSwatches(onSelect: @escaping (Color) -> Void) -> some View {
        GroupColorSwatches(selectedColor: groupAppearanceColor, onSelect: onSelect)
    }

    func groupButton(_ group: ClipboardGroup, compact: Bool = false) -> some View {
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

    var resultCountBadge: some View {
        HistoryResultCountBadge(
            filteredCount: filteredItems.count,
            totalCount: items.count,
            foregroundStyle: toolbarSecondaryForeground
        )
    }

    var authorizationButton: some View {
        HistoryAuthorizationButton(action: openAccessibilitySettingsIfNeeded)
    }

    var searchFilterPanel: some View {
        SearchFilterPanelView(
            criteria: $searchUIState.criteria,
            isFilterPanelPresented: $searchUIState.isFilterPanelPresented,
            sourceAppFilterOptions: previewItemsState.sourceAppFilterOptions,
            systemGroups: SystemHistoryGroup.allCases,
            customGroups: store.groups,
            onClear: { searchUIState.criteria = HistorySearchCriteria() },
            onClose: { focusSearchField() },
            onToggleType: { toggleSearchType($0) },
            onToggleSourceApp: { toggleSearchSourceApp($0) },
            onToggleDateRange: { toggleSearchDateRange($0) },
            onToggleGroup: { toggleSearchGroup($0) },
            systemGroupIconName: { systemGroupIconName($0) }
        )
    }

    private func searchFilterSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        SearchFilterSection(title: title, content: content)
    }

    private func filterChipGrid<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        SearchFilterChipGrid(content: content)
    }

    private func searchFilterChip(
        title: String,
        systemImage: String? = nil,
        iconFileName: String? = nil,
        fallbackSystemImage: String = "circle",
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        SearchFilterChip(
            title: title,
            systemImage: systemImage,
            iconFileName: iconFileName,
            fallbackSystemImage: fallbackSystemImage,
            isSelected: isSelected,
            action: action
        )
    }

    @ViewBuilder
    private func cardContextMenu(for item: HistoryPreviewItem) -> some View {
        HistoryCardContextMenu(
            item: item,
            isEditable: isEditable(item),
            hasMoveToGroupSnapshot: !groupUIState.moveToGroupMenuSnapshot.isEmpty,
            sourceItem: store.item(with: item.id),
            sourceAppIgnoreTitle: store.item(with: item.id).map { sourceAppIgnoreMenuTitle(for: $0) } ?? "",
            onPaste: { pasteItem(item.id) },
            onPastePlainText: { pastePlainTextItem(item.id) },
            onPreview: { showPreview(item.id) },
            onEdit: { beginEditItem(item.id) },
            onTogglePinned: { togglePinned(item.id) },
            onPresentMoveToGroupPicker: { presentMoveToGroupPicker(for: item) },
            onRemoveFromGroup: { removeItemFromGroup(item.id) },
            onDelete: { deleteItem(item.id) },
            onToggleSourceAppIgnored: { toggleSourceAppIgnored(item.id) },
            onCopySourceAppName: { copySourceAppName(item.id) },
            onCopySourceBundleID: { copySourceBundleID(item.id) }
        ) {
            typeSpecificContextMenu(for: item)
        }
    }

    func cardMenu(for item: HistoryPreviewItem) -> NSMenu {
        let menu = NSMenu()

        HistoryMenuBuilder.addMenuItem(HistoryCommand.paste.title, to: menu) { pasteItem(item.id) }

        if item.type == .text || item.type == .link || item.type == .color {
            HistoryMenuBuilder.addMenuItem(HistoryCommand.pastePlainText.title, to: menu) { pastePlainTextItem(item.id) }
        }

        HistoryMenuBuilder.addMenuItem(HistoryCommand.preview.title, to: menu) { showPreview(item.id) }

        if isEditable(item) {
            HistoryMenuBuilder.addMenuItem(HistoryCommand.edit.title, to: menu) { beginEditItem(item.id) }
        }

        HistoryMenuBuilder.addMenuItem(item.isPinned ? L("取消置顶") : L("置顶"), to: menu) { togglePinned(item.id) }
        menu.addItem(.separator())

        addTypeSpecificMenuItems(for: item, to: menu)

        if !groupUIState.moveToGroupMenuSnapshot.isEmpty {
            HistoryMenuBuilder.addMenuItem(item.groupID == nil ? L("加入分组...") : L("移动到分组..."), to: menu) {
                presentMoveToGroupPicker(for: item)
            }
        }

        if item.groupID != nil {
            HistoryMenuBuilder.addMenuItem(L("移出分组"), to: menu) { removeItemFromGroup(item.id) }
        }

        HistoryMenuBuilder.addMenuItem(L("删除"), to: menu) { deleteItem(item.id) }

        if let sourceItem = store.item(with: item.id),
           sourceItem.sourceBundleID != nil {
            menu.addItem(.separator())
            if !sourceItem.isFromClipEase {
                HistoryMenuBuilder.addMenuItem(sourceAppIgnoreMenuTitle(for: sourceItem), to: menu) { toggleSourceAppIgnored(item.id) }
            }
            HistoryMenuBuilder.addMenuItem(L("复制来源 App 名称"), to: menu) { copySourceAppName(item.id) }
            HistoryMenuBuilder.addMenuItem(L("复制来源 Bundle ID"), to: menu) { copySourceBundleID(item.id) }
        }

        return menu
    }

    private func addTypeSpecificMenuItems(for item: HistoryPreviewItem, to menu: NSMenu) {
        switch item.type {
        case .link:
            HistoryMenuBuilder.addMenuItem(L("打开链接"), to: menu) { openLink(item.id) }
            HistoryMenuBuilder.addMenuItem(L("复制链接地址"), to: menu) { copyLinkURL(item.id) }
            HistoryMenuBuilder.addMenuItem(L("复制为 Markdown 链接"), to: menu) { copyMarkdownLink(item.id) }
            menu.addItem(.separator())
        case .color:
            HistoryMenuBuilder.addMenuItem(L("复制 HEX"), to: menu) { copyColorHex(item.id) }
            HistoryMenuBuilder.addMenuItem(L("复制 RGB"), to: menu) { copyColorRGB(item.id) }
            menu.addItem(.separator())
        case .image:
            HistoryMenuBuilder.addMenuItem(L("打开图片"), to: menu) { openImage(item.id) }
            HistoryMenuBuilder.addMenuItem(L("复制图像"), to: menu) { copyImage(item.id) }
            HistoryMenuBuilder.addMenuItem(L("复制图片路径"), to: menu) { copyImagePath(item.id) }
            HistoryMenuBuilder.addMenuItem(L("在 Finder 中显示"), to: menu) { revealImageInFinder(item.id) }
            menu.addItem(.separator())
        case .file:
            HistoryMenuBuilder.addMenuItem(L("打开文件"), to: menu) { openFile(item.id) }
            HistoryMenuBuilder.addMenuItem(L("复制文件"), to: menu) { copyFile(item.id) }
            HistoryMenuBuilder.addMenuItem(L("复制路径"), to: menu) { copyFilePaths(item.id) }
            HistoryMenuBuilder.addMenuItem(L("在 Finder 中显示"), to: menu) { revealFilesInFinder(item.id) }
            menu.addItem(.separator())
        case .text:
            break
        }
    }

    @ViewBuilder
    private func typeSpecificContextMenu(for item: HistoryPreviewItem) -> some View {
        HistoryTypeSpecificContextMenu(
            item: item,
            onOpenLink: openLink,
            onCopyLinkURL: copyLinkURL,
            onCopyMarkdownLink: copyMarkdownLink,
            onCopyColorHex: copyColorHex,
            onCopyColorRGB: copyColorRGB,
            onOpenImage: openImage,
            onCopyImage: copyImage,
            onCopyImagePath: copyImagePath,
            onRevealImageInFinder: revealImageInFinder,
            onOpenFile: openFile,
            onCopyFile: copyFile,
            onCopyFilePaths: copyFilePaths,
            onRevealFilesInFinder: revealFilesInFinder
        )
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
        MoveToGroupPickerView(
            target: target,
            groupEntries: groupUIState.moveToGroupMenuSnapshot,
            onMoveToGroup: { itemID, groupID, groupName in
                addItem(itemID, toGroup: groupID, named: groupName)
            },
            onRemoveFromGroup: { itemID in
                removeItemFromGroup(itemID)
            },
            onDismiss: {
                groupUIState.moveToGroupPickerTarget = nil
            }
        )
    }

    @ViewBuilder
    private func searchFilterChipIcon(
        systemImage: String?,
        iconFileName: String?,
        fallbackSystemImage: String
    ) -> some View {
        SearchFilterChipIcon(
            systemImage: systemImage,
            iconFileName: iconFileName,
            fallbackSystemImage: fallbackSystemImage
        )
    }

    var moreMenu: some View {
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

        HistoryMenuBuilder.addMenuItem(HistoryCommand.newText.title, to: menu) {
            createTextFromMenu()
        }

        menu.addItem(.separator())

        HistoryMenuBuilder.addMenuItem(HistoryCommand.help.title, to: menu) {
            appMenuController.showHelp()
        }

        HistoryMenuBuilder.addMenuItem(HistoryCommand.settings.title, to: menu) {
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

        HistoryMenuBuilder.addMenuItem(HistoryCommand.quit.title, to: menu) {
            appMenuController.quit()
        }

        HistoryMenuBuilder.addMenuItem(HistoryCommand.about.title, to: menu) {
            appMenuController.showAbout()
        }

        return menu
    }

    private func makePauseNSMenu() -> NSMenu {
        let menu = NSMenu()

        HistoryMenuBuilder.addMenuItem(recordingController.pauseMenuPrimaryTitle(), to: menu) {
            togglePauseFromMenu()
        }
        HistoryMenuBuilder.addMenuItem(L("暂停 15 分钟"), to: menu) {
            pauseRecording(for: 15 * 60, message: L("已暂停 15 分钟"))
        }
        HistoryMenuBuilder.addMenuItem(L("暂停 30 分钟"), to: menu) {
            pauseRecording(for: 30 * 60, message: L("已暂停 30 分钟"))
        }
        HistoryMenuBuilder.addMenuItem(L("暂停 1 小时"), to: menu) {
            pauseRecording(for: 60 * 60, message: L("已暂停 1 小时"))
        }
        HistoryMenuBuilder.addMenuItem(L("暂停 3 小时"), to: menu) {
            pauseRecording(for: 3 * 60 * 60, message: L("已暂停 3 小时"))
        }
        HistoryMenuBuilder.addMenuItem(L("暂停 6 小时"), to: menu) {
            pauseRecording(for: 6 * 60 * 60, message: L("已暂停 6 小时"))
        }
        HistoryMenuBuilder.addMenuItem(L("截止到今日"), to: menu) {
            appMenuController.pauseUntilEndOfToday()
        }

        return menu
    }

    private var retentionSettingsMenu: some View {
        HistoryRetentionSettingsMenu(store: store, onShowStatus: showStatus)
    }

    @ViewBuilder
    private var pauseMenu: some View {
        HistoryPauseMenu(
            primaryTitle: recordingController.pauseMenuPrimaryTitle(),
            onTogglePause: { togglePauseFromMenu() },
            onPauseFor: { duration, message in
                pauseRecording(for: duration, message: message)
            },
            onPauseUntilEndOfToday: {
                appMenuController.pauseUntilEndOfToday()
            }
        )
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

    func shortcutNumber(for id: HistoryPreviewItem.ID) -> Int? {
        guard let index = filteredItems.prefix(9).firstIndex(where: { $0.id == id }) else {
            return nil
        }

        return filteredItems.distance(from: filteredItems.startIndex, to: index) + 1
    }

    func copyItem(_ id: ClipboardItem.ID?) {
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

    func copyPlainTextItem(_ id: ClipboardItem.ID?) {
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

    func pastePlainTextItem(_ id: ClipboardItem.ID?) {
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

    func pasteItem(_ id: ClipboardItem.ID?) {
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

    func showPreview(_ id: ClipboardItem.ID?) {
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

    func handleEditShortcut() {
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

    func deleteGroup(_ group: ClipboardGroup) {
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

    func togglePinned(_ id: ClipboardItem.ID?) {
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

    func selectCardForPrimaryClick(_ item: HistoryPreviewItem) {
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

    func selectCardForContextMenu(_ item: HistoryPreviewItem) {
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

    func blurSearchFieldForCardInteraction() {
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

    func cardDocumentX(for id: HistoryPreviewItem.ID) -> CGFloat {
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

    func updateCardRailVisibleRect() {
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

    func showStatus(_ text: String) {
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

    func clearSearchTextAndFilters() {
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

    func refreshSearchInteractionScreenFrames() {
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

    func handleCommandFSearch() {
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

    func toggleSearchFilterPanel() {
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

    func removeSearchToken(_ token: HistorySearchToken) {
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

    func handleSearchTokenBackspace() {
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
            appliedSearchQuery = request.searchText
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
                let isTextDriven = isSearchTextDrivenUpdate
                let shouldAnimateResults = !isTextDriven && inputState.isWindowPresentedSnapshot && shouldAnimateHistoryRailChange(
                    sourceItemCount: request.sourceItems.count,
                    renderedItemCount: result.items.count
                )
                if shouldAnimateResults {
                    transaction.animation = .easeOut(duration: focusState.pendingLatestFocusItemID != nil ? 0.30 : 0.16)
                } else {
                    transaction.disablesAnimations = true
                }
                if isTextDriven {
                    isSearchTextDrivenUpdate = false
                }
                withTransaction(transaction) {
                    appliedSearchQuery = request.searchText
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

    func toggleWindowPinnedOpen() {
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

    func handleSearchCancel() {
        switch HistorySearchCancelPolicy.action(hasSearchContent: hasSearchContent) {
        case .clearSearch:
            clearSearchTextAndFilters()
            focusSearchField()
        case .closeSearchAndFocusFirstResult:
            closeSearch()
            focusFirstSearchResultCard()
        }
    }

    func enterFirstSearchResultFromSearchField() {
        focusFirstSearchResultCard()
    }

    func synchronizeSearchTextFieldFocus(_ isFocused: Bool) {
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

    func focusSearchField() {
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

    func closeWindowFromShortcut() {
        closePreview()
        cancelPendingGroupRename()
        onClose()
    }

    func closeWindowForCardDrag() {
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

    func createTextFromShortcut() {
        onClose()
        onCreateText(selectedGroupID)
    }

    private func createTextFromMenu() {
        onClose()
        onCreateText(selectedGroupID)
    }

    func toggleRecordingFromShortcut() {
        toggleRecording()
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


