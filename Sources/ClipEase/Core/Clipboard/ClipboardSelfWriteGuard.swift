import CryptoKit
import Foundation

enum ClipboardSelfWritePayload: Equatable, Sendable {
    case text(String)
    case richText(String)
    case imageHash(String)
    case files([URL])
}

struct ClipboardSelfWriteTokenSnapshot: Equatable, Sendable {
    let changeCount: Int
    let fingerprintByteCount: Int
}

struct ClipboardPendingImageLifetimeSnapshot: Equatable, Sendable {
    let liveCanonicalizerTaskCount: Int
    let activePayloadCount: Int
    let queuedPayloadCount: Int
    let queuedPayloadByteCount: Int
    let activePayloadByteCount: Int
    let retainedPayloadByteCount: Int

    init(
        liveCanonicalizerTaskCount: Int,
        activePayloadCount: Int,
        queuedPayloadCount: Int,
        queuedPayloadByteCount: Int,
        activePayloadByteCount: Int = 0,
        retainedPayloadByteCount: Int = 0
    ) {
        self.liveCanonicalizerTaskCount = liveCanonicalizerTaskCount
        self.activePayloadCount = activePayloadCount
        self.queuedPayloadCount = queuedPayloadCount
        self.queuedPayloadByteCount = queuedPayloadByteCount
        self.activePayloadByteCount = activePayloadByteCount
        self.retainedPayloadByteCount = retainedPayloadByteCount
    }
}

final class ClipboardSelfWriteGuard: @unchecked Sendable {
    typealias ImageFingerprintOperation = @Sendable (ClipboardEncodedImagePayload) -> String?

    private struct PayloadIdentity: Equatable, Sendable {
        enum Kind: UInt8, Sendable {
            case text
            case richText
            case image
            case files
        }

        let kind: Kind
        let fingerprint: Data
    }

    private final class PendingImageWork: @unchecked Sendable {
        let id: UUID

        private let lock = NSLock()
        private var result: PayloadIdentity??
        private var waiters: [CheckedContinuation<PayloadIdentity?, Never>] = []

        init(id: UUID) {
            self.id = id
        }

        func value() async -> PayloadIdentity? {
            await withCheckedContinuation { continuation in
                let immediateResult = lock.withLock { () -> PayloadIdentity?? in
                    if let result {
                        return .some(result)
                    }
                    waiters.append(continuation)
                    return nil
                }
                if let immediateResult {
                    continuation.resume(returning: immediateResult)
                }
            }
        }

        func complete(returning result: PayloadIdentity?) {
            let waiters = lock.withLock { () -> [CheckedContinuation<PayloadIdentity?, Never>] in
                guard self.result == nil else {
                    return []
                }
                self.result = .some(result)
                let waiters = self.waiters
                self.waiters.removeAll(keepingCapacity: false)
                return waiters
            }
            waiters.forEach { $0.resume(returning: result) }
        }
    }

    private final class ImageCanonicalizationPump: @unchecked Sendable {
        private struct Job {
            let payload: ClipboardEncodedImagePayload
            let work: PendingImageWork
            let resolve: @Sendable (PayloadIdentity?) -> Void
        }

        private let lock = NSLock()
        private let operation: ImageFingerprintOperation
        private let maximumRetainedPayloadBytes: Int
        private var queue: [Job] = []
        private var queuedPayloadByteCount = 0
        private var workerID: UUID?
        private var workerTask: Task<Void, Never>?
        private var activeJobID: UUID?
        private var activePayloadByteCount = 0
        private var isShutdown = false

        init(
            maximumRetainedPayloadBytes: Int,
            operation: @escaping ImageFingerprintOperation
        ) {
            self.maximumRetainedPayloadBytes = max(0, maximumRetainedPayloadBytes)
            self.operation = operation
        }

