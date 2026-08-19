import AppKit
import Combine
import SwiftUI

@MainActor
protocol HistoryWindowEventMonitorBackend: AnyObject {
    func addGlobalMonitor(
        matching mask: NSEvent.EventTypeMask,
        handler: @escaping (NSEvent) -> Void
    ) -> Any?
    func addLocalMonitor(
        matching mask: NSEvent.EventTypeMask,
        handler: @escaping (NSEvent) -> NSEvent?
    ) -> Any?
    func removeMonitor(_ monitor: Any)
}

@MainActor
protocol HistoryWindowOpenAnimationCompletionDriver: AnyObject {
    func scheduleCompletion(_ completion: @escaping @MainActor () -> Void)
}

@MainActor
private final class SystemHistoryWindowEventMonitorBackend: HistoryWindowEventMonitorBackend {
    static let shared = SystemHistoryWindowEventMonitorBackend()

    private init() {}

    func addGlobalMonitor(
        matching mask: NSEvent.EventTypeMask,
        handler: @escaping (NSEvent) -> Void
    ) -> Any? {
        NSEvent.addGlobalMonitorForEvents(matching: mask, handler: handler)
    }

    func addLocalMonitor(
        matching mask: NSEvent.EventTypeMask,
        handler: @escaping (NSEvent) -> NSEvent?
    ) -> Any? {
        NSEvent.addLocalMonitorForEvents(matching: mask, handler: handler)
    }

    func removeMonitor(_ monitor: Any) {
        NSEvent.removeMonitor(monitor)
    }
}

@MainActor
final class HistoryWindowController: NSObject, NSWindowDelegate {
    private let panelHeight: CGFloat = HistoryWindowPanelMetrics.height
    private let panelAnimationDistance: CGFloat = HistoryWindowPanelMetrics.animationDistance
    private let panelAnimationDuration: TimeInterval = 0.22
    private var accessibilityDisplayOptionsObserver: NSObjectProtocol?
    private let store: ClipboardHistoryStore
    private let pasteExecutor: PasteExecutor
    private let accessibilityPermissionState: AccessibilityPermissionState
    private let recordingController: RecordingController
    private let appMenuController: AppMenuController
    private let previewWindowController: HistoryPreviewWindowController
    private let previewState = HistoryPreviewState()
    private let renderState = HistoryWindowRenderState()
    private let inputState: HistoryWindowInputState
    private let keyboardRouter = HistoryKeyboardActionRouter()
    private let keyboardEventTap: HistoryKeyboardEventTap
    private let eventMonitorBackend: any HistoryWindowEventMonitorBackend
    private let panelFactory: (() -> HistoryPanel)?
    private let openAnimationCompletionDriver: (any HistoryWindowOpenAnimationCompletionDriver)?
    private let setOCRInteractiveThrottleActive: (Bool) -> Void
    private let appearanceSettings: AppearanceSettings
    private var appearanceObservation: AnyCancellable?
    private var panel: HistoryPanel?
    private var outsideClickMonitor: Any?
    private var localOutsideClickMonitor: Any?
    private var isClosing = false
    private weak var previousFrontmostApplication: NSRunningApplication?
    private var lastKnownPanelFrame: NSRect?
    private var presentationRecoveryTask: Task<Void, Never>?
    private var contentLayerAnimationGeneration: UInt64 = 0
    private var isShutDown = false

