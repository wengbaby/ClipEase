import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

enum ClipboardRichTextPasteboardPayload: Sendable {
    case rtf(data: Data, fallbackPlainText: String?)
    case html(data: Data, fallbackPlainText: String?)

    var data: Data {
        switch self {
        case .rtf(let data, _), .html(let data, _):
            data
        }
    }

    var fallbackPlainText: String? {
        switch self {
        case .rtf(_, let fallbackPlainText), .html(_, let fallbackPlainText):
            fallbackPlainText
        }
    }
}

struct ClipboardRichTextImportResult: Sendable {
    let data: Data
    let plainText: String
    let rawAsset: ClipboardRichTextRawAsset?
    let previewSkipReason: ClipboardPayloadProcessingReason?

    init(
        data: Data,
        plainText: String,
        rawAsset: ClipboardRichTextRawAsset? = nil,
        previewSkipReason: ClipboardPayloadProcessingReason? = nil
    ) {
        self.data = data
        self.plainText = plainText
        self.rawAsset = rawAsset
        self.previewSkipReason = previewSkipReason
    }
}

typealias ClipboardRichTextImporter = @Sendable (
    ClipboardRichTextPasteboardPayload
) async -> ClipboardRichTextImportResult?

enum ClipboardMonitorPayloadImportRequest: Sendable {
    case image(
        stagedPayload: ClipboardStagedPayload,
        declaredTypeIdentifier: String
    )
    case richText(
        stagedPayload: ClipboardStagedPayload,
        fallbackPlainText: String?
    )
    case pdf(stagedPayload: ClipboardStagedPayload)
}

private enum ClipboardMonitorPayloadStagingRequest: Sendable {
    case image(data: Data, declaredTypeIdentifier: String)
    case richText(ClipboardRichTextPasteboardPayload)
    case pdf(data: Data)

    var source: ClipboardPayloadStagingSource {
        switch self {
        case .image(let data, let declaredTypeIdentifier):
            ClipboardPayloadStagingSource(
                data: data,
                contentKind: .image,
                preferredFileExtension: UTType(declaredTypeIdentifier)?
                    .preferredFilenameExtension
            )
        case .richText(let payload):
            ClipboardPayloadStagingSource(
                data: payload.data,
                contentKind: {
                    switch payload {
                    case .rtf: .richTextRTF
                    case .html: .richTextHTML
                    }
                }()
            )
        case .pdf(let data):
            ClipboardPayloadStagingSource(
                data: data,
                contentKind: .pdf,
                preferredFileExtension: "pdf"
            )
        }
    }

    var stagedDescriptor: ClipboardMonitorStagedPayloadDescriptor {
        switch self {
        case .image(_, let declaredTypeIdentifier):
            .image(declaredTypeIdentifier: declaredTypeIdentifier)
        case .richText(let payload):
            .richText(fallbackPlainText: payload.fallbackPlainText)
        case .pdf:
            .pdf
        }
    }
}

private enum ClipboardMonitorStagedPayloadDescriptor: Sendable {
    case image(declaredTypeIdentifier: String)
    case richText(fallbackPlainText: String?)
    case pdf

    func importRequest(
        stagedPayload: ClipboardStagedPayload
    ) -> ClipboardMonitorPayloadImportRequest {
        switch self {
        case .image(let declaredTypeIdentifier):
            .image(
                stagedPayload: stagedPayload,
                declaredTypeIdentifier: declaredTypeIdentifier
            )
        case .richText(let fallbackPlainText):
            .richText(
                stagedPayload: stagedPayload,
                fallbackPlainText: fallbackPlainText
            )
        case .pdf:
            .pdf(stagedPayload: stagedPayload)
        }
    }
}

enum ClipboardMonitorPayloadImportResult: Sendable {
    case image(ClipboardImportedImage)
    case richText(ClipboardRichTextImportResult?)
    case pdf(ClipboardImportedPDF)
}

extension ClipboardMonitorPayloadImportResult {
    static func image(_ storedImage: StoredClipboardImage) -> ClipboardMonitorPayloadImportResult {
        .image(ClipboardImportedImage(storedImage: storedImage, fingerprint: nil))
    }
}

private enum ClipboardMonitorPreparedImport: Sendable {
    case image(ClipboardImportedImage)
    case richText(ClipboardRichTextImportResult)
    case pdf(ClipboardImportedPDF)
    case completed(storedType: String, payloadByteCount: Int)
}

typealias ClipboardMonitorPayloadImporter = @Sendable (
    ClipboardMonitorPayloadImportRequest
) async throws -> ClipboardMonitorPayloadImportResult

enum ClipboardMonitorImportDiagnosticEvent: Equatable, Sendable {
    case success(capturedType: String)
    case failure(capturedType: String)
}

enum ClipboardMonitorPayloadImportRunnerEvent: Equatable, Sendable {
    case started(UUID)
    case finished(UUID)
}

typealias ClipboardMonitorImportDiagnosticRecorder = @MainActor (
    ClipboardMonitorImportDiagnosticEvent
) -> Void

typealias ClipboardMonitorPayloadImportRunnerEventRecorder = @Sendable (
    ClipboardMonitorPayloadImportRunnerEvent
) -> Void

struct ClipboardMonitorPayloadImportPumpDiagnostics: Equatable, Sendable {
    let hasActiveImport: Bool
    let hasPendingImport: Bool
    let ownedRequestCount: Int
}

private final class ClipboardMonitorPayloadImportCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var isFinished = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    lazy var task: Task<Void, Never> = Task.detached { [weak self] in
        await self?.waitUntilFinished()
    }

    func finish() {
        let waiters = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            guard !isFinished else {
                return []
            }
            isFinished = true
            defer { self.waiters.removeAll() }
            return self.waiters
        }
        waiters.forEach { $0.resume() }
    }

    private func waitUntilFinished() async {
        if lock.withLock({ isFinished }) {
            return
        }
        await withCheckedContinuation { continuation in
            let shouldResume = lock.withLock { () -> Bool in
                guard !isFinished else {
                    return true
                }
                waiters.append(continuation)
                return false
            }
            if shouldResume {
                continuation.resume()
            }
        }
    }
}

private struct ClipboardMonitorPayloadImportContext: Sendable {
    let id: UUID
    let sourceApp: SourceAppInfo
    let changeCount: Int
    let startedAt: CFAbsoluteTime
    let capturedType: String
    let generation: UInt64
    let authority: ClipboardImportAuthority
}

private final class ClipboardMonitorActivePayloadImport: @unchecked Sendable {
    let context: ClipboardMonitorPayloadImportContext
    let completion: ClipboardMonitorPayloadImportCompletion
    var task: Task<Void, Never>?

    init(
        context: ClipboardMonitorPayloadImportContext,
        completion: ClipboardMonitorPayloadImportCompletion
    ) {
        self.context = context
        self.completion = completion
    }
}

private final class ClipboardMonitorPayloadStagingOperation: @unchecked Sendable {
    let context: ClipboardMonitorPayloadImportContext
    let completion: ClipboardMonitorPayloadImportCompletion
    var task: Task<Void, Never>?

    init(
        context: ClipboardMonitorPayloadImportContext,
        completion: ClipboardMonitorPayloadImportCompletion
    ) {
        self.context = context
        self.completion = completion
    }
}

private struct ClipboardMonitorPendingPayloadImport: Sendable {
    let request: ClipboardMonitorPayloadImportRequest
    let context: ClipboardMonitorPayloadImportContext
    let completion: ClipboardMonitorPayloadImportCompletion
}

@MainActor
protocol ClipboardMonitorTimerToken: AnyObject {
    var timeInterval: TimeInterval { get }
    var tolerance: TimeInterval { get set }
    func invalidate()
}

extension Timer: ClipboardMonitorTimerToken {}

@MainActor
struct ClipboardMonitorTimerScheduler {
    typealias Handler = @MainActor () -> Void
    typealias Schedule = (TimeInterval, @escaping Handler) -> any ClipboardMonitorTimerToken

    let schedule: Schedule

    init(_ schedule: @escaping Schedule) {
        self.schedule = schedule
    }

    static let live = ClipboardMonitorTimerScheduler { interval, handler in
        Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            Task { @MainActor in handler() }
        }
    }
}

private enum ClipboardPasteboardSnapshot {
    case text(String, fastPath: Bool)
    case files([URL])
    case richText(ClipboardRichTextPasteboardPayload)
    case image(data: Data, declaredTypeIdentifier: String)
    case pdf(data: Data)
    case unsupported

    var selfWritePayload: ClipboardSelfWritePayload? {
        switch self {
        case .text(let text, _):
            .text(text)
        case .files(let urls):
            .files(urls)
        case .richText(let payload):
            payload.fallbackPlainText.map(ClipboardSelfWritePayload.richText)
        case .image, .pdf, .unsupported:
            nil
        }
    }
}

