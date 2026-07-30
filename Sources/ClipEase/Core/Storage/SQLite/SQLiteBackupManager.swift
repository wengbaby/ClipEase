import Foundation

struct SQLiteBackupResult: Sendable, Equatable {
    let directoryURL: URL
    let copiedFiles: [String]
}

enum SQLiteBackupRestoreError: Error, Equatable, LocalizedError {
    case missingMainDatabaseBackup
    case missingCopiedBackupFile(String)

    var errorDescription: String? {
        switch self {
        case .missingMainDatabaseBackup:
            "SQLite backup restore failed because the main database backup is missing."
        case .missingCopiedBackupFile(let fileName):
            "SQLite backup restore failed because copied backup file \(fileName) is missing."
        }
    }
}

struct SQLiteBackupManager {
    let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func backupDatabaseFiles(for databaseURL: URL, reason: String) throws -> SQLiteBackupResult? {
        guard fileManager.fileExists(atPath: databaseURL.path) else {
            return nil
        }

        let backupDirectory = databaseURL
            .deletingLastPathComponent()
            .appendingPathComponent(Self.backupDirectoryName(for: databaseURL, reason: reason), isDirectory: true)
        try fileManager.createDirectory(at: backupDirectory, withIntermediateDirectories: true)

        var copiedFiles: [String] = []
        for sourceURL in Self.databaseFileURLs(for: databaseURL) where fileManager.fileExists(atPath: sourceURL.path) {
            let destinationURL = backupDirectory.appendingPathComponent(sourceURL.lastPathComponent)
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
            copiedFiles.append(sourceURL.lastPathComponent)
        }

        return SQLiteBackupResult(directoryURL: backupDirectory, copiedFiles: copiedFiles)
    }

    func restoreDatabaseFiles(
        from backup: SQLiteBackupResult,
        to databaseURL: URL
    ) throws {
        let expectedURLs = Self.databaseFileURLs(for: databaseURL)
        let mainFileName = databaseURL.lastPathComponent
        let copiedFileNames = Set(backup.copiedFiles)
        guard copiedFileNames.contains(mainFileName),
              fileManager.fileExists(atPath: backup.directoryURL.appendingPathComponent(mainFileName).path) else {
            throw SQLiteBackupRestoreError.missingMainDatabaseBackup
        }

        let restoreDirectory = databaseURL
            .deletingLastPathComponent()
            .appendingPathComponent(".\(mainFileName).restore-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: restoreDirectory, withIntermediateDirectories: true)
        do {
            for destinationURL in expectedURLs where copiedFileNames.contains(destinationURL.lastPathComponent) {
                let sourceURL = backup.directoryURL.appendingPathComponent(destinationURL.lastPathComponent)
                guard fileManager.fileExists(atPath: sourceURL.path) else {
                    throw SQLiteBackupRestoreError.missingCopiedBackupFile(destinationURL.lastPathComponent)
                }
                try fileManager.copyItem(
                    at: sourceURL,
                    to: restoreDirectory.appendingPathComponent(destinationURL.lastPathComponent)
                )
            }

            for destinationURL in expectedURLs {
                let stagedURL = restoreDirectory.appendingPathComponent(destinationURL.lastPathComponent)
                if fileManager.fileExists(atPath: stagedURL.path) {
                    try replaceLiveFile(at: destinationURL, with: stagedURL)
                } else if fileManager.fileExists(atPath: destinationURL.path) {
                    try fileManager.removeItem(at: destinationURL)
                }
            }
        } catch {
            try? fileManager.removeItem(at: restoreDirectory)
            throw error
        }
        try? fileManager.removeItem(at: restoreDirectory)
    }

    static func databaseFileURLs(for databaseURL: URL) -> [URL] {
        [
            databaseURL,
            URL(fileURLWithPath: databaseURL.path + "-wal"),
            URL(fileURLWithPath: databaseURL.path + "-shm"),
            URL(fileURLWithPath: databaseURL.path + "-journal")
        ]
    }

    private static func backupDirectoryName(for databaseURL: URL, reason: String) -> String {
        let safeReason = reason
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let timestamp = ISO8601DateFormatter()
            .string(from: Date())
            .replacingOccurrences(of: ":", with: "")
        return "\(databaseURL.lastPathComponent).backup-\(safeReason)-\(timestamp)-\(UUID().uuidString)"
    }

    private func replaceLiveFile(at destinationURL: URL, with stagedURL: URL) throws {
        if fileManager.fileExists(atPath: destinationURL.path) {
            _ = try fileManager.replaceItemAt(
                destinationURL,
                withItemAt: stagedURL,
                backupItemName: nil,
                options: []
            )
        } else {
            try fileManager.moveItem(at: stagedURL, to: destinationURL)
        }
    }
}
