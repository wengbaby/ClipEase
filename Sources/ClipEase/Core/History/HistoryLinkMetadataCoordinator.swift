import Foundation

protocol LinkMetadataLoading: Sendable {
    func pageMetadata(for url: URL) async -> LinkPageMetadata?
    func previewImage(from pageMetadata: LinkPageMetadata) async -> LinkPreviewDecodedImage?
}

struct LiveLinkMetadataLoader: LinkMetadataLoading {
    private let fetcher: LinkTitleFetcher

    init(fetcher: LinkTitleFetcher = .live()) {
        self.fetcher = fetcher
    }

    func pageMetadata(for url: URL) async -> LinkPageMetadata? {
        await fetcher.loadPageMetadata(for: url)
    }

    func previewImage(from pageMetadata: LinkPageMetadata) async -> LinkPreviewDecodedImage? {
        await fetcher.loadPreviewImage(from: pageMetadata)
    }
}

@MainActor
final class HistoryLinkMetadataCoordinator {
    private var taskByItemID: [ClipboardItem.ID: Task<Void, Never>] = [:]
    private var generationByItemID: [ClipboardItem.ID: Int] = [:]
    private var service = LinkMetadataService()
    private let limiter: LinkMetadataFetchLimiter
    private let loader: any LinkMetadataLoading
    private let stagedImageBarrier: @Sendable (StoredClipboardImage) async -> Void

    init(
        limiter: LinkMetadataFetchLimiter = .shared,
        loader: any LinkMetadataLoading = LiveLinkMetadataLoader(),
        stagedImageBarrier: @escaping @Sendable (StoredClipboardImage) async -> Void = { _ in }
    ) {
        self.limiter = limiter
        self.loader = loader
        self.stagedImageBarrier = stagedImageBarrier
    }

    deinit {
        for task in taskByItemID.values {
            task.cancel()
        }
    }

    @discardableResult
    func fetch(
        id: ClipboardItem.ID,
        url: URL,
        persistence: ClipboardHistoryPersistence,
        apply: @escaping @MainActor (_ title: String?, _ storedImage: StoredClipboardImage?, _ id: ClipboardItem.ID, _ url: URL) -> Void
    ) -> Task<Void, Never> {
        fetch(
            id: id,
            url: url,
            persistence: persistence,
            applying: { title, storedImage, id, url in
                apply(title, storedImage, id, url)
                return true
            }
        )
    }

    @discardableResult
    func fetch(
        id: ClipboardItem.ID,
        url: URL,
        persistence: ClipboardHistoryPersistence,
        applying apply: @escaping @MainActor (_ title: String?, _ storedImage: StoredClipboardImage?, _ id: ClipboardItem.ID, _ url: URL) -> Bool
    ) -> Task<Void, Never> {
        taskByItemID[id]?.cancel()
        let generation = service.nextGeneration(for: id)
        generationByItemID[id] = generation
        let limiter = limiter
        let loader = loader
        let stagedImageBarrier = stagedImageBarrier
        let task = Task.detached(priority: .utility) { [weak self] in
            var didEnterLimiter = false
            defer {
                if didEnterLimiter {
                    Task {
                        await limiter.finishTurn()
                    }
                }
            }

            guard await limiter.waitForTurn() else {
                await self?.finishTask(for: id, generation: generation)
                return
            }
            didEnterLimiter = true
            guard !Task.isCancelled,
                  await self?.isCurrentTask(for: id, generation: generation) == true else {
                await self?.finishTask(for: id, generation: generation)
                return
            }

            guard let pageMetadata = await loader.pageMetadata(for: url) else {
                await self?.finishTask(for: id, generation: generation)
                return
            }

            guard !Task.isCancelled,
                  await self?.isCurrentTask(for: id, generation: generation) == true else {
                await self?.finishTask(for: id, generation: generation)
                return
            }

            if let title = pageMetadata.title,
               await self?.applyIfCurrent(
                   title: title,
                   storedImage: nil,
                   id: id,
                   url: url,
                   generation: generation,
                   apply: apply
               ) != true {
                await self?.finishTask(for: id, generation: generation)
                return
            }

            await Task.yield()
            guard !Task.isCancelled,
                  await self?.isCurrentTask(for: id, generation: generation) == true else {
                await self?.finishTask(for: id, generation: generation)
                return
            }

            let storedImage = await loader.previewImage(from: pageMetadata)
                .flatMap(persistence.saveLinkPreviewImage)

            guard let storedImage else {
                await self?.finishTask(for: id, generation: generation)
                return
            }

            await stagedImageBarrier(storedImage)

            guard !Task.isCancelled,
                  await self?.isCurrentTask(for: id, generation: generation) == true else {
                persistence.discardStagedAttachment(storedImage.reservation)
                await self?.finishTask(for: id, generation: generation)
                return
            }

            let wasAccepted = await self?.applyIfCurrent(
                title: nil,
                storedImage: storedImage,
                id: id,
                url: url,
                generation: generation,
                apply: apply
            ) == true
            if !wasAccepted {
                persistence.discardStagedAttachment(storedImage.reservation)
            }
            await self?.finishTask(for: id, generation: generation)
        }
        taskByItemID[id] = task
        return task
    }

