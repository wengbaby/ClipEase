import AppKit

@MainActor
enum ClipEaseAppIcon {
    static func image(size: NSSize? = nil) -> NSImage {
        let baseImage = Bundle.main.url(forResource: "ClipEase", withExtension: "icns")
            .flatMap(NSImage.init(contentsOf:))
            ?? NSApp.applicationIconImage
            ?? NSImage(size: NSSize(width: 512, height: 512))

        guard let size else {
            return baseImage
        }

        return baseImage.resized(to: size) ?? baseImage
    }

    static func statusBarImage(isPaused: Bool) -> NSImage {
        let imageSize = NSSize(width: 18, height: 18)
        let statusImage = NSImage(size: imageSize)
        statusImage.lockFocus()
        let rect = NSRect(origin: .zero, size: imageSize)
        let radius = nativeAppIconCornerRadius(for: imageSize)
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).addClip()
        image(size: imageSize).draw(in: NSRect(origin: .zero, size: imageSize))

        if isPaused {
            let badgeRect = NSRect(x: 9.5, y: 0.5, width: 8, height: 8)
            NSColor.controlAccentColor.setFill()
            NSBezierPath(ovalIn: badgeRect).fill()

            NSColor.white.setFill()
            NSBezierPath(rect: NSRect(x: 12, y: 2.4, width: 1.1, height: 4.2)).fill()
            NSBezierPath(rect: NSRect(x: 14.1, y: 2.4, width: 1.1, height: 4.2)).fill()
        }

        statusImage.unlockFocus()

        return statusImage
    }

    nonisolated static func roundedImage(_ image: NSImage, size: NSSize? = nil, radius: CGFloat? = nil) -> NSImage {
        let targetSize = size ?? image.size
        let targetRadius = radius ?? nativeAppIconCornerRadius(for: targetSize)
        let rounded = NSImage(size: targetSize)
        rounded.lockFocus()
        let rect = NSRect(origin: .zero, size: targetSize)
        NSBezierPath(roundedRect: rect, xRadius: targetRadius, yRadius: targetRadius).addClip()
        image.draw(in: rect, from: NSRect(origin: .zero, size: image.size), operation: .copy, fraction: 1)
        rounded.unlockFocus()
        return rounded
    }

    nonisolated static func nativeAppIconCornerRadius(for size: NSSize) -> CGFloat {
        min(size.width, size.height) * 0.225
    }
}

private extension NSImage {
    func resized(to targetSize: NSSize) -> NSImage? {
        let image = NSImage(size: targetSize)
        image.lockFocus()
        draw(
            in: NSRect(origin: .zero, size: targetSize),
            from: NSRect(origin: .zero, size: size),
            operation: .copy,
            fraction: 1
        )
        image.unlockFocus()
        return image
    }
}
