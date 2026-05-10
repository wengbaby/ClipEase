import AppKit
import Foundation

struct CachedAppIcon {
    let fileName: String
    let dominantColorHex: String
}

enum AppIconCache {
    static func cacheIcon(for app: NSRunningApplication) -> CachedAppIcon? {
        guard let bundleID = app.bundleIdentifier,
              let icon = app.icon,
              let iconData = icon.pngData() else {
            return nil
        }

        let fileName = "\(sanitized(bundleID)).png"
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

    private static func sanitized(_ bundleID: String) -> String {
        bundleID.map { character in
            character.isLetter || character.isNumber || character == "." ? character : "_"
        }
        .map(String.init)
        .joined()
    }

    private static func dominantColorHex(from image: NSImage) -> String {
        guard let resized = image.resized(to: NSSize(width: 32, height: 32)),
              let bitmap = NSBitmapImageRep(data: resized.tiffRepresentation ?? Data()) else {
            return "#2E8CFF"
        }

        let centerX = bitmap.pixelsWide / 2
        let centerY = bitmap.pixelsHigh / 2
        guard let color = bitmap.colorAt(x: centerX, y: centerY),
              color.alphaComponent > 0.1 else {
            return "#2E8CFF"
        }

        return String(
            format: "#%02X%02X%02X",
            darken(color.redComponent),
            darken(color.greenComponent),
            darken(color.blueComponent)
        )
    }

    private static func darken(_ component: CGFloat) -> Int {
        max(0, min(255, Int(component * 255 * 0.72)))
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

    func pngData() -> Data? {
        guard let tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffRepresentation) else {
            return nil
        }

        return bitmap.representation(using: .png, properties: [:])
    }
}
