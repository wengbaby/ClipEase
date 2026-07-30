import Foundation

@MainActor
final class HistoryOCRCoordinator {
    typealias ImageRecognizer = @Sendable (URL) async -> ClipboardOCRMatch?
    typealias PDFRecognizer = @Sendable (URL) async -> ClipboardOCRMatch?
    private typealias ServiceRecognizer = @Sendable (URL) async -> ClipboardOCRServiceResult

    private struct TaskEntry {
        let generation: UUID
        let task: Task<Void, Never>
    }

    private var taskByItemID: [ClipboardItem.ID: TaskEntry] = [:]
    private let limiter: ClipboardOCRConcurrencyLimiter
    private let imageRecognizer: ServiceRecognizer
    private let pdfRecognizer: ServiceRecognizer
    private let itemTimeoutNanoseconds: UInt64

    init(
        limiter: ClipboardOCRConcurrencyLimiter = .shared,
        service: ClipboardOCRService = .shared,
        imageRecognizer: ImageRecognizer? = nil,
        pdfRecognizer: PDFRecognizer? = nil,
        itemTimeoutNanoseconds: UInt64 = ClipboardOCRInputPolicy.itemTimeoutNanoseconds
    ) {
        self.limiter = limiter
        if let imageRecognizer {
            self.imageRecognizer = { url in
                if let match = await imageRecognizer(url) {
                    return .completed(match)
                }
                return .failed(.recognitionFailed)
            }
        } else {
            self.imageRecognizer = { url in
                await service.recognizeImageResult(at: url)
            }
        }
        if let pdfRecognizer {
            self.pdfRecognizer = { url in
                if let match = await pdfRecognizer(url) {
                    return .completed(match)
                }
                return .failed(.recognitionFailed)
            }
        } else {
            self.pdfRecognizer = { url in
                await service.recognizePDFResult(at: url)
            }
        }
        self.itemTimeoutNanoseconds = itemTimeoutNanoseconds
    }

    func setInteractiveThrottleActive(_ isActive: Bool) {
        Task {
            await limiter.setInteractionActive(isActive)
        }
    }

    func enqueue(
        item: ClipboardItem,
        sourceURL: URL?,
        setProcessing: @escaping @MainActor (_ id: ClipboardItem.ID) -> Void,
        applyResult: @escaping @MainActor (_ result: ClipboardOCRMatch, _ status: ClipboardOCRStatus, _ id: ClipboardItem.ID) -> Void,
        applyOutcome: @escaping @MainActor (_ outcome: ClipboardOCRExecutionOutcome, _ id: ClipboardItem.ID) -> Void = { _, _ in }
    ) {
        guard item.ocrStatus == .pending else {
            return
        }

        taskByItemID[item.id]?.task.cancel()
        let generation = UUID()
        let task = Task(priority: .utility) { [weak self] in
            guard let self else {
                return
            }
            await self.performOCR(
                for: item,
                sourceURL: sourceURL,
                generation: generation,
                setProcessing: setProcessing,
                applyResult: applyResult,
                applyOutcome: applyOutcome
            )
        }
        taskByItemID[item.id] = TaskEntry(generation: generation, task: task)
    }

    func cancelTasks(for items: [ClipboardItem]) {
        cancelTasks(for: Set(items.map(\.id)))
    }

    func cancelTasks(for ids: Set<ClipboardItem.ID>) {
        for id in ids {
            taskByItemID[id]?.task.cancel()
            taskByItemID[id] = nil
        }
    }

    func cancelAllTasks() {
        for task in taskByItemID.values {
            task.task.cancel()
        }
        taskByItemID.removeAll()
    }

    func hasInFlightTask(for id: ClipboardItem.ID) -> Bool {
        taskByItemID[id] != nil
    }

