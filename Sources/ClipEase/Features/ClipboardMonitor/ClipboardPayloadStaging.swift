import Darwin
import Foundation

enum ClipboardPayloadContentKind: String, Equatable, Sendable {
    case image
    case richTextRTF
    case richTextHTML
    case pdf

    fileprivate var fileExtension: String {
        switch self {
        case .image:
            "image"
        case .richTextRTF:
            "rtf"
        case .richTextHTML:
            "html"
        case .pdf:
            "pdf"
        }
    }
}

enum ClipboardPayloadProcessingReason: String, Equatable, Sendable {
    case residentTaskLimitExceeded
    case retainedDataLimitExceeded
    case diskFull
    case atomicWriteFailed
    case stagedFileUnreadable
    case staleGeneration
    case importFailed
    case notPersisted
    case previewLimitExceeded
    case ocrLimitExceeded
    case selfWrite
}

enum ClipboardPayloadProcessingStatus: Equatable, Sendable {
    case queued
    case processing
    case deferred(ClipboardPayloadProcessingReason)
    case skipped(ClipboardPayloadProcessingReason)
    case failed(ClipboardPayloadProcessingReason)
    case completed
}

struct ClipboardPayloadProcessingUpdate: Equatable, Sendable {
    let id: UUID
    let capturedType: String
    let status: ClipboardPayloadProcessingStatus
}

struct ClipboardPayloadProcessingFailure: Error, LocalizedError, Sendable {
    let reason: ClipboardPayloadProcessingReason

    var errorDescription: String? {
        "Clipboard payload processing failed: \(reason.rawValue)."
    }
}

typealias ClipboardPayloadProcessingRecorder = @MainActor (
    ClipboardPayloadProcessingUpdate
) -> Void

@MainActor
enum ClipboardPayloadProcessingStatusPresenter {
    static func present(_ update: ClipboardPayloadProcessingUpdate) {
        guard let message = userVisibleMessage(for: update.status) else {
            return
        }
        GlobalStatusToastController.shared.show(message, relativeTo: nil)
    }

    static func userVisibleMessage(
        for status: ClipboardPayloadProcessingStatus
    ) -> String? {
        switch status {
        case .failed(.diskFull):
            L("磁盘空间不足，剪贴板内容未保存")
        case .failed, .skipped(.notPersisted):
            L("剪贴板内容未能保存")
        case .deferred(.residentTaskLimitExceeded),
             .deferred(.retainedDataLimitExceeded):
            L("剪贴板内容处理队列已满")
        case .queued, .processing, .deferred, .skipped, .completed:
            nil
        }
    }
}

enum ClipboardPayloadStagingError: Error, Equatable, Sendable {
    case residentTaskLimitExceeded
    case retainedDataLimitExceeded
    case diskFull
    case atomicWriteFailed
    case stagedFileUnreadable
    case invalidReservation

    var processingReason: ClipboardPayloadProcessingReason {
        switch self {
        case .residentTaskLimitExceeded:
            .residentTaskLimitExceeded
        case .retainedDataLimitExceeded:
            .retainedDataLimitExceeded
        case .diskFull:
            .diskFull
        case .atomicWriteFailed, .invalidReservation:
            .atomicWriteFailed
        case .stagedFileUnreadable:
            .stagedFileUnreadable
        }
    }
}

extension ClipboardPayloadStagingError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .residentTaskLimitExceeded:
            "Clipboard payload staging reached its resident task limit."
        case .retainedDataLimitExceeded:
            "Clipboard payload staging reached its retained data limit."
        case .diskFull:
            "Clipboard payload staging could not continue because the disk is full."
        case .atomicWriteFailed:
            "Clipboard payload staging could not atomically persist the payload."
        case .stagedFileUnreadable:
            "Clipboard payload staging could not read the staged payload."
        case .invalidReservation:
            "Clipboard payload staging received an invalid capacity reservation."
        }
    }
}

struct ClipboardPayloadStagingSource: Sendable {
    let data: Data
    let contentKind: ClipboardPayloadContentKind
    let preferredFileExtension: String?

    init(
        data: Data,
        contentKind: ClipboardPayloadContentKind,
        preferredFileExtension: String? = nil
    ) {
        self.data = data
        self.contentKind = contentKind
        self.preferredFileExtension = preferredFileExtension
    }
}

enum ClipboardRichTextStagingEnvelope {
    private static let magic = Data("CERT1".utf8)
    private static let headerByteCount = magic.count + 1 + MemoryLayout<UInt64>.size

    static func encode(
        _ payload: ClipboardRichTextPasteboardPayload
    ) -> ClipboardPayloadStagingSource {
        let contentKind: ClipboardPayloadContentKind
        switch payload {
        case .rtf:
            contentKind = .richTextRTF
        case .html:
            contentKind = .richTextHTML
        }

        let fallbackData = payload.fallbackPlainText?.data(using: .utf8)
        var data = Data()
        data.append(magic)
        data.append(fallbackData == nil ? 0 : 1)
        var primaryByteCount = UInt64(payload.data.count).bigEndian
        withUnsafeBytes(of: &primaryByteCount) { data.append(contentsOf: $0) }
        data.append(payload.data)
        if let fallbackData {
            data.append(fallbackData)
        }
        return ClipboardPayloadStagingSource(data: data, contentKind: contentKind)
    }