        func enqueue(
            payload: ClipboardEncodedImagePayload,
            work: PendingImageWork,
            resolve: @escaping @Sendable (PayloadIdentity?) -> Void
        ) -> Bool {
            lock.withLock {
                guard !isShutdown else {
                    return false
                }
                let retainedPayloadBytes = activePayloadByteCount
                    .addingReportingOverflow(queuedPayloadByteCount)
                let proposedPayloadBytes = retainedPayloadBytes.partialValue
                    .addingReportingOverflow(payload.data.count)
                guard !retainedPayloadBytes.overflow,
                      !proposedPayloadBytes.overflow,
                      proposedPayloadBytes.partialValue <= maximumRetainedPayloadBytes else {
                    return false
                }
                queue.append(Job(
                    payload: payload,
                    work: work,
                    resolve: resolve
                ))
                queuedPayloadByteCount += payload.data.count
                startWorkerIfNeededLocked()
                return true
            }
        }

        func retire(workIDs: Set<UUID>) {
            guard !workIDs.isEmpty else {
                return
            }
            lock.withLock {
                let retiredPayloadByteCount = queue.reduce(into: 0) { result, job in
                    if workIDs.contains(job.work.id) {
                        result += job.payload.data.count
                    }
                }
                queue.removeAll { workIDs.contains($0.work.id) }
                queuedPayloadByteCount = max(
                    0,
                    queuedPayloadByteCount - retiredPayloadByteCount
                )
                if let activeJobID,
                   workIDs.contains(activeJobID) {
                    workerTask?.cancel()
                }
            }
        }

        func shutdown() {
            lock.withLock {
                isShutdown = true
                queue.removeAll(keepingCapacity: false)
                queuedPayloadByteCount = 0
                workerTask?.cancel()
            }
        }

        func lifetimeSnapshot() -> ClipboardPendingImageLifetimeSnapshot {
            lock.withLock {
                ClipboardPendingImageLifetimeSnapshot(
                    liveCanonicalizerTaskCount: workerTask == nil ? 0 : 1,
                    activePayloadCount: activeJobID == nil ? 0 : 1,
                    queuedPayloadCount: queue.count,
                    queuedPayloadByteCount: queuedPayloadByteCount,
                    activePayloadByteCount: activePayloadByteCount,
                    retainedPayloadByteCount: activePayloadByteCount
                        + queuedPayloadByteCount
                )
            }
        }

        func waitUntilQuiescent() async {
            while let task = lock.withLock({ workerTask }) {
                await task.value
            }
        }

        private func startWorkerIfNeededLocked() {
            guard !isShutdown,
                  workerTask == nil,
                  !queue.isEmpty else {
                return
            }
            let workerID = UUID()
            self.workerID = workerID
            workerTask = Task.detached(priority: .utility) { [weak self] in
                self?.runWorker(id: workerID)
            }
        }

        private func runWorker(id: UUID) {
            while let job = nextJob(workerID: id) {
                let identity: PayloadIdentity?
                if Task.isCancelled {
                    identity = nil
                } else {
                    identity = operation(job.payload).flatMap(
                        ClipboardSelfWriteGuard.canonicalImageIdentity
                    )
                }

                let shouldContinue = finish(
                    job,
                    workerID: id,
                    identity: identity,
                    wasCancelled: Task.isCancelled
                )
                guard shouldContinue else {
                    break
                }
            }
            workerDidExit(id: id)
        }

        private func nextJob(workerID: UUID) -> Job? {
            lock.withLock {
                guard self.workerID == workerID,
                      !isShutdown,
                      !Task.isCancelled,
                      activeJobID == nil,
                      !queue.isEmpty else {
                    return nil
                }
                let job = queue.removeFirst()
                queuedPayloadByteCount = max(
                    0,
                    queuedPayloadByteCount - job.payload.data.count
                )
                activeJobID = job.work.id
                activePayloadByteCount = job.payload.data.count
                return job
            }
        }