    init(
        store: ClipboardHistoryStore,
        pasteExecutor: PasteExecutor,
        accessibilityPermissionState: AccessibilityPermissionState,
        recordingController: RecordingController,
        appMenuController: AppMenuController,
        inputState: HistoryWindowInputState? = nil,
        keyboardEventTapBackend: (any HistoryKeyboardEventTapBackend)? = nil,
        eventMonitorBackend: (any HistoryWindowEventMonitorBackend)? = nil,
        panelFactory: (() -> HistoryPanel)? = nil,
        openAnimationCompletionDriver: (any HistoryWindowOpenAnimationCompletionDriver)? = nil,
        setOCRInteractiveThrottleActive: ((Bool) -> Void)? = nil,
        appearanceSettings: AppearanceSettings = .shared
    ) {
        let resolvedInputState = inputState ?? HistoryWindowInputState()
        self.store = store
        self.pasteExecutor = pasteExecutor
        self.accessibilityPermissionState = accessibilityPermissionState
        self.recordingController = recordingController
        self.appMenuController = appMenuController
        self.previewWindowController = HistoryPreviewWindowController(
            clipboardWriter: .generalTextWriter(registerSelfWrite: { [weak store] changeCount, payload in
                store?.registerSelfWrite(changeCount: changeCount, payload: payload)
            })
        )
        self.inputState = resolvedInputState
        if let keyboardEventTapBackend {
            self.keyboardEventTap = HistoryKeyboardEventTap(
                inputState: resolvedInputState,
                backend: keyboardEventTapBackend
            )
        } else {
            self.keyboardEventTap = HistoryKeyboardEventTap(inputState: resolvedInputState)
        }
        self.eventMonitorBackend = eventMonitorBackend ?? SystemHistoryWindowEventMonitorBackend.shared
        self.panelFactory = panelFactory
        self.openAnimationCompletionDriver = openAnimationCompletionDriver
        self.setOCRInteractiveThrottleActive = setOCRInteractiveThrottleActive ?? { isActive in
            store.setOCRInteractiveThrottleActive(isActive)
        }
        self.appearanceSettings = appearanceSettings
        super.init()
        installAccessibilityDisplayOptionsObserver()
        appearanceObservation = appearanceSettings.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                self?.applyAppearancePreference()
            }
        }
    }

    func shutdown() {
        guard !isShutDown else {
            return
        }

        isShutDown = true
        removeAccessibilityDisplayOptionsObserver()
        appearanceObservation = nil
        presentationRecoveryTask?.cancel()
        presentationRecoveryTask = nil
        contentLayerAnimationGeneration &+= 1
        keyboardEventTap.stop()
        removeOutsideClickMonitor()
        closePreview()
        inputState.notifyWindowWillHide()
        panel?.orderOut(nil)
        panel?.hasShadow = false
        if let panel {
            resetHistoryContentLayerAnimationState(for: panel)
        }
        setHistoryContentRasterization(false, for: panel)
        setOCRInteractiveThrottleActive(false)
        isClosing = false
    }

    func preloadHistoryDataAfterLaunch() {
        guard !isShutDown else {
            return
        }

        guard HistoryWindowLifecycleScheduler.shouldRunLaunchPreload(
            hasPanel: panel != nil,
            isWindowVisible: inputState.isWindowVisibleSnapshot,
            isOpenAnimationActive: inputState.isOpenAnimationActiveSnapshot
        ) else {
            return
        }

        let panel = panel ?? makePanel()
        self.panel = panel
        let targetFrame = frameForPanel()
        let usesContentLayerAnimation = HistoryWindowLifecycleScheduler.shouldUseContentLayerAnimation(
            shouldAnimate: true
        )
        if HistoryWindowLifecycleScheduler.shouldKeepHiddenPanelAtTargetFrame(
            usesContentLayerAnimation: usesContentLayerAnimation
        ) {
            applyTargetFrameIfNeeded(to: panel, targetFrame: targetFrame)
        } else {
            applyHiddenFrameIfNeeded(to: panel, targetFrame: targetFrame)
        }
        renderState.prepareForPreload(itemCount: store.items.count)
        if HistoryWindowLifecycleScheduler.shouldPublishVisibleStateForLaunchPreload() {
            inputState.setWindowVisible(true)
        }
        inputState.setWindowPresented(false)
        PerformanceDiagnosticsService.shared.record(
            "history.preload.start",
            category: "history",
            durationMS: 0,
            itemCount: store.items.count,
            metadata: ["reason": "app.launch"]
        )
        renderState.mark("prepared")
        renderState.finishTrace()
    }

    func toggle() {
        guard !isShutDown else {
            return
        }

        if let panel,
           HistoryWindowLifecycleScheduler.shouldCloseOnToggle(
               isPanelOrdered: panel.isVisible,
               isWindowVisible: inputState.isWindowVisibleSnapshot
           ) {
            close()
            return
        }

        let shouldRefreshAccessibility = HistoryWindowLifecycleScheduler.shouldRefreshAccessibilityBeforeToggle(
            isWindowVisible: false
        )
        guard !shouldRefreshAccessibility || accessibilityPermissionState.refresh() else {
            appMenuController.showPermissionGuide()
            return
        }

        show(accessibilityAlreadyVerified: true)
    }

    func show(accessibilityAlreadyVerified: Bool = false) {
        guard !isShutDown else {
            return
        }

        if HistoryWindowLifecycleScheduler.shouldRefreshAccessibilityBeforeShow(
            alreadyVerified: accessibilityAlreadyVerified
        ) {
            guard accessibilityPermissionState.refresh() else {
                appMenuController.showPermissionGuide()
                return
            }
        }

        captureFrontmostApplicationIfNeeded()
        presentationRecoveryTask?.cancel()
        presentationRecoveryTask = nil
        let panel = panel ?? makePanel()
        self.panel = panel
        setHistoryContentRasterization(false, for: panel)
        resetHistoryContentLayerAnimationState(for: panel)
        isClosing = false
        let targetFrame = frameForPanel()
        lastKnownPanelFrame = targetFrame
        GlobalStatusToastController.shared.updateHistoryWindowFrame(targetFrame, screen: panel.screen ?? NSScreen.clipeaseScreenContainingMouse ?? NSScreen.main)
        appMenuController.setStatusToastAnchorWindow(panel)
        let wasVisible = panel.isVisible
        let shouldAnimate = !wasVisible
        let hasPendingFocus = store.latestItemFocusRequest != nil
        let latestFocusRequest = store.consumeLatestItemFocusRequest()
        let hadPendingExplicitOffset = HistoryScrollCoordinator.shared.hasPendingExplicitOffset
        let shouldUseContentLayerAnimation = HistoryWindowLifecycleScheduler.shouldUseContentLayerAnimation(
            shouldAnimate: shouldAnimate
        )
        inputState.setOpenAnimationActive(shouldAnimate)
        HistoryWindowLifecycleDiagnostics.record(
            .openRequest,
            itemCount: store.items.count,
            wasVisible: wasVisible,
            shouldAnimate: shouldAnimate,
            hasPendingFocus: hasPendingFocus
        )

        panel.hasShadow = false
        panel.alphaValue = 1
        panel.ignoresMouseEvents = false
        if shouldAnimate {
            renderState.prepareForShow(itemCount: store.items.count)
            if shouldUseContentLayerAnimation {
                applyTargetFrameIfNeeded(to: panel, targetFrame: targetFrame)
                prepareHistoryContentLayerForAnimatedOrdering(
                    panel,
                    initialTranslationY: -panelAnimationDistance
                )
            } else {
                applyHiddenFrameIfNeeded(to: panel, targetFrame: targetFrame)
                if HistoryWindowLifecycleScheduler.shouldPrepareContentLayerBeforeOrdering(
                    shouldAnimate: shouldAnimate
                ) {
                    prepareHistoryContentLayerForAnimatedOrdering(panel)
                }
            }
        } else {
            panel.disableScreenUpdatesUntilFlush()
            lockHistoryContentSize(for: panel, size: targetFrame.size)
            panel.setFrame(targetFrame, display: true)
        }
        renderState.mark("panel-frame-ready")

        if HistoryWindowLifecycleScheduler.shouldStartKeyboardEventTapBeforeOrdering(shouldAnimate: shouldAnimate) {
            keyboardEventTap.start()
            renderState.mark("keyboard-tap-ready-before-order")
        }
        panel.orderFrontRegardless()
        renderState.mark("panel-ordered")
        if HistoryWindowLifecycleScheduler.shouldMakeKeyBeforeAnimation(shouldAnimate: shouldAnimate) {
            panel.makeKey()
        }
        HistoryWindowLifecycleDiagnostics.record(
            .openOrdered,
            itemCount: store.items.count,
            wasVisible: wasVisible,
            shouldAnimate: shouldAnimate,
            hasPendingFocus: hasPendingFocus
        )

        if HistoryWindowLifecycleScheduler.shouldApplyPresentationStateBeforeAnimation(shouldAnimate: shouldAnimate) {
            applyOpenPresentationState(
                latestFocusRequest: latestFocusRequest,
                hadPendingExplicitOffset: hadPendingExplicitOffset,
                wasVisible: wasVisible,
                shouldAnimate: shouldAnimate
            )
        }

        guard shouldAnimate else {
            finishShowingWindow(shouldAnimate: shouldAnimate)
            return
        }

        let completeOpenAnimation: @MainActor (Bool) -> Void = { [weak self, weak panel] resetsContentLayerState in
            guard let self,
                  !self.isShutDown,
                  let panel else {
                return
            }

            if resetsContentLayerState {
                self.resetHistoryContentLayerAnimationState(for: panel)
            } else {
                self.setHistoryContentRasterization(false, for: panel)
            }
            panel.hasShadow = false
            panel.makeKey()
            self.renderState.mark("open-animation-complete")
            self.finishShowingWindow(shouldAnimate: shouldAnimate)
            self.applyOpenPresentationState(
                latestFocusRequest: latestFocusRequest,
                hadPendingExplicitOffset: hadPendingExplicitOffset,
                wasVisible: wasVisible,
                shouldAnimate: shouldAnimate
            )
        }

        if let openAnimationCompletionDriver {
            openAnimationCompletionDriver.scheduleCompletion {
                completeOpenAnimation(true)
            }
            return
        }

        if shouldUseContentLayerAnimation {
            contentLayerAnimationGeneration &+= 1
            let animationGeneration = contentLayerAnimationGeneration
            animateHistoryContentLayerTranslation(
                panel,
                from: -panelAnimationDistance,
                to: 0,
                key: "history.open.contentTranslation",
                generation: animationGeneration
            ) { [weak panel] in
                guard panel?.isVisible == true else {
                    return
                }
                completeOpenAnimation(true)
            }
            return
        }

        setHistoryContentRasterization(
            HistoryWindowLifecycleScheduler.shouldRasterizeContentDuringWindowAnimation(
                shouldAnimate: shouldAnimate
            ),
            for: panel
        )
        NSAnimationContext.runAnimationGroup { context in
            context.duration = panelAnimationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(targetFrame, display: false)
        } completionHandler: {
            Task { @MainActor [weak panel] in
                guard panel?.isVisible == true else {
                    return
                }
                completeOpenAnimation(false)
            }
        }
    }

    func close() {
        presentationRecoveryTask?.cancel()
        presentationRecoveryTask = nil
        let wasVisible = panel?.isVisible == true
        let shouldAnimate = wasVisible && !isClosing
        inputState.setOpenAnimationActive(false)
        HistoryWindowLifecycleDiagnostics.record(
            .closeRequest,
            itemCount: store.items.count,
            wasVisible: wasVisible,
            shouldAnimate: shouldAnimate,
            hasPendingFocus: false
        )
        renderState.finishTrace()
        guard let panel,
              panel.isVisible,
              !isClosing else {
            inputState.notifyWindowWillHide()
            keyboardEventTap.suspend()
            removeOutsideClickMonitor()
            closePreview()
            panel?.orderOut(nil)
            panel?.hasShadow = false
            setHistoryContentRasterization(false, for: panel)
            HistoryWindowLifecycleDiagnostics.record(
                .closeCleanupComplete,
                itemCount: store.items.count,
                wasVisible: wasVisible,
                shouldAnimate: false,
                hasPendingFocus: false
            )
            return
        }

        isClosing = true
        inputState.requestWindowHideCleanup()
        panel.hasShadow = false
        let targetFrame = hiddenFrame(for: frameForPanel())
        closePreview()
        if HistoryWindowLifecycleScheduler.shouldUseContentLayerCloseAnimation(shouldAnimate: shouldAnimate) {
            contentLayerAnimationGeneration &+= 1
            let animationGeneration = contentLayerAnimationGeneration
            lockHistoryContentSize(for: panel, size: panel.frame.size)
            prepareHistoryContentLayerForAnimatedOrdering(panel)
            animateHistoryContentLayerTranslation(
                panel,
                from: 0,
                to: -panelAnimationDistance,
                key: "history.close.contentTranslation",
                generation: animationGeneration
            ) { [weak self, weak panel] in
                HistoryWindowLifecycleDiagnostics.record(
                    .closeAnimationComplete,
                    itemCount: self?.store.items.count,
                    wasVisible: true,
                    shouldAnimate: true,
                    hasPendingFocus: false
                )
                self?.inputState.notifyWindowWillHide()
                self?.keyboardEventTap.suspend()
                self?.removeOutsideClickMonitor()
                self?.closePreview()
                panel?.alphaValue = 1
                panel?.hasShadow = false
                panel?.ignoresMouseEvents = true
                if let self,
                   let panel {
                    if !HistoryWindowLifecycleScheduler.shouldKeepPanelOrderedAfterClose(
                        usesContentLayerAnimation: true
                    ) {
                        panel.orderOut(nil)
                        self.resetHistoryContentLayerAnimationState(for: panel)
                    }
                    if HistoryWindowLifecycleScheduler.shouldRepairHiddenPanelTargetFrameAfterClose(
                        usesContentLayerAnimation: true
                    ) {
                        self.applyTargetFrameIfNeeded(to: panel, targetFrame: self.frameForPanel())
                    }
                }
                self?.setOCRInteractiveThrottleActive(false)
                self?.isClosing = false
                HistoryWindowLifecycleDiagnostics.record(
                    .closeCleanupComplete,
                    itemCount: self?.store.items.count,
                    wasVisible: true,
                    shouldAnimate: true,
                    hasPendingFocus: false
                )
            }
            return
        }

        lockHistoryContentSize(for: panel, size: targetFrame.size)
        setHistoryContentRasterization(
            HistoryWindowLifecycleScheduler.shouldRasterizeContentDuringWindowAnimation(
                shouldAnimate: shouldAnimate
            ),
            for: panel
        )
        NSAnimationContext.runAnimationGroup { context in
            context.duration = panelAnimationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(targetFrame, display: false)
        } completionHandler: { [weak self, weak panel] in
            Task { @MainActor in
                HistoryWindowLifecycleDiagnostics.record(
                    .closeAnimationComplete,
                    itemCount: self?.store.items.count,
                    wasVisible: true,
                    shouldAnimate: true,
                    hasPendingFocus: false
                )
                self?.inputState.notifyWindowWillHide()
                self?.keyboardEventTap.suspend()
                self?.removeOutsideClickMonitor()
                self?.closePreview()
                self?.lockHistoryContentSize(for: panel, size: targetFrame.size)
                panel?.setFrame(targetFrame, display: false)
                panel?.orderOut(nil)
                panel?.alphaValue = 1
                panel?.hasShadow = false
                self?.setHistoryContentRasterization(false, for: panel)
                self?.setOCRInteractiveThrottleActive(false)
                self?.isClosing = false
                HistoryWindowLifecycleDiagnostics.record(
                    .closeCleanupComplete,
                    itemCount: self?.store.items.count,
                    wasVisible: true,
                    shouldAnimate: true,
                    hasPendingFocus: false
                )
            }
        }
    }

    func hideImmediatelyForAutoPaste() {
        presentationRecoveryTask?.cancel()
        presentationRecoveryTask = nil
        contentLayerAnimationGeneration &+= 1
        inputState.setOpenAnimationActive(false)
        inputState.notifyWindowWillHide()
        keyboardEventTap.suspend()
        removeOutsideClickMonitor()
        closePreview()
        panel?.orderOut(nil)
        panel?.hasShadow = false
        if let panel {
            resetHistoryContentLayerAnimationState(for: panel)
        }
        setHistoryContentRasterization(false, for: panel)
        setOCRInteractiveThrottleActive(false)
        isClosing = false
    }

    private func finishShowingWindow(shouldAnimate: Bool) {
        guard !isShutDown else {
            return
        }

        renderState.mark("finish-showing-start")
        inputState.setOpenAnimationActive(false)
        renderState.mark("finish-showing-animation-state-cleared")
        if HistoryWindowLifecycleScheduler.shouldStartKeyboardEventTapWhenFinishingShow(
            shouldAnimate: shouldAnimate
        ) {
            keyboardEventTap.start()
            renderState.mark("finish-showing-keyboard-tap-started")
        }
        installOutsideClickMonitor()
        renderState.mark("finish-showing-outside-monitor-installed")
    }

    private func applyOpenPresentationState(
        latestFocusRequest: ClipboardItemFocusRequest?,
        hadPendingExplicitOffset: Bool,
        wasVisible: Bool,
        shouldAnimate: Bool
    ) {
        guard !isShutDown else {
            return
        }

        renderState.mark("presentation-state-start")
        inputState.setWindowVisible(true)
        renderState.mark("presentation-window-visible")
        inputState.setWindowPresented(true)
        renderState.mark("presentation-window-presented")
        renderState.mark("open-presented")
        HistoryWindowLifecycleDiagnostics.record(
            .openPresented,
            itemCount: store.items.count,
            wasVisible: wasVisible,
            shouldAnimate: shouldAnimate,
            hasPendingFocus: latestFocusRequest != nil
        )
        setOCRInteractiveThrottleActive(true)
        schedulePresentationRecovery(
            latestFocusRequest: latestFocusRequest,
            hadPendingExplicitOffset: hadPendingExplicitOffset,
            shouldAnimate: shouldAnimate
        )
    }

    private func schedulePresentationRecovery(
        latestFocusRequest: ClipboardItemFocusRequest?,
        hadPendingExplicitOffset: Bool,
        shouldAnimate: Bool
    ) {
        guard !isShutDown else {
            return
        }

        let delayNanoseconds = HistoryWindowLifecycleScheduler.presentationRecoveryDelayNanoseconds(
            shouldAnimate: shouldAnimate
        )

        guard delayNanoseconds > 0 else {
            applyPresentationRecovery(
                latestFocusRequest: latestFocusRequest,
                hadPendingExplicitOffset: hadPendingExplicitOffset,
                shouldAnimate: shouldAnimate
            )
            return
        }

        presentationRecoveryTask?.cancel()
        presentationRecoveryTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            guard !Task.isCancelled,
                  !isShutDown,
                  inputState.isWindowVisibleSnapshot,
                  inputState.isWindowPresentedSnapshot else {
                return
            }

            applyPresentationRecovery(
                latestFocusRequest: latestFocusRequest,
                hadPendingExplicitOffset: hadPendingExplicitOffset,
                shouldAnimate: shouldAnimate
            )
            presentationRecoveryTask = nil
        }
    }

    private func applyPresentationRecovery(
        latestFocusRequest: ClipboardItemFocusRequest?,
        hadPendingExplicitOffset: Bool,
        shouldAnimate: Bool
    ) {
        guard !isShutDown else {
            return
        }

        renderState.mark("presentation-recovery-start")
        if let latestFocusRequest {
            inputState.requestItemFocus(
                latestFocusRequest.itemID,
                resetToAll: true,
                reason: latestFocusRequest.reason
            )
        } else if !hadPendingExplicitOffset {
            HistoryScrollCoordinator.shared.restoreSavedOffset()
        }
        renderState.mark("presentation-scroll-restored")
        if latestFocusRequest == nil,
           !hadPendingExplicitOffset {
            inputState.requestDefaultFocus(resetToFirst: shouldAnimate)
        }
        renderState.mark("presentation-recovery-complete")
        if HistoryWindowLifecycleScheduler.shouldStartKeyboardEventTapDuringPresentationRecovery(
            shouldAnimate: shouldAnimate
        ) {
            keyboardEventTap.start()
            renderState.mark("presentation-recovery-keyboard-tap-started")
        }
    }

    private func makePanel() -> HistoryPanel {
        if let panelFactory {
            let panel = panelFactory()
            AppearanceWindowApplicator.apply(appearanceSettings.windowAppearance, to: panel)
            keyboardEventTap.setKeyWindow(panel)
            panel.delegate = self
            return panel
        }

        let contentView = HistoryWindowView(
            store: store,
            previewState: previewState,
            renderState: renderState,
            inputState: inputState,
            recordingController: recordingController,
            accessibilityPermissionState: accessibilityPermissionState,
            appMenuController: appMenuController,
            pasteExecutor: pasteExecutor,
            onClose: { [weak self] in
                self?.close()
            },
            onPreview: { [weak self] item, cardFrame in
                self?.showPreview(item, cardFrame: cardFrame)
            },
            onMovePreview: { [weak self] cardFrame in
                self?.movePreview(cardFrame: cardFrame)
            },
            onClosePreview: { [weak self] in
                self?.closePreview()
            },
            onCreateText: { [weak self] defaultGroupID in
                self?.createTextFromHistoryWindow(defaultGroupID: defaultGroupID)
            }
        )

        let panel = HistoryPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        AppearanceWindowApplicator.apply(appearanceSettings.windowAppearance, to: panel)

        keyboardEventTap.setKeyWindow(panel)
        panel.delegate = self
        panel.onEscape = { [weak self] in
            self?.inputState.dispatch(.close)
        }
        panel.onSpace = { [weak self] in
            guard let self,
                  keyboardRouter.shouldTogglePreviewFromPanelSpace(
                    isHistoryTextInputActive: self.inputState.isHistoryTextInputActiveSnapshot,
                    isPreviewActive: self.inputState.isPreviewActiveSnapshot
                  ) else {
                return false
            }

            self.inputState.dispatch(.togglePreview)
            return true
        }
        panel.onDelete = { [weak self] in
            self?.inputState.dispatch(.delete)
        }
        panel.onSearchText = { [weak self] text in
            self?.inputState.dispatch(.appendSearchText(text))
        }
        panel.onBeginComposedSearchInput = { [weak self] pendingEvent in
            self?.inputState.dispatch(.beginComposedSearchInput(pendingEvent))
        }
        panel.onTextFirstResponderChanged = { [weak self] isActive in
            self?.inputState.setAppTextFirstResponderActive(isActive)
        }
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovable = false
        panel.animationBehavior = .none
        panel.hasShadow = false
        previewWindowController.onKeyStateChange = { [weak self] isKey in
            self?.inputState.setPreviewKeyWindowActive(isKey)
        }

        let hostingView = HistoryWindowHostingView(rootView: contentView)
        hostingView.autoresizingMask = [.width, .height]
        hostingView.focusRingType = .none
        hostingView.wantsLayer = true
        hostingView.layer?.borderWidth = 0
        hostingView.layer?.shadowOpacity = 0
        hostingView.layer?.masksToBounds = false
        panel.contentView = hostingView
        applyPanelMaterialState(to: panel)
        return panel
    }

    private func frameForPanel() -> NSRect {
        let screen = NSScreen.clipeaseScreenContainingMouse ?? NSScreen.main
        let frame = screen?.frame ?? NSScreen.main?.frame ?? .zero
        return NSRect(
            x: frame.minX,
            y: frame.minY,
            width: frame.width,
            height: panelHeight
        )
    }

    private func hiddenFrame(for frame: NSRect) -> NSRect {
        frame.offsetBy(dx: 0, dy: -panelAnimationDistance)
    }

    private func applyHiddenFrameIfNeeded(to panel: NSPanel, targetFrame: NSRect) {
        let hiddenFrame = hiddenFrame(for: targetFrame)
        lockHistoryContentSize(for: panel, size: hiddenFrame.size)
        guard HistoryWindowLifecycleScheduler.shouldApplyHiddenFrame(
            currentFrame: panel.frame,
            targetFrame: hiddenFrame
        ) else {
            renderState.mark("panel-frame-reused")
            return
        }

        renderState.mark("panel-frame-applying")
        panel.setFrame(hiddenFrame, display: false)
        renderState.mark("panel-frame-applied")
    }

    private func applyTargetFrameIfNeeded(to panel: NSPanel, targetFrame: NSRect) {
        lockHistoryContentSize(for: panel, size: targetFrame.size)
        let beforeFrame = panel.frame
        let beforeFrameMetadata = targetFrameDiagnosticsMetadata(
            currentFrame: beforeFrame,
            targetFrame: targetFrame
        )
        guard HistoryWindowLifecycleScheduler.shouldApplyTargetFrame(
            currentFrame: beforeFrame,
            targetFrame: targetFrame
        ) else {
            renderState.mark("panel-target-frame-reused", metadata: beforeFrameMetadata)
            return
        }

        renderState.mark("panel-target-frame-applying", metadata: beforeFrameMetadata)
        panel.setFrame(targetFrame, display: false)
        renderState.mark(
            "panel-target-frame-applied",
            metadata: targetFrameDiagnosticsMetadata(
                currentFrame: panel.frame,
                targetFrame: targetFrame
            )
        )
    }

    private func targetFrameDiagnosticsMetadata(
        currentFrame: NSRect,
        targetFrame: NSRect
    ) -> [String: String] {
        [
            "currentX": diagnosticFrameValue(currentFrame.minX),
            "currentY": diagnosticFrameValue(currentFrame.minY),
            "currentWidth": diagnosticFrameValue(currentFrame.width),
            "currentHeight": diagnosticFrameValue(currentFrame.height),
            "targetX": diagnosticFrameValue(targetFrame.minX),
            "targetY": diagnosticFrameValue(targetFrame.minY),
            "targetWidth": diagnosticFrameValue(targetFrame.width),
            "targetHeight": diagnosticFrameValue(targetFrame.height),
            "deltaX": diagnosticFrameValue(targetFrame.minX - currentFrame.minX),
            "deltaY": diagnosticFrameValue(targetFrame.minY - currentFrame.minY),
            "deltaWidth": diagnosticFrameValue(targetFrame.width - currentFrame.width),
            "deltaHeight": diagnosticFrameValue(targetFrame.height - currentFrame.height)
        ]
    }

    private func diagnosticFrameValue(_ value: CGFloat) -> String {
        String(format: "%.1f", Double(value))
    }

    private func lockHistoryContentSize(for panel: NSPanel?, size: NSSize) {
        HistoryWindowPanelSizeLock.apply(to: panel, frameSize: size)
        (panel?.contentView as? HistoryWindowHostingView<HistoryWindowView>)?.lockContentSize(size)
    }

    private func prepareHistoryContentLayerForAnimatedOrdering(
        _ panel: NSPanel,
        initialTranslationY: CGFloat = 0
    ) {
        let shouldApplyTransformPreparation = HistoryWindowLifecycleScheduler
            .shouldApplyContentLayerTransformPreparation(initialTranslationY: initialTranslationY)
        if shouldApplyTransformPreparation {
            panel.isOpaque = false
            panel.backgroundColor = .clear
            setHistoryContentLayerTranslation(initialTranslationY, for: panel)
            panel.contentView?.layer?.masksToBounds = true
        }
        setHistoryContentRasterization(
            HistoryWindowLifecycleScheduler.shouldRasterizeContentDuringWindowAnimation(
                shouldAnimate: true
            ),
            for: panel
        )
        if HistoryWindowLifecycleScheduler.shouldSynchronouslyFlushContentLayerBeforeOrdering(
            usesContentLayerAnimation: shouldApplyTransformPreparation
        ) {
            panel.contentView?.needsLayout = true
            panel.contentView?.layoutSubtreeIfNeeded()
            panel.contentView?.displayIfNeeded()
        }
        renderState.mark("content-layer-prepared-before-order")
    }

    private func animateHistoryContentLayerTranslation(
        _ panel: NSPanel,
        from startTranslationY: CGFloat,
        to endTranslationY: CGFloat,
        key: String,
        generation: UInt64,
        completion: @MainActor @escaping () -> Void
    ) {
        guard let layer = panel.contentView?.layer else {
            completion()
            return
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.transform = CATransform3DMakeTranslation(0, endTranslationY, 0)
        CATransaction.commit()

        let animation = CABasicAnimation(keyPath: "transform.translation.y")
        animation.fromValue = startTranslationY
        animation.toValue = endTranslationY
        animation.duration = panelAnimationDuration
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

        CATransaction.begin()
        CATransaction.setCompletionBlock {
            Task { @MainActor [weak self, weak panel] in
                guard let self,
                      let panel,
                      self.contentLayerAnimationGeneration == generation else {
                    return
                }

                panel.contentView?.layer?.removeAnimation(forKey: key)
                completion()
            }
        }
        layer.add(animation, forKey: key)
        CATransaction.commit()
    }

    private func resetHistoryContentLayerAnimationState(for panel: NSPanel) {
        panel.contentView?.layer?.removeAnimation(forKey: "history.open.contentTranslation")
        panel.contentView?.layer?.removeAnimation(forKey: "history.close.contentTranslation")
        setHistoryContentLayerTranslation(0, for: panel)
        panel.contentView?.layer?.masksToBounds = false
        applyPanelMaterialState(to: panel)
        setHistoryContentRasterization(false, for: panel)
    }

    private func installAccessibilityDisplayOptionsObserver() {
        accessibilityDisplayOptionsObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshPanelMaterialState()
            }
        }
    }

    private func removeAccessibilityDisplayOptionsObserver() {
        guard let accessibilityDisplayOptionsObserver else {
            return
        }

        NSWorkspace.shared.notificationCenter.removeObserver(accessibilityDisplayOptionsObserver)
        self.accessibilityDisplayOptionsObserver = nil
    }

    private func refreshPanelMaterialState() {
        guard let panel else {
            return
        }

        applyPanelMaterialState(to: panel)
    }

    private func applyPanelMaterialState(to panel: NSPanel) {
        let environment = HistoryGlassEnvironment(
            supportsNativeGlass: HistoryGlassRuntime.supportsNativeGlass,
            reduceTransparency: NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency,
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
            increaseContrast: NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast,
            isDarkMode: NSApp.effectiveAppearance.bestMatch(from: [.darkAqua]) == .darkAqua,
            isWindowActive: panel.isKeyWindow,
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
        let plan = HistoryGlassPolicy.resolve(role: .panel, environment: environment)
        let backingState = HistoryGlassPanelBackingPolicy.resolve(plan: plan)
        let backgroundColor: NSColor = backingState.isOpaque ? .windowBackgroundColor : .clear

        panel.isOpaque = backingState.isOpaque
        panel.backgroundColor = backgroundColor
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.backgroundColor = backgroundColor.cgColor
    }

    private func applyAppearancePreference() {
        AppearanceWindowApplicator.apply(appearanceSettings.windowAppearance, to: panel)
        previewWindowController.applyAppearance(appearanceSettings.windowAppearance)
        if let panel {
            applyPanelMaterialState(to: panel)
        }
    }

    private func setHistoryContentLayerTranslation(_ translationY: CGFloat, for panel: NSPanel?) {
        guard let layer = panel?.contentView?.layer else {
            return
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.transform = CATransform3DMakeTranslation(0, translationY, 0)
        CATransaction.commit()
    }

    private func setHistoryContentRasterization(_ isEnabled: Bool, for panel: NSPanel?) {
        guard let contentView = panel?.contentView else {
            return
        }

        contentView.wantsLayer = true
        guard let layer = contentView.layer else {
            return
        }

        let targetScale = max(panel?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1, 1)
        guard HistoryWindowLifecycleScheduler.shouldUpdateContentRasterization(
            currentIsRasterized: layer.shouldRasterize,
            targetIsRasterized: isEnabled,
            currentScale: layer.rasterizationScale,
            targetScale: targetScale
        ) else {
            return
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.shouldRasterize = isEnabled
        layer.rasterizationScale = targetScale
        CATransaction.commit()
        renderState.mark(isEnabled ? "content-rasterization-enabled" : "content-rasterization-disabled")
    }

    func pasteTargetApplication() -> NSRunningApplication? {
        previousFrontmostApplication
    }

    var isPreviewInteractionActive: Bool {
        previewWindowController.isRecordingSuppressionActive
    }

    private func captureFrontmostApplicationIfNeeded() {
        guard let frontmostApplication = NSWorkspace.shared.frontmostApplication,
              frontmostApplication.bundleIdentifier != Bundle.main.bundleIdentifier else {
            return
        }

        previousFrontmostApplication = frontmostApplication
    }

    private func installOutsideClickMonitor() {
        guard !isShutDown else {
            return
        }

        removeOutsideClickMonitor()
        outsideClickMonitor = eventMonitorBackend.addGlobalMonitor(matching: [.leftMouseDown, .rightMouseDown, .leftMouseUp, .rightMouseUp]) { [weak self] event in
            Task { @MainActor in
                self?.closeIfClickIsOutsideHistory(event)
            }
        }
        localOutsideClickMonitor = eventMonitorBackend.addLocalMonitor(matching: [.leftMouseDown, .rightMouseDown, .leftMouseUp, .rightMouseUp]) { [weak self] event in
            self?.closeIfClickIsOutsideHistory(event)
            return event
        }
    }

    private func removeOutsideClickMonitor() {
        if let outsideClickMonitor {
            eventMonitorBackend.removeMonitor(outsideClickMonitor)
            self.outsideClickMonitor = nil
        }
        if let localOutsideClickMonitor {
            eventMonitorBackend.removeMonitor(localOutsideClickMonitor)
            self.localOutsideClickMonitor = nil
        }
    }

    private func closeIfClickIsOutsideHistory(_ event: NSEvent) {
        guard let panel, panel.isVisible else {
            return
        }
        guard !inputState.isWindowPinnedOpenSnapshot else {
            return
        }
        guard !inputState.isPreviewContentActive else {
            return
        }

        if event.window === panel {
            return
        }

        if let eventWindow = event.window,
           NSApp.windows.contains(eventWindow) {
            return
        }

        let screenPoint = NSEvent.mouseLocation
        if panel.frame.contains(screenPoint) || previewWindowController.contains(screenPoint: screenPoint) {
            return
        }

        close()
    }

    private func showPreview(_ item: ClipboardItem, cardFrame: CGRect) {
        guard let panel else {
            inputState.setPreviewActive(false)
            previewState.close()
            return
        }

        let anchorScreenPoint = CGPoint(
            x: panel.frame.minX + cardFrame.midX,
            y: panel.frame.maxY - cardFrame.minY
        )
        let screenFrame = panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? panel.frame
        let didShowPreview = previewWindowController.show(
            item: item,
            parentWindow: panel,
            anchorScreenPoint: anchorScreenPoint,
            screenFrame: screenFrame,
            onCopy: { [weak self, pasteExecutor] in
                guard let self else {
                    return
                }
                switch pasteExecutor.copyToPasteboard(item) {
                case .copied:
                    ClipEaseSoundPlayer.shared.playCopyFeedback()
                    self.showStatus(self.copyStatus(for: item))
                case .copiedFallbackText:
                    ClipEaseSoundPlayer.shared.playCopyFeedback()
                    self.showStatus(self.copyFallbackTextStatus(for: item))
                case .failed(let reason):
                    self.showStatus(reason)
                }
            },
            onOpen: { [weak self] in
                self?.openPreviewItem(item)
            },
            onReveal: { [weak self] in
                self?.revealPreviewItem(item)
            },
            onCopyURL: { [weak self] in
                self?.copyPlainPreviewText(item.text)
            },
            onCopyMarkdown: { [weak self] in
                self?.copyPlainPreviewText(self?.markdownLink(for: item))
            },
            onCopyPath: { [weak self] in
                self?.copyPreviewPath(for: item)
            },
            onCopyRGB: { [weak self] in
                self?.copyPlainPreviewText(self?.rgbString(from: item.text))
            },
            onClose: { [weak self] in
                self?.closePreview()
            },
            onDetach: { [weak self] in
                guard let self else {
                    return
                }
                self.inputState.setPreviewActive(false)
                self.previewState.close()
                self.close()
            }
        )
        guard didShowPreview else {
            inputState.setPreviewActive(false)
            previewState.close()
            return
        }

        guard previewWindowController.isAttachedVisible else {
            inputState.setPreviewActive(false)
            previewState.close()
            return
        }

        previewState.open(item.id)
        inputState.setPreviewActive(true)
        previewWindowController.installOutsideClickMonitor { [weak self] in
            self?.closePreview()
        }
        previewWindowController.installEscapeKeyMonitor { [weak self] in
            self?.closePreview()
        }
    }

    private func movePreview(cardFrame: CGRect) {
        guard let panel else {
            return
        }

        let anchorScreenPoint = CGPoint(
            x: panel.frame.minX + cardFrame.midX,
            y: panel.frame.maxY - cardFrame.minY
        )
        let screenFrame = panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? panel.frame
        previewWindowController.move(anchorScreenPoint: anchorScreenPoint, screenFrame: screenFrame)
    }

    private func openPreviewItem(_ item: ClipboardItem) {
        switch item.type {
        case .link:
            if let url = item.url {
                NSWorkspace.shared.open(url)
            }
        case .image:
            if let url = imageURL(for: item) {
                NSWorkspace.shared.open(url)
            }
        case .text, .color, .file:
            break
        }
    }

    private func revealPreviewItem(_ item: ClipboardItem) {
        switch item.type {
        case .image:
            guard let url = imageURL(for: item) else {
                return
            }

            NSWorkspace.shared.activateFileViewerSelecting([url])
        case .file:
            let urls = existingPreviewFileURLs(for: item)
            guard !urls.isEmpty else {
                showStatus(L("未找到文件"))
                return
            }

            NSWorkspace.shared.activateFileViewerSelecting(urls)
        case .text, .link, .color:
            break
        }
    }

    private func copyPlainPreviewText(_ text: String?) {
        guard let text,
              !text.isEmpty else {
            return
        }

        ClipboardWriteCoordinator.generalTextWriter(registerSelfWrite: store.registerSelfWrite)
            .writeText(text)
        ClipEaseSoundPlayer.shared.playCopyFeedback()
    }

    private func copyPreviewPath(for item: ClipboardItem) {
        switch item.type {
        case .image:
            copyPlainPreviewText(imagePath(for: item))
        case .file:
            copyPreviewFilePaths(for: item)
        case .text, .link, .color:
            break
        }
    }

    private func copyPreviewFilePaths(for item: ClipboardItem) {
        guard item.type == .file else {
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
        ClipboardWriteCoordinator.generalTextWriter(registerSelfWrite: store.registerSelfWrite)
            .writeText(pathsText)
        ClipEaseSoundPlayer.shared.playCopyFeedback()
        showStatus(paths.count > 1 ? L("已复制 \(paths.count) 个文件路径") : L("已复制文件路径"))
    }

    private func markdownLink(for item: ClipboardItem) -> String? {
        guard item.type == .link else {
            return nil
        }

        let title = (item.linkTitle?.isEmpty == false ? item.linkTitle : nil)
            ?? item.url?.host(percentEncoded: false)
            ?? item.text
        return "[\(title)](\(item.text))"
    }

    private func imagePath(for item: ClipboardItem) -> String? {
        imageURL(for: item)?.path
    }

    private func imageURL(for item: ClipboardItem) -> URL? {
        guard item.type == .image,
              let fileName = item.imageFileName else {
            return nil
        }

        return try? ClipEaseStoragePaths.imageFileURL(fileName: fileName)
    }

    private func existingPreviewFileURLs(for item: ClipboardItem) -> [URL] {
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

    private func showStatus(_ text: String) {
        if let frame = lastKnownPanelFrame {
            GlobalStatusToastController.shared.updateHistoryWindowFrame(frame, screen: panel?.screen ?? NSScreen.clipeaseScreenContainingMouse ?? NSScreen.main)
        }
        appMenuController.setStatusToastAnchorWindow(panel)
        GlobalStatusToastController.shared.show(text, relativeTo: panel)
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

    private func rgbString(from hex: String) -> String? {
        guard let components = ClipEaseColorComponents(hex: hex) else {
            return nil
        }

        let red = Int(round(components.red * 255))
        let green = Int(round(components.green * 255))
        let blue = Int(round(components.blue * 255))
        return "rgb(\(red), \(green), \(blue))"
    }

    private func closePreview() {
        inputState.setPreviewActive(false)
        previewState.close()
        previewWindowController.close()
    }

    private func showAndFocusCreatedItem(_ item: ClipboardItem) {
        show()
        inputState.requestItemFocus(item.id, resetToAll: item.groupID == nil)
    }

    func createTextFromHistoryWindow(defaultGroupID: ClipboardGroup.ID?) {
        close()
        appMenuController.createTextItem(defaultGroupID: defaultGroupID) { [weak self] item in
            self?.showAndFocusCreatedItem(item)
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        if previewWindowController.isAttachedVisible {
            return
        }

        closePreview()
    }
}
