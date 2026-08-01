import Foundation
import Testing
@testable import ClipEase

@Test func sqliteConnectionExecutesParameterizedQueriesAndCloses() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("clipease-sqlite-connection-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let databaseURL = directory.appendingPathComponent("ClipEase.sqlite")
    let connection = try SQLiteConnection(url: databaseURL)
    defer { connection.close() }

    try connection.execute("CREATE TABLE sample (id INTEGER PRIMARY KEY, value TEXT NOT NULL)")
    try connection.execute("INSERT INTO sample (value) VALUES (?)", values: [.text("hello")])

    #expect(try connection.queryInt("SELECT COUNT(*) FROM sample") == 1)
    #expect(try connection.query("SELECT value FROM sample").first?.requiredText("value") == "hello")
}

@Test func sqliteCancellableQueryInterruptsAndConnectionRemainsReusable() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("clipease-sqlite-interrupt-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let connection = try SQLiteConnection(url: directory.appendingPathComponent("ClipEase.sqlite"))
    defer { connection.close() }

    let queryTask = Task {
        try await connection.queryCancellable(
            """
            WITH RECURSIVE counter(value) AS (
                VALUES(0)
                UNION ALL
                SELECT value + 1 FROM counter WHERE value < 1000000000
            )
            SELECT SUM(value) AS total FROM counter
            """
        )
    }
    try await Task.sleep(nanoseconds: 5_000_000)
    queryTask.cancel()

    var wasCancelled = false
    do {
        _ = try await queryTask.value
    } catch is CancellationError {
        wasCancelled = true
    }

    #expect(wasCancelled)
    #expect(try connection.queryInt("SELECT 7") == 7)
}

@Test func sqliteConnectionCoordinatorKeepsOneWriterAndAtMostTwoReaders() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("clipease-sqlite-coordinator-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let coordinator = SQLiteConnectionCoordinator(
        databaseURL: directory.appendingPathComponent("ClipEase.sqlite"),
        maximumReaderCount: 2
    )
    defer { coordinator.invalidate() }

    let firstWriterID = try coordinator.withWriter { connection -> ObjectIdentifier in
        try connection.execute("CREATE TABLE sample (value INTEGER NOT NULL)")
        return ObjectIdentifier(connection)
    }
    let secondWriterID = try coordinator.withWriter { connection -> ObjectIdentifier in
        try connection.execute("INSERT INTO sample (value) VALUES (1)")
        return ObjectIdentifier(connection)
    }
    #expect(firstWriterID == secondWriterID)

    let probe = SQLiteReaderConcurrencyProbe()
    let releaseReaders = DispatchSemaphore(value: 0)
    let twoReadersEntered = DispatchSemaphore(value: 0)
    let group = DispatchGroup()
    for _ in 0..<3 {
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            defer { group.leave() }
            try? coordinator.withReader { connection in
                if probe.enter() == 2 {
                    twoReadersEntered.signal()
                }
                defer { probe.leave() }
                releaseReaders.wait()
                _ = try connection.queryInt("SELECT 1")
            }
        }
    }

    #expect(twoReadersEntered.wait(timeout: .now() + 2) == .success)
    Thread.sleep(forTimeInterval: 0.05)
    #expect(probe.maximumActiveCount == 2)
    #expect(coordinator.createdReaderCount == 2)

    releaseReaders.signal()
    releaseReaders.signal()
    releaseReaders.signal()
    #expect(group.wait(timeout: .now() + 2) == .success)
}

@Test func sqliteConnectionCoordinatorInvalidatesEveryCoordinatorForDatabaseURL() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(
            "clipease-sqlite-coordinator-registry-\(UUID().uuidString)",
            isDirectory: true
        )
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let databaseURL = directory.appendingPathComponent("ClipEase.sqlite")
    let firstCoordinator = SQLiteConnectionCoordinator(databaseURL: databaseURL)
    let secondCoordinator = SQLiteConnectionCoordinator(databaseURL: databaseURL)
    defer {
        firstCoordinator.invalidate()
        secondCoordinator.invalidate()
    }

    try firstCoordinator.withWriter { connection in
        try connection.execute("CREATE TABLE sample (value INTEGER NOT NULL)")
    }
    _ = try firstCoordinator.withReader { connection in
        try connection.queryInt("SELECT COUNT(*) FROM sample")
    }
    _ = try secondCoordinator.withReader { connection in
        try connection.queryInt("SELECT COUNT(*) FROM sample")
    }

    #expect(firstCoordinator.createdWriterCount == 1)
    #expect(firstCoordinator.createdReaderCount == 1)
    #expect(secondCoordinator.createdReaderCount == 1)
    #expect(firstCoordinator.hasLiveWriterConnectionForTesting)

    SQLiteConnectionCoordinator.invalidateAll(for: databaseURL)

    #expect(firstCoordinator.createdWriterCount == 1)
    #expect(firstCoordinator.createdReaderCount == 0)
    #expect(secondCoordinator.createdWriterCount == 0)
    #expect(secondCoordinator.createdReaderCount == 0)
    #expect(!firstCoordinator.hasLiveWriterConnectionForTesting)
    #expect(!secondCoordinator.hasLiveWriterConnectionForTesting)

    #expect(try secondCoordinator.withReader { connection in
        try connection.queryInt("SELECT COUNT(*) FROM sample")
    } == 0)
}

