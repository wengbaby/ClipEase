import AppKit
import Foundation
@testable import ClipEase

@MainActor
func makePayloadStagingMonitor(
    payload: ClipboardPayloadStagingPasteboardProbe,
    stager: ClipboardPayloadStager,
    payloadImporter: @escaping ClipboardMonitorPayloadImporter,
    statusRecorder: @escaping ClipboardPayloadProcessingRecorder = { _ in },
    diagnosticRecorder: @escaping ClipboardMonitorImportDiagnosticRecorder = { _ in },
    store suppliedStore: ClipboardHistoryStore? = nil
) -> ClipboardMonitor {
    let store = suppliedStore ?? ClipboardHistoryStore(
        persistence: ClipboardHistoryPersistence(
            repository: ClipboardPayloadStagingEmptyRepository()
        )
    )
    let pasteboard = NSPasteboard(
        name: NSPasteboard.Name("ClipEaseTests-\(UUID().uuidString)")
    )
    return ClipboardMonitor(
        store: store,
        pasteboard: pasteboard,
        sourceAppProvider: {
            SourceAppInfo(
                name: "Source",
                bundleID: "com.example.source",
                iconName: "app.fill",
                iconFileName: nil,
                headerColorHex: "#2E8CFF"
            )
        },
        isPaused: { false },
        isIgnored: { _ in false },
        pasteboardChangeCountProvider: { payload.changeCount },
        pasteboardSnapshotProvider: { payload.snapshot() },
        payloadImporter: payloadImporter,
        importDiagnosticRecorder: diagnosticRecorder,
        payloadStager: stager,
        payloadProcessingRecorder: statusRecorder,
        observesSystemLifecycle: false
    )
}

@MainActor
final class ClipboardPayloadStagingPasteboardProbe {
    var changeCount: Int
    var imageData: Data
    let pasteboardType: NSPasteboard.PasteboardType

    init(
        changeCount: Int,
        imageData: Data,
        pasteboardType: NSPasteboard.PasteboardType = NSPasteboard.PasteboardType(
            "public.png"
        )
    ) {
        self.changeCount = changeCount
        self.imageData = imageData
        self.pasteboardType = pasteboardType
    }

    func snapshot() -> ClipboardMonitorPasteboardReadSnapshot {
        ClipboardMonitorPasteboardReadSnapshot(
            changeCount: changeCount,
            types: [pasteboardType],
            strings: [:],
            data: [pasteboardType: imageData],
            fileURLs: []
        )
    }
}

final class ReverseCompletionPayloadStagingFileSystemProbe: @unchecked Sendable {
    private let lock = NSLock()
    private let firstWriteRelease = DispatchSemaphore(value: 0)
    private var storedDataByPath: [String: Data] = [:]
    private var storedSecondWriteFinished = false

    var secondWriteFinished: Bool {
        lock.withLock { storedSecondWriteFinished }
    }

    lazy var fileSystem = ClipboardPayloadStagingFileSystem(
        createDirectory: { _ in },
        writeAtomically: { [weak self] data, url in
            guard let self else { return }
            lock.withLock {
                storedDataByPath[url.path] = data
            }
            if data.first == 0x01 {
                firstWriteRelease.wait()
            } else if data.first == 0x02 {
                lock.withLock {
                    storedSecondWriteFinished = true
                }
            }
        },
        readData: { [weak self] url in
            guard let self,
                  let data = lock.withLock({ storedDataByPath[url.path] }) else {
                throw ClipboardPayloadStagingError.stagedFileUnreadable
            }
            return data
        },
        removeItem: { [weak self] url in
            _ = self?.lock.withLock {
                self?.storedDataByPath.removeValue(forKey: url.path)
            }
        }
    )

    func waitForSecondWrite(
        timeout: Duration = .seconds(2)
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !secondWriteFinished {
            guard clock.now < deadline else {
                return false
            }
            await Task.yield()
        }
        return true
    }

    func releaseFirstWrite() {
        firstWriteRelease.signal()
    }
}

actor PayloadImportOrderProbe {
    private var values: [UInt8] = []

    func importPayload(
        _ request: ClipboardMonitorPayloadImportRequest
    ) async throws -> ClipboardMonitorPayloadImportResult {
        let data: Data
        switch request {
        case .image(let stagedPayload, _), .pdf(let stagedPayload):
            data = try stagedPayload.readData()
        case .richText:
            throw ClipboardPayloadStagingError.stagedFileUnreadable
        }
        if let first = data.first {
            values.append(first)
        }
        throw CancellationError()
    }

    var importedValues: [UInt8] {
        values
    }
}

final class PayloadTestFileManager: FileManager, @unchecked Sendable {
    private let rootURL: URL

    init(rootURL: URL) {
        self.rootURL = rootURL
        super.init()
    }