    static func decode(
        _ stagedData: Data,
        contentKind: ClipboardPayloadContentKind
    ) throws -> ClipboardRichTextPasteboardPayload {
        guard stagedData.count >= headerByteCount,
              stagedData.prefix(magic.count) == magic else {
            throw ClipboardPayloadStagingError.stagedFileUnreadable
        }
        let fallbackFlagIndex = magic.count
        let fallbackFlag = stagedData[fallbackFlagIndex]
        guard fallbackFlag == 0 || fallbackFlag == 1 else {
            throw ClipboardPayloadStagingError.stagedFileUnreadable
        }

        let lengthStart = fallbackFlagIndex + 1
        let lengthEnd = lengthStart + MemoryLayout<UInt64>.size
        let primaryByteCount = stagedData[lengthStart..<lengthEnd].reduce(UInt64(0)) {
            ($0 << 8) | UInt64($1)
        }
        let primaryStart = lengthEnd
        let availablePrimaryAndFallbackBytes = stagedData.count - primaryStart
        guard primaryByteCount <= UInt64(availablePrimaryAndFallbackBytes) else {
            throw ClipboardPayloadStagingError.stagedFileUnreadable
        }
        let primaryEnd = primaryStart + Int(primaryByteCount)
        let primaryData = Data(stagedData[primaryStart..<primaryEnd])
        let fallbackPlainText: String?
        if fallbackFlag == 0 {
            guard primaryEnd == stagedData.count else {
                throw ClipboardPayloadStagingError.stagedFileUnreadable
            }
            fallbackPlainText = nil
        } else {
            guard let decoded = String(
                data: stagedData[primaryEnd..<stagedData.count],
                encoding: .utf8
            ) else {
                throw ClipboardPayloadStagingError.stagedFileUnreadable
            }
            fallbackPlainText = decoded
        }

        switch contentKind {
        case .richTextRTF:
            return .rtf(data: primaryData, fallbackPlainText: fallbackPlainText)
        case .richTextHTML:
            return .html(data: primaryData, fallbackPlainText: fallbackPlainText)
        case .image, .pdf:
            throw ClipboardPayloadStagingError.stagedFileUnreadable
        }
    }
}

struct ClipboardPayloadStagingDiagnostics: Equatable, Sendable {
    let residentTaskCount: Int
    let retainedByteCount: Int
    let rejectedTaskCount: Int
    let waitingTaskCount: Int
}

struct ClipboardPayloadStagingFileSystem: @unchecked Sendable {
    let createDirectory: @Sendable (URL) throws -> Void
    let writeAtomically: @Sendable (Data, URL) throws -> Void
    let readData: @Sendable (URL) throws -> Data
    let removeItem: @Sendable (URL) throws -> Void
    let moveItem: @Sendable (URL, URL) throws -> Void
    let contentsOfDirectory: @Sendable (URL) throws -> [URL]

    init(
        createDirectory: @escaping @Sendable (URL) throws -> Void,
        writeAtomically: @escaping @Sendable (Data, URL) throws -> Void,
        readData: @escaping @Sendable (URL) throws -> Data,
        removeItem: @escaping @Sendable (URL) throws -> Void,
        moveItem: @escaping @Sendable (URL, URL) throws -> Void = { _, _ in },
        contentsOfDirectory: @escaping @Sendable (URL) throws -> [URL] = { _ in [] }
    ) {
        self.createDirectory = createDirectory
        self.writeAtomically = writeAtomically
        self.readData = readData
        self.removeItem = removeItem
        self.moveItem = moveItem
        self.contentsOfDirectory = contentsOfDirectory
    }

    static let live: ClipboardPayloadStagingFileSystem = {
        return ClipboardPayloadStagingFileSystem(
            createDirectory: { directoryURL in
                try ClipboardPayloadStagingDarwinFileSystem.createDirectory(
                    at: directoryURL
                )
            },
            writeAtomically: { data, fileURL in
                try ClipboardPayloadStagingDarwinFileSystem.writeAtomically(
                    data,
                    to: fileURL
                )
            },
            readData: { fileURL in
                try ClipboardPayloadStagingDarwinFileSystem.readData(
                    at: fileURL
                )
            },
            removeItem: { fileURL in
                try ClipboardPayloadStagingDarwinFileSystem.removeItem(
                    at: fileURL
                )
            },
            moveItem: { sourceURL, destinationURL in
                try ClipboardPayloadStagingDarwinFileSystem.moveItem(
                    at: sourceURL,
                    to: destinationURL
                )
            },
            contentsOfDirectory: { directoryURL in
                try ClipboardPayloadStagingDarwinFileSystem.contentsOfDirectory(
                    at: directoryURL
                )
            }
        )
    }()
}

private enum ClipboardPayloadStagingPathPolicy {
    static let controlledFileExtensions: Set<String> = [
        "atomic", "bmp", "gif", "heic", "heif", "html", "ico", "image",
        "jpeg", "jpg", "pdf", "png", "rtf", "tif", "tiff", "tmp", "webp",
    ]

