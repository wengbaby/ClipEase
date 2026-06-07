import Foundation

struct SQLiteBackupResult: Sendable, Equatable {
    let directoryURL: URL
    let copiedFiles: [String]
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
}
