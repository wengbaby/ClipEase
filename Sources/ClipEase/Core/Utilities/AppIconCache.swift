import AppKit
import Foundation

struct CachedAppIcon: Codable, Equatable, Sendable {
    let fileName: String
    let dominantColorHex: String
}

final class AppIconCacheGeneration: @unchecked Sendable {
    struct Token: Equatable, Sendable {
        fileprivate let value: UInt64
    }

    private let lock = NSLock()
    private var value: UInt64 = 0

    func begin() -> Token {
        lock.withLock { Token(value: value) }
    }

    @discardableResult
    func advance() -> UInt64 {
        lock.withLock {
            value &+= 1
            return value
        }
    }

    func isCurrent(_ token: Token) -> Bool {
        lock.withLock { value == token.value }
    }

    func commitIfCurrent(_ token: Token) -> Bool {
        isCurrent(token)
    }
}

private final class AppIconLoadStartGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Never>?
    private var isReleased = false

    func wait() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let resumeImmediately = lock.withLock {
                if isReleased {
                    return true
                }

                self.continuation = continuation
                return false
            }

            if resumeImmediately {
                continuation.resume()
            }
        }
    }

    func release() {
        let continuation = lock.withLock {
            isReleased = true
            defer { self.continuation = nil }
            return self.continuation
        }
        continuation?.resume()
    }
}

actor AppIconCacheCoordinator {
    private struct ScopedKey: Hashable {
        let generation: UInt64
        let key: String
    }

    private let generation: AppIconCacheGeneration
    private var memory: [ScopedKey: CachedAppIcon] = [:]
    private var inFlight: [ScopedKey: Task<CachedAppIcon?, Never>] = [:]
    private var nextProbeSequence: UInt64 = 0
    private var latestProbeSequence: [ScopedKey: UInt64] = [:]
    private var activeProbeCounts: [ScopedKey: Int] = [:]

    init(generation: AppIconCacheGeneration = AppIconCacheGeneration()) {
        self.generation = generation
    }

    func value(
        for key: String,
        cachedValue: @escaping @Sendable () async -> CachedAppIcon?,
        loadValue: @escaping @Sendable () async -> CachedAppIcon?
    ) async -> CachedAppIcon? {
        let generationToken = generation.begin()
        let scopedKey = ScopedKey(generation: generationToken.value, key: key)
        if let cached = memory[scopedKey] {
            return cached
        }
        if let task = inFlight[scopedKey] {
            return await task.value
        }

        nextProbeSequence &+= 1
        let probeSequence = nextProbeSequence
        latestProbeSequence[scopedKey] = probeSequence
        activeProbeCounts[scopedKey, default: 0] += 1
        defer {
            finishProbe(for: scopedKey)
        }
        if let cached = await cachedValue() {
            if generation.isCurrent(generationToken) {
                memory[scopedKey] = cached
            }
            return cached
        }

        // A newer probe may have completed while this one was suspended. Give
        // that caller a bounded chance to claim the load slot first, making
        // the single-flight ordering deterministic without waiting forever on
        // a broken disk probe.
        if latestProbeSequence[scopedKey] != probeSequence {
            for _ in 0..<4 {
                if let cached = memory[scopedKey] {
                    return cached
                }
                if let task = inFlight[scopedKey] {
                    return await task.value
                }
                guard latestProbeSequence[scopedKey] != probeSequence else {
                    break
                }
                await Task.yield()
            }
        }

        if let cached = memory[scopedKey] {
            return cached
        }
        // Disk probes may overlap, but the actor re-checks this map after the
        // suspension so only one expensive icon load is ever in flight.
        if let task = inFlight[scopedKey] {
            return await task.value
        }

        // Register the task before allowing its loader to start. Task bodies
        // may begin on another executor immediately; without this handoff a
        // loader can signal progress before `inFlight` is visible to the
        // actor, allowing a concurrent request to start a duplicate load.
        let startGate = AppIconLoadStartGate()
        let task = Task {
            await startGate.wait()
            return await loadValue()
        }
        inFlight[scopedKey] = task
        startGate.release()
        let value = await task.value
        if let value, generation.isCurrent(generationToken) {
            memory[scopedKey] = value
        }
        return value
    }

    nonisolated func invalidateSynchronously() {
        let currentGeneration = generation.advance()
        Task {
            await removeEntries(before: currentGeneration)
        }
    }

    private func removeEntries(before currentGeneration: UInt64) {
        memory = memory.filter { $0.key.generation >= currentGeneration }
        let staleKeys = inFlight.keys.filter { $0.generation < currentGeneration }
        for key in staleKeys {
            inFlight.removeValue(forKey: key)?.cancel()
        }
        latestProbeSequence = latestProbeSequence.filter { $0.key.generation >= currentGeneration }
        activeProbeCounts = activeProbeCounts.filter { $0.key.generation >= currentGeneration }
    }

    private func finishProbe(for key: ScopedKey) {
        guard let count = activeProbeCounts[key] else {
            return
        }
        if count <= 1 {
            activeProbeCounts[key] = nil
            latestProbeSequence[key] = nil
            inFlight[key] = nil
        } else {
            activeProbeCounts[key] = count - 1
        }
    }
}

