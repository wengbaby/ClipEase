import AppKit
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
}

typealias ClipboardRichTextImporter = @Sendable (
    ClipboardRichTextPasteboardPayload
) async -> ClipboardRichTextImportResult?

enum ClipboardMonitorPayloadImportRequest: Sendable {
    case image(data: Data, declaredTypeIdentifier: String)
    case richText(ClipboardRichTextPasteboardPayload)
}

enum ClipboardMonitorPayloadImportResult: Sendable {
    case image(ClipboardImportedImage)
    case richText(ClipboardRichTextImportResult?)
}

extension ClipboardMonitorPayloadImportResult {
    static func image(_ storedImage: StoredClipboardImage) -> ClipboardMonitorPayloadImportResult {
        .image(ClipboardImportedImage(storedImage: storedImage, fingerprint: nil))
    }
}

private enum ClipboardMonitorPreparedImport: Sendable {
    case image(ClipboardImportedImage)
    case richText(ClipboardRichTextImportResult)
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

private struct ClipboardMonitorPendingPayloadImport: Sendable {
    let request: ClipboardMonitorPayloadImportRequest
    let context: ClipboardMonitorPayloadImportContext
    let completion: ClipboardMonitorPayloadImportCompletion
}

@MainActor
protocol ClipboardMonitorTimerToken: AnyObject {
    var timeInterval: TimeInterval { get }
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
    case unsupported

