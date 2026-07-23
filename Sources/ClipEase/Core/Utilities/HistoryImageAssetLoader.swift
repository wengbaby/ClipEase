import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum HistoryImageLoadPriority: Int, Sendable {
    case preheat
    case visible
}

enum HistoryImageAssetOutput: Hashable, Sendable {
    case thumbnail(
        maximumPixelWidth: Int,
        maximumPixelHeight: Int,
        persistedURL: URL?
    )
    case sourceIcon(pixelSize: Int)
}

struct HistoryImageAssetRequest: Hashable, Sendable {
    let cacheKey: String
    let primaryURL: URL
    let fallbackURL: URL?
    let output: HistoryImageAssetOutput
    let priority: HistoryImageLoadPriority

    static func cardThumbnail(
        fileName: String,
        priority: HistoryImageLoadPriority
    ) -> HistoryImageAssetRequest? {
        guard let thumbnailURL = try? ClipEaseStoragePaths.thumbnailFileURL(
            fileName: fileName
        ),
        let imageURL = try? ClipEaseStoragePaths.imageFileURL(fileName: fileName) else {
            return nil
        }
        return HistoryImageAssetRequest(
            cacheKey: "history-thumbnail:\(fileName)",
            primaryURL: thumbnailURL,
            fallbackURL: imageURL,
            output: .thumbnail(
                maximumPixelWidth: 500,
                maximumPixelHeight: 360,
                persistedURL: thumbnailURL
            ),
            priority: priority
        )
    }

    static func popoverHistoryImage(
        fileName: String,
        maximumPixelWidth: Int,
        maximumPixelHeight: Int,
        priority: HistoryImageLoadPriority
    ) -> HistoryImageAssetRequest? {
        guard maximumPixelWidth > 0,
              maximumPixelHeight > 0,
              let imageURL = try? ClipEaseStoragePaths.imageFileURL(fileName: fileName) else {
            return nil
        }
        return HistoryImageAssetRequest(
            cacheKey: "history-popover:\(fileName):\(maximumPixelWidth)x\(maximumPixelHeight)",
            primaryURL: imageURL,
            fallbackURL: nil,
            output: .thumbnail(
                maximumPixelWidth: maximumPixelWidth,
                maximumPixelHeight: maximumPixelHeight,
                persistedURL: nil
            ),
            priority: priority
        )
    }

    static func popoverFileImage(
        url: URL,
        cacheIdentity: String,
        maximumPixelWidth: Int,
        maximumPixelHeight: Int,
        priority: HistoryImageLoadPriority
    ) -> HistoryImageAssetRequest? {
        guard url.isFileURL,
              !cacheIdentity.isEmpty,
              maximumPixelWidth > 0,
              maximumPixelHeight > 0 else {
            return nil
        }

        let standardizedURL = url.standardizedFileURL
        guard FileManager.default.fileExists(atPath: standardizedURL.path) else {
            return nil
        }
        let canonicalURL = standardizedURL.resolvingSymlinksInPath()
        return HistoryImageAssetRequest(
            cacheKey: "file-popover:\(cacheIdentity):\(maximumPixelWidth)x\(maximumPixelHeight)",
            primaryURL: canonicalURL,
            fallbackURL: nil,
            output: .thumbnail(
                maximumPixelWidth: maximumPixelWidth,
                maximumPixelHeight: maximumPixelHeight,
                persistedURL: nil
            ),
            priority: priority
        )
    }

    static func sourceIcon(
        fileName: String,
        priority: HistoryImageLoadPriority
    ) -> HistoryImageAssetRequest? {
        guard (try? ClipEaseStoragePaths.validAttachmentBaseName(fileName)) == fileName,
              let iconURL = try? ClipEaseStoragePaths.appIconFileURL(
            fileName: fileName
        ) else {
            return nil
        }
        return HistoryImageAssetRequest(
            cacheKey: "app-icon:\(fileName)",
            primaryURL: iconURL,
            fallbackURL: nil,
            output: .sourceIcon(pixelSize: 64),
            priority: priority
        )
    }
}

struct HistoryImageAsset: @unchecked Sendable {
    let cacheKey: String
    let image: NSImage
    let pixelWidth: Int
    let pixelHeight: Int
}

struct HistoryImageAssetDecoderLimits: Sendable {
    let maximumEncodedBytes: Int
    let maximumSourceEdge: Int
    let maximumSourcePixels: Int