    static func isControlledStagingFileName(_ fileName: String) -> Bool {
        let components = fileName.split(
            separator: ".",
            omittingEmptySubsequences: false
        )
        guard components.count == 2,
              let identifier = UUID(uuidString: String(components[0])),
              identifier.uuidString.caseInsensitiveCompare(
                  String(components[0])
              ) == .orderedSame,
              controlledFileExtensions.contains(
                  String(components[1]).lowercased()
              ) else {
            return false
        }
        return true
    }

    static func isSafeDestinationFileName(_ fileName: String) -> Bool {
        !fileName.isEmpty
            && fileName != "."
            && fileName != ".."
            && !fileName.contains("/")
            && !fileName.contains("\0")
            && fileName.utf8.count <= Int(NAME_MAX)
    }
}

private enum ClipboardPayloadStagingDarwinFileSystem {
    private static let directoryFlags =
        O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
    private static let regularFileReadFlags = O_RDONLY | O_NOFOLLOW | O_CLOEXEC
    private static let maximumExaminedDirectoryEntries = 1_024

    static func createDirectory(at directoryURL: URL) throws {
        let descriptor = try openDirectory(
            at: directoryURL,
            createIfMissing: true,
            enforcePrivateMode: true
        )
        Darwin.close(descriptor)
    }

    static func writeAtomically(_ data: Data, to fileURL: URL) throws {
        let fileName = try controlledFileName(for: fileURL)
        let directoryDescriptor = try openDirectory(
            at: fileURL.deletingLastPathComponent(),
            createIfMissing: true,
            enforcePrivateMode: true
        )
        defer { Darwin.close(directoryDescriptor) }
        try requireMissingEntry(
            named: fileName,
            in: directoryDescriptor
        )

        let temporaryName = "\(UUID().uuidString).tmp"
        var temporaryDescriptor = temporaryName.withCString {
            Darwin.openat(
                directoryDescriptor,
                $0,
                O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
                mode_t(0o600)
            )
        }
        guard temporaryDescriptor >= 0 else {
            throw posixError()
        }
        var shouldRemoveTemporaryEntry = true
        defer {
            if temporaryDescriptor >= 0 {
                Darwin.close(temporaryDescriptor)
            }
            if shouldRemoveTemporaryEntry {
                temporaryName.withCString {
                    _ = Darwin.unlinkat(directoryDescriptor, $0, 0)
                }
            }
        }

        guard Darwin.fchmod(temporaryDescriptor, mode_t(0o600)) == 0 else {
            throw posixError()
        }
        try writeAll(data, to: temporaryDescriptor)
        guard Darwin.fsync(temporaryDescriptor) == 0 else {
            throw posixError()
        }
        guard Darwin.close(temporaryDescriptor) == 0 else {
            temporaryDescriptor = -1
            throw posixError()
        }
        temporaryDescriptor = -1
        let renameResult = temporaryName.withCString { temporaryPointer in
            fileName.withCString { filePointer in
                Darwin.renameat(
                    directoryDescriptor,
                    temporaryPointer,
                    directoryDescriptor,
                    filePointer
                )
            }
        }
        guard renameResult == 0 else {
            throw posixError()
        }
        shouldRemoveTemporaryEntry = false
        guard Darwin.fsync(directoryDescriptor) == 0 else {
            throw posixError()
        }
    }

