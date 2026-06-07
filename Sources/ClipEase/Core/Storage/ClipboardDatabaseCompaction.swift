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

final class ClipboardDatabaseCompactionScheduler {
    private static let defaultMinimumInterval: TimeInterval = 10 * 60

    private let minimumInterval: TimeInterval
    private var lastCheckAt: Date?

    init(minimumInterval: TimeInterval = ClipboardDatabaseCompactionScheduler.defaultMinimumInterval) {
        self.minimumInterval = minimumInterval
    }

    func shouldRun(now: Date = Date(), force: Bool = false) -> Bool {
        if force {
            return true
        }

        guard let lastCheckAt else {
            return true
        }

        return now.timeIntervalSince(lastCheckAt) >= minimumInterval
    }

    func markRun(at date: Date = Date()) {
        lastCheckAt = date
    }
}
