import Foundation

enum StorageUsageCalculator {
    static func formattedApplicationSupportSize() -> String {
        guard let directoryURL = try? ClipEaseStoragePaths.applicationSupportDirectory() else {
            return "无法读取"
        }

        let byteCount = directorySize(directoryURL)
        return ByteCountFormatter.string(
            fromByteCount: Int64(byteCount),
            countStyle: .file
        )
    }

    private static func directorySize(_ url: URL) -> UInt64 {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var size: UInt64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
                  let fileSize = values.fileSize else {
                continue
            }

            size += UInt64(fileSize)
        }
        return size
    }
}
