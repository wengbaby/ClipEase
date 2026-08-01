import Foundation
import Dispatch

private enum SQLiteConnectionCoordinatorError: Error {
    case retryWriterOpening
}

/// Owns one serialized writer connection and a bounded set of reusable readers.
///
/// `SQLiteConnection` itself serializes statements per handle. This coordinator
/// adds the higher-level ownership rule required by the repository: one writer,
/// at most two concurrently leased readers, and explicit invalidation before a
/// database file is replaced.
final class SQLiteConnectionCoordinator: @unchecked Sendable {
    private static let registry = SQLiteConnectionCoordinatorRegistry()

    let maximumReaderCount: Int

    fileprivate let databaseURL: URL
    private let readerCondition = NSCondition()
    private let writerLock = NSLock()

    private var writerConnection: SQLiteConnection?
    private var totalWriterCount = 0
    private var writerGeneration: UInt64 = 0
    private var idleReaders: [SQLiteConnection] = []
    private var leasedReaders: [ObjectIdentifier: SQLiteConnection] = [:]
    private var totalReaderCount = 0
    private var isInvalidating = false
    private var isPreparing = false
    private var preparingThreadID: ObjectIdentifier?
    private var invalidationRequested = false
    private var isPrepared = false

    init(databaseURL: URL, maximumReaderCount: Int = 2) {
        self.databaseURL = databaseURL
        self.maximumReaderCount = max(1, maximumReaderCount)
        Self.registry.register(self)
    }

    deinit {
        Self.registry.unregister(self)
        invalidate()
    }

    static func invalidateAll(for databaseURL: URL) {
        registry.invalidateAll(for: databaseURL)
    }

    /// Strictly drains every coordinator for a database URL. Unlike migration
    /// invalidation, reset cannot proceed while another coordinator is still
    /// preparing a reader because it is about to unlink the database files.
    static func drainAll(for databaseURL: URL) {
        registry.drainAll(for: databaseURL)
    }

    /// Runs destructive database-file maintenance while preventing any
    /// coordinator for the same URL from registering or reopening a handle.
    /// The URL gate first waits for all active reader/writer access leases;
    /// retained idle handles are then drained by the maintenance operation.
    static func withExclusiveMaintenance<Result>(
        for databaseURL: URL,
        _ operation: () throws -> Result
    ) rethrows -> Result {
        try registry.withExclusiveMaintenance(for: databaseURL, operation)
    }

    private func withDatabaseAccess<Result>(
        _ operation: () throws -> Result
    ) rethrows -> Result {
        try Self.registry.withAccess(for: databaseURL, operation)
    }

    private func withDatabaseAccess<Result>(
        _ operation: () async throws -> Result
    ) async rethrows -> Result {
        try await Self.registry.withAccess(for: databaseURL, operation)
    }

    var createdReaderCount: Int {
        readerCondition.withLock { totalReaderCount }
    }

    var createdWriterCount: Int {
        writerLock.withLock { totalWriterCount }
    }

    var hasLiveWriterConnectionForTesting: Bool {
        writerLock.withLock { writerConnection != nil }
    }

    var readerConnectionsOpenedReadOnlyForTesting: Bool {
        readerCondition.withLock {
            let connections = idleReaders + Array(leasedReaders.values)
            return !connections.isEmpty && connections.allSatisfy(\.openedReadOnly)
        }
    }

    /// Runs schema/configuration work once before pooled access. A failed
    /// preparation remains retryable and never publishes a half-ready state.
    func prepareIfNeeded(
        _ prepare: () throws -> SQLiteConnection
    ) throws {
        try withDatabaseAccess {
            while true {
                readerCondition.lock()
                while isPreparing || isInvalidating {
                    readerCondition.wait()
                }
                if isPrepared {
                    readerCondition.unlock()
                    return
                }
                isPreparing = true
                preparingThreadID = ObjectIdentifier(Thread.current)
                readerCondition.unlock()

                do {
                    let preparedConnection = try prepare()
                    do {
                        try configureReader(preparedConnection)
                    } catch {
                        preparedConnection.close()
                        throw error
                    }
                    let shouldRetry = readerCondition.withLock {
                        isPreparing = false
                        preparingThreadID = nil
                        guard !invalidationRequested else {
                            invalidationRequested = false
                            isPrepared = false
                            readerCondition.broadcast()
                            return true
                        }
                        idleReaders.append(preparedConnection)
                        totalReaderCount += 1
                        isPrepared = true
                        readerCondition.broadcast()
                        return false
                    }
                    if shouldRetry {
                        preparedConnection.close()
                        continue
                    }
                    return
                } catch {
                    readerCondition.withLock {
                        isPreparing = false
                        preparingThreadID = nil
                        invalidationRequested = false
                        readerCondition.broadcast()
                    }
                    throw error
                }
            }
        }
    }