        private func finish(
            _ job: Job,
            workerID: UUID,
            identity: PayloadIdentity?,
            wasCancelled: Bool
        ) -> Bool {
            let result = lock.withLock { () -> (shouldPublish: Bool, shouldContinue: Bool) in
                guard self.workerID == workerID,
                      activeJobID == job.work.id else {
                    return (false, false)
                }
                activeJobID = nil
                activePayloadByteCount = 0
                let shouldPublish = !isShutdown && !wasCancelled
                return (shouldPublish, shouldPublish)
            }

            if result.shouldPublish {
                job.resolve(identity)
                job.work.complete(returning: identity)
            } else {
                job.work.complete(returning: nil)
            }
            return result.shouldContinue
        }

        private func workerDidExit(id: UUID) {
            lock.withLock {
                guard workerID == id else {
                    return
                }
                workerID = nil
                workerTask = nil
                activeJobID = nil
                activePayloadByteCount = 0
                startWorkerIfNeededLocked()
            }
        }
    }

    private enum TokenState {
        case resolved(PayloadIdentity)
        case pendingImage(PendingImageWork)
    }

    private final class ImageConsumeClaim: @unchecked Sendable {
        private enum State {
            case waiting
            case cancelled
            case claimed
        }

        private let lock = NSLock()
        private var state = State.waiting

        func cancel() {
            lock.withLock {
                guard case .waiting = state else {
                    return
                }
                state = .cancelled
            }
        }

        func perform<Result>(_ operation: () -> Result) -> Result? {
            lock.withLock {
                if Task.isCancelled,
                   case .waiting = state {
                    state = .cancelled
                }
                guard case .waiting = state else {
                    return nil
                }
                state = .claimed
                return operation()
            }
        }
    }

    private struct Token {
        let id: UUID
        let changeCount: Int
        var state: TokenState
        let insertedAt: Date
        let insertionOrder: UInt64

        var fingerprintByteCount: Int {
            switch state {
            case .resolved(let identity):
                return identity.fingerprint.count
            case .pendingImage:
                return 0
            }
        }
    }

    private enum ImageConsumePlan {
        case resolved(tokenID: UUID)
        case pending(tokenID: UUID, work: PendingImageWork)
        case missing
    }

    private static let defaultTTL: TimeInterval = 10
    private static let defaultCapacity = 64
    private static let sha256DigestByteCount = 32

    private let lock = NSLock()
    private let now: @Sendable () -> Date
    private let ttl: TimeInterval
    private let capacity: Int
    private let imageCanonicalizationPump: ImageCanonicalizationPump
    private var tokens: [Token] = []
    private var nextInsertionOrder: UInt64 = 0

    init(
        now: @escaping @Sendable () -> Date = Date.init,
        ttl: TimeInterval = ClipboardSelfWriteGuard.defaultTTL,
        capacity: Int = ClipboardSelfWriteGuard.defaultCapacity,
        maximumPendingImagePayloadBytes: Int = ClipboardImageFingerprintLimits()
            .maximumEncodedBytes,
        imageFingerprint: @escaping ImageFingerprintOperation = {
            try? ClipboardImageFingerprint.encoded($0)
        }
    ) {
        self.now = now
        self.ttl = max(0, ttl)
        self.capacity = max(1, capacity)
        imageCanonicalizationPump = ImageCanonicalizationPump(
            maximumRetainedPayloadBytes: maximumPendingImagePayloadBytes,
            operation: imageFingerprint
        )
    }

    deinit {
        let retiredWorks = lock.withLock {
            let retiredWorks = removeTokens { _ in true }
            imageCanonicalizationPump.shutdown()
            return retiredWorks
        }
        completeRetiredWorks(retiredWorks)
    }

    func register(changeCount: Int, payload: ClipboardSelfWritePayload) {
        guard let identity = Self.identity(for: payload) else {
            return
        }
        let timestamp = now()
        let retiredWorks = lock.withLock {
            var retiredWorks = removeExpiredTokens(at: timestamp)
            nextInsertionOrder &+= 1
            tokens.append(Token(
                id: UUID(),
                changeCount: changeCount,
                state: .resolved(identity),
                insertedAt: timestamp,
                insertionOrder: nextInsertionOrder
            ))
            retiredWorks.append(contentsOf: evictTokensBeyondCapacity())
            return retiredWorks
        }
        completeRetiredWorks(retiredWorks)
    }

