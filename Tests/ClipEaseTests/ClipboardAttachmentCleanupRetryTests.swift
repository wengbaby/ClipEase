import Foundation
import Testing
@testable import ClipEase

@Test func postCommitAttachmentCleanupFailurePersistsAndReplaysOnNextWriterStartup() throws {
    let context = try CleanupRetryTestContext(
        policy: ClipboardAttachmentCleanupRetryPolicy(
            maximumEntryCount: 8,
            maximumCandidatesPerEntry: 8,
            maximumAttempts: 3,
            baseRetryDelay: 60,
            maximumRetryDelay: 60,
            maximumRetainedTerminalEntries: 2
        ),
        failuresBeforeSuccess: 1
    )
    defer { context.removeTemporaryFiles() }
    let fileName = "old-image.png"
    let fileURL = try context.createImageFile(named: fileName)
    let firstPersistence = context.makePersistence()
    let firstWriter = ClipboardHistorySaveWriter(
        persistence: firstPersistence,
        batchPolicy: ClipboardHistoryWriteBatchPolicy(
            maximumDelayMilliseconds: 60_000,
            maximumMutationCount: 50
        )
    )

    firstWriter.upsertAsync(
        ClipboardItem.text("replacement", sourceApp: .clipease),
        deleting: [],
        groups: [],
        attachmentCleanup: ClipboardAttachmentCleanup(imageFileNames: [fileName]),
        revision: 1
    )
    let drainResult = firstWriter.drain()

    #expect(drainResult.committedMutationCount == 1)
    #expect(context.repository.snapshot.items.map(\.text) == ["replacement"])
    #expect(FileManager.default.fileExists(atPath: fileURL.path))
    let pendingStatus = try firstPersistence.attachmentCleanupRetryStatusOrThrow()
    #expect(pendingStatus.pendingEntryCount == 1)
    #expect(pendingStatus.maximumAttemptCount == 1)
    #expect(pendingStatus.terminalEntryCount == 0)
    #expect(FileManager.default.fileExists(atPath: context.ledgerURL.path))

    let duplicateStatus = try firstPersistence.scheduleAttachmentCleanupOrThrow(
        ClipboardAttachmentCleanup(imageFileNames: [fileName])
    )
    #expect(duplicateStatus.pendingEntryCount == 1)
    #expect(duplicateStatus.maximumAttemptCount == 1)
    #expect(context.fileManager.removalAttemptCount == 1)

    context.clock.advance(by: 61)
    let restartedPersistence = context.makePersistence()
    let restartedWriter = ClipboardHistorySaveWriter(persistence: restartedPersistence)
    restartedWriter.flush()

    #expect(!FileManager.default.fileExists(atPath: fileURL.path))
    let replayedStatus = try restartedPersistence.attachmentCleanupRetryStatusOrThrow()
    #expect(replayedStatus.pendingEntryCount == 0)
    #expect(replayedStatus.terminalEntryCount == 0)
}