    func withWriter<Result>(
        opening: (() throws -> SQLiteConnection)? = nil,
        _ operation: (SQLiteConnection) throws -> Result
    ) throws -> Result {
        try withDatabaseAccess {
            // A caller may need to run migration before the coordinator's writer
            // lock is taken. Migration invalidation itself drains this coordinator
            // and therefore cannot be invoked while the lock is held.
            if let opening, !hasWriterConnection {
                while true {
                    let openingGeneration = writerLock.withLock { writerGeneration }
                    let preparedConnection = try opening()
                    do {
                        return try writerLock.withLock {
                            guard writerGeneration == openingGeneration else {
                                preparedConnection.close()
                                throw SQLiteConnectionCoordinatorError.retryWriterOpening
                            }
                            if let writerConnection {
                                preparedConnection.close()
                                return try operation(writerConnection)
                            }
                            writerConnection = preparedConnection
                            totalWriterCount += 1
                            return try operation(preparedConnection)
                        }
                    } catch SQLiteConnectionCoordinatorError.retryWriterOpening {
                        continue
                    }
                }
            }

            return try writerLock.withLock {
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
    }

    private var hasWriterConnection: Bool {
        writerLock.withLock { writerConnection != nil }
    }

    func withReader<Result>(
        _ operation: (SQLiteConnection) throws -> Result
    ) throws -> Result {
        try withDatabaseAccess {
            let connection = try acquireReader()
            defer { releaseReader(connection) }
            return try operation(connection)
        }
    }

    /// Opens, configures, and leases the first reader as one operation. This
    /// avoids a second condition-lock round trip on cold compatibility reads,
    /// while still publishing the connection to the bounded pool for reuse.
    func withReader<Result>(
        opening: () throws -> SQLiteConnection,
        _ operation: (SQLiteConnection) throws -> Result
    ) throws -> Result {
        try withDatabaseAccess {
            while true {
                readerCondition.lock()
                while isPreparing || isInvalidating {
                    readerCondition.wait()
                }
                if isPrepared {
                    readerCondition.unlock()
                    let connection = try acquireReader()
                    defer { releaseReader(connection) }
                    return try operation(connection)
                }
                isPreparing = true
                preparingThreadID = ObjectIdentifier(Thread.current)
                readerCondition.unlock()

                let connection: SQLiteConnection
                do {
                    let opened = try opening()
                    do {
                        try configureReader(opened)
                    } catch {
                        opened.close()
                        throw error
                    }
                    connection = opened
                } catch {
                    readerCondition.withLock {
                        isPreparing = false
                        preparingThreadID = nil
                        invalidationRequested = false
                        readerCondition.broadcast()
                    }
                    throw error
                }

                let shouldRetry = readerCondition.withLock {
                    isPreparing = false
                    preparingThreadID = nil
                    guard !invalidationRequested else {
                        invalidationRequested = false
                        isPrepared = false
                        readerCondition.broadcast()
                        return true
                    }
                    leasedReaders[ObjectIdentifier(connection)] = connection
                    totalReaderCount += 1
                    isPrepared = true
                    readerCondition.broadcast()
                    return false
                }
                if shouldRetry {
                    connection.close()
                    continue
                }
                defer { releaseReader(connection) }
                return try operation(connection)
            }
        }
    }

    func withReaderAsync<Result: Sendable>(
        _ operation: @escaping @Sendable (SQLiteConnection) async throws -> Result
    ) async throws -> Result {
        try await withDatabaseAccess {
            let connection = try acquireReader()
            defer { releaseReader(connection) }

            return try await withTaskCancellationHandler {
                try Task.checkCancellation()
                return try await operation(connection)
            } onCancel: {
                connection.interrupt()
            }
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
        try withDatabaseAccess {
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
                if preparingThreadID == ObjectIdentifier(Thread.current) {
                    readerCondition.unlock()
                    return
                }
                // Do not wait while the migration gate is held: the other
                // preparation may itself be waiting to enter that gate. The
                // preparation completion will observe this request and
                // discard its not-yet-published handle.
                invalidationRequested = true
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
            writerGeneration &+= 1
            writerConnection?.interrupt()
            writerConnection?.close()
            writerConnection = nil
        }

        readerCondition.withLock {
            isInvalidating = false
            invalidationRequested = false
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
                do {
                    try configureReader(opened)
                } catch {
                    opened.close()
                    throw error
                }
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

    private func configureReader(_ connection: SQLiteConnection) throws {
        try connection.execute("PRAGMA foreign_keys = ON")
        try connection.execute("PRAGMA query_only = ON")
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

private enum SQLiteConnectionAccessContext {
    @TaskLocal static var counts: [String: Int] = [:]
}

private final class SQLiteConnectionCoordinatorRegistry: @unchecked Sendable {
    private final class WeakCoordinator {
        weak var value: SQLiteConnectionCoordinator?

        init(_ value: SQLiteConnectionCoordinator) {
            self.value = value
        }
    }

    private let condition = NSCondition()
    private let threadAccessCountsKey = "ClipEase.SQLiteConnectionCoordinatorRegistry.\(UUID().uuidString)"
    private var coordinators: [String: [ObjectIdentifier: WeakCoordinator]] = [:]
    private var maintenanceKeys: Set<String> = []
    private var activeAccessCounts: [String: Int] = [:]

    func register(_ coordinator: SQLiteConnectionCoordinator) {
        let key = Self.key(for: coordinator.databaseURL)
        condition.lock()
        while maintenanceKeys.contains(key) {
            condition.wait()
        }
        defer { condition.unlock() }
        var entries = coordinators[key] ?? [:]
        entries[ObjectIdentifier(coordinator)] = WeakCoordinator(coordinator)
        coordinators[key] = entries
    }

    func unregister(_ coordinator: SQLiteConnectionCoordinator) {
        let key = Self.key(for: coordinator.databaseURL)
        condition.withLock {
            guard var entries = coordinators[key] else {
                return
            }
            entries.removeValue(forKey: ObjectIdentifier(coordinator))
            if entries.isEmpty {
                coordinators.removeValue(forKey: key)
            } else {
                coordinators[key] = entries
            }
        }
    }

    func invalidateAll(for databaseURL: URL) {
        let key = Self.key(for: databaseURL)
        let targets: [SQLiteConnectionCoordinator] = condition.withLock {
            guard let entries = coordinators[key] else {
                return []
            }

            var live: [ObjectIdentifier: WeakCoordinator] = [:]
            var targets: [SQLiteConnectionCoordinator] = []
            for (identifier, entry) in entries {
                guard let coordinator = entry.value else {
                    continue
                }
                live[identifier] = entry
                targets.append(coordinator)
            }
            coordinators[key] = live
            return targets
        }

        // Never hold the registry lock while acquiring a coordinator lock.
        for coordinator in targets {
            coordinator.invalidateForMigration()
        }
    }

    func drainAll(for databaseURL: URL) {
        let key = Self.key(for: databaseURL)
        let targets: [SQLiteConnectionCoordinator] = condition.withLock {
            guard let entries = coordinators[key] else {
                return []
            }

            var live: [ObjectIdentifier: WeakCoordinator] = [:]
            var targets: [SQLiteConnectionCoordinator] = []
            for (identifier, entry) in entries {
                guard let coordinator = entry.value else {
                    continue
                }
                live[identifier] = entry
                targets.append(coordinator)
            }
            coordinators[key] = live
            return targets
        }

        // Never hold the registry lock while acquiring a coordinator lock.
        for coordinator in targets {
            coordinator.invalidate()
        }
    }

    func withAccess<Result>(
        for databaseURL: URL,
        _ operation: () throws -> Result
    ) rethrows -> Result {
        let key = Self.key(for: databaseURL)
        acquireAccess(for: key)
        recordThreadAccess(for: key)
        defer {
            removeThreadAccess(for: key)
            releaseAccess(for: key)
        }
        return try operation()
    }

    func withAccess<Result>(
        for databaseURL: URL,
        _ operation: () async throws -> Result
    ) async rethrows -> Result {
        let key = Self.key(for: databaseURL)
        acquireAccess(for: key)
        var counts = SQLiteConnectionAccessContext.counts
        counts[key, default: 0] += 1
        return try await SQLiteConnectionAccessContext.$counts.withValue(counts) {
            defer { releaseAccess(for: key) }
            return try await operation()
        }
    }

    private func acquireAccess(for key: String) {
        condition.lock()
        while maintenanceKeys.contains(key) {
            condition.wait()
        }
        activeAccessCounts[key, default: 0] += 1
        condition.unlock()
    }

    private func releaseAccess(for key: String) {
        condition.withLock {
            guard let count = activeAccessCounts[key], count > 0 else {
                assertionFailure("Released an unowned SQLite database access lease")
                return
            }
            if count == 1 {
                activeAccessCounts.removeValue(forKey: key)
                condition.broadcast()
            } else {
                activeAccessCounts[key] = count - 1
            }
        }
    }

    private func recordThreadAccess(for key: String) {
        var counts = Thread.current.threadDictionary[threadAccessCountsKey] as? [String: Int] ?? [:]
        counts[key, default: 0] += 1
        Thread.current.threadDictionary[threadAccessCountsKey] = counts
    }

    private func removeThreadAccess(for key: String) {
        guard var counts = Thread.current.threadDictionary[threadAccessCountsKey] as? [String: Int],
              let count = counts[key], count > 0 else {
            assertionFailure("Released an unowned thread-local SQLite database access lease")
            return
        }
        if count == 1 {
            counts.removeValue(forKey: key)
        } else {
            counts[key] = count - 1
        }
        if counts.isEmpty {
            Thread.current.threadDictionary.removeObject(forKey: threadAccessCountsKey)
        } else {
            Thread.current.threadDictionary[threadAccessCountsKey] = counts
        }
    }

    private func currentThreadAccessCount(for key: String) -> Int {
        let counts = Thread.current.threadDictionary[threadAccessCountsKey] as? [String: Int]
        return counts?[key] ?? 0
    }

    private func currentAccessCount(for key: String) -> Int {
        currentThreadAccessCount(for: key)
            + (SQLiteConnectionAccessContext.counts[key] ?? 0)
    }

    func withExclusiveMaintenance<Result>(
        for databaseURL: URL,
        _ operation: () throws -> Result
    ) rethrows -> Result {
        let key = Self.key(for: databaseURL)
        let suspendedAccessCount = currentAccessCount(for: key)
        condition.lock()
        // Do not reserve maintenance while another access is active. An
        // access that is already on this thread/task may safely upgrade, but
        // every other reader/writer must finish before the reservation is
        // published. This ordering prevents two maintenance callers from
        // deadlocking while also keeping an outer SQLite handle alive.
        while maintenanceKeys.contains(key)
            || activeAccessCounts[key, default: 0] > suspendedAccessCount {
            condition.wait()
        }
        if suspendedAccessCount > 0 {
            let activeCount = activeAccessCounts[key, default: 0]
            precondition(activeCount >= suspendedAccessCount)
            let remainingCount = activeCount - suspendedAccessCount
            if remainingCount == 0 {
                activeAccessCounts.removeValue(forKey: key)
            } else {
                activeAccessCounts[key] = remainingCount
            }
        }
        maintenanceKeys.insert(key)
        condition.unlock()

        defer {
            condition.withLock {
                if suspendedAccessCount > 0 {
                    activeAccessCounts[key, default: 0] += suspendedAccessCount
                }
                maintenanceKeys.remove(key)
                condition.broadcast()
            }
        }
        return try operation()
    }

    private static func key(for databaseURL: URL) -> String {
        databaseURL.standardizedFileURL.path
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