@Test func sqliteConnectionCoordinatorExclusiveMaintenanceBlocksNewRegistration() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(
            "clipease-sqlite-coordinator-maintenance-(UUID().uuidString)",
            isDirectory: true
        )
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let databaseURL = directory.appendingPathComponent("ClipEase.sqlite")
    let maintenanceEntered = DispatchSemaphore(value: 0)
    let releaseMaintenance = DispatchSemaphore(value: 0)
    let coordinatorRegistered = DispatchSemaphore(value: 0)

    DispatchQueue.global(qos: .userInitiated).async {
        SQLiteConnectionCoordinator.withExclusiveMaintenance(for: databaseURL) {
            maintenanceEntered.signal()
            releaseMaintenance.wait()
        }
    }

    #expect(maintenanceEntered.wait(timeout: .now() + 2) == .success)
    DispatchQueue.global(qos: .userInitiated).async {
        let coordinator = SQLiteConnectionCoordinator(databaseURL: databaseURL)
        coordinatorRegistered.signal()
        coordinator.invalidate()
    }

    #expect(coordinatorRegistered.wait(timeout: .now() + 0.05) == .timedOut)
    releaseMaintenance.signal()
    #expect(coordinatorRegistered.wait(timeout: .now() + 2) == .success)
}

@Test func sqliteConnectionCoordinatorRetriesWriterOpeningInvalidatedMidFlight() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(
            "clipease-sqlite-coordinator-writer-race-\(UUID().uuidString)",
            isDirectory: true
        )
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let databaseURL = directory.appendingPathComponent("ClipEase.sqlite")
    let coordinator = SQLiteConnectionCoordinator(databaseURL: databaseURL)
    defer { coordinator.invalidate() }

    let openingStarted = DispatchSemaphore(value: 0)
    let releaseOpening = DispatchSemaphore(value: 0)
    let openingProbe = SQLiteOpeningCountProbe()
    let operationFinished = DispatchSemaphore(value: 0)

    DispatchQueue.global(qos: .userInitiated).async {
        defer { operationFinished.signal() }
        try? coordinator.withWriter(opening: {
            let attempt = openingProbe.increment()
            let connection = try SQLiteConnection(url: databaseURL)
            if attempt == 1 {
                openingStarted.signal()
                releaseOpening.wait()
            }
            return connection
        }) { connection in
            try connection.execute("CREATE TABLE sample (value INTEGER NOT NULL)")
        }
    }

    #expect(openingStarted.wait(timeout: .now() + 2) == .success)
    coordinator.invalidate()
    releaseOpening.signal()
    #expect(operationFinished.wait(timeout: .now() + 2) == .success)
    #expect(openingProbe.count == 2)
    #expect(coordinator.hasLiveWriterConnectionForTesting)
}

@Test func sqliteConnectionCoordinatorAdoptsPreparedConnectionAsFirstReader() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(
            "clipease-sqlite-coordinator-prepared-\(UUID().uuidString)",
            isDirectory: true
        )
    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(at: directory) }

    let databaseURL = directory.appendingPathComponent("ClipEase.sqlite")
    let coordinator = SQLiteConnectionCoordinator(
        databaseURL: databaseURL,
        maximumReaderCount: 2
    )
    defer { coordinator.invalidate() }

    var preparedConnectionID: ObjectIdentifier?
    try coordinator.prepareIfNeeded {
        let connection = try SQLiteConnection(url: databaseURL)
        try connection.execute("CREATE TABLE sample (value INTEGER NOT NULL)")
        preparedConnectionID = ObjectIdentifier(connection)
        return connection
    }

    let leasedConnectionID = try coordinator.withReader { connection in
        let rowCount = try connection.queryInt("SELECT COUNT(*) FROM sample")
        #expect(rowCount == 0)
        return ObjectIdentifier(connection)
    }

    #expect(leasedConnectionID == preparedConnectionID)
    #expect(coordinator.createdReaderCount == 1)
}

@Test func sqliteConnectionCoordinatorOpensAndLeasesFirstReaderAtomically() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(
            "clipease-sqlite-coordinator-first-reader-\(UUID().uuidString)",
            isDirectory: true
        )
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let databaseURL = directory.appendingPathComponent("ClipEase.sqlite")
    let coordinator = SQLiteConnectionCoordinator(
        databaseURL: databaseURL,
        maximumReaderCount: 2
    )
    defer { coordinator.invalidate() }

    var openCount = 0
    let firstReaderID = try coordinator.withReader(opening: {
        openCount += 1
        let connection = try SQLiteConnection(url: databaseURL)
        try connection.execute("CREATE TABLE sample (value INTEGER NOT NULL)")
        return connection
    }) { connection in
        let queryOnly = try connection.queryInt("PRAGMA query_only")
        #expect(queryOnly == 1)
        return ObjectIdentifier(connection)
    }

    let secondReaderID = try coordinator.withReader { connection in
        let rowCount = try connection.queryInt("SELECT COUNT(*) FROM sample")
        #expect(rowCount == 0)
        return ObjectIdentifier(connection)
    }

    #expect(openCount == 1)
    #expect(firstReaderID == secondReaderID)
    #expect(coordinator.createdReaderCount == 1)
}

