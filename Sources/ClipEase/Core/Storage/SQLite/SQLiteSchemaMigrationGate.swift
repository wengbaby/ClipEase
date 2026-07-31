import Foundation

final class SQLiteSchemaMigrationGate: @unchecked Sendable {
    private let lock = NSLock()

    func withLock<Result>(_ operation: () throws -> Result) rethrows -> Result {
        lock.lock()
        defer { lock.unlock() }
        return try operation()
    }
}