    static func readData(at fileURL: URL) throws -> Data {
        let fileName = try controlledFileName(for: fileURL)
        let directoryDescriptor = try openDirectory(
            at: fileURL.deletingLastPathComponent(),
            createIfMissing: false,
            enforcePrivateMode: false
        )
        defer { Darwin.close(directoryDescriptor) }

        var entryStatus = stat()
        let statusResult = fileName.withCString {
            Darwin.fstatat(
                directoryDescriptor,
                $0,
                &entryStatus,
                AT_SYMLINK_NOFOLLOW
            )
        }
        guard statusResult == 0,
              isRegularFile(entryStatus) else {
            throw statusResult == 0
                ? posixError(code: EINVAL)
                : posixError()
        }
        let descriptor = fileName.withCString {
            Darwin.openat(directoryDescriptor, $0, regularFileReadFlags)
        }
        guard descriptor >= 0 else {
            throw posixError()
        }
        var openedStatus = stat()
        guard Darwin.fstat(descriptor, &openedStatus) == 0,
              isRegularFile(openedStatus),
              openedStatus.st_dev == entryStatus.st_dev,
              openedStatus.st_ino == entryStatus.st_ino else {
            Darwin.close(descriptor)
            throw posixError(code: EINVAL)
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        return try handle.readToEnd() ?? Data()
    }

    static func removeItem(at fileURL: URL) throws {
        let fileName = try controlledFileName(for: fileURL)
        let directoryDescriptor: Int32
        do {
            directoryDescriptor = try openDirectory(
                at: fileURL.deletingLastPathComponent(),
                createIfMissing: false,
                enforcePrivateMode: false
            )
        } catch let error as NSError
            where error.domain == NSPOSIXErrorDomain && error.code == Int(ENOENT) {
            return
        }
        defer { Darwin.close(directoryDescriptor) }

        var entryStatus = stat()
        let statusResult = fileName.withCString {
            Darwin.fstatat(
                directoryDescriptor,
                $0,
                &entryStatus,
                AT_SYMLINK_NOFOLLOW
            )
        }
        if statusResult != 0 {
            if errno == ENOENT {
                return
            }
            throw posixError()
        }
        guard isRegularFile(entryStatus) || isSymbolicLink(entryStatus) else {
            throw posixError(code: EINVAL)
        }
        let unlinkResult = fileName.withCString {
            Darwin.unlinkat(directoryDescriptor, $0, 0)
        }
        guard unlinkResult == 0 || errno == ENOENT else {
            throw posixError()
        }
    }

    static func moveItem(at sourceURL: URL, to destinationURL: URL) throws {
        let sourceName = try controlledFileName(for: sourceURL)
        let destinationName = destinationURL.lastPathComponent
        guard ClipboardPayloadStagingPathPolicy.isSafeDestinationFileName(
            destinationName
        ) else {
            throw posixError(code: EINVAL)
        }
        let sourceDirectoryDescriptor = try openDirectory(
            at: sourceURL.deletingLastPathComponent(),
            createIfMissing: false,
            enforcePrivateMode: false
        )
        defer { Darwin.close(sourceDirectoryDescriptor) }
        let destinationDirectoryDescriptor = try openDirectory(
            at: destinationURL.deletingLastPathComponent(),
            createIfMissing: true,
            enforcePrivateMode: true
        )
        defer { Darwin.close(destinationDirectoryDescriptor) }

        var sourceStatus = stat()
        let sourceStatusResult = sourceName.withCString {
            Darwin.fstatat(
                sourceDirectoryDescriptor,
                $0,
                &sourceStatus,
                AT_SYMLINK_NOFOLLOW
            )
        }
        guard sourceStatusResult == 0, isRegularFile(sourceStatus) else {
            throw sourceStatusResult == 0
                ? posixError(code: EINVAL)
                : posixError()
        }
        try requireMissingEntry(
            named: destinationName,
            in: destinationDirectoryDescriptor
        )
        let renameResult = sourceName.withCString { sourcePointer in
            destinationName.withCString { destinationPointer in
                Darwin.renameat(
                    sourceDirectoryDescriptor,
                    sourcePointer,
                    destinationDirectoryDescriptor,
                    destinationPointer
                )
            }
        }
        guard renameResult == 0 else {
            throw posixError()
        }
        guard Darwin.fsync(destinationDirectoryDescriptor) == 0 else {
            throw posixError()
        }
    }

    static func contentsOfDirectory(at directoryURL: URL) throws -> [URL] {
        let directoryDescriptor = try openDirectory(
            at: directoryURL,
            createIfMissing: false,
            enforcePrivateMode: false
        )
        defer { Darwin.close(directoryDescriptor) }
        let streamDescriptor = Darwin.dup(directoryDescriptor)
        guard streamDescriptor >= 0 else {
            throw posixError()
        }
        guard let directoryStream = Darwin.fdopendir(streamDescriptor) else {
            Darwin.close(streamDescriptor)
            throw posixError()
        }
        defer { Darwin.closedir(directoryStream) }

        var urls: [URL] = []
        var examinedEntryCount = 0
        while examinedEntryCount < maximumExaminedDirectoryEntries,
              let entry = Darwin.readdir(directoryStream) {
            examinedEntryCount += 1
            let fileName = withUnsafePointer(to: entry.pointee.d_name) {
                pointer in
                pointer.withMemoryRebound(
                    to: CChar.self,
                    capacity: Int(NAME_MAX) + 1
                ) {
                    String(cString: $0)
                }
            }
            guard ClipboardPayloadStagingPathPolicy
                .isControlledStagingFileName(fileName) else {
                continue
            }
            var entryStatus = stat()
            let statusResult = fileName.withCString {
                Darwin.fstatat(
                    directoryDescriptor,
                    $0,
                    &entryStatus,
                    AT_SYMLINK_NOFOLLOW
                )
            }
            guard statusResult == 0,
                  isRegularFile(entryStatus) || isSymbolicLink(entryStatus) else {
                continue
            }
            urls.append(
                directoryURL.appendingPathComponent(
                    fileName,
                    isDirectory: false
                )
            )
        }
        return urls
    }

    private static func openDirectory(
        at directoryURL: URL,
        createIfMissing: Bool,
        enforcePrivateMode: Bool
    ) throws -> Int32 {
        guard directoryURL.isFileURL else {
            throw posixError(code: EINVAL)
        }
        let components = securePathComponents(for: directoryURL)
        guard components.first == "/",
              components.count > 1,
              components.dropFirst().allSatisfy({
                  !$0.isEmpty && $0 != "." && $0 != ".."
              }) else {
            throw posixError(code: EINVAL)
        }
        var descriptor = "/".withCString {
            Darwin.open($0, directoryFlags)
        }
        guard descriptor >= 0 else {
            throw posixError()
        }
        do {
            for component in components.dropFirst() {
                var nextDescriptor = component.withCString {
                    Darwin.openat(descriptor, $0, directoryFlags)
                }
                if nextDescriptor < 0, errno == ENOENT, createIfMissing {
                    let createResult = component.withCString {
                        Darwin.mkdirat(descriptor, $0, mode_t(0o700))
                    }
                    if createResult != 0, errno != EEXIST {
                        throw posixError()
                    }
                    nextDescriptor = component.withCString {
                        Darwin.openat(descriptor, $0, directoryFlags)
                    }
                }
                guard nextDescriptor >= 0 else {
                    throw posixError()
                }
                Darwin.close(descriptor)
                descriptor = nextDescriptor
            }
            if enforcePrivateMode,
               Darwin.fchmod(descriptor, mode_t(0o700)) != 0 {
                throw posixError()
            }
            return descriptor
        } catch {
            Darwin.close(descriptor)
            throw error
        }
    }

    private static func securePathComponents(for directoryURL: URL) -> [String] {
        let path = directoryURL.path
        let normalizedPath: String
        if path == "/var" || path.hasPrefix("/var/") {
            normalizedPath = "/private\(path)"
        } else if path == "/tmp" || path.hasPrefix("/tmp/") {
            normalizedPath = "/private\(path)"
        } else {
            normalizedPath = path
        }
        return URL(fileURLWithPath: normalizedPath).pathComponents
    }

    private static func controlledFileName(for fileURL: URL) throws -> String {
        let fileName = fileURL.lastPathComponent
        guard fileURL.isFileURL,
              ClipboardPayloadStagingPathPolicy
                  .isControlledStagingFileName(fileName) else {
            throw posixError(code: EINVAL)
        }
        return fileName
    }

    private static func requireMissingEntry(
        named fileName: String,
        in directoryDescriptor: Int32
    ) throws {
        var entryStatus = stat()
        let statusResult = fileName.withCString {
            Darwin.fstatat(
                directoryDescriptor,
                $0,
                &entryStatus,
                AT_SYMLINK_NOFOLLOW
            )
        }
        if statusResult == 0 {
            throw posixError(code: EEXIST)
        }
        guard errno == ENOENT else {
            throw posixError()
        }
    }

    private static func writeAll(_ data: Data, to descriptor: Int32) throws {
        try data.withUnsafeBytes { buffer in
            guard let baseAddress = buffer.baseAddress else {
                return
            }
            var writtenByteCount = 0
            while writtenByteCount < buffer.count {
                let result = Darwin.write(
                    descriptor,
                    baseAddress.advanced(by: writtenByteCount),
                    buffer.count - writtenByteCount
                )
                if result < 0, errno == EINTR {
                    continue
                }
                guard result > 0 else {
                    throw posixError(code: result == 0 ? EIO : errno)
                }
                writtenByteCount += result
            }
        }
    }

    private static func isRegularFile(_ status: stat) -> Bool {
        status.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG)
    }