    func cancelTasks(for items: [ClipboardItem]) {
        cancelTasks(for: Set(items.map(\.id)))
    }

    func cancelTasks(for ids: Set<ClipboardItem.ID>) {
        for id in ids {
            taskByItemID[id]?.cancel()
            taskByItemID[id] = nil
            generationByItemID[id] = nil
        }
        service.cancelTasks(for: ids)
    }

    func cancelAllTasks() {
        for task in taskByItemID.values {
            task.cancel()
        }
        taskByItemID.removeAll()
        generationByItemID.removeAll()
        service.cancelAllTasks()
    }

    func hasInFlightTask(for id: ClipboardItem.ID) -> Bool {
        service.hasInFlightTask(for: id)
    }

    private func isCurrentTask(for id: ClipboardItem.ID, generation: Int) -> Bool {
        generationByItemID[id] == generation && service.hasInFlightTask(for: id)
    }

    private func applyIfCurrent(
        title: String?,
        storedImage: StoredClipboardImage?,
        id: ClipboardItem.ID,
        url: URL,
        generation: Int,
        apply: @MainActor (_ title: String?, _ storedImage: StoredClipboardImage?, _ id: ClipboardItem.ID, _ url: URL) -> Bool
    ) -> Bool {
        guard isCurrentTask(for: id, generation: generation) else {
            return false
        }

        return apply(title, storedImage, id, url)
    }

    private func finishTask(for id: ClipboardItem.ID, generation: Int) {
        guard generationByItemID[id] == generation,
              service.finishTask(for: id, generation: generation) else {
            return
        }

        generationByItemID[id] = nil
        taskByItemID[id] = nil
    }
}

actor LinkMetadataFetchLimiter {
    static let shared = LinkMetadataFetchLimiter()

    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Bool, Never>
    }

    private let limit: Int
    private var activeCount = 0
    private var waiters: [Waiter] = []

    init(limit: Int = 3) {
        self.limit = max(1, limit)
    }

    func waitForTurn() async -> Bool {
        guard !Task.isCancelled else {
            return false
        }
        if activeCount < limit {
            activeCount += 1
            return true
        }

        let waiterID = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !Task.isCancelled else {
                    continuation.resume(returning: false)
                    return
                }
                waiters.append(
                    Waiter(id: waiterID, continuation: continuation)
                )
            }
        } onCancel: {
            Task {
                await self.cancelWaiter(id: waiterID)
            }
        }
    }

    func finishTurn() {
        if waiters.isEmpty {
            activeCount = max(0, activeCount - 1)
            return
        }

        let next = waiters.removeFirst()
        next.continuation.resume(returning: true)
    }

    func queuedWaiterCount() -> Int {
        waiters.count
    }

    private func cancelWaiter(id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else {
            return
        }
        let waiter = waiters.remove(at: index)
        waiter.continuation.resume(returning: false)
    }
}
