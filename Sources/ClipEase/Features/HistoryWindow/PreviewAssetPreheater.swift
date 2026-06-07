import AppKit
import Foundation

enum PreviewAssetPreheater {
    static let defaultBatchSize = 18

    static func itemsToPreheat(
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

    static func schedule(
        existingTask: inout Task<Void, Never>?,
        items: [HistoryPreviewItem],
        visibleWindow: Range<Int>,
        batchSize: Int = Self.defaultBatchSize
    ) {
        existingTask?.cancel()
        let itemsToPreheat = itemsToPreheat(items: items, visibleWindow: visibleWindow)
        guard !itemsToPreheat.isEmpty else {
            existingTask = nil
            return
        }

        existingTask = Task.detached(priority: .utility) {
            try? await Task.sleep(nanoseconds: 260_000_000)
            guard !Task.isCancelled else {
                return
            }

            for batchStart in stride(from: 0, to: itemsToPreheat.count, by: batchSize) {
                guard !Task.isCancelled else {
                    return
                }

                let batchEnd = min(batchStart + batchSize, itemsToPreheat.count)
                for item in itemsToPreheat[batchStart..<batchEnd] {
                    guard !Task.isCancelled else {
                        return
                    }

                    await preheatImageThumbnailInBackground(for: item)
                    await preheatSourceIconInBackground(for: item)
                    await preheatRichTextInBackground(for: item)
                }
                try? await Task.sleep(nanoseconds: 80_000_000)
            }
        }
    }

    private static func preheatImageThumbnailInBackground(for item: HistoryPreviewItem) async {
        guard let imageFileName = item.imageFileName,
              let thumbnailURL = try? ClipEaseStoragePaths.thumbnailFileURL(fileName: imageFileName),
              let imageURL = try? ClipEaseStoragePaths.imageFileURL(fileName: imageFileName) else {
            return
        }

        let cacheKey = "history-thumbnail:\(imageFileName)"
        let isCached = await MainActor.run {
            ImageMemoryCache.shared.cachedImage(for: cacheKey) != nil
        }
        guard !isCached else {
            return
        }

        let image = HistoryCardAssetLoadGate.shared.load {
            NSImage(contentsOf: thumbnailURL) ?? NSImage(contentsOf: imageURL)
        }
        if let image {
            await MainActor.run {
                ImageMemoryCache.shared.store(image, for: cacheKey)
            }
        }
    }

    private static func preheatSourceIconInBackground(for item: HistoryPreviewItem) async {
        guard let iconFileName = item.iconFileName,
              let iconURL = try? ClipEaseStoragePaths.appIconFileURL(fileName: iconFileName) else {
            return
        }

        let cacheKey = "app-icon:\(iconFileName)"
        let isCached = await MainActor.run {
            ImageMemoryCache.shared.cachedImage(for: cacheKey) != nil
        }
        guard !isCached else {
            return
        }

        let image = HistoryCardAssetLoadGate.shared.load {
            NSImage(contentsOf: iconURL).map {
                ClipEaseAppIcon.roundedImage($0, size: NSSize(width: 64, height: 64))
            }
        }
        if let image {
            await MainActor.run {
                ImageMemoryCache.shared.store(image, for: cacheKey)
            }
        }
    }

    private static func preheatRichTextInBackground(for item: HistoryPreviewItem) async {
        guard let richTextFileName = item.richTextFileName else {
            return
        }

        _ = HistoryCardAssetLoadGate.shared.load {
            RichTextCardPreviewCache.loadAttributedString(
                fileName: richTextFileName,
                fallbackText: item.preview
            )
        }
    }
}
