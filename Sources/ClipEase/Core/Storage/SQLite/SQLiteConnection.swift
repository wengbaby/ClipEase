import Foundation
import SQLite3

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

typealias SQLiteDatabase = SQLiteConnection

enum SQLiteStoreError: Error, LocalizedError {
    case openFailed(String)
    case prepareFailed(String)
    case executeFailed(String)
    case bindFailed(String)
    case queryReturnedNoRows

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
        case .queryReturnedNoRows:
            "SQLite query returned no rows"
        }
    }
}

final class SQLiteConnection {
    private var handle: OpaquePointer?

    init(url: URL) throws {
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        if sqlite3_open_v2(url.path, &handle, flags, nil) != SQLITE_OK {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            sqlite3_close(handle)
            throw SQLiteStoreError.openFailed(message)
        }
    }

    func close() {
        sqlite3_close(handle)
        handle = nil
    }

    func execute(_ sql: String, values: [SQLiteValue] = []) throws {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }

        try bind(values, to: statement)

        let result = sqlite3_step(statement)
        guard result == SQLITE_DONE || result == SQLITE_ROW else {
            throw SQLiteStoreError.executeFailed(lastErrorMessage)
        }
    }

    func queryInt(_ sql: String, values: [SQLiteValue] = []) throws -> Int {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }

        try bind(values, to: statement)

        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw SQLiteStoreError.queryReturnedNoRows
        }

        return Int(sqlite3_column_int64(statement, 0))
    }

    func query(_ sql: String, values: [SQLiteValue] = []) throws -> [SQLiteRow] {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }

        try bind(values, to: statement)

        var rows: [SQLiteRow] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE {
                break
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

    private func prepare(_ sql: String) throws -> OpaquePointer? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
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
            }

            guard result == SQLITE_OK else {
                throw SQLiteStoreError.bindFailed(lastErrorMessage)
            }
        }
    }

    private var lastErrorMessage: String {
        handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
    }
}

enum SQLiteValue {
    case null
    case text(String)
    case int(Int)
    case double(Double)
    case bool(Bool)

    static func optionalText(_ text: String?) -> SQLiteValue {
        text.map(SQLiteValue.text) ?? .null
    }

    static func optionalInt(_ int: Int?) -> SQLiteValue {
        int.map(SQLiteValue.int) ?? .null
    }

    static func optionalDouble(_ double: Double?) -> SQLiteValue {
        double.map(SQLiteValue.double) ?? .null
    }
}

struct SQLiteRow {
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
        case .null, .none:
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
        case .null, .none:
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
        case .null, .none:
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

enum SQLiteCell {
    case null
    case text(String)
    case int(Int)
    case double(Double)
}