    func registerPendingImage(
        changeCount: Int,
        payload: ClipboardEncodedImagePayload
    ) {
        let timestamp = now()
        let tokenID = UUID()
        let work = PendingImageWork(id: tokenID)
        let retiredWorks = lock.withLock {
            var retiredWorks = removeExpiredTokens(at: timestamp)
            nextInsertionOrder &+= 1
            tokens.append(Token(
                id: tokenID,
                changeCount: changeCount,
                state: .pendingImage(work),
                insertedAt: timestamp,
                insertionOrder: nextInsertionOrder
            ))
            let didEnqueue = imageCanonicalizationPump.enqueue(
                payload: payload,
                work: work,
                resolve: { [weak self] identity in
                    self?.resolvePendingImage(
                        tokenID: tokenID,
                        changeCount: changeCount,
                        identity: identity
                    )
                }
            )
            if didEnqueue {
                retiredWorks.append(contentsOf: evictTokensBeyondCapacity())
            } else {
                retiredWorks.append(contentsOf: removeTokens { $0.id == tokenID })
            }
            return retiredWorks
        }
        completeRetiredWorks(retiredWorks)
    }

    @discardableResult
    func consume(changeCount: Int, payload: ClipboardSelfWritePayload?) -> Bool {
        let identity = payload.flatMap(Self.identity(for:))
        let timestamp = now()
        let result = lock.withLock { () -> (matched: Bool, retiredWorks: [PendingImageWork]) in
            var retiredWorks = removeExpiredTokens(at: timestamp)
            let matched = identity.map { identity in
                tokens.contains { token in
                    guard token.changeCount == changeCount,
                          case .resolved(let tokenIdentity) = token.state else {
                        return false
                    }
                    return tokenIdentity == identity
                }
            } ?? false
            retiredWorks.append(contentsOf: removeTokens { $0.changeCount <= changeCount })
            return (matched, retiredWorks)
        }
        completeRetiredWorks(result.retiredWorks)
        return result.matched
    }

    @discardableResult
    func consumeImage(changeCount: Int, fingerprint: String?) async -> Bool {
        guard !Task.isCancelled else {
            return false
        }
        guard let expectedIdentity = fingerprint.flatMap(Self.canonicalImageIdentity) else {
            let timestamp = now()
            let result = lock.withLock {
                var retiredWorks = removeExpiredTokens(at: timestamp)
                let matched = tokens.contains { token in
                    guard token.changeCount == changeCount else {
                        return false
                    }
                    switch token.state {
                    case .resolved(let identity):
                        return identity.kind == .image
                    case .pendingImage:
                        return true
                    }
                }
                retiredWorks.append(contentsOf: removeTokens { $0.changeCount <= changeCount })
                return (matched, retiredWorks)
            }
            completeRetiredWorks(result.1)
            return result.0
        }

        let claim = ImageConsumeClaim()
        return await withTaskCancellationHandler {
            let timestamp = now()
            let preflight = lock.withLock { () -> (plan: ImageConsumePlan, retiredWorks: [PendingImageWork]) in
                var retiredWorks = removeExpiredTokens(at: timestamp)
                retiredWorks.append(contentsOf: removeTokens { $0.changeCount < changeCount })

                guard let token = tokens.first(where: { token in
                    guard token.changeCount == changeCount else {
                        return false
                    }
                    switch token.state {
                    case .resolved(let identity):
                        return identity.kind == .image
                    case .pendingImage:
                        return true
                    }
                }) else {
                    return (.missing, retiredWorks)
                }

                switch token.state {
                case .resolved:
                    return (.resolved(tokenID: token.id), retiredWorks)
                case .pendingImage(let work):
                    return (
                        .pending(tokenID: token.id, work: work),
                        retiredWorks
                    )
                }
            }
            completeRetiredWorks(preflight.retiredWorks)

            switch preflight.plan {
            case .resolved(let tokenID):
                return claimImageToken(
                    claim,
                    changeCount: changeCount,
                    tokenID: tokenID,
                    expectedIdentity: expectedIdentity,
                    pendingWork: nil,
                    completedWorkIdentity: nil
                )
            case .pending(let tokenID, let work):
                let resolvedIdentity = await work.value()
                return claimImageToken(
                    claim,
                    changeCount: changeCount,
                    tokenID: tokenID,
                    expectedIdentity: expectedIdentity,
                    pendingWork: work,
                    completedWorkIdentity: resolvedIdentity
                )
            case .missing:
                return claimImageToken(
                    claim,
                    changeCount: changeCount,
                    tokenID: nil,
                    expectedIdentity: expectedIdentity,
                    pendingWork: nil,
                    completedWorkIdentity: nil
                )
            }
        } onCancel: {
            claim.cancel()
        }
    }