    private static func isSymbolicLink(_ status: stat) -> Bool {
        status.st_mode & mode_t(S_IFMT) == mode_t(S_IFLNK)
    }

    private static func posixError(code: Int32 = errno) -> NSError {
        NSError(domain: NSPOSIXErrorDomain, code: Int(code))
    }
}

enum ClipboardFileSystemErrorClassifier {
    static func isDiskFull(_ error: Error) -> Bool {
        isDiskFull(error as NSError, remainingDepth: 8)
    }

    private static func isDiskFull(
        _ error: NSError,
        remainingDepth: Int
    ) -> Bool {
        guard remainingDepth > 0 else {
            return false
        }
        if (
            error.domain == NSPOSIXErrorDomain
                && error.code == Int(POSIXErrorCode.ENOSPC.rawValue)
        ) || (
            error.domain == NSCocoaErrorDomain
                && error.code == NSFileWriteOutOfSpaceError
        ) {
            return true
        }
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError,
           isDiskFull(underlying, remainingDepth: remainingDepth - 1) {
            return true
        }
        let detailedErrors = error.userInfo["NSDetailedErrors"] as? [NSError] ?? []
        return detailedErrors.contains {
            isDiskFull($0, remainingDepth: remainingDepth - 1)
        }
    }
}

final class ClipboardPayloadCleanupCoordinator: @unchecked Sendable {
    private let fileSystem: ClipboardPayloadStagingFileSystem
    private let lock = NSLock()
    private var pendingURLs: Set<URL> = []

    init(fileSystem: ClipboardPayloadStagingFileSystem) {
        self.fileSystem = fileSystem
    }

    var pendingCount: Int {
        lock.withLock { pendingURLs.count }
    }

    func removeOrEnqueue(_ fileURL: URL) {
        do {
            try fileSystem.removeItem(fileURL)
            _ = lock.withLock {
                pendingURLs.remove(fileURL)
            }
        } catch {
            _ = lock.withLock {
                pendingURLs.insert(fileURL)
            }
        }
    }

    func enqueue(_ fileURLs: [URL]) {
        lock.withLock {
            pendingURLs.formUnion(fileURLs)
        }
    }

    func drain(maximumAttempts: Int = 3) async {
        let boundedAttempts = max(1, maximumAttempts)
        for _ in 0..<boundedAttempts {
            let urls = lock.withLock { Array(pendingURLs) }
            guard !urls.isEmpty else {
                return
            }
            let fileSystem = self.fileSystem
            let results = await Task.detached(priority: .utility) {
                urls.map { url -> (URL, Bool) in
                    do {
                        try fileSystem.removeItem(url)
                        return (url, true)
                    } catch {
                        return (url, false)
                    }
                }
            }.value
            lock.withLock { () -> Void in
                for (url, didRemove) in results where didRemove {
                    _ = pendingURLs.remove(url)
                }
            }
            await Task.yield()
        }
    }
}