enum AppIconCache {
    private struct DiskMetadata: Codable {
        let cacheKey: String
        let generation: UInt64
        let icon: CachedAppIcon
    }

    private final class RunningApplicationReference: @unchecked Sendable {
        let value: NSRunningApplication

        init(_ value: NSRunningApplication) {
            self.value = value
        }
    }

    private final class ImageReference: @unchecked Sendable {
        let value: NSImage

        init(_ value: NSImage) {
            self.value = value
        }
    }

    private static let generation = AppIconCacheGeneration()
    private static let coordinator = AppIconCacheCoordinator(generation: generation)

    static func cachedIconMetadata(forBundleID bundleID: String) -> CachedAppIcon? {
        cachedIconMetadata(forBundleID: bundleID, cacheKey: nil)
    }

    static func cachedIconMetadata(
        forBundleID bundleID: String,
        cacheKey: String?
    ) -> CachedAppIcon? {
        let fileName = fileName(forBundleID: bundleID)
        guard let fileURL = try? ClipEaseStoragePaths.appIconFileURL(fileName: fileName),
              FileManager.default.fileExists(atPath: fileURL.path),
              let metadata = diskMetadata(at: metadataURL(for: fileURL)),
              metadata.generation == generation.begin().value,
              (cacheKey == nil || metadata.cacheKey == cacheKey) else {
            return nil
        }

        return metadata.icon
    }

    static func expectedFileName(forBundleID bundleID: String) -> String {
        fileName(forBundleID: bundleID)
    }

    @MainActor
    static func cacheIcon(for app: NSRunningApplication) async -> CachedAppIcon? {
        guard let bundleID = app.bundleIdentifier else {
            return nil
        }

        let cacheKey = cacheKey(for: app, bundleID: bundleID)
        let cacheGeneration = generation.begin()
        let appReference = RunningApplicationReference(app)
        return await coordinator.value(
            for: cacheKey,
            cachedValue: {
                cachedIconMetadata(forBundleID: bundleID, cacheKey: cacheKey)
            },
            loadValue: {
                guard let iconReference = await MainActor.run(body: {
                    appReference.value.icon.map(ImageReference.init)
                }) else {
                    return nil
                }
                let writtenIcon = writeIcon(
                    iconReference.value,
                    bundleID: bundleID,
                    cacheKey: cacheKey,
                    generation: cacheGeneration
                )
                guard generation.commitIfCurrent(cacheGeneration) else {
                    removeStaleIconIfOwned(
                        bundleID: bundleID,
                        cacheKey: cacheKey,
                        generation: cacheGeneration
                    )
                    return nil
                }
                return writtenIcon
            }
        )
    }

    private static func cachedIconMetadata(
        forBundleID bundleID: String,
        cacheKey: String
    ) -> CachedAppIcon? {
        let fileName = fileName(forBundleID: bundleID)
        guard let fileURL = try? ClipEaseStoragePaths.appIconFileURL(fileName: fileName),
              FileManager.default.fileExists(atPath: fileURL.path),
              let metadata = diskMetadata(at: metadataURL(for: fileURL)),
              metadata.generation == generation.begin().value,
              metadata.cacheKey == cacheKey else {
            return nil
        }
        return metadata.icon
    }

    private static func writeIcon(
        _ icon: NSImage,
        bundleID: String,
        cacheKey: String,
        generation cacheGeneration: AppIconCacheGeneration.Token
    ) -> CachedAppIcon? {
        guard let iconData = icon.pngData(size: NSSize(width: 256, height: 256)) else {
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
            try iconData.write(to: fileURL, options: [.atomic])

            let cachedIcon = CachedAppIcon(
                fileName: fileName,
                dominantColorHex: dominantColorHex(from: icon)
            )
            let metadata = DiskMetadata(
                cacheKey: cacheKey,
                generation: cacheGeneration.value,
                icon: cachedIcon
            )
            let metadataData = try JSONEncoder().encode(metadata)
            try metadataData.write(to: metadataURL(for: fileURL), options: [.atomic])
            return cachedIcon
        } catch {
            NSLog("ClipEase failed to cache app icon: \(error.localizedDescription)")
            return nil
        }
    }

