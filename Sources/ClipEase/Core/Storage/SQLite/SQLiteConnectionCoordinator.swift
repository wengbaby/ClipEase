import Foundation
import Dispatch

/// Owns one serialized writer connection and a bounded set of reusable readers.
///
/// `SQLiteConnection` itself serializes statements per handle. This coordinator
/// adds the higher-level ownership rule required by the repository: one writer,
/// at most two concurrently leased readers, and explicit invalidation before a
/// database file is replaced.
final class SQLiteConnectionCoordinator: @unchecked Sendable {
    let maximumReaderCount: Int

    private let databaseURL: URL
    private let readerCondition = NSCondition()
    private let writerLock = NSLock()

    private var writerConnection: SQLiteConnection?
    private var totalWriterCount = 0
    private var idleReaders: [SQLiteConnection] = []
    private var leasedReaders: [ObjectIdentifier: SQLiteConnection] = [:]
    private var totalReaderCount = 0
    private var isInvalidating = false
    private var isPreparing = false
    private var isPrepared = false

    init(databaseURL: URL, maximumReaderCount: Int = 2) {
        self.databaseURL = databaseURL
        self.maximumReaderCount = max(1, maximumReaderCount)
    }

    deinit {
        invalidate()
    }

    var createdReaderCount: Int {
        readerCondition.withLock { totalReaderCount }
    }

    var createdWriterCount: Int {
        writerLock.withLock { totalWriterCount }
    }

    /// Runs schema/configuration work once before pooled access. A failed
    /// preparation remains retryable and never publishes a half-ready state.
    func prepareIfNeeded(
        _ prepare: () throws -> SQLiteConnection
    ) throws {
        readerCondition.lock()
        while isPreparing || isInvalidating {
            readerCondition.wait()
        }
        if isPrepared {
            readerCondition.unlock()
            return
        }
        isPreparing = true
        readerCondition.unlock()

        do {
            let preparedConnection = try prepare()
            do {
                try preparedConnection.execute("PRAGMA foreign_keys = ON")
                try preparedConnection.execute("PRAGMA query_only = ON")
            } catch {
                preparedConnection.close()
                throw error
            }
            readerCondition.withLock {
                idleReaders.append(preparedConnection)
                totalReaderCount += 1
                isPreparing = false
                isPrepared = true
                readerCondition.broadcast()
            }
        } catch {
            readerCondition.withLock {
                isPreparing = false
                readerCondition.broadcast()
            }
            throw error
        }
    }

    func withWriter<Result>(
        _ operation: (SQLiteConnection) throws -> Result
    ) throws -> Result {
        try writerLock.withLock {
            let connection: SQLiteConnection
            if let writerConnection {
                connection = writerConnection
            } else {
                let opened = try SQLiteConnection(url: databaseURL)
                do {
                    try opened.execute("PRAGMA foreign_keys = ON")
                } catch {
                    opened.close()
                    throw error
                }
                writerConnection = opened
                totalWriterCount += 1
                connection = opened
            }
            return try operation(connection)
        }
    }

    func withReader<Result>(
        _ operation: (SQLiteConnection) throws -> Result
    ) throws -> Result {
        let connection = try acquireReader()
        defer { releaseReader(connection) }
        return try operation(connection)
    }