struct ClipboardMonitorPasteboardReadSnapshot {
    let changeCount: Int
    let types: Set<NSPasteboard.PasteboardType>
    let strings: [NSPasteboard.PasteboardType: String]
    let data: [NSPasteboard.PasteboardType: Data]
    let fileURLs: [URL]

    func string(forType type: NSPasteboard.PasteboardType) -> String? { strings[type] }
    func data(forType type: NSPasteboard.PasteboardType) -> Data? { data[type] }
}

struct ClipboardPollingPolicy: Sendable {
    static let maximumScheduledInterval: TimeInterval = 1.0
    static let timerTolerance: TimeInterval = 0.05

    let activeInterval: TimeInterval
    let idleInterval: TimeInterval
    let idleThreshold: Int

    static let `default` = ClipboardPollingPolicy(
        activeInterval: 0.25,
        idleInterval: 1.0,
        idleThreshold: 12
    )

    func interval(afterUnchangedPollCount unchangedPollCount: Int) -> TimeInterval {
        min(
            unchangedPollCount >= idleThreshold ? idleInterval : activeInterval,
            Self.maximumScheduledInterval
        )
    }
}

enum ClipboardPayloadImportQueueError: Error, Equatable, Sendable {
    case residentTaskLimitExceeded
    case retainedDataLimitExceeded
}

struct ClipboardPayloadImportQueue<Element: Sendable>: Sendable {
    private struct Entry: Sendable {
        let element: Element
        let retainedByteCount: Int
    }

    let maximumResidentTasks: Int
    let maximumRetainedBytes: Int
    private var entries: [Entry] = []
    private(set) var retainedByteCount = 0

    var residentTaskCount: Int {
        entries.count
    }

    var first: Element? {
        entries.first?.element
    }

    var values: [Element] {
        entries.map(\.element)
    }

    init(maximumResidentTasks: Int, maximumRetainedBytes: Int) {
        self.maximumResidentTasks = max(0, maximumResidentTasks)
        self.maximumRetainedBytes = max(0, maximumRetainedBytes)
    }

    mutating func enqueue(
        _ element: Element,
        retaining retainedBytes: Int
    ) -> ClipboardPayloadImportQueueError? {
        guard entries.count < maximumResidentTasks else {
            return .residentTaskLimitExceeded
        }
        let boundedBytes = max(0, retainedBytes)
        guard boundedBytes <= maximumRetainedBytes - retainedByteCount else {
            return .retainedDataLimitExceeded
        }
        entries.append(Entry(element: element, retainedByteCount: boundedBytes))
        retainedByteCount += boundedBytes
        return nil
    }

    @discardableResult
    mutating func dequeue() -> Element? {
        guard !entries.isEmpty else {
            return nil
        }
        let entry = entries.removeFirst()
        retainedByteCount -= entry.retainedByteCount
        return entry.element
    }

    mutating func removeAll() -> [Element] {
        defer {
            entries.removeAll(keepingCapacity: true)
            retainedByteCount = 0
        }
        return values
    }
}

private final class ClipboardMonitorNotificationObserver: @unchecked Sendable {
    private let notificationCenter: NotificationCenter
    private let token: NSObjectProtocol

    init(notificationCenter: NotificationCenter, token: NSObjectProtocol) {
        self.notificationCenter = notificationCenter
        self.token = token
    }

    deinit {
        notificationCenter.removeObserver(token)
    }
}

private final class ClipboardMonitorDistributedNotificationObserver: @unchecked Sendable {
    private let notificationCenter: DistributedNotificationCenter
    private let token: NSObjectProtocol

    init(notificationCenter: DistributedNotificationCenter, token: NSObjectProtocol) {
        self.notificationCenter = notificationCenter
        self.token = token
    }

    deinit {
        notificationCenter.removeObserver(token)
    }
}

enum ClipboardMonitorLifecycleEvent: Sendable {
    case willSleep
    case didWake
    case sessionLocked
    case sessionUnlocked
}

@MainActor
final class ClipboardMonitorLifecycleState {
    private(set) var isSleeping = false
    private(set) var isSessionLocked = false

    var isSuspended: Bool {
        isSleeping || isSessionLocked
    }

    func apply(_ event: ClipboardMonitorLifecycleEvent) {
        switch event {
        case .willSleep:
            isSleeping = true
        case .didWake:
            isSleeping = false
        case .sessionLocked:
            isSessionLocked = true
        case .sessionUnlocked:
            isSessionLocked = false
        }
    }
}

@MainActor
final class ClipboardMonitor {
    private static let maximumQueuedPayloadImports = 64
    private static let maximumPayloadQueueHandoffs = 4
    private static let screenLockedNotification = Notification.Name("com.apple.screenIsLocked")
    private static let screenUnlockedNotification = Notification.Name("com.apple.screenIsUnlocked")
    private static let filenamesPasteboardType = NSPasteboard.PasteboardType("NSFilenamesPboardType")
    private static let publicFileURLPasteboardType = NSPasteboard.PasteboardType("public.file-url")
    private static let fileURLPromisePasteboardType = NSPasteboard.PasteboardType("com.apple.pasteboard.promised-file-url")
    private static let filePromiseContentPasteboardType = NSPasteboard.PasteboardType("com.apple.pasteboard.promised-file-content-type")
    private static let filePromiseMetadataPasteboardType = NSPasteboard.PasteboardType("com.apple.NSFilePromiseItemMetaData")
    private static let publicPNGType = NSPasteboard.PasteboardType("public.png")
    private static let publicTIFFType = NSPasteboard.PasteboardType("public.tiff")
    private static let publicJPEGType = NSPasteboard.PasteboardType("public.jpeg")

    private let pasteboard: NSPasteboard
    private let store: ClipboardHistoryStore
    private let pollingPolicy: ClipboardPollingPolicy
    private let sourceAppSnapshot: ClipboardSourceAppSnapshot
    private let isPaused: () -> Bool
    private let isIgnored: (String?) -> Bool
    private let timerScheduler: ClipboardMonitorTimerScheduler
    private let pasteboardChangeCountProvider: @MainActor () -> Int
    private let pasteboardSnapshotProvider: (@MainActor () -> ClipboardMonitorPasteboardReadSnapshot)?
    private let payloadImporter: ClipboardMonitorPayloadImporter
    private let payloadStager: ClipboardPayloadStager
    private let payloadImportRunnerEventRecorder: ClipboardMonitorPayloadImportRunnerEventRecorder
    private let importDiagnosticRecorder: ClipboardMonitorImportDiagnosticRecorder
    private let payloadProcessingRecorder: ClipboardPayloadProcessingRecorder
    private let lifecycleState: ClipboardMonitorLifecycleState
    var shouldSuppressRecording: (() -> Bool)?
    private var timer: (any ClipboardMonitorTimerToken)?
    private var lastChangeCount: Int
    private var sourceActivationObserver: ClipboardMonitorNotificationObserver?
    private var workspaceLifecycleObservers: [ClipboardMonitorNotificationObserver] = []
    private var distributedLifecycleObservers: [ClipboardMonitorDistributedNotificationObserver] = []
    private var recordingPauseObserver: AnyCancellable?
    private var isMonitoringRequested = false
    private var unchangedPollCount = 0
    private var payloadStagingOperations: [
        UUID: ClipboardMonitorPayloadStagingOperation
    ] = [:]
    private var payloadStagingOrder: [UUID] = []
    private var payloadStagingReadyBuffer: [
        UUID: ClipboardMonitorPendingPayloadImport
    ] = [:]
    private var pendingPayloadChangeCounts: Set<Int> = []
    private var activePayloadImport: ClipboardMonitorActivePayloadImport?
    private var payloadImportQueue = ClipboardPayloadImportQueue<ClipboardMonitorPendingPayloadImport>(
        maximumResidentTasks: ClipboardMonitor.maximumQueuedPayloadImports,
        maximumRetainedBytes: 128 * 1_024 * 1_024
    )
    private var payloadQueueHandoffBuffer: [ClipboardMonitorPendingPayloadImport] = []
    private var payloadSkipReasons: [UUID: ClipboardPayloadProcessingReason] = [:]
    private var isDrainingPayloads = false
    private var payloadDrainWaiters: [CheckedContinuation<Void, Never>] = []
    private var payloadStagingStartupTask: Task<Void, Never>?

    var hasActivePayloadImportForTesting: Bool {
        activePayloadImport != nil
    }

    var hasCurrentImportAuthorityForTesting: Bool {
        activePayloadImport?.context.authority.isCurrent == true
    }