@Test func attachmentCleanupRetryStopsAtConfiguredAttemptLimitAndPersistsTerminalFailure() throws {
    let sensitiveFailureText = "SECRET-CLIPBOARD-CONTENT-MUST-NOT-BE-PERSISTED"
    let context = try CleanupRetryTestContext(
        policy: ClipboardAttachmentCleanupRetryPolicy(
            maximumEntryCount: 4,
            maximumCandidatesPerEntry: 4,
            maximumAttempts: 2,
            baseRetryDelay: 0,
            maximumRetryDelay: 0,
            maximumRetainedTerminalEntries: 2
        ),
        failuresBeforeSuccess: .max,
        failureDescription: sensitiveFailureText
    )
    defer { context.removeTemporaryFiles() }
    let fileName = "never-removed.png"
    _ = try context.createImageFile(named: fileName)
    let persistence = context.makePersistence()

    let firstRun = try persistence.scheduleAttachmentCleanupOrThrow(
        ClipboardAttachmentCleanup(imageFileNames: [fileName])
    )
    #expect(firstRun.pendingEntryCount == 1)
    #expect(firstRun.maximumAttemptCount == 1)

    let terminalStatus = try persistence.replayPendingAttachmentCleanupOrThrow()
    #expect(terminalStatus.pendingEntryCount == 0)
    #expect(terminalStatus.terminalEntryCount == 1)
    #expect(terminalStatus.totalTerminalFailureCount == 1)
    #expect(terminalStatus.maximumAttemptCount == 2)
    #expect(terminalStatus.retryDelay == nil)

    let restartedStatus = try context.makePersistence().attachmentCleanupRetryStatusOrThrow()
    #expect(restartedStatus.pendingEntryCount == 0)
    #expect(restartedStatus.terminalEntryCount == 1)
    #expect(restartedStatus.totalTerminalFailureCount == 1)

    let ledgerText = try String(contentsOf: context.ledgerURL, encoding: .utf8)
    #expect(!ledgerText.contains(sensitiveFailureText))
    #expect(!ledgerText.contains(context.rootURL.path))
}

@Test func attachmentCleanupRetryLedgerRejectsOverflowAndRecordsBoundedFailureMetadata() throws {
    let context = try CleanupRetryTestContext(
        policy: ClipboardAttachmentCleanupRetryPolicy(
            maximumEntryCount: 1,
            maximumCandidatesPerEntry: 1,
            maximumAttempts: 2,
            baseRetryDelay: 1,
            maximumRetryDelay: 1,
            maximumRetainedTerminalEntries: 1
        ),
        failuresBeforeSuccess: 0
    )
    defer { context.removeTemporaryFiles() }
    let persistence = context.makePersistence()

    #expect(throws: ClipboardAttachmentCleanupRetryError.self) {
        try persistence.scheduleAttachmentCleanupOrThrow(
            ClipboardAttachmentCleanup(
                imageFileNames: ["one.png", "two.png"]
            )
        )
    }

    let status = try persistence.attachmentCleanupRetryStatusOrThrow()
    #expect(status.pendingEntryCount == 0)
    #expect(status.terminalEntryCount == 0)
    #expect(status.rejectedCandidateCount == 2)

    let ledgerData = try Data(contentsOf: context.ledgerURL)
    #expect(ledgerData.count < 16_384)
}

@Test func attachmentCleanupRetryUsesCappedExponentialBackoff() {
    let policy = ClipboardAttachmentCleanupRetryPolicy(
        maximumEntryCount: 4,
        maximumCandidatesPerEntry: 2,
        maximumAttempts: 5,
        baseRetryDelay: 2,
        maximumRetryDelay: 5,
        maximumRetainedTerminalEntries: 1
    )

    #expect(policy.retryDelay(afterAttempt: 1) == 2)
    #expect(policy.retryDelay(afterAttempt: 2) == 4)
    #expect(policy.retryDelay(afterAttempt: 3) == 5)
    #expect(policy.retryDelay(afterAttempt: 30) == 5)
}

@Test func attachmentCleanupRetryProcessesOnlyOneBoundedLedgerEntryPerWriterTurn() throws {
    let context = try CleanupRetryTestContext(
        policy: ClipboardAttachmentCleanupRetryPolicy(
            maximumEntryCount: 4,
            maximumCandidatesPerEntry: 1,
            maximumAttempts: 2,
            baseRetryDelay: 1,
            maximumRetryDelay: 1,
            maximumRetainedTerminalEntries: 1,
            maximumEntriesPerRun: 1
        ),
        failuresBeforeSuccess: 0
    )
    defer { context.removeTemporaryFiles() }
    for fileName in ["one.png", "two.png", "three.png"] {
        _ = try context.createImageFile(named: fileName)
    }
    let persistence = context.makePersistence()

    let firstTurn = try persistence.scheduleAttachmentCleanupOrThrow(
        ClipboardAttachmentCleanup(
            imageFileNames: ["one.png", "two.png", "three.png"]
        )
    )
    #expect(firstTurn.pendingEntryCount == 2)
    #expect(firstTurn.retryDelay == 0)

    let secondTurn = try persistence.replayPendingAttachmentCleanupOrThrow()
    #expect(secondTurn.pendingEntryCount == 1)
    let thirdTurn = try persistence.replayPendingAttachmentCleanupOrThrow()
    #expect(thirdTurn.pendingEntryCount == 0)
}

