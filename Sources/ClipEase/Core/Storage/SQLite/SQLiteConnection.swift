import Foundation
import SQLite3

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

typealias SQLiteDatabase = SQLiteConnection

enum SQLiteStoreError: Error, LocalizedError {
    case openFailed(String)
    case prepareFailed(String)
    case executeFailed(String)
    case bindFailed(String)
    case interrupted
    case queryReturnedNoRows
    case incompatibleSchemaVersion(found: Int, supported: Int)

    var errorDescription: String? {
        switch self {
        case .openFailed(let message):
            "SQLite open failed: \(message)"
        case .prepareFailed(let message):
            "SQLite prepare failed: \(message)"
        case .executeFailed(let message):
            "SQLite execute failed: \(message)"
        case .bindFailed(let message):
            "SQLite bind failed: \(message)"
        case .interrupted:
            "SQLite query was interrupted"
        case .queryReturnedNoRows:
            "SQLite query returned no rows"
        case .incompatibleSchemaVersion(let found, let supported):
            "SQLite schema version \(found) is newer than supported version \(supported)"
        }
    }
}

final class SQLiteConnection: @unchecked Sendable {
    static let defaultBusyTimeoutMilliseconds = 5_000

    private let operationLock = NSRecursiveLock()
    private let handleLock = NSLock()
    private var handle: OpaquePointer?

    init(url: URL) throws {
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        if sqlite3_open_v2(url.path, &handle, flags, nil) != SQLITE_OK {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            sqlite3_close(handle)
            throw SQLiteStoreError.openFailed(message)
        }

        guard sqlite3_busy_timeout(handle, Int32(Self.defaultBusyTimeoutMilliseconds)) == SQLITE_OK else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            sqlite3_close(handle)
            handle = nil
            throw SQLiteStoreError.executeFailed(message)
        }
    }

    deinit {
        close()
    }

    func close() {
        operationLock.withLock {
            handleLock.withLock {
                guard let handle else {
                    return
                }
                sqlite3_close(handle)
                self.handle = nil
            }
        }
    }

    @discardableResult
    func interrupt() -> Bool {
        handleLock.withLock {
            guard let handle else {
                return false
            }
            sqlite3_interrupt(handle)
            return true
        }
    }

    func execute(_ sql: String, values: [SQLiteValue] = []) throws {
        try operationLock.withLock {
            let statement = try prepare(sql)
            defer { sqlite3_finalize(statement) }

            try bind(values, to: statement)

            let result = sqlite3_step(statement)
            if result == SQLITE_INTERRUPT {
                throw SQLiteStoreError.interrupted
            }
            guard result == SQLITE_DONE || result == SQLITE_ROW else {
                throw SQLiteStoreError.executeFailed(lastErrorMessage)
            }
        }
    }

    func queryInt(_ sql: String, values: [SQLiteValue] = []) throws -> Int {
        try operationLock.withLock {
            let statement = try prepare(sql)
            defer { sqlite3_finalize(statement) }

            try bind(values, to: statement)

            let result = sqlite3_step(statement)
            if result == SQLITE_INTERRUPT {
                throw SQLiteStoreError.interrupted
            }
            guard result == SQLITE_ROW else {
                throw SQLiteStoreError.queryReturnedNoRows
            }

            return Int(sqlite3_column_int64(statement, 0))
        }
    }

    func query(_ sql: String, values: [SQLiteValue] = []) throws -> [SQLiteRow] {
        try query(
            sql,
            values: values,
            cancellationCheck: { false }
        )
    }

    func queryCancellable(
        _ sql: String,
        values: [SQLiteValue] = []
    ) async throws -> [SQLiteRow] {
        let cancellationState = SQLiteQueryCancellationState()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            do {
                return try await Task.detached(priority: .userInitiated) { [self] in
                    try query(
                        sql,
                        values: values,
                        cancellationCheck: cancellationState.isCancelled
                    )
                }.value
            } catch SQLiteStoreError.interrupted {
                throw CancellationError()
            }
        } onCancel: {
            cancellationState.cancel()
            interrupt()
        }
    }

    private func query(
        _ sql: String,
        values: [SQLiteValue],
        cancellationCheck: @escaping @Sendable () -> Bool
    ) throws -> [SQLiteRow] {
        try operationLock.withLock {
            if cancellationCheck() {
                throw CancellationError()
            }

            let statement = try prepare(sql)
            defer { sqlite3_finalize(statement) }

            try bind(values, to: statement)
            if cancellationCheck() {
                throw CancellationError()
            }

            var rows: [SQLiteRow] = []
            while true {
                if cancellationCheck() {
                    throw CancellationError()
                }

                let result = sqlite3_step(statement)
                if result == SQLITE_DONE {
                    break
                }
                if result == SQLITE_INTERRUPT {
                    throw SQLiteStoreError.interrupted
                }

                guard result == SQLITE_ROW else {
                    throw SQLiteStoreError.executeFailed(lastErrorMessage)
                }

                var values: [String: SQLiteCell] = [:]
                for index in 0..<sqlite3_column_count(statement) {
                    guard let namePointer = sqlite3_column_name(statement, index) else {
                        continue
                    }

                    let name = String(cString: namePointer)
                    switch sqlite3_column_type(statement, index) {
                    case SQLITE_NULL:
                        values[name] = .null
                    case SQLITE_INTEGER:
                        values[name] = .int(Int(sqlite3_column_int64(statement, index)))
                    case SQLITE_FLOAT:
                        values[name] = .double(sqlite3_column_double(statement, index))
                    case SQLITE_BLOB:
                        let byteCount = Int(sqlite3_column_bytes(statement, index))
                        if byteCount == 0 {
                            values[name] = .blob(Data())
                        } else if let bytes = sqlite3_column_blob(statement, index) {
                            values[name] = .blob(Data(bytes: bytes, count: byteCount))
                        } else {
                            values[name] = .blob(Data())
                        }
                    default:
                        let text = sqlite3_column_text(statement, index)
                            .map { String(cString: $0) } ?? ""
                        values[name] = .text(text)
                    }
                }

                rows.append(SQLiteRow(values: values))
            }

            return rows
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer? {
        var statement: OpaquePointer?
        let handle = handleLock.withLock { self.handle }
        let result = sqlite3_prepare_v2(handle, sql, -1, &statement, nil)
        if result == SQLITE_INTERRUPT {
            throw SQLiteStoreError.interrupted
        }
        guard result == SQLITE_OK else {
            throw SQLiteStoreError.prepareFailed(lastErrorMessage)
        }
        return statement
    }

    private func bind(_ values: [SQLiteValue], to statement: OpaquePointer?) throws {
        for (index, value) in values.enumerated() {
            let sqliteIndex = Int32(index + 1)
            let result: Int32

            switch value {
            case .null:
                result = sqlite3_bind_null(statement, sqliteIndex)
            case .text(let text):
                result = sqlite3_bind_text(statement, sqliteIndex, text, -1, sqliteTransient)
            case .int(let int):
                result = sqlite3_bind_int64(statement, sqliteIndex, sqlite3_int64(int))
            case .double(let double):
                result = sqlite3_bind_double(statement, sqliteIndex, double)
            case .bool(let bool):
                result = sqlite3_bind_int(statement, sqliteIndex, bool ? 1 : 0)
            case .blob(let data):
                result = data.withUnsafeBytes { bytes in
                    sqlite3_bind_blob(
                        statement,
                        sqliteIndex,
                        bytes.baseAddress,
                        Int32(bytes.count),
                        sqliteTransient
                    )
                }
            }

            guard result == SQLITE_OK else {
                throw SQLiteStoreError.bindFailed(lastErrorMessage)
            }
        }
    }

    private var lastErrorMessage: String {
        handleLock.withLock {
            handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
        }
    }
}

private final class SQLiteQueryCancellationState: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    func cancel() {
        lock.withLock {
            cancelled = true
        }
    }

    func isCancelled() -> Bool {
        lock.withLock { cancelled }
    }
}

