import Foundation

struct ClipboardAttachmentCleanupRetryPolicy: Equatable, Sendable {
    static let enterpriseDefault = ClipboardAttachmentCleanupRetryPolicy(
        maximumEntryCount: 512,
        maximumCandidatesPerEntry: 256,
        maximumAttempts: 5,
        baseRetryDelay: 5,
        maximumRetryDelay: 300,
        maximumRetainedTerminalEntries: 64,
        maximumEntriesPerRun: 1,
        maximumLedgerBytes: 16 * 1_024 * 1_024
    )

    let maximumEntryCount: Int
    let maximumCandidatesPerEntry: Int
    let maximumAttempts: Int
    let baseRetryDelay: TimeInterval
    let maximumRetryDelay: TimeInterval
    let maximumRetainedTerminalEntries: Int
    let maximumEntriesPerRun: Int
    let maximumLedgerBytes: Int

    init(
        maximumEntryCount: Int,
        maximumCandidatesPerEntry: Int,
        maximumAttempts: Int,
        baseRetryDelay: TimeInterval,
        maximumRetryDelay: TimeInterval,
        maximumRetainedTerminalEntries: Int,
        maximumEntriesPerRun: Int = 1,
        maximumLedgerBytes: Int = 16 * 1_024 * 1_024
    ) {
        self.maximumEntryCount = max(1, maximumEntryCount)
        self.maximumCandidatesPerEntry = max(1, maximumCandidatesPerEntry)
        self.maximumAttempts = max(1, maximumAttempts)
        self.baseRetryDelay = max(0, baseRetryDelay)
        self.maximumRetryDelay = max(0, maximumRetryDelay)
        self.maximumRetainedTerminalEntries = max(
            0,
            min(maximumRetainedTerminalEntries, maximumEntryCount)
        )
        self.maximumEntriesPerRun = max(
            1,
            min(maximumEntriesPerRun, maximumEntryCount)
        )
        self.maximumLedgerBytes = max(4_096, maximumLedgerBytes)
    }

    func retryDelay(afterAttempt attempt: Int) -> TimeInterval {
        guard baseRetryDelay > 0 else {
            return 0
        }
        let exponent = max(0, min(attempt - 1, 20))
        return min(
            baseRetryDelay * pow(2, Double(exponent)),
            maximumRetryDelay
        )
    }
}

struct ClipboardAttachmentCleanupRetryStatus: Equatable, Sendable {
    static let empty = ClipboardAttachmentCleanupRetryStatus(
        pendingEntryCount: 0,
        terminalEntryCount: 0,
        totalTerminalFailureCount: 0,
        rejectedCandidateCount: 0,
        maximumAttemptCount: 0,
        retryDelay: nil
    )

    let pendingEntryCount: Int
    let terminalEntryCount: Int
    let totalTerminalFailureCount: Int
    let rejectedCandidateCount: Int
    let maximumAttemptCount: Int
    let retryDelay: TimeInterval?
}

enum ClipboardAttachmentCleanupRetryError: Error, Equatable, LocalizedError, Sendable {
    case ledgerUnavailable
    case ledgerCorrupted
    case ledgerTooLarge
    case invalidCandidateName
    case capacityExceeded(rejectedCandidateCount: Int)
    case persistenceFailed(code: Int)

    var errorDescription: String? {
        switch self {
        case .ledgerUnavailable:
            "Attachment cleanup retry storage is unavailable."
        case .ledgerCorrupted:
            "Attachment cleanup retry storage is corrupted."
        case .ledgerTooLarge:
            "Attachment cleanup retry storage exceeded its configured size limit."
        case .invalidCandidateName:
            "Attachment cleanup candidate name is invalid."
        case .capacityExceeded(let rejectedCandidateCount):
            "Attachment cleanup retry storage rejected \(rejectedCandidateCount) candidates at capacity."
        case .persistenceFailed(let code):
            "Attachment cleanup retry storage failed with system code \(code)."
        }
    }
}

struct ClipboardAttachmentCleanupRetryClaim: Sendable {
    let id: UUID
    let candidates: ClipboardAttachmentCleanup
}

struct ClipboardAttachmentCleanupRetryCompletion: Sendable {
    enum Outcome: Sendable {
        case succeeded
        case failed(errorCode: Int)
    }

    let id: UUID
    let outcome: Outcome
}

final class ClipboardAttachmentCleanupRetryLedger: @unchecked Sendable {
    private static let schemaVersion = 1
    private static let maximumAttachmentFileNameBytes = 255