final class ClipboardStagedPayload: @unchecked Sendable {
    let id: UUID
    let fileURL: URL
    let byteCount: Int
    let contentKind: ClipboardPayloadContentKind
    let preferredFileExtension: String?

    private let fileSystem: ClipboardPayloadStagingFileSystem
    private let cleanupCoordinator: ClipboardPayloadCleanupCoordinator
    private let lock = NSLock()
    private var isDiscarded = false
    private var isPromoted = false
    private var isTransferring = false

    init(
        id: UUID,
        fileURL: URL,
        byteCount: Int,
        contentKind: ClipboardPayloadContentKind,
        fileSystem: ClipboardPayloadStagingFileSystem,
        preferredFileExtension: String? = nil,
        cleanupCoordinator: ClipboardPayloadCleanupCoordinator? = nil
    ) {
        self.id = id
        self.fileURL = fileURL
        self.byteCount = max(0, byteCount)
        self.contentKind = contentKind
        self.preferredFileExtension = preferredFileExtension
        self.fileSystem = fileSystem
        self.cleanupCoordinator = cleanupCoordinator
            ?? ClipboardPayloadCleanupCoordinator(fileSystem: fileSystem)
    }

    deinit {
        discard()
    }

    func readData() throws -> Data {
        let canRead = lock.withLock { !isDiscarded && !isPromoted }
        guard canRead else {
            throw ClipboardPayloadStagingError.stagedFileUnreadable
        }
        do {
            return try fileSystem.readData(fileURL)
        } catch {
            throw ClipboardPayloadStagingError.stagedFileUnreadable
        }
    }

    func promote(to destinationURL: URL) throws {
        let canPromote = lock.withLock { () -> Bool in
            guard !isDiscarded, !isPromoted, !isTransferring else {
                return false
            }
            isTransferring = true
            return true
        }
        guard canPromote else {
            throw ClipboardPayloadStagingError.stagedFileUnreadable
        }
        do {
            try fileSystem.createDirectory(destinationURL.deletingLastPathComponent())
            try fileSystem.moveItem(fileURL, destinationURL)
        } catch {
            lock.withLock {
                isTransferring = false
            }
            throw ClipboardPayloadStager.stagingError(for: error)
        }
        lock.withLock {
            isTransferring = false
            isPromoted = true
        }
    }

    func discard() {
        let shouldRemove = lock.withLock { () -> Bool in
            guard !isDiscarded, !isPromoted, !isTransferring else {
                return false
            }
            isDiscarded = true
            return true
        }
        guard shouldRemove else {
            return
        }
        cleanupCoordinator.removeOrEnqueue(fileURL)
    }
}

final class ClipboardPayloadStagingReservation: @unchecked Sendable {
    let byteCount: Int
    fileprivate let id = UUID()

    private let gate: ClipboardPayloadStagingCapacityGate
    private let lock = NSLock()
    private enum State {
        case pending(CheckedContinuation<Void, Error>?)
        case active
        case released
    }
    private var state: State = .pending(nil)

    fileprivate init(byteCount: Int, gate: ClipboardPayloadStagingCapacityGate) {
        self.byteCount = byteCount
        self.gate = gate
    }

    deinit {
        release()
    }

    fileprivate func isOwned(
        by candidate: ClipboardPayloadStagingCapacityGate
    ) -> Bool {
        gate === candidate
    }

    fileprivate func waitUntilActive() async throws {
        try Task.checkCancellation()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let outcome = lock.withLock { () -> Bool? in
                    switch state {
                    case .active:
                        return true
                    case .pending:
                        state = .pending(continuation)
                        return nil
                    case .released:
                        return false
                    }
                }
                if let outcome {
                    if outcome {
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: CancellationError())
                    }
                }
            }
        } onCancel: {
            self.release()
        }
        try Task.checkCancellation()
    }

    fileprivate func activate() {
        let continuation = lock.withLock {
            () -> CheckedContinuation<Void, Error>? in
            guard case .pending(let continuation) = state else {
                return nil
            }
            state = .active
            return continuation
        }
        continuation?.resume()
    }

    func release() {
        let result = lock.withLock {
            () -> (Bool, CheckedContinuation<Void, Error>?) in
            switch state {
            case .pending(let continuation):
                state = .released
                return (true, continuation)
            case .active:
                state = .released
                return (true, nil)
            case .released:
                return (false, nil)
            }
        }
        guard result.0 else {
            return
        }
        gate.release(reservationID: id, byteCount: byteCount)
        result.1?.resume(throwing: CancellationError())
    }
}