    init(
        maximumEncodedBytes: Int = 256 * 1_024 * 1_024,
        maximumSourceEdge: Int = 32_768,
        maximumSourcePixels: Int = 128_000_000
    ) {
        self.maximumEncodedBytes = max(0, maximumEncodedBytes)
        self.maximumSourceEdge = max(0, maximumSourceEdge)
        self.maximumSourcePixels = max(0, maximumSourcePixels)
    }
}

enum HistoryImageAssetDecoderError: Error, Equatable {
    case encodedDataTooLarge
    case invalidImage
    case sourceDimensionsTooLarge
    case invalidOutputBounds
}

struct HistoryImageAssetDecoder {
    typealias BeforePersistCommit = @Sendable () throws -> Void

    private let limits: HistoryImageAssetDecoderLimits
    private let fileManager: FileManager
    private let beforePersistCommit: BeforePersistCommit

    init(
        limits: HistoryImageAssetDecoderLimits = HistoryImageAssetDecoderLimits(),
        fileManager: FileManager = .default,
        beforePersistCommit: @escaping BeforePersistCommit = {}
    ) {
        self.limits = limits
        self.fileManager = fileManager
        self.beforePersistCommit = beforePersistCommit
    }

    func decode(_ request: HistoryImageAssetRequest) throws -> HistoryImageAsset? {
        try Task.checkCancellation()

        var primaryError: Error?
        if fileManager.fileExists(atPath: request.primaryURL.path) {
            do {
                let primaryImage = try decodeImage(
                    at: request.primaryURL,
                    output: request.output
                )
                try Task.checkCancellation()
                return makeAsset(
                    cacheKey: request.cacheKey,
                    cgImage: primaryImage,
                    output: request.output
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                primaryError = error
            }
        }

        guard let fallbackURL = request.fallbackURL,
              fileManager.fileExists(atPath: fallbackURL.path) else {
            if let primaryError {
                throw primaryError
            }
            return nil
        }
        let fallbackImage = try decodeImage(at: fallbackURL, output: request.output)
        try Task.checkCancellation()
        if case .thumbnail(_, _, let persistedURL?) = request.output {
            do {
                try persistPNG(fallbackImage, at: persistedURL)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // A cache write failure must not hide a valid in-memory preview.
            }
        }
        try Task.checkCancellation()
        return makeAsset(
            cacheKey: request.cacheKey,
            cgImage: fallbackImage,
            output: request.output
        )
    }

    private func decodeImage(
        at url: URL,
        output: HistoryImageAssetOutput
    ) throws -> CGImage {
        let values = try url.resourceValues(forKeys: [
            .fileSizeKey,
            .isRegularFileKey,
            .isSymbolicLinkKey
        ])
        guard values.isRegularFile == true,
              values.isSymbolicLink != true else {
            throw HistoryImageAssetDecoderError.invalidImage
        }
        guard let fileSize = values.fileSize,
              fileSize >= 0,
              fileSize <= limits.maximumEncodedBytes else {
            throw HistoryImageAssetDecoderError.encodedDataTooLarge
        }
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions),
              let sourceTypeIdentifier = CGImageSourceGetType(source),
              let sourceType = UTType(sourceTypeIdentifier as String),
              sourceType.conforms(to: .image),
              let properties = CGImageSourceCopyPropertiesAtIndex(
                source,
                0,
                nil
              ) as NSDictionary?,
              let rawWidth = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let rawHeight = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              rawWidth > 0,
              rawHeight > 0 else {
            throw HistoryImageAssetDecoderError.invalidImage
        }
        guard rawWidth <= limits.maximumSourceEdge,
              rawHeight <= limits.maximumSourceEdge,
              rawWidth <= limits.maximumSourcePixels / rawHeight else {
            throw HistoryImageAssetDecoderError.sourceDimensionsTooLarge
        }

        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        let swapsDimensions = (5...8).contains(orientation)
        let orientedWidth = swapsDimensions ? rawHeight : rawWidth
        let orientedHeight = swapsDimensions ? rawWidth : rawHeight
        let bounds = try outputBounds(for: output)
        let scale = min(
            CGFloat(bounds.width) / CGFloat(orientedWidth),
            CGFloat(bounds.height) / CGFloat(orientedHeight),
            1
        )
        let maximumPixelSize = max(
            1,
            Int(floor(CGFloat(max(orientedWidth, orientedHeight)) * scale))
        )
        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
            kCGImageSourceShouldCache: false,
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary
        try Task.checkCancellation()
        guard let image = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            thumbnailOptions
        ),
        image.width <= bounds.width,
        image.height <= bounds.height else {
            throw HistoryImageAssetDecoderError.invalidImage
        }
        return image
    }

    private func outputBounds(
        for output: HistoryImageAssetOutput
    ) throws -> (width: Int, height: Int) {
        let width: Int
        let height: Int
        switch output {
        case .thumbnail(let maximumPixelWidth, let maximumPixelHeight, _):
            width = maximumPixelWidth
            height = maximumPixelHeight
        case .sourceIcon(let pixelSize):
            width = pixelSize
            height = pixelSize
        }
        guard width > 0, height > 0 else {
            throw HistoryImageAssetDecoderError.invalidOutputBounds
        }
        return (width, height)
    }

    private func makeAsset(
        cacheKey: String,
        cgImage: CGImage,
        output: HistoryImageAssetOutput
    ) -> HistoryImageAsset {
        let decodedImage = NSImage(
            cgImage: cgImage,
            size: NSSize(width: cgImage.width, height: cgImage.height)
        )
        let image: NSImage
        let pixelWidth: Int
        let pixelHeight: Int
        switch output {
        case .thumbnail:
            image = decodedImage
            pixelWidth = cgImage.width
            pixelHeight = cgImage.height
        case .sourceIcon(let pixelSize):
            image = ClipEaseAppIcon.roundedImage(
                decodedImage,
                size: NSSize(width: pixelSize, height: pixelSize)
            )
            pixelWidth = pixelSize
            pixelHeight = pixelSize
        }
        return HistoryImageAsset(
            cacheKey: cacheKey,
            image: image,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight
        )
    }

    private func persistPNG(_ image: CGImage, at url: URL) throws {
        try Task.checkCancellation()
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw HistoryImageAssetDecoderError.invalidImage
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw HistoryImageAssetDecoderError.invalidImage
        }
        try Task.checkCancellation()
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let temporaryURL = url.deletingLastPathComponent().appendingPathComponent(
            ".\(url.lastPathComponent).\(UUID().uuidString).tmp",
            isDirectory: false
        )
        defer { try? fileManager.removeItem(at: temporaryURL) }
        try (data as Data).write(to: temporaryURL, options: .atomic)
        try beforePersistCommit()
        try Task.checkCancellation()
        if fileManager.fileExists(atPath: url.path) {
            _ = try fileManager.replaceItemAt(
                url,
                withItemAt: temporaryURL,
                backupItemName: nil,
                options: []
            )
        } else {
            try fileManager.moveItem(at: temporaryURL, to: url)
        }
    }
}

