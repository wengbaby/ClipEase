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
        guard let resized = image.resized(to: NSSize(width: 28, height: 28)),
              let bitmap = NSBitmapImageRep(data: resized.tiffRepresentation ?? Data()) else {
            return "#2E8CFF"
        }

        var buckets: [ColorBucket: Int] = [:]

        for x in 0..<bitmap.pixelsWide {
            for y in 0..<bitmap.pixelsHigh {
                guard let color = bitmap.colorAt(x: x, y: y),
                      color.alphaComponent > 0.35 else {
                    continue
                }

                let red = Int(color.redComponent * 255)
                let green = Int(color.greenComponent * 255)
                let blue = Int(color.blueComponent * 255)
                guard !isNearWhite(red: red, green: green, blue: blue),
                      !isNearBlack(red: red, green: green, blue: blue) else {
                    continue
                }

                let bucket = ColorBucket(
                    red: (red / 24) * 24,
                    green: (green / 24) * 24,
                    blue: (blue / 24) * 24
                )
                buckets[bucket, default: 0] += 1
            }
        }

        guard let dominant = buckets.max(by: { $0.value < $1.value })?.key else {
            return "#2E8CFF"
        }

        return String(
            format: "#%02X%02X%02X",
            min(dominant.red + 12, 255),
            min(dominant.green + 12, 255),
            min(dominant.blue + 12, 255)
        )
    }

    private static func isNearWhite(red: Int, green: Int, blue: Int) -> Bool {
        red > 235 && green > 235 && blue > 235
    }

    private static func isNearBlack(red: Int, green: Int, blue: Int) -> Bool {
        red < 24 && green < 24 && blue < 24
    }
}

private struct ColorBucket: Hashable {
    let red: Int
    let green: Int
    let blue: Int
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