    private func claimImageToken(
        _ claim: ImageConsumeClaim,
        changeCount: Int,
        tokenID: UUID?,
        expectedIdentity: PayloadIdentity,
        pendingWork: PendingImageWork?,
        completedWorkIdentity: PayloadIdentity?
    ) -> Bool {
        let timestamp = now()
        guard let result = claim.perform({
            lock.withLock { () -> (matched: Bool, retiredWorks: [PendingImageWork]) in
                var retiredWorks = removeExpiredTokens(at: timestamp)
                let matched = tokenID.flatMap { tokenID in
                    tokens.first(where: {
                        $0.id == tokenID && $0.changeCount == changeCount
                    })
                }.map { token in
                    let currentIdentity: PayloadIdentity?
                    switch token.state {
                    case .resolved(let identity):
                        currentIdentity = identity
                    case .pendingImage(let currentWork) where currentWork === pendingWork:
                        currentIdentity = completedWorkIdentity
                    case .pendingImage:
                        currentIdentity = nil
                    }
                    let completedWorkMatches = pendingWork == nil
                        || completedWorkIdentity == expectedIdentity
                    return completedWorkMatches && currentIdentity == expectedIdentity
                } ?? false
                retiredWorks.append(contentsOf: removeTokens { $0.changeCount <= changeCount })
                return (matched, retiredWorks)
            }
        }) else {
            return false
        }
        completeRetiredWorks(result.retiredWorks)
        return result.matched
    }

    func removeAll() {
        let retiredWorks = lock.withLock {
            removeTokens { _ in true }
        }
        completeRetiredWorks(retiredWorks)
    }

    func snapshot() -> [ClipboardSelfWriteTokenSnapshot] {
        let timestamp = now()
        let result = lock.withLock { () -> (snapshots: [ClipboardSelfWriteTokenSnapshot], retiredWorks: [PendingImageWork]) in
            let retiredWorks = removeExpiredTokens(at: timestamp)
            let snapshots = tokens
                .sorted { lhs, rhs in lhs.insertionOrder < rhs.insertionOrder }
                .map { token in
                    ClipboardSelfWriteTokenSnapshot(
                        changeCount: token.changeCount,
                        fingerprintByteCount: token.fingerprintByteCount
                    )
                }
            return (snapshots, retiredWorks)
        }
        completeRetiredWorks(result.retiredWorks)
        return result.snapshots
    }

    func pendingImageLifetimeSnapshot() -> ClipboardPendingImageLifetimeSnapshot {
        imageCanonicalizationPump.lifetimeSnapshot()
    }

    func waitForPendingImageCanonicalizationToQuiesce() async {
        await imageCanonicalizationPump.waitUntilQuiescent()
    }

    private func resolvePendingImage(
        tokenID: UUID,
        changeCount: Int,
        identity: PayloadIdentity?
    ) {
        let timestamp = now()
        let retiredWorks = lock.withLock {
            var retiredWorks = removeExpiredTokens(at: timestamp)
            guard let tokenIndex = tokens.firstIndex(where: {
                $0.id == tokenID && $0.changeCount == changeCount
            }), case .pendingImage(let work) = tokens[tokenIndex].state,
            work.id == tokenID else {
                return retiredWorks
            }

            if let identity {
                tokens[tokenIndex].state = .resolved(identity)
            } else {
                retiredWorks.append(contentsOf: removeTokens { $0.id == tokenID })
            }
            return retiredWorks
        }
        completeRetiredWorks(retiredWorks)
    }

