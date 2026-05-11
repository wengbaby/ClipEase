import AppKit

@MainActor
final class ImageMemoryCache {
    static let shared = ImageMemoryCache()

    private let cache = NSCache<NSString, NSImage>()

    private init() {}

    func image(for key: String, load: () -> NSImage?) -> NSImage? {
        if let image = cache.object(forKey: key as NSString) {
            return image
        }

        guard let image = load() else {
            return nil
        }

        cache.setObject(image, forKey: key as NSString)
        return image
    }
}
