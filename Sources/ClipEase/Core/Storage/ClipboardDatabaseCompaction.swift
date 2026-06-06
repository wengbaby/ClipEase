import Foundation

struct ClipboardDatabaseCompactionPolicy: Equatable, Sendable {
    static let automatic = ClipboardDatabaseCompactionPolicy(
        minimumFreeRatio: 0.25,
        minimumFreeBytes: 5 * 1_024 * 1_024
    )

    let minimumFreeRatio: Double
    let minimumFreeBytes: Int

    func shouldCompact(pageSize: Int, pageCount: Int, freelistCount: Int) -> Bool {
        guard pageSize > 0,
              pageCount > 0,
              freelistCount > 0 else {
            return false
        }

        let freeRatio = Double(freelistCount) / Double(pageCount)
        let freeBytes = pageSize * freelistCount
        return freeRatio >= minimumFreeRatio && freeBytes >= minimumFreeBytes
    }
}

enum ClipboardDatabaseCompactionResult: Equatable, Sendable {
    case compacted(beforeBytes: Int, afterBytes: Int)
    case skipped

    var reclaimedBytes: Int {
        switch self {
        case .compacted(let beforeBytes, let afterBytes):
            max(0, beforeBytes - afterBytes)
        case .skipped:
            0
        }
    }
}
