import AppKit
import Foundation

@MainActor
final class HistoryLinkMetadataCoordinator {
    private var taskByItemID: [ClipboardItem.ID: Task<Void, Never>] = [:]
    private var service = LinkMetadataService()
    private let limiter: LinkMetadataFetchLimiter

    init(limiter: LinkMetadataFetchLimiter = .shared) {
        self.limiter = limiter
    }

    func fetch(
        id: ClipboardItem.ID,
        url: URL,
        persistence: ClipboardHistoryPersistence,
        apply: @escaping @MainActor (_ title: String?, _ storedImage: StoredClipboardImage?, _ id: ClipboardItem.ID, _ url: URL) -> Void
    ) {
        taskByItemID[id]?.cancel()
        let generation = service.nextGeneration(for: id)
        let limiter = limiter
        taskByItemID[id] = Task.detached(priority: .utility) { [weak self] in
            var didEnterLimiter = false
            defer {
                if didEnterLimiter {
                    Task {
                        await limiter.finishTurn()
                    }
                }
            }

            await limiter.waitForTurn()
            didEnterLimiter = true
            do {
                try Task.checkCancellation()
            } catch {
                await self?.finishTask(for: id, generation: generation)
                return
            }

            guard let pageMetadata = await LinkTitleFetcher.pageMetadata(for: url) else {
                await self?.finishTask(for: id, generation: generation)
                return
            }

            guard !Task.isCancelled else {
                await self?.finishTask(for: id, generation: generation)
                return
            }

            if let title = pageMetadata.title {
                await apply(title, nil, id, url)
            }

            await Task.yield()
            guard !Task.isCancelled else {
                await self?.finishTask(for: id, generation: generation)
                return
            }

            let storedImage = await LinkTitleFetcher.previewImageData(from: pageMetadata, baseURL: url)
                .flatMap(NSImage.init(data:))
                .flatMap(persistence.saveImage)

            guard let storedImage else {
                await self?.finishTask(for: id, generation: generation)
                return
            }

            guard !Task.isCancelled else {
                await self?.finishTask(for: id, generation: generation)
                return
            }

            await apply(nil, storedImage, id, url)
            await self?.finishTask(for: id, generation: generation)
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
        service.cancelTasks(for: ids)
    }

    func cancelAllTasks() {
        for task in taskByItemID.values {
            task.cancel()
        }
        taskByItemID.removeAll()
        service.cancelAllTasks()
    }

    func hasInFlightTask(for id: ClipboardItem.ID) -> Bool {
        service.hasInFlightTask(for: id)
    }

    private func finishTask(for id: ClipboardItem.ID, generation: Int) {
        guard service.finishTask(for: id, generation: generation) else {
            return
        }

        taskByItemID[id] = nil
    }
}

actor LinkMetadataFetchLimiter {
    static let shared = LinkMetadataFetchLimiter()

    private let limit: Int
    private var activeCount = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int = 3) {
        self.limit = limit
    }

    func waitForTurn() async {
        if activeCount < limit {
            activeCount += 1
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func finishTurn() {
        if waiters.isEmpty {
            activeCount = max(0, activeCount - 1)
            return
        }

        let next = waiters.removeFirst()
        next.resume()
    }
}