@Test func attachmentCleanupRetryRetainsOnlyBoundedTerminalDetails() throws {
    let context = try CleanupRetryTestContext(
        policy: ClipboardAttachmentCleanupRetryPolicy(
            maximumEntryCount: 2,
            maximumCandidatesPerEntry: 1,
            maximumAttempts: 1,
            baseRetryDelay: 0,
            maximumRetryDelay: 0,
            maximumRetainedTerminalEntries: 1
        ),
        failuresBeforeSuccess: .max
    )
    defer { context.removeTemporaryFiles() }
    let persistence = context.makePersistence()
    _ = try context.createImageFile(named: "first.png")
    _ = try context.createImageFile(named: "second.png")

    _ = try persistence.scheduleAttachmentCleanupOrThrow(
        ClipboardAttachmentCleanup(imageFileNames: ["first.png"])
    )
    let status = try persistence.scheduleAttachmentCleanupOrThrow(
        ClipboardAttachmentCleanup(imageFileNames: ["second.png"])
    )

    #expect(status.pendingEntryCount == 0)
    #expect(status.terminalEntryCount == 1)
    #expect(status.totalTerminalFailureCount == 2)
    #expect(status.maximumAttemptCount == 1)
}

@Test func attachmentCleanupRetryRejectsInvalidNamesWithoutWritingPaths() throws {
    let context = try CleanupRetryTestContext(
        policy: ClipboardAttachmentCleanupRetryPolicy.enterpriseDefault,
        failuresBeforeSuccess: 0
    )
    defer { context.removeTemporaryFiles() }

    #expect(throws: ClipboardAttachmentCleanupRetryError.invalidCandidateName) {
        try context.makePersistence().scheduleAttachmentCleanupOrThrow(
            ClipboardAttachmentCleanup(imageFileNames: ["../outside.png"])
        )
    }
    #expect(!FileManager.default.fileExists(atPath: context.ledgerURL.path))
}

@Test func attachmentCleanupRetryFailsClosedForCorruptedOrOversizedLedger() throws {
    let corruptedContext = try CleanupRetryTestContext(
        policy: ClipboardAttachmentCleanupRetryPolicy.enterpriseDefault,
        failuresBeforeSuccess: 0
    )
    defer { corruptedContext.removeTemporaryFiles() }
    try Data("{not-json".utf8).write(
        to: corruptedContext.ledgerURL,
        options: .atomic
    )

    #expect(throws: ClipboardAttachmentCleanupRetryError.ledgerCorrupted) {
        try corruptedContext.makePersistence().attachmentCleanupRetryStatusOrThrow()
    }

    let oversizedContext = try CleanupRetryTestContext(
        policy: ClipboardAttachmentCleanupRetryPolicy(
            maximumEntryCount: 4,
            maximumCandidatesPerEntry: 4,
            maximumAttempts: 2,
            baseRetryDelay: 1,
            maximumRetryDelay: 1,
            maximumRetainedTerminalEntries: 1,
            maximumLedgerBytes: 4_096
        ),
        failuresBeforeSuccess: 0
    )
    defer { oversizedContext.removeTemporaryFiles() }
    try Data(repeating: 0xAB, count: 4_097).write(
        to: oversizedContext.ledgerURL,
        options: .atomic
    )

    #expect(throws: ClipboardAttachmentCleanupRetryError.ledgerTooLarge) {
        try oversizedContext.makePersistence().attachmentCleanupRetryStatusOrThrow()
    }
}

