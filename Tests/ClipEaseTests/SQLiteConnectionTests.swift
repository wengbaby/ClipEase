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
    let queryTask = Task.detached {
        try coordinator.withCancellableReader(cancellation: cancellation) { connection in
            try connection.query(
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
