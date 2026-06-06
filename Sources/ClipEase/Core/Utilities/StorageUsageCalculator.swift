import Foundation

enum StorageUsageCalculator {
    static let defaultHistoryExcludedNames: Set<String> = [
        "ClipEaseDiagnostics.sqlite",
        "ClipEaseDiagnostics.sqlite-shm",
        "ClipEaseDiagnostics.sqlite-wal",
        "PerformanceLogs"
    ]

    static func formattedApplicationSupportSize() -> String {
        guard let directoryURL = try? ClipEaseStoragePaths.applicationSupportDirectory() else {
            return "无法读取"
        }

        let byteCount = applicationSupportSize(
            directoryURL,
            excludedNames: defaultHistoryExcludedNames
        )
        return ByteCountFormatter.string(
            fromByteCount: Int64(byteCount),
            countStyle: .file
        )
    }

    static func applicationSupportSize(
        _ url: URL,
        excludedNames: Set<String> = []
    ) -> UInt64 {
        directorySize(url, excludedNames: excludedNames)
    }

    private static func directorySize(
        _ url: URL,
        excludedNames: Set<String>
    ) -> UInt64 {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var size: UInt64 = 0
        for case let fileURL as URL in enumerator {
            if excludedNames.contains(fileURL.lastPathComponent) {
                enumerator.skipDescendants()
                continue
            }

            guard let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
                  let fileSize = values.fileSize else {
                continue
            }

            size += UInt64(fileSize)
        }
        return size
    }
}