enum SQLiteValue: Sendable {
    case null
    case text(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case blob(Data)

    static func optionalText(_ text: String?) -> SQLiteValue {
        text.map(SQLiteValue.text) ?? .null
    }

    static func optionalInt(_ int: Int?) -> SQLiteValue {
        int.map(SQLiteValue.int) ?? .null
    }

    static func optionalDouble(_ double: Double?) -> SQLiteValue {
        double.map(SQLiteValue.double) ?? .null
    }

    static func optionalBlob(_ data: Data?) -> SQLiteValue {
        data.map(SQLiteValue.blob) ?? .null
    }
}

struct SQLiteRow: Sendable {
    let values: [String: SQLiteCell]

    func requiredText(_ key: String) -> String {
        optionalText(key) ?? ""
    }

    func optionalText(_ key: String) -> String? {
        switch values[key] {
        case .text(let text):
            text
        case .int(let int):
            String(int)
        case .double(let double):
            String(double)
        case .blob, .null, .none:
            nil
        }
    }

    func requiredDouble(_ key: String) -> Double {
        optionalDouble(key) ?? 0
    }

    func optionalDouble(_ key: String) -> Double? {
        switch values[key] {
        case .double(let double):
            double
        case .int(let int):
            Double(int)
        case .text(let text):
            Double(text)
        case .blob, .null, .none:
            nil
        }
    }

    func optionalInt(_ key: String) -> Int? {
        switch values[key] {
        case .int(let int):
            int
        case .double(let double):
            Int(double)
        case .text(let text):
            Int(text)
        case .blob, .null, .none:
            nil
        }
    }

    func requiredInt(_ key: String) -> Int {
        optionalInt(key) ?? 0
    }

    func requiredBool(_ key: String) -> Bool {
        (optionalInt(key) ?? 0) != 0
    }
}

enum SQLiteCell: Sendable {
    case null
    case text(String)
    case int(Int)
    case double(Double)
    case blob(Data)
}
