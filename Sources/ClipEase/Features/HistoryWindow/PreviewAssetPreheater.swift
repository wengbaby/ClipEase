import AppKit
import Combine
import Foundation

struct PreviewAssetPreheatAsset: @unchecked Sendable {
    let cacheKey: String
    let image: NSImage
}

@MainActor
final class PreviewAssetPreheater: ObservableObject {
    typealias Loader = @Sendable (HistoryPreviewItem) async -> [PreviewAssetPreheatAsset]
    typealias Publisher = @MainActor @Sendable (PreviewAssetPreheatAsset) -> Void

    nonisolated static let defaultBatchSize = 18

    private let initialDelayNanoseconds: UInt64
    private let interBatchDelayNanoseconds: UInt64
    private let loader: Loader
    private let publisher: Publisher
    private var task: Task<Void, Never>?
    private var generation: UInt64 = 0
    private var isEnabled = false

    init(
        initialDelayNanoseconds: UInt64 = 260_000_000,
        interBatchDelayNanoseconds: UInt64 = 80_000_000,
        loader: @escaping Loader = PreviewAssetPreheater.loadAssets,
        publisher: @escaping Publisher = { asset in
            ImageMemoryCache.shared.store(asset.image, for: asset.cacheKey)
        }
    ) {
        self.initialDelayNanoseconds = initialDelayNanoseconds
        self.interBatchDelayNanoseconds = interBatchDelayNanoseconds
        self.loader = loader
        self.publisher = publisher
    }

    deinit {
        task?.cancel()
    }

    nonisolated static func itemsToPreheat(
        items: [HistoryPreviewItem],
        visibleWindow: Range<Int>,
        sideBuffer: Int = 8
    ) -> [HistoryPreviewItem] {
        let preheatStart = max(0, visibleWindow.lowerBound - sideBuffer)
        let preheatEnd = min(items.count, visibleWindow.upperBound + sideBuffer)
        guard preheatStart < preheatEnd else {
            return []
        }

        return Array(items[preheatStart..<preheatEnd])
    }

    func setEnabled(_ enabled: Bool) {
        guard isEnabled != enabled else {
            return
        }
        isEnabled = enabled
        if !enabled {
            invalidateCurrentTask()
        }
    }

    @discardableResult
    func schedule(
        items: [HistoryPreviewItem],
        visibleWindow: Range<Int>,
        batchSize: Int = PreviewAssetPreheater.defaultBatchSize
    ) -> Task<Void, Never>? {
        guard isEnabled else {
            return nil
        }

        task?.cancel()
        generation &+= 1
        let requestedGeneration = generation
        let requestedItems = Self.itemsToPreheat(
            items: items,
            visibleWindow: visibleWindow
        ).filter(Self.hasPreheatableAsset)
        guard !requestedItems.isEmpty else {
            task = nil
            return nil
        }

        let loader = self.loader
        let initialDelayNanoseconds = self.initialDelayNanoseconds
        let interBatchDelayNanoseconds = self.interBatchDelayNanoseconds
        let effectiveBatchSize = max(1, batchSize)
        let newTask = Task.detached(priority: .utility) { [weak self] in
            if initialDelayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: initialDelayNanoseconds)
            }

            if !Task.isCancelled,
               await self?.isCurrent(requestedGeneration) == true {
                for batchStart in stride(
                    from: 0,
                    to: requestedItems.count,
                    by: effectiveBatchSize
                ) {
                    guard !Task.isCancelled,
                          await self?.isCurrent(requestedGeneration) == true else {
                        break
                    }

                    let batchEnd = min(
                        batchStart + effectiveBatchSize,
                        requestedItems.count
                    )
                    for item in requestedItems[batchStart..<batchEnd] {
                        guard !Task.isCancelled,
                              await self?.isCurrent(requestedGeneration) == true else {
                            break
                        }

                        let assets = await loader(item)
                        guard !Task.isCancelled,
                              await self?.publishIfCurrent(
                                assets,
                                generation: requestedGeneration
                              ) == true else {
                            break
                        }
                    }

                    if interBatchDelayNanoseconds > 0,
                       batchEnd < requestedItems.count {
                        try? await Task.sleep(nanoseconds: interBatchDelayNanoseconds)
                    }
                }
            }

            await self?.finish(generation: requestedGeneration)
        }
        task = newTask
        return newTask
    }

    private func invalidateCurrentTask() {
        generation &+= 1
        task?.cancel()
        task = nil
    }

    private func isCurrent(_ requestedGeneration: UInt64) -> Bool {
        isEnabled && generation == requestedGeneration
    }

    private func publishIfCurrent(
        _ assets: [PreviewAssetPreheatAsset],
        generation requestedGeneration: UInt64
    ) -> Bool {
        guard !Task.isCancelled,
              isCurrent(requestedGeneration) else {
            return false
        }
        assets.forEach(publisher)
        return true
    }

    private func finish(generation requestedGeneration: UInt64) {
        guard generation == requestedGeneration else {
            return
        }
        task = nil
    }

    nonisolated private static func hasPreheatableAsset(
        _ item: HistoryPreviewItem
    ) -> Bool {
        item.imageFileName != nil || item.iconFileName != nil
    }

    nonisolated private static func loadAssets(
        for item: HistoryPreviewItem
    ) async -> [PreviewAssetPreheatAsset] {
        var assets: [PreviewAssetPreheatAsset] = []

        if let imageFileName = item.imageFileName,
           let request = HistoryImageAssetRequest.cardThumbnail(
            fileName: imageFileName,
            priority: .preheat
           ),
           !Task.isCancelled,
           let asset = try? await HistoryImageAssetLoader.shared.load(request) {
            assets.append(
                PreviewAssetPreheatAsset(
                    cacheKey: asset.cacheKey,
                    image: asset.image
                )
            )
        }

        if let iconFileName = item.iconFileName,
           let request = HistoryImageAssetRequest.sourceIcon(
            fileName: iconFileName,
            priority: .preheat
           ),
           !Task.isCancelled,
           let asset = try? await HistoryImageAssetLoader.shared.load(request) {
            assets.append(
                PreviewAssetPreheatAsset(
                    cacheKey: asset.cacheKey,
                    image: asset.image
                )
            )
        }

        return assets
    }
}