    static func clearCache() {
        coordinator.invalidateSynchronously()
        guard let directoryURL = try? ClipEaseStoragePaths.appIconsDirectory(),
              FileManager.default.fileExists(atPath: directoryURL.path) else {
            return
        }

        try? FileManager.default.removeItem(at: directoryURL)
    }

    private static func removeStaleIconIfOwned(
        bundleID: String,
        cacheKey: String,
        generation cacheGeneration: AppIconCacheGeneration.Token
    ) {
        let fileName = fileName(forBundleID: bundleID)
        guard let fileURL = try? ClipEaseStoragePaths.appIconFileURL(fileName: fileName),
              let metadata = diskMetadata(at: metadataURL(for: fileURL)),
              metadata.cacheKey == cacheKey,
              metadata.generation == cacheGeneration.value else {
            return
        }
        try? FileManager.default.removeItem(at: fileURL)
        try? FileManager.default.removeItem(at: metadataURL(for: fileURL))
    }

    static func cacheKey(for app: NSRunningApplication, bundleID: String) -> String {
        let colorSamplingVersion = "color-v2"
        guard let bundleURL = app.bundleURL else {
            return "\(bundleID)|\(colorSamplingVersion)|unknown"
        }
        let version = Bundle(url: bundleURL)?
            .object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        let modificationDate = (try? bundleURL.resourceValues(
            forKeys: [.contentModificationDateKey]
        ).contentModificationDate)?.timeIntervalSince1970 ?? 0
        return "\(bundleID)|\(colorSamplingVersion)|\(version)|\(modificationDate)"
    }

    private static func diskMetadata(at url: URL) -> DiskMetadata? {
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? JSONDecoder().decode(DiskMetadata.self, from: data)
    }

    private static func metadataURL(for iconURL: URL) -> URL {
        iconURL.appendingPathExtension("metadata")
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

        let centerX = bitmap.pixelsWide / 2
        let centerY = bitmap.pixelsHigh / 2

        if let centerColor = bestColor(in: bitmap, centerX: centerX, centerY: centerY, ignoresNeutral: false) {
            if !isNearWhite(centerColor) {
                return hexString(from: centerColor)
            }

            let halfWidth = bitmap.pixelsWide / 2
            for offset in [halfWidth / 2, halfWidth - 4] {
                if let leftColor = bestColor(in: bitmap, centerX: max(4, centerX - offset), centerY: centerY),
                   !isNearWhite(leftColor) {
                    return hexString(from: leftColor)
                }
                if let rightColor = bestColor(in: bitmap, centerX: min(bitmap.pixelsWide - 5, centerX + offset), centerY: centerY),
                   !isNearWhite(rightColor) {
                    return hexString(from: rightColor)
                }
            }

            return hexString(from: centerColor)
        }

        return "#2E8CFF"
    }

    private static func bestColor(
        in bitmap: NSBitmapImageRep,
        centerX: Int,
        centerY: Int,
        ignoresNeutral: Bool = true
    ) -> NSColor? {
        var selectedColor: NSColor?
        var selectedScore = CGFloat.greatestFiniteMagnitude

        for y in max(0, centerY - 8)..<min(bitmap.pixelsHigh, centerY + 9) {
            for x in max(0, centerX - 8)..<min(bitmap.pixelsWide, centerX + 9) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                      color.alphaComponent > 0.2,
                      (!ignoresNeutral || !isIgnoredNeutral(color)) else {
                    continue
                }

                let score = brightness(color) - saturation(color) * 0.18
                if score < selectedScore {
                    selectedScore = score
                    selectedColor = color
                }
            }
        }

        return selectedColor
    }

    private static func hexString(from color: NSColor) -> String {
        String(
            format: "#%02X%02X%02X",
            component(color.redComponent),
            component(color.greenComponent),
            component(color.blueComponent)
        )
    }

    private static func isIgnoredNeutral(_ color: NSColor) -> Bool {
        (brightness(color) > 0.86 && saturation(color) < 0.24) || saturation(color) < 0.1
    }

    private static func isNearWhite(_ color: NSColor) -> Bool {
        brightness(color) > 0.88 && saturation(color) < 0.2
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