    private enum EntryState: String, Codable {
        case pending
        case terminal
    }

    private struct Entry: Codable {
        let id: UUID
        let createdAt: Date
        var lastAttemptAt: Date?
        var nextAttemptAt: Date?
        var attemptCount: Int
        var state: EntryState
        var lastErrorCode: Int?
        let imageFileNames: [String]
        let richTextFileNames: [String]

        var candidateCount: Int {
            imageFileNames.count + richTextFileNames.count
        }

        var candidates: ClipboardAttachmentCleanup {
            ClipboardAttachmentCleanup(
                imageFileNames: Set(imageFileNames),
                richTextFileNames: Set(richTextFileNames)
            )
        }
    }

    private struct Document: Codable {
        let schemaVersion: Int
        var entries: [Entry]
        var totalTerminalFailureCount: Int
        var rejectedCandidateCount: Int

        static var empty: Document {
            Document(
                schemaVersion: ClipboardAttachmentCleanupRetryLedger.schemaVersion,
                entries: [],
                totalTerminalFailureCount: 0,
                rejectedCandidateCount: 0
            )
        }
    }

    private enum Candidate {
        case image(String)
        case richText(String)
    }

    private let ledgerURL: URL
    private let fileManager: FileManager
    private let policy: ClipboardAttachmentCleanupRetryPolicy
    private let lock = NSLock()
    private var cachedDocument: Document?
    private var claimedEntryIDs = Set<UUID>()

    init(
        ledgerURL: URL,
        fileManager: FileManager,
        policy: ClipboardAttachmentCleanupRetryPolicy
    ) {
        self.ledgerURL = ledgerURL
        self.fileManager = fileManager
        self.policy = policy
    }

    func enqueue(
        _ candidates: ClipboardAttachmentCleanup,
        now: Date
    ) throws {
        guard !candidates.isEmpty else {
            return
        }
        try validateNewCandidates(candidates)

        try lock.withLock {
            var document = try loadDocumentLocked()
            let existingImages = Set(document.entries.flatMap(\.imageFileNames))
            let existingRichTexts = Set(document.entries.flatMap(\.richTextFileNames))
            let newImages = candidates.imageFileNames
                .subtracting(existingImages)
                .sorted()
            let newRichTexts = candidates.richTextFileNames
                .subtracting(existingRichTexts)
                .sorted()
            let candidateChunks = chunks(
                imageFileNames: newImages,
                richTextFileNames: newRichTexts
            )
            guard !candidateChunks.isEmpty else {
                return
            }

            pruneTerminalEntriesForCapacity(
                document: &document,
                requiredEntryCount: candidateChunks.count
            )
            guard document.entries.count + candidateChunks.count <= policy.maximumEntryCount else {
                let rejectedCount = newImages.count + newRichTexts.count
                document.rejectedCandidateCount = addingWithoutOverflow(
                    document.rejectedCandidateCount,
                    rejectedCount
                )
                try persistLocked(document)
                throw ClipboardAttachmentCleanupRetryError.capacityExceeded(
                    rejectedCandidateCount: rejectedCount
                )
            }

            document.entries.append(contentsOf: candidateChunks.map { cleanup in
                Entry(
                    id: UUID(),
                    createdAt: now,
                    lastAttemptAt: nil,
                    nextAttemptAt: now,
                    attemptCount: 0,
                    state: .pending,
                    lastErrorCode: nil,
                    imageFileNames: cleanup.imageFileNames.sorted(),
                    richTextFileNames: cleanup.richTextFileNames.sorted()
                )
            })
            try persistLocked(document)
        }
    }

    func claimDueEntries(now: Date) throws -> [ClipboardAttachmentCleanupRetryClaim] {
        try lock.withLock {
            let document = try loadDocumentLocked()
            let dueEntries = Array(
                document.entries
                    .lazy
                    .filter { entry in
                        entry.state == .pending
                            && entry.nextAttemptAt.map { $0 <= now } != false
                            && !self.claimedEntryIDs.contains(entry.id)
                    }
                    .prefix(self.policy.maximumEntriesPerRun)
            )
            claimedEntryIDs.formUnion(dueEntries.map(\.id))
            return dueEntries.map { entry in
                ClipboardAttachmentCleanupRetryClaim(
                    id: entry.id,
                    candidates: entry.candidates
                )
            }
        }
    }