@Test func sqliteCancellationHandlerGateQuiescesBeforeReaderReuse() {
    let gate = SQLiteCancellationHandlerGate()
    let handlerEntered = DispatchSemaphore(value: 0)
    let handlerMayFinish = DispatchSemaphore(value: 0)
    let deactivationFinished = DispatchSemaphore(value: 0)
    let invocationProbe = SQLiteHandlerInvocationProbe()

    DispatchQueue.global(qos: .userInitiated).async {
        gate.perform {
            handlerEntered.signal()
            handlerMayFinish.wait()
            invocationProbe.increment()
        }
    }
    #expect(handlerEntered.wait(timeout: .now() + 2) == .success)

    DispatchQueue.global(qos: .userInitiated).async {
        gate.deactivateAndWait()
        deactivationFinished.signal()
    }
    #expect(deactivationFinished.wait(timeout: .now() + 0.05) == .timedOut)

    handlerMayFinish.signal()
    #expect(deactivationFinished.wait(timeout: .now() + 2) == .success)
    gate.perform {
        invocationProbe.increment()
    }

    #expect(invocationProbe.count == 1)
}

@Test func sqliteConnectionCoordinatorInterruptsCancelledSynchronousReader() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("clipease-sqlite-coordinator-cancel-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let coordinator = SQLiteConnectionCoordinator(
        databaseURL: directory.appendingPathComponent("ClipEase.sqlite"),
        maximumReaderCount: 2
    )
    defer { coordinator.invalidate() }
    let cancellation = ClipboardSearchCancellationToken()
    let queryWorkerReady = DispatchSemaphore(value: 0)
    let queryMayStart = DispatchSemaphore(value: 0)
    let completionProbe = SQLiteQueryCompletionProbe()
    let queryTask = Task.detached {
        try coordinator.withCancellableReader(cancellation: cancellation) { connection in
            queryWorkerReady.signal()
            queryMayStart.wait()
            let rows = try connection.query(
                """
                WITH RECURSIVE counter(value) AS (
                    VALUES(0)
                    UNION ALL
                    SELECT value + 1 FROM counter WHERE value < 5000000
                )
                SELECT SUM(value) AS total FROM counter
                """
            )
            completionProbe.markCompletedNormally()
            return rows
        }
    }

    let workerReadyResult = await Task.detached {
        waitSynchronously(for: queryWorkerReady, timeout: .now() + 2)
    }.value
    #expect(workerReadyResult == .success)
    queryTask.cancel()
    let cancellationDeadline = Date().addingTimeInterval(2)
    while !cancellation.isCancelled && Date() < cancellationDeadline {
        try await Task.sleep(nanoseconds: 1_000_000)
    }
    #expect(cancellation.isCancelled)
    queryMayStart.signal()

    var wasCancelled = false
    do {
        _ = try await queryTask.value
    } catch is CancellationError {
        wasCancelled = true
    }

    #expect(wasCancelled)
    #expect(!completionProbe.completedNormally)
    #expect(try coordinator.withReader { try $0.queryInt("SELECT 11") } == 11)
}

private final class SQLiteReaderConcurrencyProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var activeCount = 0
    private var storedMaximumActiveCount = 0

    var maximumActiveCount: Int {
        lock.withLock { storedMaximumActiveCount }
    }

    func enter() -> Int {
        lock.withLock {
            activeCount += 1
            storedMaximumActiveCount = max(storedMaximumActiveCount, activeCount)
            return activeCount
        }
    }

    func leave() {
        lock.withLock {
            activeCount -= 1
        }
    }
}

private final class SQLiteQueryCompletionProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var storedCompletedNormally = false

    var completedNormally: Bool {
        lock.withLock { storedCompletedNormally }
    }

    func markCompletedNormally() {
        lock.withLock {
            storedCompletedNormally = true
        }
    }
}

private final class SQLiteHandlerInvocationProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var storedCount = 0

    var count: Int {
        lock.withLock { storedCount }
    }

    func increment() {
        lock.withLock {
            storedCount += 1
        }
    }
}

private final class SQLiteOpeningCountProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var storedCount = 0

    var count: Int {
        lock.withLock { storedCount }
    }

    func increment() -> Int {
        lock.withLock {
            storedCount += 1
            return storedCount
        }
    }
}

private func waitSynchronously(
    for semaphore: DispatchSemaphore,
    timeout: DispatchTime
) -> DispatchTimeoutResult {
    semaphore.wait(timeout: timeout)
}