fileprivate final class ClipboardPayloadStagingCapacityGate: @unchecked Sendable {
    private final class Waiter {
        let id: UUID
        let byteCount: Int
        weak var reservation: ClipboardPayloadStagingReservation?

        init(
            reservation: ClipboardPayloadStagingReservation,
            byteCount: Int
        ) {
            id = reservation.id
            self.byteCount = byteCount
            self.reservation = reservation
        }
    }

    private struct State {
        var activeReservationIDs: Set<UUID> = []
        var retainedByteCount = 0
        var rejectedTaskCount = 0
        var waiters: [Waiter] = []
    }

    private let maximumResidentTasks: Int
    private let maximumRetainedBytes: Int
    private let maximumWaitingCount: Int
    private let lock = NSLock()
    private var state = State()

    init(
        maximumResidentTasks: Int,
        maximumRetainedBytes: Int,
        maximumWaitingCount: Int
    ) {
        self.maximumResidentTasks = max(0, maximumResidentTasks)
        self.maximumRetainedBytes = max(0, maximumRetainedBytes)
        self.maximumWaitingCount = max(0, maximumWaitingCount)
    }

    func reserveImmediately(
        byteCount: Int
    ) throws -> ClipboardPayloadStagingReservation {
        let boundedByteCount = max(0, byteCount)
        guard maximumResidentTasks > 0 else {
            recordRejectedTask()
            throw ClipboardPayloadStagingError.residentTaskLimitExceeded
        }
        let reservation = ClipboardPayloadStagingReservation(
            byteCount: boundedByteCount,
            gate: self
        )
        let result = lock.withLock { () -> Result<Bool, ClipboardPayloadStagingError> in
            guard boundedByteCount <= maximumRetainedBytes - state.retainedByteCount else {
                state.rejectedTaskCount += 1
                return .failure(.retainedDataLimitExceeded)
            }
            let activatesImmediately =
                state.activeReservationIDs.count < maximumResidentTasks
                && state.waiters.isEmpty
            if !activatesImmediately,
               state.waiters.count >= maximumWaitingCount {
                state.rejectedTaskCount += 1
                return .failure(.retainedDataLimitExceeded)
            }
            state.retainedByteCount += boundedByteCount
            if activatesImmediately {
                state.activeReservationIDs.insert(reservation.id)
            } else {
                state.waiters.append(
                    Waiter(
                        reservation: reservation,
                        byteCount: boundedByteCount
                    )
                )
            }
            return .success(activatesImmediately)
        }
        switch result {
        case .success(let activatesImmediately):
            if activatesImmediately {
                reservation.activate()
            }
            return reservation
        case .failure(let error):
            reservation.release()
            throw error
        }
    }

    func acquire(byteCount: Int) async throws -> ClipboardPayloadStagingReservation {
        let reservation = try reserveImmediately(byteCount: byteCount)
        do {
            try await reservation.waitUntilActive()
            return reservation
        } catch {
            reservation.release()
            throw error
        }
    }

    private func recordRejectedTask() {
        lock.withLock {
            state.rejectedTaskCount += 1
        }
    }

    func release(reservationID: UUID, byteCount: Int) {
        let activatedReservations = lock.withLock {
            () -> [ClipboardPayloadStagingReservation] in
            let didRemoveActive =
                state.activeReservationIDs.remove(reservationID) != nil
            let waitingIndex = state.waiters.firstIndex {
                $0.id == reservationID
            }
            guard didRemoveActive || waitingIndex != nil else {
                return []
            }
            if let waitingIndex {
                state.waiters.remove(at: waitingIndex)
            }
            state.retainedByteCount = max(
                0,
                state.retainedByteCount - max(0, byteCount)
            )

            var activated: [ClipboardPayloadStagingReservation] = []
            while state.activeReservationIDs.count < maximumResidentTasks,
                  !state.waiters.isEmpty {
                let waiter = state.waiters.removeFirst()
                guard let reservation = waiter.reservation else {
                    state.retainedByteCount = max(
                        0,
                        state.retainedByteCount - waiter.byteCount
                    )
                    continue
                }
                state.activeReservationIDs.insert(waiter.id)
                activated.append(reservation)
            }
            return activated
        }
        activatedReservations.forEach {
            $0.activate()
        }
    }

    var diagnostics: ClipboardPayloadStagingDiagnostics {
        lock.withLock {
            ClipboardPayloadStagingDiagnostics(
                residentTaskCount: state.activeReservationIDs.count,
                retainedByteCount: state.retainedByteCount,
                rejectedTaskCount: state.rejectedTaskCount,
                waitingTaskCount: state.waiters.count
            )
        }
    }
}