    func apply(
        _ completions: [ClipboardAttachmentCleanupRetryCompletion],
        now: Date
    ) throws {
        guard !completions.isEmpty else {
            return
        }
        let completionByID = Dictionary(
            uniqueKeysWithValues: completions.map { ($0.id, $0.outcome) }
        )

        try lock.withLock {
            defer {
                claimedEntryIDs.subtract(completionByID.keys)
            }
            var document = try loadDocumentLocked()
            var succeededIDs = Set<UUID>()

            for index in document.entries.indices {
                let id = document.entries[index].id
                guard let outcome = completionByID[id],
                      document.entries[index].state == .pending else {
                    continue
                }

                switch outcome {
                case .succeeded:
                    succeededIDs.insert(id)
                case .failed(let errorCode):
                    document.entries[index].attemptCount += 1
                    document.entries[index].lastAttemptAt = now
                    document.entries[index].lastErrorCode = errorCode
                    if document.entries[index].attemptCount >= policy.maximumAttempts {
                        document.entries[index].state = .terminal
                        document.entries[index].nextAttemptAt = nil
                        document.totalTerminalFailureCount = addingWithoutOverflow(
                            document.totalTerminalFailureCount,
                            1
                        )
                    } else {
                        let delay = policy.retryDelay(
                            afterAttempt: document.entries[index].attemptCount
                        )
                        document.entries[index].nextAttemptAt = now.addingTimeInterval(delay)
                    }
                }
            }

            document.entries.removeAll { succeededIDs.contains($0.id) }
            pruneRetainedTerminalEntries(document: &document)
            try persistLocked(document)
        }
    }

    func releaseClaims(_ claims: [ClipboardAttachmentCleanupRetryClaim]) {
        lock.withLock {
            claimedEntryIDs.subtract(claims.map(\.id))
        }
    }

    func status(now: Date) throws -> ClipboardAttachmentCleanupRetryStatus {
        try lock.withLock {
            status(for: try loadDocumentLocked(), now: now)
        }
    }

    private func status(
        for document: Document,
        now: Date
    ) -> ClipboardAttachmentCleanupRetryStatus {
        let pendingEntries = document.entries.filter { $0.state == .pending }
        let terminalEntries = document.entries.filter { $0.state == .terminal }
        let nextAttemptAt = pendingEntries.compactMap(\.nextAttemptAt).min()
        return ClipboardAttachmentCleanupRetryStatus(
            pendingEntryCount: pendingEntries.count,
            terminalEntryCount: terminalEntries.count,
            totalTerminalFailureCount: document.totalTerminalFailureCount,
            rejectedCandidateCount: document.rejectedCandidateCount,
            maximumAttemptCount: document.entries.map(\.attemptCount).max() ?? 0,
            retryDelay: nextAttemptAt.map {
                max(0, $0.timeIntervalSince(now))
            }
        )
    }

    private func chunks(
        imageFileNames: [String],
        richTextFileNames: [String]
    ) -> [ClipboardAttachmentCleanup] {
        var candidates = imageFileNames.map(Candidate.image)
        candidates.append(contentsOf: richTextFileNames.map(Candidate.richText))

        return stride(
            from: 0,
            to: candidates.count,
            by: policy.maximumCandidatesPerEntry
        ).map { startIndex in
            let endIndex = min(
                startIndex + policy.maximumCandidatesPerEntry,
                candidates.count
            )
            var images = Set<String>()
            var richTexts = Set<String>()
            for candidate in candidates[startIndex ..< endIndex] {
                switch candidate {
                case .image(let fileName):
                    images.insert(fileName)
                case .richText(let fileName):
                    richTexts.insert(fileName)
                }
            }
            return ClipboardAttachmentCleanup(
                imageFileNames: images,
                richTextFileNames: richTexts
            )
        }
    }

    private func pruneTerminalEntriesForCapacity(
        document: inout Document,
        requiredEntryCount: Int
    ) {
        while document.entries.count + requiredEntryCount > policy.maximumEntryCount,
              let terminalIndex = oldestTerminalEntryIndex(in: document) {
            document.entries.remove(at: terminalIndex)
        }
    }

    private func pruneRetainedTerminalEntries(document: inout Document) {
        while document.entries.lazy.filter({ $0.state == .terminal }).count
            > policy.maximumRetainedTerminalEntries,
              let terminalIndex = oldestTerminalEntryIndex(in: document) {
            document.entries.remove(at: terminalIndex)
        }
    }

