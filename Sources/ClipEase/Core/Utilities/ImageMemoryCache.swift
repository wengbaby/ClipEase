import AppKit

final class ImageMemoryCache: @unchecked Sendable {
    static let shared = ImageMemoryCache()

    private let cache = NSCache<NSString, NSImage>()

    init(
        countLimit: Int = 256,
        totalCostLimit: Int = 96 * 1_024 * 1_024
    ) {
        cache.countLimit = max(1, countLimit)
        cache.totalCostLimit = max(1, totalCostLimit)
    }

    func cachedImage(for key: String) -> NSImage? {
        cache.object(forKey: key as NSString)
    }

    func store(
        _ image: NSImage,
        for key: String,
        pixelWidth: Int? = nil,
        pixelHeight: Int? = nil
    ) {
        let width = max(1, pixelWidth ?? Int(image.size.width.rounded(.up)))
        let height = max(1, pixelHeight ?? Int(image.size.height.rounded(.up)))
        let pixelCount = width.multipliedReportingOverflow(by: height)
        let byteCount = pixelCount.partialValue.multipliedReportingOverflow(by: 4)
        let cost = pixelCount.overflow || byteCount.overflow ? Int.max : byteCount.partialValue
        cache.setObject(image, forKey: key as NSString, cost: cost)
    }

    func image(for key: String, load: () -> NSImage?) -> NSImage? {
        if let image = cache.object(forKey: key as NSString) {
            return image
        }

        guard let image = load() else {
            return nil
        }

        store(image, for: key)
        return image
    }

    func preheatImage(for key: String, load: () -> NSImage?) {
        _ = image(for: key, load: load)
    }
}