    private func removeExpiredTokens(at timestamp: Date) -> [PendingImageWork] {
        removeTokens { timestamp.timeIntervalSince($0.insertedAt) >= ttl }
    }

    private func evictTokensBeyondCapacity() -> [PendingImageWork] {
        let excessCount = tokens.count - capacity
        guard excessCount > 0 else {
            return []
        }
        let evictedIDs = Set(
            tokens
                .sorted { lhs, rhs in lhs.insertionOrder < rhs.insertionOrder }
                .prefix(excessCount)
                .map(\.id)
        )
        return removeTokens { evictedIDs.contains($0.id) }
    }

    private func removeTokens(
        where shouldRemove: (Token) -> Bool
    ) -> [PendingImageWork] {
        var pendingWorks: [PendingImageWork] = []
        tokens.removeAll { token in
            guard shouldRemove(token) else {
                return false
            }
            if case .pendingImage(let work) = token.state {
                pendingWorks.append(work)
            }
            return true
        }
        imageCanonicalizationPump.retire(workIDs: Set(pendingWorks.map(\.id)))
        return pendingWorks
    }

    private func completeRetiredWorks(_ works: [PendingImageWork]) {
        works.forEach { $0.complete(returning: nil) }
    }

    private static func identity(for payload: ClipboardSelfWritePayload) -> PayloadIdentity? {
        switch payload {
        case .text(let text):
            return textIdentity(text, kind: .text)
        case .richText(let text):
            return textIdentity(text, kind: .richText)
        case .imageHash(let hash):
            let normalizedHash = hash.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedHash.isEmpty else {
                return nil
            }
            return PayloadIdentity(
                kind: .image,
                fingerprint: digest(Data(normalizedHash.utf8))
            )
        case .files(let urls):
            let paths = Set(urls.lazy.map { $0.standardizedFileURL.path }.filter { !$0.isEmpty }).sorted()
            guard !paths.isEmpty else {
                return nil
            }
            var hasher = SHA256()
            for path in paths {
                let bytes = Data(path.utf8)
                var byteCount = UInt64(bytes.count).bigEndian
                withUnsafeBytes(of: &byteCount) { rawBuffer in
                    hasher.update(data: Data(rawBuffer))
                }
                hasher.update(data: bytes)
            }
            return PayloadIdentity(kind: .files, fingerprint: Data(hasher.finalize()))
        }
    }

    private static func canonicalImageIdentity(_ fingerprint: String) -> PayloadIdentity? {
        let characters = Array(fingerprint.utf8)
        guard characters.count == sha256DigestByteCount * 2 else {
            return nil
        }
        var digest = Data()
        digest.reserveCapacity(sha256DigestByteCount)
        for offset in stride(from: 0, to: characters.count, by: 2) {
            guard let highNibble = lowercaseHexNibble(characters[offset]),
                  let lowNibble = lowercaseHexNibble(characters[offset + 1]) else {
                return nil
            }
            digest.append((highNibble << 4) | lowNibble)
        }
        return PayloadIdentity(
            kind: .image,
            fingerprint: digest
        )
    }

    private static func lowercaseHexNibble(_ character: UInt8) -> UInt8? {
        switch character {
        case 48...57:
            return character - 48
        case 97...102:
            return character - 97 + 10
        default:
            return nil
        }
    }

    private static func textIdentity(
        _ text: String,
        kind: PayloadIdentity.Kind
    ) -> PayloadIdentity? {
        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedText.isEmpty else {
            return nil
        }
        return PayloadIdentity(
            kind: kind,
            fingerprint: digest(Data(normalizedText.utf8))
        )
    }

    private static func digest(_ data: Data) -> Data {
        Data(SHA256.hash(data: data))
    }
}