    var payloadImportPumpDiagnosticsForTesting: ClipboardMonitorPayloadImportPumpDiagnostics {
        ClipboardMonitorPayloadImportPumpDiagnostics(
            hasActiveImport: activePayloadImport != nil,
            hasPendingImport: !payloadStagingOperations.isEmpty
                || !payloadStagingReadyBuffer.isEmpty
                || payloadImportQueue.residentTaskCount > (activePayloadImport == nil ? 0 : 1)
                || !payloadQueueHandoffBuffer.isEmpty,
            ownedRequestCount: payloadStagingOperations.count
                + payloadStagingReadyBuffer.count
                + payloadImportQueue.residentTaskCount
                + payloadQueueHandoffBuffer.count
        )
    }
    private var payloadImportGeneration: UInt64 = 0

    convenience init(
        store: ClipboardHistoryStore,
        recordingController: RecordingController,
        ignoredAppSettings: IgnoredAppSettings,
        pasteboard: NSPasteboard = .general,
        pollingPolicy: ClipboardPollingPolicy = .default
    ) {
        self.init(
            store: store,
            pasteboard: pasteboard,
            pollingPolicy: pollingPolicy,
            sourceAppProvider: { Self.monitoredSourceApp(SourceAppInfo.current) },
            isPaused: { recordingController.isPaused },
            isIgnored: { ignoredAppSettings.contains(bundleID: $0) },
            payloadProcessingRecorder: ClipboardPayloadProcessingStatusPresenter.present
        )
        recordingPauseObserver = recordingController.$isPaused
            .removeDuplicates()
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.refreshSuspensionState()
                }
            }
    }

    init(
        store: ClipboardHistoryStore,
        pasteboard: NSPasteboard,
        pollingPolicy: ClipboardPollingPolicy = .default,
        sourceAppProvider: @escaping () -> SourceAppInfo,
        isPaused: @escaping () -> Bool,
        isIgnored: @escaping (String?) -> Bool,
        timerScheduler: ClipboardMonitorTimerScheduler = .live,
        pasteboardChangeCountProvider: (@MainActor () -> Int)? = nil,
        pasteboardSnapshotProvider: (@MainActor () -> ClipboardMonitorPasteboardReadSnapshot)? = nil,
        richTextImporter: ClipboardRichTextImporter? = nil,
        payloadImporter: ClipboardMonitorPayloadImporter? = nil,
        payloadImportRunnerEventRecorder: @escaping ClipboardMonitorPayloadImportRunnerEventRecorder = { _ in },
        importDiagnosticRecorder: @escaping ClipboardMonitorImportDiagnosticRecorder = { _ in },
        payloadStager: ClipboardPayloadStager = ClipboardPayloadStager(),
        payloadProcessingRecorder: @escaping ClipboardPayloadProcessingRecorder = { _ in },
        lifecycleState: ClipboardMonitorLifecycleState = ClipboardMonitorLifecycleState(),
        observesSystemLifecycle: Bool = true
    ) {
        self.store = store
        self.pollingPolicy = pollingPolicy
        self.pasteboard = pasteboard
        let initialSourceApp = Self.monitoredSourceApp(sourceAppProvider())
        self.sourceAppSnapshot = ClipboardSourceAppSnapshot(initial: initialSourceApp)
        self.isPaused = isPaused
        self.isIgnored = isIgnored
        self.timerScheduler = timerScheduler
        self.pasteboardChangeCountProvider = pasteboardChangeCountProvider ?? {
            pasteboard.changeCount
        }
        self.pasteboardSnapshotProvider = pasteboardSnapshotProvider
        self.payloadImportRunnerEventRecorder = payloadImportRunnerEventRecorder
        self.importDiagnosticRecorder = importDiagnosticRecorder
        self.payloadStager = payloadStager
        self.payloadProcessingRecorder = payloadProcessingRecorder
        self.lifecycleState = lifecycleState
        if let payloadImporter {
            self.payloadImporter = payloadImporter
        } else {
            let boundedImporter = store.makeClipboardPayloadImporter(
                payloadStager: payloadStager
            )
            self.payloadImporter = { request in
                switch request {
                case .image(let stagedPayload, let declaredTypeIdentifier):
                    return .image(try await boundedImporter.importImageForMonitor(
                        stagedPayload,
                        declaredTypeIdentifier: declaredTypeIdentifier
                    ))
                case .richText(let stagedPayload, let fallbackPlainText):
                    if let richTextImporter {
                        let data = try stagedPayload.readData()
                        let payload: ClipboardRichTextPasteboardPayload
                        switch stagedPayload.contentKind {
                        case .richTextRTF:
                            payload = .rtf(
                                data: data,
                                fallbackPlainText: fallbackPlainText
                            )
                        case .richTextHTML:
                            payload = .html(
                                data: data,
                                fallbackPlainText: fallbackPlainText
                            )
                        case .image, .pdf:
                            throw ClipboardPayloadStagingError.stagedFileUnreadable
                        }
                        return .richText(await richTextImporter(payload))
                    }
                    return .richText(try await boundedImporter.importRichText(
                        stagedPayload,
                        fallbackPlainText: fallbackPlainText
                    ))
                case .pdf(let stagedPayload):
                    return .pdf(try await boundedImporter.importPDF(stagedPayload))
                }
            }
        }
        self.lastChangeCount = self.pasteboardChangeCountProvider()
        let sourceActivationNotificationCenter = NSWorkspace.shared.notificationCenter
        let sourceAppSnapshot = self.sourceAppSnapshot
        let sourceActivationObserver = sourceActivationNotificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak sourceAppSnapshot] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication else {
                return
            }
            Task { @MainActor in
                sourceAppSnapshot?.recordActivation(
                    Self.monitoredSourceApp(SourceAppInfo.sourceAppInfo(for: app))
                )
            }
        }
        self.sourceActivationObserver = ClipboardMonitorNotificationObserver(
            notificationCenter: sourceActivationNotificationCenter,
            token: sourceActivationObserver
        )
        if observesSystemLifecycle {
            installSystemLifecycleObservers()
        }
    }

    deinit {
        payloadStagingStartupTask?.cancel()
        for operation in payloadStagingOperations.values {
            operation.context.authority.invalidate()
            operation.task?.cancel()
            operation.completion.finish()
        }
        activePayloadImport?.context.authority.invalidate()
        activePayloadImport?.task?.cancel()
        for pending in payloadImportQueue.values {
            pending.context.authority.invalidate()
            pending.request.discardStagedPayload()
            pending.completion.finish()
        }
        for pending in payloadStagingReadyBuffer.values {
            pending.context.authority.invalidate()
            pending.request.discardStagedPayload()
            pending.completion.finish()
        }
        for pending in payloadQueueHandoffBuffer {
            pending.context.authority.invalidate()
            pending.request.discardStagedPayload()
            pending.completion.finish()
        }
        payloadDrainWaiters.forEach { $0.resume() }
    }

    func start() {
        guard !isMonitoringRequested else {
            return
        }

        isMonitoringRequested = true
        if payloadStagingStartupTask == nil {
            let payloadStager = self.payloadStager
            payloadStagingStartupTask = Task {
                try? await payloadStager.initializeAndScavenge()
            }
        }
        refreshSuspensionState()
    }

    private func scheduleTimer(interval: TimeInterval) {
        timer?.invalidate()
        let scheduledTimer = timerScheduler.schedule(
            min(interval, ClipboardPollingPolicy.maximumScheduledInterval)
        ) { [weak self] in
            guard let self,
                  self.isMonitoringRequested,
                  self.refreshSuspensionState() else {
                return
            }
            self.pollNow()
        }
        scheduledTimer.tolerance = ClipboardPollingPolicy.timerTolerance
        timer = scheduledTimer
    }

    private func updatePollingIntervalForCurrentActivity() {
        let nextInterval = pollingPolicy.interval(afterUnchangedPollCount: unchangedPollCount)
        guard let timer,
              abs(timer.timeInterval - nextInterval) > 0.001 else {
            return
        }

        scheduleTimer(interval: nextInterval)
    }

    func stop() {
        isMonitoringRequested = false
        invalidateTimer()
        unchangedPollCount = 0
        payloadImportGeneration &+= 1
        clearPayloadStagingOperations()
        invalidateActivePayloadImport()
        clearPendingPayloadImports()
        pendingPayloadChangeCounts.removeAll()
        payloadSkipReasons.removeAll()
    }

    @discardableResult
    func refreshSuspensionState() -> Bool {
        let isSuspended = lifecycleState.isSuspended || isPaused()
        guard isMonitoringRequested else {
            return false
        }
        guard !isSuspended else {
            invalidateTimer()
            return false
        }

        if timer == nil {
            scheduleTimer(interval: pollingPolicy.activeInterval)
            pollNow()
        }
        return true
    }

    @discardableResult
    func pollNow() -> Task<Void, Never>? {
        guard isMonitoringRequested,
              !lifecycleState.isSuspended,
              !isPaused() else {
            return nil
        }
        let startedAt = CFAbsoluteTimeGetCurrent()
        let currentChangeCount = pasteboardChangeCountProvider()
        guard currentChangeCount != lastChangeCount else {
            unchangedPollCount += 1
            updatePollingIntervalForCurrentActivity()
            return nil
        }
        guard !pendingPayloadChangeCounts.contains(currentChangeCount) else {
            return nil
        }
        let ownedPayloadCount = payloadStagingOperations.count
            + payloadStagingReadyBuffer.count
            + payloadImportQueue.residentTaskCount
            + payloadQueueHandoffBuffer.count
        guard ownedPayloadCount
            < Self.maximumQueuedPayloadImports + Self.maximumPayloadQueueHandoffs else {
            return nil
        }
        let captureInterval = PerformanceDiagnosticsSignposter.beginInterval(
            name: "clipboard.capture",
            category: "capture"
        )
        defer {
            PerformanceDiagnosticsSignposter.endInterval(captureInterval)
        }

        unchangedPollCount = 0
        updatePollingIntervalForCurrentActivity()
        payloadImportGeneration &+= 1
        let changeDetectedAt = CFAbsoluteTimeGetCurrent()
        let suppliedSnapshot = pasteboardSnapshotProvider?()
        let availableTypes = suppliedSnapshot?.types ?? Set(pasteboard.types ?? [])
        let snapshot = pasteboardSnapshot(availableTypes: availableTypes, suppliedSnapshot: suppliedSnapshot)
        let typesLoadedAt = CFAbsoluteTimeGetCurrent()
        guard !store.consumeSelfWrite(
            changeCount: currentChangeCount,
            payload: snapshot.selfWritePayload
        ) else {
            lastChangeCount = currentChangeCount
            return nil
        }
        guard shouldSuppressRecording?() != true else {
            lastChangeCount = currentChangeCount
            return nil
        }
        let sourceApp = sourceAppSnapshot.current
        let sourceResolvedAt = CFAbsoluteTimeGetCurrent()
        guard !isIgnored(sourceApp.bundleID) else {
            lastChangeCount = currentChangeCount
            return nil
        }

        if case .image(let data, let declaredTypeIdentifier) = snapshot {
            let task = schedulePayloadImport(
                request: .image(data: data, declaredTypeIdentifier: declaredTypeIdentifier),
                sourceApp: sourceApp,
                changeCount: currentChangeCount,
                startedAt: startedAt,
                capturedType: "image",
                generation: payloadImportGeneration
            )
            recordPollDuration(startedAt: startedAt, capturedType: "image.scheduled")
            return task
        }
        if case .pdf(let data) = snapshot {
            let task = schedulePayloadImport(
                request: .pdf(data: data),
                sourceApp: sourceApp,
                changeCount: currentChangeCount,
                startedAt: startedAt,
                capturedType: "pdf",
                generation: payloadImportGeneration
            )
            recordPollDuration(startedAt: startedAt, capturedType: "pdf.scheduled")
            return task
        }

        switch snapshot {
        case .text(let text, let fastPath):
            let payloadLoadedAt = CFAbsoluteTimeGetCurrent()
            store.addText(text, sourceApp: sourceApp)
            lastChangeCount = currentChangeCount
            recordPollDuration(
                startedAt: startedAt,
                changeDetectedAt: changeDetectedAt,
                sourceResolvedAt: sourceResolvedAt,
                typesLoadedAt: typesLoadedAt,
                payloadLoadedAt: payloadLoadedAt,
                capturedType: fastPath ? "text.fastPath" : "text"
            )
            return nil
        case .files(let fileURLs):
            store.addFiles(fileURLs, sourceApp: sourceApp)
            lastChangeCount = currentChangeCount
            recordPollDuration(startedAt: startedAt, capturedType: "file")
            return nil
        case .richText(let payload):
            let capturedType: String
            switch payload {
            case .rtf:
                capturedType = "rtf"
            case .html:
                capturedType = "html"
            }
            let task = schedulePayloadImport(
                request: .richText(payload),
                sourceApp: sourceApp,
                changeCount: currentChangeCount,
                startedAt: startedAt,
                capturedType: capturedType,
                generation: payloadImportGeneration
            )
            recordPollDuration(startedAt: startedAt, capturedType: "\(capturedType).scheduled")
            return task
        case .image, .pdf:
            return nil
        case .unsupported:
            lastChangeCount = currentChangeCount
            return nil
        }
    }

    private func pasteboardSnapshot(
        availableTypes: Set<NSPasteboard.PasteboardType>,
        suppliedSnapshot: ClipboardMonitorPasteboardReadSnapshot? = nil
    ) -> ClipboardPasteboardSnapshot {
        let string: (NSPasteboard.PasteboardType) -> String?
        let data: (NSPasteboard.PasteboardType) -> Data?
        if let suppliedSnapshot {
            string = { suppliedSnapshot.string(forType: $0) }
            data = { suppliedSnapshot.data(forType: $0) }
        } else {
            string = { self.pasteboard.string(forType: $0) }
            data = { self.pasteboard.data(forType: $0) }
        }
        if shouldCapturePlainTextFirst(availableTypes),
           let text = string(.string) {
            return .text(text, fastPath: true)
        }

        let fileURLs = suppliedSnapshot?.fileURLs ?? localFileURLsFromPasteboard(availableTypes: availableTypes)
        if !fileURLs.isEmpty {
            return .files(fileURLs)
        }

        if availableTypes.contains(.pdf),
           let pdfData = data(.pdf) {
            return .pdf(data: pdfData)
        }

        if pasteboardHasRichTextTypes(availableTypes),
           let rtfData = data(.rtf) {
            return .richText(.rtf(
                data: rtfData,
                fallbackPlainText: string(.string)
            ))
        }

        if pasteboardHasImageTypes(availableTypes),
           let imagePayload = encodedImagePayload(availableTypes: availableTypes, suppliedSnapshot: suppliedSnapshot) {
            return .image(
                data: imagePayload.data,
                declaredTypeIdentifier: imagePayload.type.rawValue
            )
        }

        if pasteboardHasRichTextTypes(availableTypes),
           let htmlData = data(.html) {
            return .richText(.html(
                data: htmlData,
                fallbackPlainText: string(.string)
            ))
        }

        if let text = string(.string) {
            return .text(text, fastPath: false)
        }
        return .unsupported
    }

    private func recordPollDuration(startedAt: CFAbsoluteTime, capturedType: String) {
        PerformanceDiagnosticsService.shared.record(
            "clipboard.poll",
            category: "clipboard",
            durationMS: (CFAbsoluteTimeGetCurrent() - startedAt) * 1_000,
            metadata: ["capturedType": capturedType]
        )
    }

    private func recordPollDuration(
        startedAt: CFAbsoluteTime,
        changeDetectedAt: CFAbsoluteTime,
        sourceResolvedAt: CFAbsoluteTime,
        typesLoadedAt: CFAbsoluteTime,
        payloadLoadedAt: CFAbsoluteTime,
        capturedType: String
    ) {
        let finishedAt = CFAbsoluteTimeGetCurrent()
        PerformanceDiagnosticsService.shared.record(
            "clipboard.poll",
            category: "clipboard",
            durationMS: (finishedAt - startedAt) * 1_000,
            metadata: [
                "capturedType": capturedType,
                "changeMS": Self.formatStageMS(changeDetectedAt - startedAt),
                "sourceMS": Self.formatStageMS(sourceResolvedAt - changeDetectedAt),
                "typesMS": Self.formatStageMS(typesLoadedAt - sourceResolvedAt),
                "payloadMS": Self.formatStageMS(payloadLoadedAt - typesLoadedAt),
                "storeMS": Self.formatStageMS(finishedAt - payloadLoadedAt)
            ]
        )
    }

    nonisolated private static func formatStageMS(_ seconds: CFAbsoluteTime) -> String {
        String(format: "%.3f", seconds * 1_000)
    }

    private func schedulePayloadImport(
        request: ClipboardMonitorPayloadStagingRequest,
        sourceApp: SourceAppInfo,
        changeCount: Int,
        startedAt: CFAbsoluteTime,
        capturedType: String,
        generation: UInt64
    ) -> Task<Void, Never> {
        let context = ClipboardMonitorPayloadImportContext(
            id: UUID(),
            sourceApp: sourceApp,
            changeCount: changeCount,
            startedAt: startedAt,
            capturedType: capturedType,
            generation: generation,
            authority: ClipboardImportAuthority()
        )
        let completion = ClipboardMonitorPayloadImportCompletion()
        recordPayloadProcessingStatus(.queued, context: context)
        pendingPayloadChangeCounts.insert(changeCount)

        let stagingSource = request.source
        let stagedDescriptor = request.stagedDescriptor
        let operation = ClipboardMonitorPayloadStagingOperation(
            context: context,
            completion: completion
        )
        payloadStagingOperations[context.id] = operation
        payloadStagingOrder.append(context.id)
        recordPayloadProcessingStatus(.processing, context: context)

        let payloadStager = self.payloadStager
        let reservation: ClipboardPayloadStagingReservation
        do {
            reservation = try payloadStager.reserveImmediately(
                byteCount: stagingSource.data.count
            )
        } catch let error as ClipboardPayloadStagingError {
            completePayloadStagingFailure(
                error,
                context: context,
                completion: completion,
                processingStatus: .deferred(error.processingReason)
            )
            return completion.task
        } catch {
            completePayloadStagingFailure(
                .atomicWriteFailed,
                context: context,
                completion: completion
            )
            return completion.task
        }
        let task = Task.detached(priority: .utility) { [weak self] in
            do {
                let stagedPayload = try await payloadStager.stage(
                    stagingSource,
                    reservation: reservation
                )
                await self?.completePayloadStaging(
                    stagedPayload,
                    descriptor: stagedDescriptor,
                    context: context,
                    completion: completion
                )
            } catch is CancellationError {
                await self?.completePayloadStagingCancellation(
                    context: context,
                    completion: completion
                )
            } catch let error as ClipboardPayloadStagingError {
                await self?.completePayloadStagingFailure(
                    error,
                    context: context,
                    completion: completion
                )
            } catch {
                await self?.completePayloadStagingFailure(
                    .atomicWriteFailed,
                    context: context,
                    completion: completion
                )
            }
        }
        operation.task = task
        return completion.task
    }

    private func completePayloadStaging(
        _ stagedPayload: ClipboardStagedPayload,
        descriptor: ClipboardMonitorStagedPayloadDescriptor,
        context: ClipboardMonitorPayloadImportContext,
        completion: ClipboardMonitorPayloadImportCompletion
    ) {
        guard payloadStagingOperations.removeValue(forKey: context.id) != nil else {
            stagedPayload.discard()
            completion.finish()
            return
        }
        pendingPayloadChangeCounts.remove(context.changeCount)
        if pasteboardChangeCountProvider() == context.changeCount {
            lastChangeCount = context.changeCount
        }
        guard (isMonitoringRequested || isDrainingPayloads),
              context.authority.isCurrent else {
            stagedPayload.discard()
            removePayloadStagingOrder(context.id)
            flushCompletedPayloadStagingInCaptureOrder()
            recordPayloadProcessingStatus(
                .deferred(.staleGeneration),
                context: context
            )
            completion.finish()
            return
        }

        let pending = ClipboardMonitorPendingPayloadImport(
            request: descriptor.importRequest(stagedPayload: stagedPayload),
            context: context,
            completion: completion
        )
        payloadStagingReadyBuffer[context.id] = pending
        flushCompletedPayloadStagingInCaptureOrder()
    }

    private func completePayloadStagingFailure(
        _ error: ClipboardPayloadStagingError,
        context: ClipboardMonitorPayloadImportContext,
        completion: ClipboardMonitorPayloadImportCompletion,
        processingStatus: ClipboardPayloadProcessingStatus? = nil
    ) {
        guard payloadStagingOperations.removeValue(forKey: context.id) != nil else {
            completion.finish()
            return
        }
        pendingPayloadChangeCounts.remove(context.changeCount)
        if pasteboardChangeCountProvider() == context.changeCount {
            lastChangeCount = context.changeCount
        }
        removePayloadStagingOrder(context.id)
        flushCompletedPayloadStagingInCaptureOrder()
        context.authority.invalidate()
        recordPayloadProcessingStatus(
            processingStatus ?? .failed(error.processingReason),
            context: context
        )
        importDiagnosticRecorder(.failure(capturedType: context.capturedType))
        PerformanceDiagnosticsService.shared.recordError(
            "clipboard.payload.staging.failed",
            category: "clipboard",
            error: error,
            metadata: ["capturedType": context.capturedType]
        )
        NSLog("ClipEase failed to stage clipboard payload: \(error.processingReason.rawValue)")
        completion.finish()
    }

    private func completePayloadStagingCancellation(
        context: ClipboardMonitorPayloadImportContext,
        completion: ClipboardMonitorPayloadImportCompletion
    ) {
        guard payloadStagingOperations.removeValue(forKey: context.id) != nil else {
            completion.finish()
            return
        }
        pendingPayloadChangeCounts.remove(context.changeCount)
        removePayloadStagingOrder(context.id)
        flushCompletedPayloadStagingInCaptureOrder()
        context.authority.invalidate()
        recordPayloadProcessingStatus(
            .deferred(.staleGeneration),
            context: context
        )
        completion.finish()
    }

    private func startPayloadImport(_ pending: ClipboardMonitorPendingPayloadImport) {
        precondition(activePayloadImport == nil)
        let active = ClipboardMonitorActivePayloadImport(
            context: pending.context,
            completion: pending.completion
        )
        activePayloadImport = active

        let importer = payloadImporter
        let store = store
        let context = pending.context
        let completion = pending.completion
        let runnerEventRecorder = payloadImportRunnerEventRecorder
        runnerEventRecorder(.started(context.id))
        let task = Task.detached(priority: .utility) { [weak self] in
            await Self.runPayloadImport(
                pending.request,
                importer: importer,
                store: store,
                context: context,
                prepare: { [weak self] result in
                    await self?.preparePayloadImport(result, context: context)
                },
                recordSuccess: { [weak self] completion, parseStartedAt, parsedAt in
                    await self?.finishPayloadImport(
                        completion,
                        startedAt: context.startedAt,
                        parseStartedAt: parseStartedAt,
                        parsedAt: parsedAt,
                        context: context
                    )
                },
                recordFailure: { [weak self] error, payloadByteCount in
                    await self?.completePayloadImportFailure(
                        error,
                        payloadByteCount: payloadByteCount,
                        context: context
                    )
                },
                recordSkipped: { [weak self] in
                    await self?.completePayloadImportWithoutCommit(
                        context: context
                    )
                },
                didFinish: { [weak self] in
                    runnerEventRecorder(.finished(context.id))
                    await self?.completeActivePayloadImport(ifCurrent: context.id)
                }
            )
            completion.finish()
        }
        active.task = task
    }

    private func flushCompletedPayloadStagingInCaptureOrder() {
        while let firstID = payloadStagingOrder.first,
              let pending = payloadStagingReadyBuffer.removeValue(forKey: firstID) {
            payloadStagingOrder.removeFirst()
            enqueueStagedPayloadForImport(pending)
        }
    }

    private func removePayloadStagingOrder(_ id: UUID) {
        if let index = payloadStagingOrder.firstIndex(of: id) {
            payloadStagingOrder.remove(at: index)
        }
        payloadStagingReadyBuffer.removeValue(forKey: id)
    }

    private func enqueueStagedPayloadForImport(
        _ pending: ClipboardMonitorPendingPayloadImport
    ) {
        if payloadImportQueue.enqueue(pending, retaining: 0) != nil {
            guard payloadQueueHandoffBuffer.count
                    < Self.maximumPayloadQueueHandoffs else {
                pending.context.authority.invalidate()
                pending.request.discardStagedPayload()
                recordPayloadProcessingStatus(
                    .failed(.residentTaskLimitExceeded),
                    context: pending.context
                )
                importDiagnosticRecorder(
                    .failure(capturedType: pending.context.capturedType)
                )
                pending.completion.finish()
                return
            }
            payloadQueueHandoffBuffer.append(pending)
            return
        }

        if activePayloadImport == nil {
            startPayloadImport(pending)
        }
    }

    private func invalidateActivePayloadImport() {
        guard let active = activePayloadImport else {
            return
        }
        activePayloadImport = nil
        active.context.authority.invalidate()
        active.task?.cancel()
        recordPayloadProcessingStatus(
            .deferred(.staleGeneration),
            context: active.context
        )
        active.completion.finish()
    }

    private func clearPayloadStagingOperations() {
        let operations = Array(payloadStagingOperations.values)
        let operationIDs = Set(operations.map(\.context.id))
        payloadStagingOperations.removeAll(keepingCapacity: true)
        for operation in operations {
            pendingPayloadChangeCounts.remove(operation.context.changeCount)
            operation.context.authority.invalidate()
            operation.task?.cancel()
            recordPayloadProcessingStatus(
                .deferred(.staleGeneration),
                context: operation.context
            )
            operation.completion.finish()
        }
        payloadStagingOrder.removeAll { operationIDs.contains($0) }
    }

    private func clearPendingPayloadImports() {
        for pending in payloadStagingReadyBuffer.values {
            pending.context.authority.invalidate()
            pending.request.discardStagedPayload()
            recordPayloadProcessingStatus(
                .deferred(.staleGeneration),
                context: pending.context
            )
            pending.completion.finish()
        }
        payloadStagingReadyBuffer.removeAll(keepingCapacity: true)
        payloadStagingOrder.removeAll(keepingCapacity: true)
        for pending in payloadImportQueue.removeAll() {
            pending.context.authority.invalidate()
            pending.request.discardStagedPayload()
            recordPayloadProcessingStatus(
                .deferred(.staleGeneration),
                context: pending.context
            )
            pending.completion.finish()
        }
        for pending in payloadQueueHandoffBuffer {
            pending.context.authority.invalidate()
            pending.request.discardStagedPayload()
            recordPayloadProcessingStatus(
                .deferred(.staleGeneration),
                context: pending.context
            )
            pending.completion.finish()
        }
        payloadQueueHandoffBuffer.removeAll(keepingCapacity: true)
    }

    private func completeActivePayloadImport(ifCurrent taskID: UUID) {
        guard let active = activePayloadImport,
              active.context.id == taskID else {
            return
        }
        activePayloadImport = nil
        _ = payloadImportQueue.dequeue()
        if !payloadQueueHandoffBuffer.isEmpty {
            let durablePending = payloadQueueHandoffBuffer.removeFirst()
            if payloadImportQueue.enqueue(durablePending, retaining: 0) != nil {
                payloadQueueHandoffBuffer.insert(durablePending, at: 0)
            }
        }
        if let pending = payloadImportQueue.first {
            startPayloadImport(pending)
        }
    }

    func waitForPayloadImportsForTesting() async -> Bool {
        if let payloadStagingStartupTask {
            await payloadStagingStartupTask.value
        }
        let completionTasks = payloadStagingOperations.values.map(\.completion.task)
            + payloadStagingReadyBuffer.values.map(\.completion.task)
            + payloadImportQueue.values.map(\.completion.task)
            + payloadQueueHandoffBuffer.map(\.completion.task)
            + [activePayloadImport?.completion.task].compactMap { $0 }
        for task in completionTasks {
            await task.value
        }
        await payloadStager.drainCleanup()
        return payloadStagingOperations.isEmpty
            && payloadStagingReadyBuffer.isEmpty
            && activePayloadImport == nil
            && payloadImportQueue.residentTaskCount == 0
            && payloadQueueHandoffBuffer.isEmpty
    }

    func stopAndDrainPayloads() async {
        if isDrainingPayloads {
            await withCheckedContinuation { continuation in
                payloadDrainWaiters.append(continuation)
            }
            return
        }

        isDrainingPayloads = true
        isMonitoringRequested = false
        invalidateTimer()
        unchangedPollCount = 0
        let completionTasks = payloadStagingOperations.values.map(\.completion.task)
            + payloadStagingReadyBuffer.values.map(\.completion.task)
            + payloadImportQueue.values.map(\.completion.task)
            + payloadQueueHandoffBuffer.map(\.completion.task)
            + [activePayloadImport?.completion.task].compactMap { $0 }
        for task in completionTasks {
            await task.value
        }
        if let payloadStagingStartupTask {
            await payloadStagingStartupTask.value
        }
        await payloadStager.drainCleanup()
        isDrainingPayloads = false
        let waiters = payloadDrainWaiters
        payloadDrainWaiters.removeAll(keepingCapacity: true)
        waiters.forEach { $0.resume() }
    }

    private func invalidateTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func handleLifecycleEvent(_ event: ClipboardMonitorLifecycleEvent) {
        lifecycleState.apply(event)
        refreshSuspensionState()
    }

    private func installSystemLifecycleObservers() {
        let workspaceNotificationCenter = NSWorkspace.shared.notificationCenter
        observeWorkspaceLifecycle(
            NSWorkspace.willSleepNotification,
            event: .willSleep,
            notificationCenter: workspaceNotificationCenter
        )
        observeWorkspaceLifecycle(
            NSWorkspace.didWakeNotification,
            event: .didWake,
            notificationCenter: workspaceNotificationCenter
        )
        observeWorkspaceLifecycle(
            NSWorkspace.sessionDidResignActiveNotification,
            event: .sessionLocked,
            notificationCenter: workspaceNotificationCenter
        )
        observeWorkspaceLifecycle(
            NSWorkspace.sessionDidBecomeActiveNotification,
            event: .sessionUnlocked,
            notificationCenter: workspaceNotificationCenter
        )

        let distributedNotificationCenter = DistributedNotificationCenter.default()
        observeDistributedLifecycle(
            Self.screenLockedNotification,
            event: .sessionLocked,
            notificationCenter: distributedNotificationCenter
        )
        observeDistributedLifecycle(
            Self.screenUnlockedNotification,
            event: .sessionUnlocked,
            notificationCenter: distributedNotificationCenter
        )
    }

    private func observeWorkspaceLifecycle(
        _ name: Notification.Name,
        event: ClipboardMonitorLifecycleEvent,
        notificationCenter: NotificationCenter
    ) {
        let token = notificationCenter.addObserver(
            forName: name,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleLifecycleEvent(event)
            }
        }
        workspaceLifecycleObservers.append(
            ClipboardMonitorNotificationObserver(
                notificationCenter: notificationCenter,
                token: token
            )
        )
    }

    private func observeDistributedLifecycle(
        _ name: Notification.Name,
        event: ClipboardMonitorLifecycleEvent,
        notificationCenter: DistributedNotificationCenter
    ) {
        let token = notificationCenter.addObserver(
            forName: name,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleLifecycleEvent(event)
            }
        }
        distributedLifecycleObservers.append(
            ClipboardMonitorDistributedNotificationObserver(
                notificationCenter: notificationCenter,
                token: token
            )
        )
    }

    nonisolated private static func runPayloadImport(
        _ request: ClipboardMonitorPayloadImportRequest,
        importer: @escaping ClipboardMonitorPayloadImporter,
        store: ClipboardHistoryStore,
        context: ClipboardMonitorPayloadImportContext,
        prepare: @escaping @Sendable (ClipboardMonitorPayloadImportResult) async -> ClipboardMonitorPreparedImport?,
        recordSuccess: @escaping @Sendable (
            (
                storedType: String,
                payloadByteCount: Int,
                status: ClipboardPayloadProcessingStatus
            ),
            CFAbsoluteTime,
            CFAbsoluteTime
        ) async -> Void,
        recordFailure: @escaping @Sendable (Error, Int) async -> Void,
        recordSkipped: @escaping @Sendable () async -> Void,
        didFinish: @escaping @Sendable () async -> Void
    ) async {
        defer { request.discardStagedPayload() }
        let parseStartedAt = CFAbsoluteTimeGetCurrent()
        let result: ClipboardMonitorPayloadImportResult
        do {
            result = try await importer(request)
        } catch is CancellationError {
            await didFinish()
            return
        } catch {
            if !Task.isCancelled {
                await recordFailure(error, request.payloadByteCount)
            }
            await didFinish()
            return
        }

        guard !Task.isCancelled else {
            await rollbackImportedImageIfNeeded(result, store: store)
            await didFinish()
            return
        }

        let parsedAt = CFAbsoluteTimeGetCurrent()
        guard let prepared = await prepare(result) else {
            await rollbackImportedImageIfNeeded(result, store: store)
            await recordSkipped()
            await didFinish()
            return
        }

        do {
            if let completion = try await commitPreparedPayloadImport(
                prepared,
                store: store,
                sourceApp: context.sourceApp,
                authority: context.authority,
                capturedType: context.capturedType
            ) {
                await recordSuccess(completion, parseStartedAt, parsedAt)
            } else {
                await recordSkipped()
            }
        } catch is CancellationError {
            // Cancellation is advisory once an import has reached Store work.
        } catch {
            if !Task.isCancelled {
                await recordFailure(error, 0)
            }
        }
        await didFinish()
    }

    nonisolated private static func rollbackImportedImageIfNeeded(
        _ result: ClipboardMonitorPayloadImportResult,
        store: ClipboardHistoryStore
    ) async {
        switch result {
        case .image(let importedImage):
            await store.rollbackImportedClipboardImage(importedImage.storedImage)
        case .pdf(let importedPDF):
            await store.rollbackImportedOwnedFile(importedPDF.storedFile)
        case .richText:
            break
        }
    }

    private func preparePayloadImport(
        _ result: ClipboardMonitorPayloadImportResult,
        context: ClipboardMonitorPayloadImportContext
    ) async -> ClipboardMonitorPreparedImport? {
        guard isCurrentPayloadImport(context) else {
            return nil
        }

        switch result {
        case .image(let importedImage):
            let isSelfWrite = await store.consumeImageSelfWrite(
                changeCount: context.changeCount,
                fingerprint: importedImage.fingerprint
            )
            guard isCurrentPayloadImport(context),
                  !isSelfWrite else {
                if isSelfWrite {
                    payloadSkipReasons[context.id] = .selfWrite
                }
                return nil
            }
            return .image(importedImage)
        case .richText(let richTextResult):
            guard let richTextResult else {
                return nil
            }
            if shouldCaptureRichTextAsPlainText(richTextResult.plainText)
                || (
                    richTextResult.rawAsset == nil
                        && richTextResult.data.isEmpty
                ) {
                store.addText(richTextResult.plainText, sourceApp: context.sourceApp)
                return .completed(
                    storedType: "\(context.capturedType)AsText",
                    payloadByteCount: richTextResult.data.count
                )
            }
            return .richText(richTextResult)
        case .pdf(let importedPDF):
            return .pdf(importedPDF)
        }
    }

    nonisolated private static func commitPreparedPayloadImport(
        _ prepared: ClipboardMonitorPreparedImport,
        store: ClipboardHistoryStore,
        sourceApp: SourceAppInfo,
        authority: ClipboardImportAuthority,
        capturedType: String
    ) async throws -> (
        storedType: String,
        payloadByteCount: Int,
        status: ClipboardPayloadProcessingStatus
    )? {
        switch prepared {
        case .image(let importedImage):
            guard try await store.addImage(
                importedImage.storedImage,
                sourceApp: sourceApp,
                importAuthority: authority,
                automaticOCRAllowed: importedImage.previewSkipReason
                    != .previewLimitExceeded
            ) != nil else { return nil }
            return (
                capturedType,
                0,
                importedImage.previewSkipReason.map {
                    ClipboardPayloadProcessingStatus.skipped($0)
                } ?? .completed
            )
        case .richText(let result):
            guard try await store.addRichText(
                result.data,
                plainText: result.plainText,
                sourceApp: sourceApp,
                importAuthority: authority,
                rawAsset: result.rawAsset
            ) != nil else { return nil }
            return (
                capturedType,
                result.rawAsset?.stagedPayload.byteCount ?? result.data.count,
                result.previewSkipReason.map {
                    ClipboardPayloadProcessingStatus.skipped($0)
                } ?? .completed
            )
        case .pdf(let importedPDF):
            guard try await store.addOwnedFile(
                importedPDF.storedFile,
                sourceApp: sourceApp,
                importAuthority: authority,
                automaticOCRAllowed: importedPDF.previewSkipReason
                    != .ocrLimitExceeded
            ) != nil else { return nil }
            return (
                capturedType,
                importedPDF.storedFile.byteCount,
                importedPDF.previewSkipReason.map {
                    ClipboardPayloadProcessingStatus.skipped($0)
                } ?? .completed
            )
        case .completed(let storedType, let payloadByteCount):
            return (storedType, payloadByteCount, .completed)
        }
    }

    private func finishPayloadImport(
        _ completion: (
            storedType: String,
            payloadByteCount: Int,
            status: ClipboardPayloadProcessingStatus
        ),
        startedAt: CFAbsoluteTime,
        parseStartedAt: CFAbsoluteTime,
        parsedAt: CFAbsoluteTime,
        context: ClipboardMonitorPayloadImportContext
    ) {
        guard isMatchingPayloadImport(context) else { return }
        recordRichTextImportDuration(
            startedAt: startedAt,
            parseStartedAt: parseStartedAt,
            parsedAt: parsedAt,
            capturedType: completion.storedType,
            payloadByteCount: completion.payloadByteCount
        )
        payloadSkipReasons.removeValue(forKey: context.id)
        recordPayloadProcessingStatus(completion.status, context: context)
        importDiagnosticRecorder(.success(capturedType: completion.storedType))
    }

    private func recordPayloadImportStoreFailure(
        _ error: Error,
        context: ClipboardMonitorPayloadImportContext
    ) {
        guard isMatchingPayloadImport(context) else { return }
        PerformanceDiagnosticsService.shared.recordError(
            "clipboard.richText.import.failed",
            category: "clipboard",
            error: error,
            metadata: ["capturedType": context.capturedType, "payloadBytes": "0"]
        )
        NSLog("ClipEase failed to import rich text from clipboard: \(error.localizedDescription)")
    }

    private func completePayloadImportFailure(
        _ error: Error,
        payloadByteCount: Int,
        context: ClipboardMonitorPayloadImportContext
    ) {
        guard isCurrentPayloadImport(context) else { return }
        let processingReason = Self.payloadProcessingReason(for: error)
        recordPayloadProcessingStatus(
            .failed(processingReason),
            context: context
        )
        importDiagnosticRecorder(.failure(capturedType: context.capturedType))
        PerformanceDiagnosticsService.shared.recordError(
            "clipboard.richText.import.failed",
            category: "clipboard",
            error: ClipboardPayloadProcessingFailure(reason: processingReason),
            metadata: [
                "capturedType": context.capturedType,
                "payloadBytes": "\(payloadByteCount)"
            ]
        )
        NSLog("ClipEase failed to import clipboard payload: \(processingReason.rawValue)")
    }

    private func completePayloadImportWithoutCommit(
        context: ClipboardMonitorPayloadImportContext
    ) {
        guard isMatchingPayloadImport(context) else {
            return
        }
        let reason = payloadSkipReasons.removeValue(forKey: context.id)
            ?? .notPersisted
        recordPayloadProcessingStatus(.skipped(reason), context: context)
    }

    nonisolated private static func payloadProcessingReason(
        for error: Error
    ) -> ClipboardPayloadProcessingReason {
        if let stagingError = error as? ClipboardPayloadStagingError {
            return stagingError.processingReason
        }
        if let imageStagingError = error as? ClipboardImageStagingError {
            switch imageStagingError {
            case .diskFull:
                return .diskFull
            case .writeFailed, .thumbnailFailed:
                return .atomicWriteFailed
            case .encodingFailed, .outputTooLarge:
                return .importFailed
            }
        }
        if ClipboardFileSystemErrorClassifier.isDiskFull(error) {
            return .diskFull
        }
        return .importFailed
    }

    private func recordPayloadProcessingStatus(
        _ status: ClipboardPayloadProcessingStatus,
        context: ClipboardMonitorPayloadImportContext
    ) {
        payloadProcessingRecorder(
            ClipboardPayloadProcessingUpdate(
                id: context.id,
                capturedType: context.capturedType,
                status: status
            )
        )
    }

    private func isCurrentPayloadImport(_ context: ClipboardMonitorPayloadImportContext) -> Bool {
        isMatchingPayloadImport(context) && context.authority.isCurrent
    }

    private func isMatchingPayloadImport(_ context: ClipboardMonitorPayloadImportContext) -> Bool {
        !Task.isCancelled && activePayloadImport?.context.id == context.id
    }

    private func encodedImagePayload(
        availableTypes: Set<NSPasteboard.PasteboardType>,
        suppliedSnapshot: ClipboardMonitorPasteboardReadSnapshot? = nil
    ) -> (data: Data, type: NSPasteboard.PasteboardType)? {
        let preferredTypes: [NSPasteboard.PasteboardType] = [
            Self.publicPNGType,
            .tiff,
            Self.publicTIFFType,
            Self.publicJPEGType,
        ]
        let genericImageTypes = availableTypes
            .filter { type in
                UTType(type.rawValue)?.conforms(to: .image) == true
            }
            .sorted { $0.rawValue.localizedCaseInsensitiveCompare($1.rawValue) == .orderedAscending }
        var visitedTypes = Set<NSPasteboard.PasteboardType>()
        for type in preferredTypes + genericImageTypes
        where visitedTypes.insert(type).inserted && availableTypes.contains(type) {
            let data: Data?
            if let suppliedSnapshot {
                data = suppliedSnapshot.data(forType: type)
            } else {
                data = pasteboard.data(forType: type)
            }
            if let data {
                return (data, type)
            }
        }
        return nil
    }

    private func recordRichTextImportDuration(
        startedAt: CFAbsoluteTime,
        parseStartedAt: CFAbsoluteTime,
        parsedAt: CFAbsoluteTime,
        capturedType: String,
        payloadByteCount: Int
    ) {
        let finishedAt = CFAbsoluteTimeGetCurrent()
        PerformanceDiagnosticsService.shared.record(
            "clipboard.richText.import",
            category: "clipboard",
            durationMS: (finishedAt - startedAt) * 1_000,
            metadata: [
                "capturedType": capturedType,
                "mode": "background",
                "payloadBytes": "\(payloadByteCount)",
                "parseMS": Self.formatStageMS(parsedAt - parseStartedAt),
                "storeMS": Self.formatStageMS(finishedAt - parsedAt)
            ]
        )
    }

    private func shouldCapturePlainTextFirst(_ types: Set<NSPasteboard.PasteboardType>) -> Bool {
        types.contains(.string) &&
            !pasteboardHasFileSemanticTypes(types) &&
            !pasteboardHasRichTextTypes(types) &&
            !pasteboardHasImageTypes(types)
    }

    private func shouldCaptureRichTextAsPlainText(_ text: String) -> Bool {
        ColorParser.hexColor(from: text) != nil || URLParser.url(from: text) != nil
    }

    nonisolated static let defaultRichTextImporter: ClipboardRichTextImporter = { payload in
        switch payload {
        case .rtf(let data, let fallbackPlainText):
            richTextFromRTFData(data, fallbackPlainText: fallbackPlainText)
        case .html(let data, let fallbackPlainText):
            richTextFromHTMLData(data, fallbackPlainText: fallbackPlainText)
        }
    }

    nonisolated private static func richTextFromRTFData(
        _ data: Data,
        fallbackPlainText: String?
    ) -> ClipboardRichTextImportResult? {
        guard let plainText = plainTextForRichTextData(
            data,
            documentType: .rtf
        ) ?? fallbackPlainText,
              !plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        return ClipboardRichTextImportResult(data: data, plainText: plainText)
    }

    nonisolated private static func richTextFromHTMLData(
        _ data: Data,
        fallbackPlainText: String?
    ) -> ClipboardRichTextImportResult? {
        guard let attributedString = attributedString(from: data, documentType: .html) else {
            if let fallbackPlainText,
               !fallbackPlainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return ClipboardRichTextImportResult(data: Data(), plainText: fallbackPlainText)
            }
            return nil
        }

        let plainText = attributedString.string
        guard !plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let rtfData = try? attributedString.data(
                from: NSRange(location: 0, length: attributedString.length),
                documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
              ) else {
            return nil
        }

        return ClipboardRichTextImportResult(data: rtfData, plainText: plainText)
    }

    nonisolated private static func plainTextForRichTextData(
        _ data: Data,
        documentType: NSAttributedString.DocumentType
    ) -> String? {
        attributedString(from: data, documentType: documentType)?.string
    }

    nonisolated private static func attributedString(
        from data: Data,
        documentType: NSAttributedString.DocumentType
    ) -> NSAttributedString? {
        try? NSAttributedString(
            data: data,
            options: [.documentType: documentType],
            documentAttributes: nil
        )
    }

    private func localFileURLsFromPasteboard(availableTypes: Set<NSPasteboard.PasteboardType>) -> [URL] {
        guard pasteboardHasFileSemanticTypes(availableTypes) else {
            return []
        }

        var urls = fileURLsFromReadObjects(options: [.urlReadingFileURLsOnly: true])
        urls.append(contentsOf: fileURLsFromFilenamesPropertyList())
        urls.append(contentsOf: fileURLs(fromPasteboardString: pasteboard.string(forType: .fileURL)))

        for item in pasteboard.pasteboardItems ?? [] {
            urls.append(contentsOf: fileURLs(from: item))
        }

        var seenPaths = Set<String>()
        return urls.filter { url in
            guard url.isFileURL else {
                return false
            }

            return seenPaths.insert(url.standardizedFileURL.path).inserted
        }
    }

    private static func monitoredSourceApp(_ current: SourceAppInfo) -> SourceAppInfo {
        current.isClipEase ? .clipease : current
    }

    private static func isSameSource(_ lhs: SourceAppInfo, _ rhs: SourceAppInfo) -> Bool {
        if lhs.bundleID != nil || rhs.bundleID != nil {
            return lhs.bundleID == rhs.bundleID
        }
        return lhs.name == rhs.name
    }

    private func fileURLsFromReadObjects(options: [NSPasteboard.ReadingOptionKey: Any]) -> [URL] {
        pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: options
        )?.compactMap { object -> URL? in
            let url: URL?
            if let swiftURL = object as? URL {
                url = swiftURL
            } else if let nsURL = object as? NSURL {
                url = nsURL as URL
            } else {
                url = nil
            }

            guard let url, url.isFileURL else {
                return nil
            }

            return url.standardizedFileURL
        } ?? []
    }

    private func fileURLsFromFilenamesPropertyList() -> [URL] {
        guard let propertyList = pasteboard.propertyList(forType: Self.filenamesPasteboardType) else {
            return []
        }

        return fileURLs(fromFilenamesPropertyList: propertyList)
    }

    private func fileURLs(from item: NSPasteboardItem) -> [URL] {
        var urls: [URL] = []

        for type in fileURLTypes {
            urls.append(contentsOf: fileURLs(fromPasteboardString: item.string(forType: type)))
            urls.append(contentsOf: fileURLs(fromPasteboardData: item.data(forType: type)))
        }

        if itemHasPathBackedFileSemanticTypes(item) {
            urls.append(contentsOf: fileURLs(fromFilenamesPropertyList: item.propertyList(forType: Self.filenamesPasteboardType)))
            urls.append(contentsOf: fileURLs(fromPathText: item.string(forType: .string)))
        }

        return urls
    }

    private var fileURLTypes: [NSPasteboard.PasteboardType] {
        [
            .fileURL,
            Self.publicFileURLPasteboardType,
            .URL,
            Self.fileURLPromisePasteboardType,
        ]
    }

    private var fileSemanticTypes: [NSPasteboard.PasteboardType] {
        fileURLTypes + [
            Self.filenamesPasteboardType,
            Self.filePromiseContentPasteboardType,
            Self.filePromiseMetadataPasteboardType,
        ]
    }

    private func pasteboardHasFileSemanticTypes(_ types: Set<NSPasteboard.PasteboardType>) -> Bool {
        types.contains { fileSemanticTypes.contains($0) }
    }

    private func pasteboardHasRichTextTypes(_ types: Set<NSPasteboard.PasteboardType>) -> Bool {
        types.contains(.rtf) || types.contains(.html)
    }

    private func pasteboardHasImageTypes(_ types: Set<NSPasteboard.PasteboardType>) -> Bool {
        types.contains(.tiff) ||
            types.contains(Self.publicPNGType) ||
            types.contains(Self.publicTIFFType) ||
            types.contains(Self.publicJPEGType) ||
            types.contains { UTType($0.rawValue)?.conforms(to: .image) == true }
    }

    private func itemHasPathBackedFileSemanticTypes(_ item: NSPasteboardItem) -> Bool {
        item.types.contains { pathBackedFileSemanticTypes.contains($0) }
    }

    private var pathBackedFileSemanticTypes: [NSPasteboard.PasteboardType] {
        [
            Self.filenamesPasteboardType,
            Self.filePromiseContentPasteboardType,
            Self.filePromiseMetadataPasteboardType,
        ]
    }

    private func fileURLs(fromFilenamesPropertyList propertyList: Any?) -> [URL] {
        if let paths = propertyList as? [String] {
            return paths.compactMap(fileURLFromExistingPath)
        }

        if let paths = propertyList as? NSArray {
            return paths.compactMap { value in
                guard let path = value as? String else {
                    return nil
                }

                return fileURLFromExistingPath(path)
            }
        }

        if let path = propertyList as? String {
            return fileURLs(fromPathText: path)
        }

        return []
    }

    private func fileURLs(fromPasteboardData data: Data?) -> [URL] {
        guard let data else {
            return []
        }

        if let url = URL(dataRepresentation: data, relativeTo: nil), url.isFileURL {
            return [url.standardizedFileURL]
        }

        return fileURLs(fromPasteboardString: String(data: data, encoding: .utf8))
    }

    private func fileURLs(fromPasteboardString text: String?) -> [URL] {
        guard let text else {
            return []
        }

        return fileURLStrings(from: text).compactMap { value in
            guard let url = URL(string: value), url.isFileURL else {
                return nil
            }

            return url.standardizedFileURL
        }
    }

    private func fileURLs(fromPathText text: String?) -> [URL] {
        guard let text else {
            return []
        }

        let paths = pathStrings(from: text)
        guard !paths.isEmpty else {
            return []
        }

        let urls = paths.compactMap(fileURLFromExistingPath)
        guard urls.count == paths.count else {
            return []
        }

        return urls
    }

    private func fileURLStrings(from text: String) -> [String] {
        text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.lowercased().hasPrefix("file://") }
    }

    private func pathStrings(from text: String) -> [String] {
        text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func fileURLFromExistingPath(_ path: String) -> URL? {
        let normalizedPath = NSString(string: path).expandingTildeInPath
        guard normalizedPath.hasPrefix("/"),
              FileManager.default.fileExists(atPath: normalizedPath) else {
            return nil
        }

        return URL(fileURLWithPath: normalizedPath).standardizedFileURL
    }
}

private extension ClipboardMonitorPayloadImportRequest {
    var payloadByteCount: Int {
        switch self {
        case .image(let stagedPayload, _),
             .richText(let stagedPayload, _),
             .pdf(let stagedPayload):
            stagedPayload.byteCount
        }
    }

    func discardStagedPayload() {
        switch self {
        case .image(let stagedPayload, _),
             .richText(let stagedPayload, _),
             .pdf(let stagedPayload):
            stagedPayload.discard()
        }
    }
}

private extension ClipboardPayloadImportQueueError {
    var processingReason: ClipboardPayloadProcessingReason {
        switch self {
        case .residentTaskLimitExceeded:
            .residentTaskLimitExceeded
        case .retainedDataLimitExceeded:
            .retainedDataLimitExceeded
        }
    }
}