    func withReaderAsync<Result: Sendable>(
        _ operation: @escaping @Sendable (SQLiteConnection) async throws -> Result
    ) async throws -> Result {
        let connection = try acquireReader()
        defer { releaseReader(connection) }

        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await operation(connection)
        } onCancel: {
            connection.interrupt()
        }
    }

    /// Bridges the synchronous repository surface to an interruptible SQLite
    /// read. The SQL work runs on a dedicated queue while the calling task
    /// checks cancellation in bounded intervals and invokes `sqlite3_interrupt`
    /// through the shared cancellation token.
    func withCancellableReader<Result: Sendable>(
        cancellation: ClipboardSearchCancellationToken,
        _ operation: @escaping @Sendable (SQLiteConnection) throws -> Result
    ) throws -> Result {
        let connection = try acquireReader()
        defer { releaseReader(connection) }

        let cancellationHandlerGate = SQLiteCancellationHandlerGate()
        let cancellationHandlerID = cancellation.registerCancellationHandler {
            cancellationHandlerGate.perform {
                connection.interrupt()
            }
        }
        defer {
            cancellation.unregisterCancellationHandler(cancellationHandlerID)
            cancellationHandlerGate.deactivateAndWait()
        }
        try cancellation.throwIfCancelled()

        let resultBox = SQLiteBlockingResultBox<Result>()
        DispatchQueue.global(qos: .userInitiated).async {
            resultBox.complete(Swift.Result {
                try connection.withCancellationCheck(
                    { cancellation.isCancelled }
                ) {
                    try operation(connection)
                }
            })
        }

        while true {
            let taskIsCancelled = withUnsafeCurrentTask {
                $0?.isCancelled ?? false
            }
            if taskIsCancelled {
                cancellation.cancel()
            }

            guard let result = resultBox.waitForResult(timeout: 0.005) else {
                continue
            }

            let completionTaskIsCancelled = withUnsafeCurrentTask {
                $0?.isCancelled ?? false
            }
            if completionTaskIsCancelled {
                cancellation.cancel()
            }
            let shouldCancel = cancellation.isCancelled
                || taskIsCancelled
                || completionTaskIsCancelled

            switch result {
            case .success(let value):
                if shouldCancel {
                    throw CancellationError()
                }
                return value
            case .failure(let error):
                if shouldCancel {
                    if error is CancellationError {
                        throw CancellationError()
                    }
                    if let storeError = error as? SQLiteStoreError,
                       case .interrupted = storeError {
                        throw CancellationError()
                    }
                }
                throw error
            }
        }
    }

    /// Interrupts active readers, waits for their leases to return, and closes
    /// every retained handle. The coordinator remains reusable afterwards.
    func invalidate() {
        invalidate(skipIfPreparing: false)
    }

    /// Migration can be entered from `prepareIfNeeded`'s preparation closure.
    /// In that case no reader has been published yet, so waiting for
    /// `isPreparing` would deadlock the preparation thread itself.
    func invalidateForMigration() {
        invalidate(skipIfPreparing: true)
    }

    private func invalidate(skipIfPreparing: Bool) {
        readerCondition.lock()
        while isPreparing {
            if skipIfPreparing {
                readerCondition.unlock()
                return
            }
            readerCondition.wait()
        }
        isInvalidating = true
        for connection in leasedReaders.values {
            connection.interrupt()
        }
        while !leasedReaders.isEmpty {
            readerCondition.wait()
        }
        let readersToClose = idleReaders
        idleReaders.removeAll(keepingCapacity: false)
        totalReaderCount = 0
        isPrepared = false
        readerCondition.unlock()

        for connection in readersToClose {
            connection.close()
        }

        writerLock.withLock {
            writerConnection?.interrupt()
            writerConnection?.close()
            writerConnection = nil
        }

        readerCondition.withLock {
            isInvalidating = false
            readerCondition.broadcast()
        }
    }

    private func acquireReader() throws -> SQLiteConnection {
        readerCondition.lock()
        defer { readerCondition.unlock() }

        while isInvalidating || isPreparing {
            readerCondition.wait()
        }
        while idleReaders.isEmpty && totalReaderCount >= maximumReaderCount {
            readerCondition.wait()
            while isInvalidating || isPreparing {
                readerCondition.wait()
            }
        }

        let connection: SQLiteConnection
        if let existing = idleReaders.popLast() {
            connection = existing
        } else {
            totalReaderCount += 1
            do {
                let opened = try SQLiteConnection(url: databaseURL)
                try opened.execute("PRAGMA foreign_keys = ON")
                try opened.execute("PRAGMA query_only = ON")
                connection = opened
            } catch {
                totalReaderCount -= 1
                readerCondition.broadcast()
                throw error
            }
        }

        leasedReaders[ObjectIdentifier(connection)] = connection
        return connection
    }

    private func releaseReader(_ connection: SQLiteConnection) {
        readerCondition.withLock {
            leasedReaders[ObjectIdentifier(connection)] = nil
            if isInvalidating {
                connection.close()
                totalReaderCount = max(0, totalReaderCount - 1)
            } else {
                idleReaders.append(connection)
            }
            readerCondition.broadcast()
        }
    }
}

/// Prevents a copied cancellation callback from interrupting a pooled
/// connection after its current reader lease has ended.
final class SQLiteCancellationHandlerGate: @unchecked Sendable {
    private let condition = NSCondition()
    private var isActive = true
    private var inFlightCount = 0

    func perform(_ operation: @Sendable () -> Void) {
        condition.lock()
        guard isActive else {
            condition.unlock()
            return
        }
        inFlightCount += 1
        condition.unlock()

        operation()

        condition.withLock {
            inFlightCount -= 1
            if inFlightCount == 0 {
                condition.broadcast()
            }
        }
    }

    func deactivateAndWait() {
        condition.lock()
        isActive = false
        while inFlightCount > 0 {
            condition.wait()
        }
        condition.unlock()
    }
}

private final class SQLiteBlockingResultBox<Output: Sendable>: @unchecked Sendable {
    private let condition = NSCondition()
    private var storedResult: Result<Output, any Error>?

    func complete(_ result: Result<Output, any Error>) {
        condition.withLock {
            guard storedResult == nil else {
                return
            }
            storedResult = result
            condition.broadcast()
        }
    }

    func waitForResult(
        timeout: TimeInterval
    ) -> Result<Output, any Error>? {
        condition.lock()
        defer { condition.unlock() }
        if storedResult == nil {
            _ = condition.wait(until: Date().addingTimeInterval(timeout))
        }
        return storedResult
    }
}