    override func url(
        for directory: FileManager.SearchPathDirectory,
        in domain: FileManager.SearchPathDomainMask,
        appropriateFor url: URL?,
        create shouldCreate: Bool
    ) throws -> URL {
        if shouldCreate {
            try createDirectory(
                at: rootURL,
                withIntermediateDirectories: true
            )
        }
        return rootURL
    }
}

private enum PayloadTestFixtureError: Error {
    case imageEncodingFailed
    case pdfEncodingFailed
}

@MainActor
final class PayloadImporterTestContext {
    let rootURL: URL
    let fileManager: PayloadTestFileManager
    let persistence: ClipboardHistoryPersistence
    let stager: ClipboardPayloadStager
    let store: ClipboardHistoryStore

    init() throws {
        let temporaryRootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "ClipEase-Payload-\(UUID().uuidString)",
                isDirectory: true
            )
        rootURL = temporaryRootURL
        try FileManager.default.createDirectory(
            at: temporaryRootURL,
            withIntermediateDirectories: true
        )
        fileManager = PayloadTestFileManager(rootURL: temporaryRootURL)
        persistence = ClipboardHistoryPersistence(
            fileManager: fileManager,
            repository: ClipboardPayloadStagingEmptyRepository()
        )
        stager = ClipboardPayloadStager(
            directoryProvider: {
                temporaryRootURL.appendingPathComponent(
                    "PayloadStaging",
                    isDirectory: true
                )
            }
        )
        store = ClipboardHistoryStore(
            persistence: persistence,
            externalCopyFeedback: { _ in }
        )
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: rootURL)
    }
}

@MainActor
func makePayloadTestPNG() throws -> Data {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: 2,
        pixelsHigh: 2,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw PayloadTestFixtureError.imageEncodingFailed
    }
    for x in 0..<2 {
        for y in 0..<2 {
            bitmap.setColor(.systemBlue, atX: x, y: y)
        }
    }
    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw PayloadTestFixtureError.imageEncodingFailed
    }
    return data
}

func makePayloadTestPDF(pageCount: Int = 1) throws -> Data {
    let data = NSMutableData()
    guard let consumer = CGDataConsumer(data: data as CFMutableData) else {
        throw PayloadTestFixtureError.pdfEncodingFailed
    }
    var mediaBox = CGRect(x: 0, y: 0, width: 32, height: 32)
    guard let context = CGContext(
        consumer: consumer,
        mediaBox: &mediaBox,
        nil
    ) else {
        throw PayloadTestFixtureError.pdfEncodingFailed
    }
    guard let fillColor = CGColor(
        colorSpace: CGColorSpaceCreateDeviceRGB(),
        components: [0.1, 0.4, 0.9, 1.0]
    ) else {
        throw PayloadTestFixtureError.pdfEncodingFailed
    }
    for _ in 0..<max(0, pageCount) {
        context.beginPDFPage(nil)
        context.setFillColor(fillColor)
        context.fill(mediaBox)
        context.endPDFPage()
    }
    context.closePDF()
    return data as Data
}

actor ClipboardPayloadImporterCallProbe {
    private(set) var callCount = 0
    private(set) var lastRequest: ClipboardMonitorPayloadImportRequest?

    func record(_ request: ClipboardMonitorPayloadImportRequest) {
        callCount += 1
        lastRequest = request
    }
}

final class PayloadDecodeProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var storedDecodeCount = 0

    var decodeCount: Int {
        lock.withLock { storedDecodeCount }
    }

    func recordDecode() {
        lock.withLock {
            storedDecodeCount += 1
        }
    }
}

actor PayloadImportBlockingGate {
    private var continuations: [CheckedContinuation<Void, Never>?] = []

    var callCount: Int {
        continuations.count
    }

    func importPayload(
        _ request: ClipboardMonitorPayloadImportRequest
    ) async throws -> ClipboardMonitorPayloadImportResult {
        _ = request
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
        throw CancellationError()
    }

    func waitForCallCount(
        _ expectedCount: Int,
        timeout: Duration = .seconds(2)
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while continuations.count < expectedCount {
            guard clock.now < deadline else {
                return false
            }
            await Task.yield()
        }
        return true
    }

    func resumeCall(at index: Int) {
        guard continuations.indices.contains(index),
              let continuation = continuations[index] else {
            return
        }
        continuations[index] = nil
        continuation.resume()
    }
}

final class PayloadStagingFileSystemProbe: @unchecked Sendable {
    private let lock = NSLock()
    private let writeError: Error?
    private let readError: Error?
    private let moveError: Error?
    private let directoryContents: [URL]
    private var storedWriteCount = 0
    private var storedRemoveCount = 0
    private var remainingRemoveFailureCount: Int
    private var remainingContentsFailureCount: Int
    private var storedContentsCallCount = 0
    private var storedRemovedURLs: [URL] = []