    private func performOCR(
        for item: ClipboardItem,
        sourceURL: URL?,
        generation: UUID,
        setProcessing: @escaping @MainActor (_ id: ClipboardItem.ID) -> Void,
        applyResult: @escaping @MainActor (_ result: ClipboardOCRMatch, _ status: ClipboardOCRStatus, _ id: ClipboardItem.ID) -> Void,
        applyOutcome: @escaping @MainActor (_ outcome: ClipboardOCRExecutionOutcome, _ id: ClipboardItem.ID) -> Void
    ) async {
        guard item.ocrStatus == .pending else {
            finishTask(for: item.id, generation: generation)
            return
        }

        guard let sourceURL else {
            applyResult(Self.emptyResult, .failed, item.id)
            applyOutcome(.failed(.sourceUnavailable), item.id)
            finishTask(for: item.id, generation: generation)
            return
        }

        let turn = await limiter.waitForTurn()
        guard turn == .acquired else {
            if turn == .deferred {
                applyOutcome(.deferred, item.id)
            }
            finishTask(for: item.id, generation: generation)
            return
        }

        guard !Task.isCancelled else {
            await limiter.finishTurn()
            finishTask(for: item.id, generation: generation)
            return
        }

        setProcessing(item.id)
        let ocrInterval = PerformanceDiagnosticsSignposter.beginInterval(
            name: "asset.ocr",
            category: "ocr"
        )
        defer {
            PerformanceDiagnosticsSignposter.endInterval(ocrInterval)
        }

        let recognitionTask: Task<ClipboardOCRServiceResult, Never>
        switch item.type {
        case .image:
            recognitionTask = Task {
                await imageRecognizer(sourceURL)
            }
        case .file:
            recognitionTask = Task {
                await pdfRecognizer(sourceURL)
            }
        default:
            await limiter.finishTurn()
            applyResult(Self.emptyResult, .failed, item.id)
            applyOutcome(.skipped(.unsupportedItem), item.id)
            finishTask(for: item.id, generation: generation)
            return
        }

        let timedResult = await ClipboardOCRTimeout.wait(
            for: recognitionTask,
            nanoseconds: itemTimeoutNanoseconds
        )
        let serviceResult: ClipboardOCRServiceResult
        switch timedResult {
        case .value(let result):
            await limiter.finishTurn()
            serviceResult = result
        case .timedOut:
            recognitionTask.cancel()
            await limiter.finishTurn()
            serviceResult = .failed(.timedOut)
        case .cancelled:
            recognitionTask.cancel()
            await limiter.finishTurn()
            finishTask(for: item.id, generation: generation)
            return
        }

        guard !Task.isCancelled else {
            finishTask(for: item.id, generation: generation)
            return
        }

        switch serviceResult {
        case .completed(let result):
            applyResult(result, .completed, item.id)
            applyOutcome(.completed, item.id)
        case .skipped(let reason):
            applyResult(Self.emptyResult, .failed, item.id)
            applyOutcome(.skipped(reason), item.id)
        case .failed(let reason):
            applyResult(Self.emptyResult, .failed, item.id)
            applyOutcome(.failed(reason), item.id)
        }
        finishTask(for: item.id, generation: generation)
    }

    private func finishTask(for id: ClipboardItem.ID, generation: UUID) {
        guard taskByItemID[id]?.generation == generation else {
            return
        }
        taskByItemID[id] = nil
    }

    private static let emptyResult = ClipboardOCRMatch(
        text: "",
        emails: [],
        phoneNumbers: [],
        urls: [],
        textRegions: []
    )
}

enum ClipboardOCRTurn: Sendable, Equatable {
    case acquired
    case deferred
    case cancelled
}

actor ClipboardOCRConcurrencyLimiter {
    static let shared = ClipboardOCRConcurrencyLimiter()
    static let defaultIdleLimit = 2
    static let defaultInteractiveLimit = 1
    static let defaultMaximumWaitingCount = 64

    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<ClipboardOCRTurn, Never>
    }

    private let idleLimit: Int
    private let interactiveLimit: Int
    private let maximumWaitingCount: Int
    private var isInteractionActive = false
    private var activeCount = 0
    private var waiters: [Waiter] = []

    init(
        idleLimit: Int = defaultIdleLimit,
        interactiveLimit: Int = defaultInteractiveLimit,
        maximumWaitingCount: Int = defaultMaximumWaitingCount
    ) {
        self.idleLimit = max(0, idleLimit)
        self.interactiveLimit = max(0, interactiveLimit)
        self.maximumWaitingCount = max(0, maximumWaitingCount)
    }

    func setInteractionActive(_ isActive: Bool) {
        isInteractionActive = isActive
        resumeAvailableWaiters()
    }

    func waitForTurn() async -> ClipboardOCRTurn {
        guard !Task.isCancelled else {
            return .cancelled
        }
        if activeCount < currentLimit {
            activeCount += 1
            return .acquired
        }
        guard waiters.count < maximumWaitingCount else {
            return .deferred
        }

        let waiterID = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                waiters.append(Waiter(id: waiterID, continuation: continuation))
            }
        } onCancel: {
            Task {
                await self.cancelWaiter(id: waiterID)
            }
        }
    }

    func finishTurn() {
        activeCount = max(0, activeCount - 1)
        resumeAvailableWaiters()
    }

    private var currentLimit: Int {
        isInteractionActive ? interactiveLimit : idleLimit
    }

    private func resumeAvailableWaiters() {
        while activeCount < currentLimit, !waiters.isEmpty {
            activeCount += 1
            let next = waiters.removeFirst()
            next.continuation.resume(returning: .acquired)
        }
    }

    private func cancelWaiter(id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else {
            return
        }
        let waiter = waiters.remove(at: index)
        waiter.continuation.resume(returning: .cancelled)
    }
}