actor ClipboardPayloadStager {
    typealias DirectoryProvider = @Sendable () throws -> URL

    private let capacityGate: ClipboardPayloadStagingCapacityGate
    private let directoryProvider: DirectoryProvider
    private let fileSystem: ClipboardPayloadStagingFileSystem
    private let cleanupCoordinator: ClipboardPayloadCleanupCoordinator
    private let maximumScavengedEntryCount: Int
    private var didRunStartupScavenger = false

    nonisolated var diagnostics: ClipboardPayloadStagingDiagnostics {
        capacityGate.diagnostics
    }

    init(
        maximumResidentTasks: Int = 4,
        maximumRetainedBytes: Int = 128 * 1_024 * 1_024,
        maximumWaitingCount: Int = 64,
        maximumScavengedEntryCount: Int = 512,
        directoryProvider: @escaping DirectoryProvider = {
            try ClipEaseStoragePaths.applicationSupportDirectory()
                .appendingPathComponent("PayloadStaging", isDirectory: true)
        },
        fileSystem: ClipboardPayloadStagingFileSystem = .live
    ) {
        capacityGate = ClipboardPayloadStagingCapacityGate(
            maximumResidentTasks: maximumResidentTasks,
            maximumRetainedBytes: maximumRetainedBytes,
            maximumWaitingCount: maximumWaitingCount
        )
        self.directoryProvider = directoryProvider
        self.fileSystem = fileSystem
        self.maximumScavengedEntryCount = max(0, maximumScavengedEntryCount)
        cleanupCoordinator = ClipboardPayloadCleanupCoordinator(fileSystem: fileSystem)
    }

    nonisolated func reserveImmediately(
        byteCount: Int
    ) throws -> ClipboardPayloadStagingReservation {
        try capacityGate.reserveImmediately(byteCount: byteCount)
    }

    func stage(
        _ source: ClipboardPayloadStagingSource
    ) async throws -> ClipboardStagedPayload {
        let reservation = try capacityGate.reserveImmediately(
            byteCount: source.data.count
        )
        return try await stage(source, reservation: reservation)
    }

    func stage(
        _ source: ClipboardPayloadStagingSource,
        reservation: ClipboardPayloadStagingReservation
    ) async throws -> ClipboardStagedPayload {
        guard reservation.isOwned(by: capacityGate),
              reservation.byteCount == source.data.count else {
            reservation.release()
            throw ClipboardPayloadStagingError.invalidReservation
        }
        defer { reservation.release() }
        try await reservation.waitUntilActive()

        let payloadID = UUID()
        let directoryURL: URL
        do {
            directoryURL = try directoryProvider()
            try await initializeAndScavenge(in: directoryURL)
        } catch {
            throw Self.stagingError(for: error)
        }
        let fileExtension = Self.sanitizedFileExtension(
            source.preferredFileExtension
        ) ?? source.contentKind.fileExtension
        let fileURL = directoryURL.appendingPathComponent(
            "\(payloadID.uuidString).\(fileExtension)",
            isDirectory: false
        )
        let fileSystem = self.fileSystem
        let operation = Task.detached(priority: .utility) {
            try Task.checkCancellation()
            try fileSystem.createDirectory(directoryURL)
            try Task.checkCancellation()
            try fileSystem.writeAtomically(source.data, fileURL)
            try Task.checkCancellation()
        }

        do {
            try await withTaskCancellationHandler {
                try await operation.value
            } onCancel: {
                operation.cancel()
            }
            return ClipboardStagedPayload(
                id: payloadID,
                fileURL: fileURL,
                byteCount: source.data.count,
                contentKind: source.contentKind,
                fileSystem: fileSystem,
                preferredFileExtension: fileExtension,
                cleanupCoordinator: cleanupCoordinator
            )
        } catch is CancellationError {
            cleanupCoordinator.removeOrEnqueue(fileURL)
            throw CancellationError()
        } catch {
            cleanupCoordinator.removeOrEnqueue(fileURL)
            throw Self.stagingError(for: error)
        }
    }

    func withWorkingSet<T: Sendable>(
        byteCount: Int,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        let reservation = try await capacityGate.acquire(byteCount: byteCount)
        defer { reservation.release() }
        return try await operation()
    }

    func drainCleanup(maximumAttempts: Int = 3) async {
        if !didRunStartupScavenger {
            try? await initializeAndScavenge()
        }
        await cleanupCoordinator.drain(maximumAttempts: maximumAttempts)
    }

    var pendingCleanupCount: Int {
        cleanupCoordinator.pendingCount
    }

    func initializeAndScavenge() async throws {
        let directoryURL: URL
        do {
            directoryURL = try directoryProvider()
            try await initializeAndScavenge(in: directoryURL)
        } catch {
            throw Self.stagingError(for: error)
        }
    }

    private func initializeAndScavenge(in directoryURL: URL) async throws {
        try runStartupScavengerIfNeeded(in: directoryURL)
        await cleanupCoordinator.drain(maximumAttempts: 3)
    }

    private func runStartupScavengerIfNeeded(in directoryURL: URL) throws {
        guard !didRunStartupScavenger else {
            return
        }
        try fileSystem.createDirectory(directoryURL)
        let staleURLs = try fileSystem.contentsOfDirectory(directoryURL)
            .lazy
            .filter {
                ClipboardPayloadStagingPathPolicy.isControlledStagingFileName(
                    $0.lastPathComponent
                )
            }
            .prefix(maximumScavengedEntryCount)
        cleanupCoordinator.enqueue(Array(staleURLs))
        didRunStartupScavenger = true
    }

    private nonisolated static func sanitizedFileExtension(
        _ candidate: String?
    ) -> String? {
        guard let candidate else {
            return nil
        }
        let normalized = candidate
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard ClipboardPayloadStagingPathPolicy.controlledFileExtensions
            .contains(normalized) else {
            return nil
        }
        return normalized
    }

    nonisolated static func stagingError(
        for error: Error
    ) -> ClipboardPayloadStagingError {
        if let stagingError = error as? ClipboardPayloadStagingError {
            return stagingError
        }
        if ClipboardFileSystemErrorClassifier.isDiskFull(error) {
            return .diskFull
        }
        return .atomicWriteFailed
    }
}
