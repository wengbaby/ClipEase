import Foundation

@MainActor
final class HistoryOCRCoordinator {
    private var taskByItemID: [ClipboardItem.ID: Task<Void, Never>] = [:]
    private let limiter: ClipboardOCRConcurrencyLimiter
    private let service: ClipboardOCRService

    init(
        limiter: ClipboardOCRConcurrencyLimiter = .shared,
        service: ClipboardOCRService = .shared
    ) {
        self.limiter = limiter
        self.service = service
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
        applyResult: @escaping @MainActor (_ result: ClipboardOCRMatch, _ status: ClipboardOCRStatus, _ id: ClipboardItem.ID) -> Void
    ) {
        guard item.ocrStatus == .pending else {
            return
        }

        taskByItemID[item.id]?.cancel()
        taskByItemID[item.id] = Task(priority: .utility) { [weak self] in
            await self?.performOCR(
                for: item,
                sourceURL: sourceURL,
                setProcessing: setProcessing,
                applyResult: applyResult
            )
        }
    }

    func cancelTasks(for items: [ClipboardItem]) {
        cancelTasks(for: Set(items.map(\.id)))
    }

    func cancelTasks(for ids: Set<ClipboardItem.ID>) {
        for id in ids {
            taskByItemID[id]?.cancel()
            taskByItemID[id] = nil
        }
    }

    func cancelAllTasks() {
        for task in taskByItemID.values {
            task.cancel()
        }
        taskByItemID.removeAll()
    }

    func hasInFlightTask(for id: ClipboardItem.ID) -> Bool {
        taskByItemID[id] != nil
    }

    private func performOCR(
        for item: ClipboardItem,
        sourceURL: URL?,
        setProcessing: @escaping @MainActor (_ id: ClipboardItem.ID) -> Void,
        applyResult: @escaping @MainActor (_ result: ClipboardOCRMatch, _ status: ClipboardOCRStatus, _ id: ClipboardItem.ID) -> Void
    ) async {
        guard item.ocrStatus == .pending else {
            finishTask(for: item.id)
            return
        }

        guard let sourceURL else {
            applyResult(Self.emptyResult, .failed, item.id)
            finishTask(for: item.id)
            return
        }

        await limiter.waitForTurn()
        defer {
            Task {
                await limiter.finishTurn()
            }
        }

        guard !Task.isCancelled else {
            finishTask(for: item.id)
            return
        }

        setProcessing(item.id)

        let result: ClipboardOCRMatch?
        switch item.type {
        case .image:
            result = await service.recognizeImage(at: sourceURL)
        case .file:
            result = await service.recognizePDF(at: sourceURL)
        default:
            result = nil
        }

        guard !Task.isCancelled else {
            finishTask(for: item.id)
            return
        }

        if let result {
            applyResult(result, .completed, item.id)
        } else {
            applyResult(Self.emptyResult, .failed, item.id)
        }
        finishTask(for: item.id)
    }

    private func finishTask(for id: ClipboardItem.ID) {
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

actor ClipboardOCRConcurrencyLimiter {
    static let shared = ClipboardOCRConcurrencyLimiter()

    private let idleLimit: Int
    private let interactiveLimit: Int
    private var isInteractionActive = false
    private var activeCount = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(idleLimit: Int = 5, interactiveLimit: Int = 2) {
        self.idleLimit = idleLimit
        self.interactiveLimit = interactiveLimit
    }

    func setInteractionActive(_ isActive: Bool) {
        isInteractionActive = isActive
        resumeAvailableWaiters()
    }

    func waitForTurn() async {
        if activeCount < currentLimit {
            activeCount += 1
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
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
            next.resume()
        }
    }
}
