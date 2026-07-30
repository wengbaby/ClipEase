import Foundation
import SwiftUI

struct HistoryCardHighlightRange: Equatable, Sendable {
    let location: Int
    let length: Int
}

actor HistoryCardHighlightCache {
    struct Key: Hashable, Sendable {
        let itemID: HistoryPreviewItem.ID
        let query: String
        let contentDigest: Data

        init(itemID: HistoryPreviewItem.ID, query: String, contentDigest: Data) {
            self.itemID = itemID
            self.query = query
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            self.contentDigest = contentDigest
        }
    }

    struct Metrics: Equatable, Sendable {
        let entryCount: Int
        let hitCount: Int
        let scanCount: Int
        let totalCostBytes: Int
    }

    static let shared = HistoryCardHighlightCache(maximumEntryCount: 512)

    private struct Entry: Sendable {
        let ranges: [HistoryCardHighlightRange]
        let costBytes: Int
    }

    private let maximumEntryCount: Int
    private let maximumTotalCostBytes: Int
    private let maximumScannedCharacterCount: Int
    private let maximumMatchCount: Int
    private var entries: [Key: Entry] = [:]
    private var insertionOrder: [Key] = []
    private var hitCount = 0
    private var scanCount = 0
    private var totalCostBytes = 0

    init(
        maximumEntryCount: Int,
        maximumTotalCostBytes: Int = 8 * 1_024 * 1_024,
        maximumScannedCharacterCount: Int = 64 * 1_024,
        maximumMatchCount: Int = 2_048
    ) {
        self.maximumEntryCount = max(1, maximumEntryCount)
        self.maximumTotalCostBytes = max(1, maximumTotalCostBytes)
        self.maximumScannedCharacterCount = max(1, maximumScannedCharacterCount)
        self.maximumMatchCount = max(1, maximumMatchCount)
    }

    func matchRanges(for key: Key, text: String) throws -> [HistoryCardHighlightRange] {
        try Task.checkCancellation()
        if let entry = entries[key] {
            hitCount += 1
            return entry.ranges
        }

        let boundedText = String(text.prefix(maximumScannedCharacterCount))
        scanCount += 1
        let ranges = try Self.scan(
            text: boundedText,
            query: key.query,
            maximumMatchCount: maximumMatchCount
        )
        try Task.checkCancellation()
        let entry = Entry(
            ranges: ranges,
            costBytes: Self.estimatedCostBytes(for: key, text: boundedText, ranges: ranges)
        )
        if entries[key] == nil {
            insertionOrder.append(key)
        }
        if let replacedEntry = entries.updateValue(entry, forKey: key) {
            totalCostBytes -= replacedEntry.costBytes
        }
        totalCostBytes += entry.costBytes
        trimIfNeeded()
        return ranges
    }

    func metrics() -> Metrics {
        Metrics(
            entryCount: entries.count,
            hitCount: hitCount,
            scanCount: scanCount,
            totalCostBytes: totalCostBytes
        )
    }

    nonisolated static func boundedDisplayText(_ text: String) -> String {
        String(text.prefix(64 * 1_024))
    }

    private static func scan(
        text: String,
        query: String,
        maximumMatchCount: Int
    ) throws -> [HistoryCardHighlightRange] {
        try Task.checkCancellation()
        guard !query.isEmpty else {
            return []
        }

        let source = text as NSString
        var searchRange = NSRange(location: 0, length: source.length)
        var ranges: [HistoryCardHighlightRange] = []
        while searchRange.length > 0, ranges.count < maximumMatchCount {
            if ranges.count.isMultiple(of: 64) {
                try Task.checkCancellation()
            }
            let matchRange = source.range(
                of: query,
                options: [.caseInsensitive, .diacriticInsensitive],
                range: searchRange
            )
            guard matchRange.location != NSNotFound else {
                break
            }

            ranges.append(
                HistoryCardHighlightRange(
                    location: matchRange.location,
                    length: matchRange.length
                )
            )
            let nextLocation = matchRange.location + max(matchRange.length, 1)
            searchRange = NSRange(
                location: nextLocation,
                length: max(0, source.length - nextLocation)
            )
        }
        return ranges
    }

    private func trimIfNeeded() {
        while (entries.count > maximumEntryCount || totalCostBytes > maximumTotalCostBytes),
              !insertionOrder.isEmpty {
            if let removedEntry = entries.removeValue(forKey: insertionOrder.removeFirst()) {
                totalCostBytes -= removedEntry.costBytes
            }
        }
    }

    private static func estimatedCostBytes(
        for key: Key,
        text: String,
        ranges: [HistoryCardHighlightRange]
    ) -> Int {
        key.query.utf8.count
            + key.contentDigest.count
            + text.utf8.count
            + ranges.count * MemoryLayout<HistoryCardHighlightRange>.stride
    }
}

struct HistoryCardHighlightedText: View {
    let itemID: HistoryPreviewItem.ID
    let text: String
    let searchQuery: String
    let contentDigest: Data
    let baseColor: Color

    @State private var renderedHighlight: RenderedHighlight?

    private struct RenderedHighlight {
        let key: HistoryCardHighlightCache.Key
        let attributedText: AttributedString
    }

    private var cacheKey: HistoryCardHighlightCache.Key {
        HistoryCardHighlightCache.Key(
            itemID: itemID,
            query: searchQuery,
            contentDigest: contentDigest
        )
    }

    var body: some View {
        let key = cacheKey
        let displayText = HistoryCardHighlightCache.boundedDisplayText(text)
        Group {
            if let renderedHighlight,
               renderedHighlight.key == key {
                Text(renderedHighlight.attributedText)
            } else {
                Text(displayText)
            }
        }
        .foregroundColor(baseColor)
        .task(id: key) {
            guard !key.query.isEmpty else {
                renderedHighlight = nil
                return
            }

            guard let ranges = try? await HistoryCardHighlightCache.shared.matchRanges(
                for: key,
                text: displayText
            ) else {
                return
            }
            guard !Task.isCancelled else {
                return
            }
            renderedHighlight = RenderedHighlight(
                key: key,
                attributedText: Self.attributedString(text: displayText, ranges: ranges)
            )
        }
    }

    private static func attributedString(
        text: String,
        ranges: [HistoryCardHighlightRange]
    ) -> AttributedString {
        var attributedText = AttributedString(text)
        for range in ranges {
            let nsRange = NSRange(location: range.location, length: range.length)
            guard let stringRange = Range(nsRange, in: text),
                  let lowerBound = AttributedString.Index(stringRange.lowerBound, within: attributedText),
                  let upperBound = AttributedString.Index(stringRange.upperBound, within: attributedText) else {
                continue
            }
            attributedText[lowerBound..<upperBound].backgroundColor = Color.yellow.opacity(0.55)
        }
        return attributedText
    }
}