enum HistoryImageAssetLoaderError: Error, Equatable {
    case queueFull
}

actor HistoryImageAssetLoader {
    typealias Decoder = @Sendable (HistoryImageAssetRequest) async throws -> HistoryImageAsset?
    typealias RetrySleep = @Sendable (UInt64) async throws -> Void
    typealias StateDidChange = @Sendable () -> Void

    struct Snapshot: Sendable {
        let activeCount: Int
        let pendingCount: Int
        let jobCount: Int
    }

    static let shared = HistoryImageAssetLoader()

    private enum JobState {
        case pending
        case running(Task<Void, Never>)
        case cancelling(Task<Void, Never>)
    }

    private struct Job {
        let id: UUID
        let request: HistoryImageAssetRequest
        var priority: HistoryImageLoadPriority
        var waiters: [UUID: HistoryImageAssetWaiterDriver]
        var state: JobState
    }

    private let maximumActiveLoads: Int
    private let maximumPendingLoads: Int
    private let cache: ImageMemoryCache
    private let decoder: Decoder
    private let stateDidChange: StateDidChange
    private var jobsByID: [UUID: Job] = [:]
    private var currentJobIDByKey: [String: UUID] = [:]
    private var jobIDByWaiterID: [UUID: UUID] = [:]
    private var pendingJobIDs: [UUID] = []
    private var activeCount = 0

    init(
        maximumActiveLoads: Int = 3,
        maximumPendingLoads: Int = 64,
        cache: ImageMemoryCache = .shared,
        decoder: @escaping Decoder = { request in
            try HistoryImageAssetDecoder().decode(request)
        },
        stateDidChange: @escaping StateDidChange = {}
    ) {
        self.maximumActiveLoads = max(1, maximumActiveLoads)
        self.maximumPendingLoads = max(0, maximumPendingLoads)
        self.cache = cache
        self.decoder = decoder
        self.stateDidChange = stateDidChange
    }

    func load(_ request: HistoryImageAssetRequest) async throws -> HistoryImageAsset? {
        let waiterID = UUID()
        let driver = HistoryImageAssetWaiterDriver()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard driver.install(continuation) else {
                    return
                }
                register(
                    request: request,
                    waiterID: waiterID,
                    driver: driver
                )
            }
        } onCancel: {
            driver.cancel()
            Task { await self.cancel(waiterID: waiterID) }
        }
    }

    nonisolated func loadVisible(
        _ request: HistoryImageAssetRequest,
        maximumQueueFullRetries: Int? = nil,
        retryDelayNanoseconds: UInt64 = 25_000_000,
        sleep: @escaping RetrySleep = { delay in
            try await Task.sleep(nanoseconds: delay)
        }
    ) async throws -> HistoryImageAsset? {
        var retryCount = 0
        while true {
            do {
                return try await load(request)
            } catch let error as HistoryImageAssetLoaderError {
                guard error == .queueFull,
                      request.priority == .visible else {
                    throw error
                }
                if let maximumQueueFullRetries,
                   retryCount >= max(0, maximumQueueFullRetries) {
                    throw error
                }
                retryCount += 1
                try Task.checkCancellation()
                try await sleep(retryDelayNanoseconds)
            }
        }
    }

    func snapshot() -> Snapshot {
        Snapshot(
            activeCount: activeCount,
            pendingCount: pendingJobIDs.count,
            jobCount: jobsByID.count
        )
    }

    func waiterCount(for cacheKey: String) -> Int {
        guard let jobID = currentJobIDByKey[cacheKey] else {
            return 0
        }
        return jobsByID[jobID]?.waiters.count ?? 0
    }

    private func register(
        request: HistoryImageAssetRequest,
        waiterID: UUID,
        driver: HistoryImageAssetWaiterDriver
    ) {
        if driver.isCompleted {
            return
        }
        if let cachedImage = cache.cachedImage(for: request.cacheKey) {
            let width = max(1, Int(cachedImage.size.width.rounded(.up)))
            let height = max(1, Int(cachedImage.size.height.rounded(.up)))
            driver.finish(.success(HistoryImageAsset(
                cacheKey: request.cacheKey,
                image: cachedImage,
                pixelWidth: width,
                pixelHeight: height
            )))
            return
        }
        if let currentJobID = currentJobIDByKey[request.cacheKey],
           var currentJob = jobsByID[currentJobID] {
            currentJob.waiters[waiterID] = driver
            jobIDByWaiterID[waiterID] = currentJobID
            if request.priority.rawValue > currentJob.priority.rawValue {
                currentJob.priority = request.priority
                jobsByID[currentJobID] = currentJob
                promotePendingJobIfNeeded(
                    currentJobID,
                    priority: request.priority
                )
                stateDidChange()
                return
            }
            jobsByID[currentJobID] = currentJob
            stateDidChange()
            return
        }

        if activeCount >= maximumActiveLoads,
           pendingJobIDs.count >= maximumPendingLoads,
           !makePendingRoom(for: request.priority) {
            driver.finish(.failure(HistoryImageAssetLoaderError.queueFull))
            return
        }

        let jobID = UUID()
        let job = Job(
            id: jobID,
            request: request,
            priority: request.priority,
            waiters: [waiterID: driver],
            state: .pending
        )
        jobsByID[jobID] = job
        currentJobIDByKey[request.cacheKey] = jobID
        jobIDByWaiterID[waiterID] = jobID
        if activeCount < maximumActiveLoads {
            start(jobID: jobID)
        } else {
            enqueuePendingJob(jobID, priority: request.priority)
        }
        stateDidChange()
    }

    private func makePendingRoom(
        for priority: HistoryImageLoadPriority
    ) -> Bool {
        guard priority == .visible,
              let index = pendingJobIDs.firstIndex(where: { jobID in
                jobsByID[jobID]?.priority == .preheat
              }) else {
            return false
        }
        let evictedJobID = pendingJobIDs.remove(at: index)
        guard let evictedJob = jobsByID.removeValue(forKey: evictedJobID) else {
            return true
        }
        if currentJobIDByKey[evictedJob.request.cacheKey] == evictedJobID {
            currentJobIDByKey[evictedJob.request.cacheKey] = nil
        }
        evictedJob.waiters.forEach { waiterID, driver in
            jobIDByWaiterID[waiterID] = nil
            driver.finish(.failure(HistoryImageAssetLoaderError.queueFull))
        }
        return true
    }

    private func promotePendingJobIfNeeded(
        _ jobID: UUID,
        priority: HistoryImageLoadPriority
    ) {
        guard let index = pendingJobIDs.firstIndex(of: jobID) else {
            return
        }
        pendingJobIDs.remove(at: index)
        enqueuePendingJob(jobID, priority: priority)
    }

    private func enqueuePendingJob(
        _ jobID: UUID,
        priority: HistoryImageLoadPriority
    ) {
        if priority == .visible,
           let firstPreheatIndex = pendingJobIDs.firstIndex(where: { pendingJobID in
            jobsByID[pendingJobID]?.priority == .preheat
           }) {
            pendingJobIDs.insert(jobID, at: firstPreheatIndex)
        } else {
            pendingJobIDs.append(jobID)
        }
    }

    private func start(jobID: UUID) {
        guard activeCount < maximumActiveLoads,
              var job = jobsByID[jobID],
              case .pending = job.state else {
            return
        }
        activeCount += 1
        let request = job.request
        let decoder = self.decoder
        let worker = Task.detached(priority: .utility) { [weak self] in
            let result: Result<HistoryImageAsset?, Error>
            do {
                result = .success(try await decoder(request))
            } catch {
                result = .failure(error)
            }
            await self?.complete(jobID: jobID, result: result)
        }
        job.state = .running(worker)
        jobsByID[jobID] = job
    }

    private func cancel(waiterID: UUID) {
        guard let jobID = jobIDByWaiterID.removeValue(forKey: waiterID),
              var job = jobsByID[jobID] else {
            return
        }
        job.waiters[waiterID] = nil
        guard job.waiters.isEmpty else {
            jobsByID[jobID] = job
            return
        }

        if currentJobIDByKey[job.request.cacheKey] == jobID {
            currentJobIDByKey[job.request.cacheKey] = nil
        }
        switch job.state {
        case .pending:
            pendingJobIDs.removeAll { $0 == jobID }
            jobsByID[jobID] = nil
        case .running(let worker):
            worker.cancel()
            job.state = .cancelling(worker)
            jobsByID[jobID] = job
        case .cancelling:
            jobsByID[jobID] = job
        }
        stateDidChange()
    }

    private func complete(
        jobID: UUID,
        result: Result<HistoryImageAsset?, Error>
    ) {
        guard let job = jobsByID.removeValue(forKey: jobID) else {
            return
        }
        switch job.state {
        case .running, .cancelling:
            activeCount = max(0, activeCount - 1)
        case .pending:
            return
        }
        if currentJobIDByKey[job.request.cacheKey] == jobID {
            currentJobIDByKey[job.request.cacheKey] = nil
        }
        let activeWaiters = job.waiters.filter { !$0.value.isCompleted }
        activeWaiters.forEach { waiterID, _ in
            jobIDByWaiterID[waiterID] = nil
        }
        if !activeWaiters.isEmpty,
           case .success(let asset?) = result {
            cache.store(
                asset.image,
                for: asset.cacheKey,
                pixelWidth: asset.pixelWidth,
                pixelHeight: asset.pixelHeight
            )
        }
        activeWaiters.values.forEach { $0.finish(result) }
        pumpPendingJobs()
        stateDidChange()
    }

    private func pumpPendingJobs() {
        while activeCount < maximumActiveLoads,
              !pendingJobIDs.isEmpty {
            let jobID = pendingJobIDs.removeFirst()
            guard jobsByID[jobID] != nil else {
                continue
            }
            start(jobID: jobID)
        }
    }
}

private final class HistoryImageAssetWaiterDriver: @unchecked Sendable {
    typealias Continuation = CheckedContinuation<HistoryImageAsset?, Error>

    private let lock = NSLock()
    private var continuation: Continuation?
    private var terminalResult: Result<HistoryImageAsset?, Error>?

    var isCompleted: Bool {
        lock.lock()
        defer { lock.unlock() }
        return terminalResult != nil
    }

    func install(_ continuation: Continuation) -> Bool {
        lock.lock()
        if let terminalResult {
            lock.unlock()
            continuation.resume(with: terminalResult)
            return false
        }
        self.continuation = continuation
        lock.unlock()
        return true
    }

    func finish(_ result: Result<HistoryImageAsset?, Error>) {
        complete(with: result)
    }

    func cancel() {
        complete(with: .failure(CancellationError()))
    }

    private func complete(with result: Result<HistoryImageAsset?, Error>) {
        lock.lock()
        guard terminalResult == nil else {
            lock.unlock()
            return
        }
        terminalResult = result
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(with: result)
    }
}