private final class CleanupRetryTestContext: @unchecked Sendable {
    let rootURL: URL
    let ledgerURL: URL
    let fileManager: CleanupRetryTestFileManager
    let repository = CleanupRetryTestRepository()
    let clock = CleanupRetryTestClock(
        Date(timeIntervalSinceReferenceDate: 800_000_000)
    )
    let policy: ClipboardAttachmentCleanupRetryPolicy

    init(
        policy: ClipboardAttachmentCleanupRetryPolicy,
        failuresBeforeSuccess: Int,
        failureDescription: String = "synthetic remove failure"
    ) throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "ClipEase-Cleanup-Retry-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true
        )
        self.rootURL = rootURL
        self.ledgerURL = rootURL.appendingPathComponent(
            "attachment-cleanup-retry-v1.json",
            isDirectory: false
        )
        self.fileManager = CleanupRetryTestFileManager(
            rootURL: rootURL,
            failuresBeforeSuccess: failuresBeforeSuccess,
            failureDescription: failureDescription
        )
        self.policy = policy
    }

    func makePersistence() -> ClipboardHistoryPersistence {
        ClipboardHistoryPersistence(
            fileManager: fileManager,
            repository: repository,
            attachmentCleanupRetryPolicy: policy,
            attachmentCleanupRetryLedgerURL: ledgerURL,
            attachmentCleanupRetryNow: { [clock] in clock.now }
        )
    }

    func createImageFile(named fileName: String) throws -> URL {
        let fileURL = try ClipEaseStoragePaths.imageFileURL(
            fileName: fileName,
            fileManager: fileManager
        )
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data([0xCA, 0xFE]).write(to: fileURL, options: .atomic)
        return fileURL
    }

    func removeTemporaryFiles() {
        try? FileManager.default.removeItem(at: rootURL)
    }
}

private final class CleanupRetryTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var storedNow: Date

    init(_ now: Date) {
        storedNow = now
    }

    var now: Date {
        lock.withLock { storedNow }
    }

    func advance(by interval: TimeInterval) {
        lock.withLock {
            storedNow = storedNow.addingTimeInterval(interval)
        }
    }
}

private final class CleanupRetryTestFileManager: FileManager, @unchecked Sendable {
    private let rootURL: URL
    private let lock = NSLock()
    private var remainingRemovalFailures: Int
    private var storedRemovalAttemptCount = 0
    private let failureDescription: String

    init(
        rootURL: URL,
        failuresBeforeSuccess: Int,
        failureDescription: String
    ) {
        self.rootURL = rootURL
        self.remainingRemovalFailures = failuresBeforeSuccess
        self.failureDescription = failureDescription
        super.init()
    }

    var removalAttemptCount: Int {
        lock.withLock { storedRemovalAttemptCount }
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

    override func removeItem(at URL: URL) throws {
        let shouldFail = lock.withLock { () -> Bool in
            storedRemovalAttemptCount += 1
            guard remainingRemovalFailures > 0 else {
                return false
            }
            remainingRemovalFailures -= 1
            return true
        }
        if shouldFail {
            throw NSError(
                domain: "ClipEaseCleanupRetryTests",
                code: 73,
                userInfo: [NSLocalizedDescriptionKey: failureDescription]
            )
        }
        try super.removeItem(at: URL)
    }
}

private final class CleanupRetryTestRepository: ClipboardHistoryRepository, @unchecked Sendable {
    private let lock = NSLock()
    private var storedSnapshot = ClipboardHistorySnapshot(items: [], groups: [])

    var snapshot: ClipboardHistorySnapshot {
        lock.withLock { storedSnapshot }
    }

    func loadSnapshot() throws -> ClipboardHistorySnapshot {
        snapshot
    }

    func saveSnapshot(_ snapshot: ClipboardHistorySnapshot) throws {
        lock.withLock {
            storedSnapshot = snapshot
        }
    }
}