    var selfWritePayload: ClipboardSelfWritePayload? {
        switch self {
        case .text(let text, _):
            .text(text)
        case .files(let urls):
            .files(urls)
        case .richText(let payload):
            payload.fallbackPlainText.map(ClipboardSelfWritePayload.richText)
        case .image, .unsupported:
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
    let activeInterval: TimeInterval
    let idleInterval: TimeInterval
    let idleThreshold: Int

    static let `default` = ClipboardPollingPolicy(
        activeInterval: 0.25,
        idleInterval: 0.75,
        idleThreshold: 12
    )

    func interval(afterUnchangedPollCount unchangedPollCount: Int) -> TimeInterval {
        unchangedPollCount >= idleThreshold ? idleInterval : activeInterval
    }
}

@MainActor
final class ClipboardMonitor {
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
    private let sourceAppProvider: () -> SourceAppInfo
    private let isPaused: () -> Bool
    private let isIgnored: (String?) -> Bool
    private let timerScheduler: ClipboardMonitorTimerScheduler
    private let pasteboardSnapshotProvider: (@MainActor () -> ClipboardMonitorPasteboardReadSnapshot)?
    private let payloadImporter: ClipboardMonitorPayloadImporter
    private let payloadImportRunnerEventRecorder: ClipboardMonitorPayloadImportRunnerEventRecorder
    private let importDiagnosticRecorder: ClipboardMonitorImportDiagnosticRecorder
    var shouldSuppressRecording: (() -> Bool)?
    private var timer: (any ClipboardMonitorTimerToken)?
    private var lastChangeCount: Int
    private var stableSourceApp: SourceAppInfo
    private var unchangedPollCount = 0
    private var activePayloadImport: ClipboardMonitorActivePayloadImport?
    private var pendingPayloadImports: [ClipboardMonitorPendingPayloadImport] = []

    var hasActivePayloadImportForTesting: Bool {
        activePayloadImport != nil
    }

    var hasCurrentImportAuthorityForTesting: Bool {
        activePayloadImport?.context.authority.isCurrent == true
    }

    var payloadImportPumpDiagnosticsForTesting: ClipboardMonitorPayloadImportPumpDiagnostics {
        ClipboardMonitorPayloadImportPumpDiagnostics(
            hasActiveImport: activePayloadImport != nil,
            hasPendingImport: !pendingPayloadImports.isEmpty,
            ownedRequestCount: (activePayloadImport == nil ? 0 : 1) + pendingPayloadImports.count
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
            isIgnored: { ignoredAppSettings.contains(bundleID: $0) }
        )
    }

    init(
        store: ClipboardHistoryStore,
        pasteboard: NSPasteboard,
        pollingPolicy: ClipboardPollingPolicy = .default,
        sourceAppProvider: @escaping () -> SourceAppInfo,
        isPaused: @escaping () -> Bool,
        isIgnored: @escaping (String?) -> Bool,
        timerScheduler: ClipboardMonitorTimerScheduler = .live,
        pasteboardSnapshotProvider: (@MainActor () -> ClipboardMonitorPasteboardReadSnapshot)? = nil,
        richTextImporter: ClipboardRichTextImporter? = nil,
        payloadImporter: ClipboardMonitorPayloadImporter? = nil,
        payloadImportRunnerEventRecorder: @escaping ClipboardMonitorPayloadImportRunnerEventRecorder = { _ in },
        importDiagnosticRecorder: @escaping ClipboardMonitorImportDiagnosticRecorder = { _ in }
    ) {
        self.store = store
        self.pollingPolicy = pollingPolicy
        self.pasteboard = pasteboard
        self.sourceAppProvider = sourceAppProvider
        self.isPaused = isPaused
        self.isIgnored = isIgnored
        self.timerScheduler = timerScheduler
        self.pasteboardSnapshotProvider = pasteboardSnapshotProvider
        self.payloadImportRunnerEventRecorder = payloadImportRunnerEventRecorder
        self.importDiagnosticRecorder = importDiagnosticRecorder
        if let payloadImporter {
            self.payloadImporter = payloadImporter
        } else {
            let boundedImporter = store.makeClipboardPayloadImporter()
            self.payloadImporter = { request in
                switch request {
                case .image(let data, let declaredTypeIdentifier):
                    return .image(try await boundedImporter.importImageForMonitor(
                        data,
                        declaredTypeIdentifier: declaredTypeIdentifier
                    ))
                case .richText(let payload):
                    if let richTextImporter {
                        return .richText(await richTextImporter(payload))
                    }
                    return .richText(try await boundedImporter.importRichText(payload))
                }
            }
        }
        self.lastChangeCount = pasteboardSnapshotProvider?().changeCount ?? pasteboard.changeCount
        self.stableSourceApp = Self.monitoredSourceApp(sourceAppProvider())
    }

    deinit {
        activePayloadImport?.context.authority.invalidate()
        activePayloadImport?.task?.cancel()
        for pending in pendingPayloadImports {
            pending.context.authority.invalidate()
            pending.completion.finish()
        }
    }

    func start() {
        guard timer == nil else {
            return
        }

        scheduleTimer(interval: pollingPolicy.activeInterval)
    }

    private func scheduleTimer(interval: TimeInterval) {
        timer?.invalidate()
        timer = timerScheduler.schedule(interval) { [weak self] in
            self?.pollNow()
        }
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
        if let timer {
            timer.invalidate()
            self.timer = nil
        }
        unchangedPollCount = 0
        payloadImportGeneration &+= 1
        invalidateActivePayloadImport()
        clearPendingPayloadImports()
    }

    @discardableResult
    func pollNow() -> Task<Void, Never>? {
        let startedAt = CFAbsoluteTimeGetCurrent()
        let currentSourceApp = Self.monitoredSourceApp(sourceAppProvider())
        let suppliedSnapshot = pasteboardSnapshotProvider?()
        let currentChangeCount = suppliedSnapshot?.changeCount ?? pasteboard.changeCount
        guard currentChangeCount != lastChangeCount else {
            stableSourceApp = currentSourceApp
            unchangedPollCount += 1
            updatePollingIntervalForCurrentActivity()
            return nil
        }

        unchangedPollCount = 0
        updatePollingIntervalForCurrentActivity()
        lastChangeCount = currentChangeCount
        payloadImportGeneration &+= 1
        let changeDetectedAt = CFAbsoluteTimeGetCurrent()
        let availableTypes = suppliedSnapshot?.types ?? Set(pasteboard.types ?? [])
        let snapshot = pasteboardSnapshot(availableTypes: availableTypes, suppliedSnapshot: suppliedSnapshot)
        let typesLoadedAt = CFAbsoluteTimeGetCurrent()
        guard !store.consumeSelfWrite(
            changeCount: currentChangeCount,
            payload: snapshot.selfWritePayload
        ) else {
            return nil
        }
        guard shouldSuppressRecording?() != true else {
            return nil
        }
        guard !isPaused() else {
            return nil
        }

        let sourceApp = currentSourceApp
        let sourceResolvedAt = CFAbsoluteTimeGetCurrent()
        guard !isIgnored(sourceApp.bundleID) else {
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

        switch snapshot {
        case .text(let text, let fastPath):
            let payloadLoadedAt = CFAbsoluteTimeGetCurrent()
            store.addText(text, sourceApp: sourceApp)
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
        case .image:
            return nil
        case .unsupported:
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
        request: ClipboardMonitorPayloadImportRequest,
        sourceApp: SourceAppInfo,
        changeCount: Int,
        startedAt: CFAbsoluteTime,
        capturedType: String,
        generation: UInt64
    ) -> Task<Void, Never> {
        let pending = ClipboardMonitorPendingPayloadImport(
            request: request,
            context: ClipboardMonitorPayloadImportContext(
                id: UUID(),
                sourceApp: sourceApp,
                changeCount: changeCount,
                startedAt: startedAt,
                capturedType: capturedType,
                generation: generation,
                authority: ClipboardImportAuthority()
            ),
            completion: ClipboardMonitorPayloadImportCompletion()
        )
        guard activePayloadImport != nil else {
            startPayloadImport(pending)
            return pending.completion.task
        }

        pendingPayloadImports.append(pending)
        return pending.completion.task
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
                didFinish: { [weak self] in
                    runnerEventRecorder(.finished(context.id))
                    await self?.completeActivePayloadImport(ifCurrent: context.id)
                }
            )
            completion.finish()
        }
        active.task = task
    }

    private func invalidateActivePayloadImport() {
        activePayloadImport?.context.authority.invalidate()
        activePayloadImport?.task?.cancel()
    }

    private func clearPendingPayloadImports() {
        for pending in pendingPayloadImports {
            pending.context.authority.invalidate()
            pending.completion.finish()
        }
        pendingPayloadImports.removeAll()
    }

    private func completeActivePayloadImport(ifCurrent taskID: UUID) {
        guard let active = activePayloadImport,
              active.context.id == taskID else {
            return
        }
        active.completion.finish()
        activePayloadImport = nil
        guard !pendingPayloadImports.isEmpty else {
            return
        }
        let pending = pendingPayloadImports.removeFirst()
        startPayloadImport(pending)
    }

    nonisolated private static func runPayloadImport(
        _ request: ClipboardMonitorPayloadImportRequest,
        importer: @escaping ClipboardMonitorPayloadImporter,
        store: ClipboardHistoryStore,
        context: ClipboardMonitorPayloadImportContext,
        prepare: @escaping @Sendable (ClipboardMonitorPayloadImportResult) async -> ClipboardMonitorPreparedImport?,
        recordSuccess: @escaping @Sendable (
            (storedType: String, payloadByteCount: Int),
            CFAbsoluteTime,
            CFAbsoluteTime
        ) async -> Void,
        recordFailure: @escaping @Sendable (Error, Int) async -> Void,
        didFinish: @escaping @Sendable () async -> Void
    ) async {
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
        if case .image(let importedImage) = result {
            await store.rollbackImportedClipboardImage(importedImage.storedImage)
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
            let isSelfWrite: Bool
            if let fingerprint = importedImage.fingerprint {
                isSelfWrite = await store.consumeImageSelfWrite(
                    changeCount: context.changeCount,
                    fingerprint: fingerprint
                )
            } else {
                isSelfWrite = false
            }
            guard isCurrentPayloadImport(context),
                  !isSelfWrite else {
                return nil
            }
            return .image(importedImage)
        case .richText(let richTextResult):
            guard let richTextResult else {
                return nil
            }
            if richTextResult.data.isEmpty || shouldCaptureRichTextAsPlainText(richTextResult.plainText) {
                store.addText(richTextResult.plainText, sourceApp: context.sourceApp)
                return .completed(
                    storedType: "\(context.capturedType)AsText",
                    payloadByteCount: richTextResult.data.count
                )
            }
            return .richText(richTextResult)
        }
    }

    nonisolated private static func commitPreparedPayloadImport(
        _ prepared: ClipboardMonitorPreparedImport,
        store: ClipboardHistoryStore,
        sourceApp: SourceAppInfo,
        authority: ClipboardImportAuthority,
        capturedType: String
    ) async throws -> (storedType: String, payloadByteCount: Int)? {
        switch prepared {
        case .image(let importedImage):
            guard try await store.addImage(
                importedImage.storedImage,
                sourceApp: sourceApp,
                importAuthority: authority
            ) != nil else { return nil }
            return (capturedType, 0)
        case .richText(let result):
            guard try await store.addRichText(
                result.data,
                plainText: result.plainText,
                sourceApp: sourceApp,
                importAuthority: authority
            ) != nil else { return nil }
            return (capturedType, result.data.count)
        case .completed(let storedType, let payloadByteCount):
            return (storedType, payloadByteCount)
        }
    }

    private func finishPayloadImport(
        _ completion: (storedType: String, payloadByteCount: Int),
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
        importDiagnosticRecorder(.failure(capturedType: context.capturedType))
        PerformanceDiagnosticsService.shared.recordError(
            "clipboard.richText.import.failed",
            category: "clipboard",
            error: error,
            metadata: [
                "capturedType": context.capturedType,
                "payloadBytes": "\(payloadByteCount)"
            ]
        )
        NSLog("ClipEase failed to import clipboard payload: \(error.localizedDescription)")
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
        case .image(let data, _):
            data.count
        case .richText(let payload):
            payload.data.count
        }
    }
}
