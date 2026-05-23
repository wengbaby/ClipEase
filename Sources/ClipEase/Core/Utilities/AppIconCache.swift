import AppKit
import Foundation

struct CachedAppIcon: Sendable {
    let fileName: String
    let dominantColorHex: String
}

enum AppIconCache {
    static func cachedIconMetadata(forBundleID bundleID: String) -> CachedAppIcon? {
        let fileName = fileName(forBundleID: bundleID)
        guard let fileURL = try? ClipEaseStoragePaths.appIconFileURL(fileName: fileName),
              FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }

        let dominantColor = NSImage(contentsOf: fileURL).map(dominantColorHex(from:)) ?? "#2E8CFF"
        return CachedAppIcon(fileName: fileName, dominantColorHex: dominantColor)
    }

    static func expectedFileName(forBundleID bundleID: String) -> String {
        fileName(forBundleID: bundleID)
    }

    static func cacheIcon(for app: NSRunningApplication) -> CachedAppIcon? {
        guard let bundleID = app.bundleIdentifier,
              let icon = app.icon,
              let iconData = icon.pngData(size: NSSize(width: 256, height: 256)) else {
            return nil
        }

        let fileName = fileName(forBundleID: bundleID)
        do {
            let directoryURL = try ClipEaseStoragePaths.appIconsDirectory()
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
            let fileURL = directoryURL.appendingPathComponent(fileName)
            if !FileManager.default.fileExists(atPath: fileURL.path) {
                try iconData.write(to: fileURL, options: [.atomic])
            }

            return CachedAppIcon(
                fileName: fileName,
                dominantColorHex: dominantColorHex(from: icon)
            )
        } catch {
            NSLog("ClipEase failed to cache app icon: \(error.localizedDescription)")
            return nil
        }
    }

    static func clearCache() {
        guard let directoryURL = try? ClipEaseStoragePaths.appIconsDirectory(),
              FileManager.default.fileExists(atPath: directoryURL.path) else {
            return
        }

        try? FileManager.default.removeItem(at: directoryURL)
    }

    private static func sanitized(_ bundleID: String) -> String {
        bundleID.map { character in
            character.isLetter || character.isNumber || character == "." ? character : "_"
        }
        .map(String.init)
        .joined()
    }

    private static func fileName(forBundleID bundleID: String) -> String {
        "\(sanitized(bundleID)).png"
    }

    private static func dominantColorHex(from image: NSImage) -> String {
        guard let resized = image.resized(to: NSSize(width: 48, height: 48)),
              let bitmap = NSBitmapImageRep(data: resized.tiffRepresentation ?? Data()) else {
            return "#2E8CFF"
        }

        let center = CGPoint(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2)
        var selectedColor: NSColor?
        var selectedScore = CGFloat.greatestFiniteMagnitude

        for y in max(0, Int(center.y) - 8)..<min(bitmap.pixelsHigh, Int(center.y) + 9) {
            for x in max(0, Int(center.x) - 8)..<min(bitmap.pixelsWide, Int(center.x) + 9) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                      color.alphaComponent > 0.2,
                      !isIgnoredNeutral(color) else {
                    continue
                }

                let score = brightness(color) - saturation(color) * 0.18
                if score < selectedScore {
                    selectedScore = score
                    selectedColor = color
                }
            }
        }

        guard let selectedColor else {
            return "#2E8CFF"
        }

        return String(
            format: "#%02X%02X%02X",
            component(selectedColor.redComponent),
            component(selectedColor.greenComponent),
            component(selectedColor.blueComponent)
        )
    }

    private static func isIgnoredNeutral(_ color: NSColor) -> Bool {
        (brightness(color) > 0.86 && saturation(color) < 0.24) || saturation(color) < 0.1
    }

    private static func brightness(_ color: NSColor) -> CGFloat {
        max(color.redComponent, color.greenComponent, color.blueComponent)
    }

    private static func saturation(_ color: NSColor) -> CGFloat {
        let maxComponent = max(color.redComponent, color.greenComponent, color.blueComponent)
        let minComponent = min(color.redComponent, color.greenComponent, color.blueComponent)
        guard maxComponent > 0 else {
            return 0
        }
        return (maxComponent - minComponent) / maxComponent
    }

    private static func component(_ value: CGFloat) -> Int {
        max(0, min(255, Int(value * 255)))
    }
}

private extension NSImage {
    func resized(to size: NSSize) -> NSImage? {
        let image = NSImage(size: size)
        image.lockFocus()
        draw(
            in: NSRect(origin: .zero, size: size),
            from: NSRect(origin: .zero, size: self.size),
            operation: .copy,
            fraction: 1
        )
        image.unlockFocus()
        return image
    }

    func pngData(size: NSSize? = nil) -> Data? {
        let image = size.flatMap { resized(to: $0) } ?? self
        guard let tiffRepresentation = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffRepresentation) else {
            return nil
        }

        return bitmap.representation(using: .png, properties: [:])
    }
}