    init(
        writeError: Error? = nil,
        readError: Error? = nil,
        moveError: Error? = nil,
        removeFailureCount: Int = 0,
        contentsFailureCount: Int = 0,
        directoryContents: [URL] = []
    ) {
        self.writeError = writeError
        self.readError = readError
        self.moveError = moveError
        self.remainingRemoveFailureCount = max(0, removeFailureCount)
        self.remainingContentsFailureCount = max(0, contentsFailureCount)
        self.directoryContents = directoryContents
    }

    var writeCount: Int {
        lock.withLock { storedWriteCount }
    }

    var removeCount: Int {
        lock.withLock { storedRemoveCount }
    }

    var removedURLs: [URL] {
        lock.withLock { storedRemovedURLs }
    }

    var contentsCallCount: Int {
        lock.withLock { storedContentsCallCount }
    }

    lazy var fileSystem = ClipboardPayloadStagingFileSystem(
        createDirectory: { _ in },
        writeAtomically: { [weak self] _, _ in
            guard let self else { return }
            lock.withLock { storedWriteCount += 1 }
            if let writeError {
                throw writeError
            }
        },
        readData: { [weak self] _ in
            guard let self else { return Data() }
            if let readError {
                throw readError
            }
            return Data([0x01])
        },
        removeItem: { [weak self] url in
            guard let self else { return }
            let shouldFail = lock.withLock { () -> Bool in
                storedRemoveCount += 1
                if remainingRemoveFailureCount > 0 {
                    remainingRemoveFailureCount -= 1
                    return true
                }
                storedRemovedURLs.append(url)
                return false
            }
            if shouldFail {
                throw NSError(
                    domain: NSCocoaErrorDomain,
                    code: NSFileWriteUnknownError
                )
            }
        },
        moveItem: { [weak self] _, _ in
            if let moveError = self?.moveError {
                throw moveError
            }
        },
        contentsOfDirectory: { [weak self] _ in
            guard let self else {
                return []
            }
            let shouldFail = lock.withLock { () -> Bool in
                storedContentsCallCount += 1
                guard remainingContentsFailureCount > 0 else {
                    return false
                }
                remainingContentsFailureCount -= 1
                return true
            }
            if shouldFail {
                throw NSError(
                    domain: NSCocoaErrorDomain,
                    code: NSFileReadUnknownError
                )
            }
            return directoryContents
        }
    )
}

final class BlockingPayloadStagingFileSystemProbe: @unchecked Sendable {
    private let lock = NSLock()
    private let releaseSemaphore = DispatchSemaphore(value: 0)
    private var storedStartedWriteCount = 0
    private var storedConcurrentWriteCount = 0
    private var storedMaximumConcurrentWriteCount = 0
    private var storedRemoveCount = 0

    var maximumConcurrentWriteCount: Int {
        lock.withLock { storedMaximumConcurrentWriteCount }
    }

    var removeCount: Int {
        lock.withLock { storedRemoveCount }
    }

    lazy var fileSystem = ClipboardPayloadStagingFileSystem(
        createDirectory: { _ in },
        writeAtomically: { [weak self] _, _ in
            guard let self else { return }
            lock.withLock {
                storedStartedWriteCount += 1
                storedConcurrentWriteCount += 1
                storedMaximumConcurrentWriteCount = max(
                    storedMaximumConcurrentWriteCount,
                    storedConcurrentWriteCount
                )
            }
            releaseSemaphore.wait()
            lock.withLock { storedConcurrentWriteCount -= 1 }
        },
        readData: { _ in Data([0x01]) },
        removeItem: { [weak self] _ in
            guard let self else { return }
            lock.withLock { storedRemoveCount += 1 }
        }
    )

    func waitForStartedWriteCount(
        _ expectedCount: Int,
        timeout: Duration = .seconds(2)
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while lock.withLock({ storedStartedWriteCount < expectedCount }) {
            guard clock.now < deadline else {
                return false
            }
            await Task.yield()
        }
        return true
    }

    func waitForRemoveCount(
        _ expectedCount: Int,
        timeout: Duration = .seconds(2)
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while lock.withLock({ storedRemoveCount < expectedCount }) {
            guard clock.now < deadline else {
                return false
            }
            await Task.yield()
        }
        return true
    }

    func releaseWrites(_ count: Int) {
        for _ in 0..<count {
            releaseSemaphore.signal()
        }
    }
}

extension Array where Element == Task<
    Result<ClipboardStagedPayload, ClipboardPayloadStagingError>,
    Never
> {
    func asyncValues() async -> [Result<ClipboardStagedPayload, ClipboardPayloadStagingError>] {
        var results: [Result<ClipboardStagedPayload, ClipboardPayloadStagingError>] = []
        results.reserveCapacity(count)
        for task in self {
            results.append(await task.value)
        }
        return results
    }
}

struct ClipboardPayloadStagingEmptyRepository: ClipboardHistoryRepository {
    func loadSnapshot() throws -> ClipboardHistorySnapshot {
        ClipboardHistorySnapshot(items: [], groups: [])
    }

    func saveSnapshot(_ snapshot: ClipboardHistorySnapshot) throws {
        _ = snapshot
    }
}