    private func oldestTerminalEntryIndex(in document: Document) -> Int? {
        document.entries.indices
            .filter { document.entries[$0].state == .terminal }
            .min { lhs, rhs in
                let left = document.entries[lhs].lastAttemptAt
                    ?? document.entries[lhs].createdAt
                let right = document.entries[rhs].lastAttemptAt
                    ?? document.entries[rhs].createdAt
                return left < right
            }
    }

    private func loadDocumentLocked() throws -> Document {
        if let cachedDocument {
            return cachedDocument
        }
        guard fileManager.fileExists(atPath: ledgerURL.path) else {
            let document = Document.empty
            cachedDocument = document
            return document
        }

        do {
            let attributes = try fileManager.attributesOfItem(atPath: ledgerURL.path)
            let byteCount = (attributes[.size] as? NSNumber)?.intValue ?? 0
            guard byteCount <= policy.maximumLedgerBytes else {
                throw ClipboardAttachmentCleanupRetryError.ledgerTooLarge
            }
            let data = try Data(contentsOf: ledgerURL, options: [.mappedIfSafe])
            guard data.count <= policy.maximumLedgerBytes else {
                throw ClipboardAttachmentCleanupRetryError.ledgerTooLarge
            }
            let document = try JSONDecoder().decode(Document.self, from: data)
            try validateLoadedDocument(document)
            cachedDocument = document
            return document
        } catch let error as ClipboardAttachmentCleanupRetryError {
            throw error
        } catch {
            throw ClipboardAttachmentCleanupRetryError.ledgerCorrupted
        }
    }

    private func persistLocked(_ document: Document) throws {
        do {
            try fileManager.createDirectory(
                at: ledgerURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(document)
            guard data.count <= policy.maximumLedgerBytes else {
                throw ClipboardAttachmentCleanupRetryError.ledgerTooLarge
            }
            try data.write(to: ledgerURL, options: [.atomic])
            cachedDocument = document
        } catch let error as ClipboardAttachmentCleanupRetryError {
            throw error
        } catch {
            throw ClipboardAttachmentCleanupRetryError.persistenceFailed(
                code: (error as NSError).code
            )
        }
    }

    private func validateNewCandidates(
        _ candidates: ClipboardAttachmentCleanup
    ) throws {
        for fileName in candidates.imageFileNames.union(candidates.richTextFileNames) {
            guard Self.isValidAttachmentFileName(fileName) else {
                throw ClipboardAttachmentCleanupRetryError.invalidCandidateName
            }
        }
    }

    private func validateLoadedDocument(_ document: Document) throws {
        guard document.schemaVersion == Self.schemaVersion,
              document.entries.count <= policy.maximumEntryCount,
              document.totalTerminalFailureCount >= 0,
              document.rejectedCandidateCount >= 0 else {
            throw ClipboardAttachmentCleanupRetryError.ledgerCorrupted
        }

        var entryIDs = Set<UUID>()
        for entry in document.entries {
            guard entryIDs.insert(entry.id).inserted,
                  entry.candidateCount > 0,
                  entry.candidateCount <= policy.maximumCandidatesPerEntry,
                  entry.attemptCount >= 0,
                  entry.attemptCount <= policy.maximumAttempts,
                  Set(entry.imageFileNames).count == entry.imageFileNames.count,
                  Set(entry.richTextFileNames).count == entry.richTextFileNames.count,
                  entry.imageFileNames.allSatisfy(Self.isValidAttachmentFileName),
                  entry.richTextFileNames.allSatisfy(Self.isValidAttachmentFileName) else {
                throw ClipboardAttachmentCleanupRetryError.ledgerCorrupted
            }
            switch entry.state {
            case .pending:
                guard entry.attemptCount < policy.maximumAttempts,
                      entry.nextAttemptAt != nil else {
                    throw ClipboardAttachmentCleanupRetryError.ledgerCorrupted
                }
            case .terminal:
                guard entry.attemptCount == policy.maximumAttempts,
                      entry.nextAttemptAt == nil else {
                    throw ClipboardAttachmentCleanupRetryError.ledgerCorrupted
                }
            }
        }
    }

    private static func isValidAttachmentFileName(_ fileName: String) -> Bool {
        guard !fileName.isEmpty,
              fileName.utf8.count <= maximumAttachmentFileNameBytes else {
            return false
        }
        return (try? ClipEaseStoragePaths.validAttachmentBaseName(fileName)) != nil
    }

    private func addingWithoutOverflow(_ lhs: Int, _ rhs: Int) -> Int {
        let (sum, overflow) = lhs.addingReportingOverflow(rhs)
        return overflow ? Int.max : sum
    }
}
