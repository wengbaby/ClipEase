import Foundation

struct HistorySourceAppFilterSnapshot: Sendable {
    let options: [HistorySourceAppFilterOption]
    let iconFileNameByName: [String: String]
}

struct HistorySourceAppFilterOption: Identifiable, Equatable, Sendable {
    let name: String
    let iconFileName: String?

    var id: String {
        name
    }
}

enum HistorySourceAppFilter {
    static func snapshot(from sourceItems: [ClipboardItem]) -> HistorySourceAppFilterSnapshot {
        (try? cancellableSnapshot(from: sourceItems))
            ?? HistorySourceAppFilterSnapshot(options: [], iconFileNameByName: [:])
    }

    static func cancellableSnapshot(
        from sourceItems: [ClipboardItem]
    ) throws -> HistorySourceAppFilterSnapshot {
        try Task.checkCancellation()
        var seen = Set<String>()
        var options: [HistorySourceAppFilterOption] = []
        var iconFileNameByName: [String: String] = [:]

        options.reserveCapacity(min(sourceItems.count, 128))
        for (index, item) in sourceItems.enumerated() {
            if index.isMultiple(of: 256) {
                try Task.checkCancellation()
            }
            let name = item.sourceAppName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else {
                continue
            }

            if iconFileNameByName[name] == nil,
               let iconFileName = item.iconFileName {
                iconFileNameByName[name] = iconFileName
            }

            guard !seen.contains(name) else {
                continue
            }

            seen.insert(name)
            options.append(HistorySourceAppFilterOption(name: name, iconFileName: item.iconFileName))
        }

        return HistorySourceAppFilterSnapshot(
            options: options,
            iconFileNameByName: iconFileNameByName
        )
    }
}
