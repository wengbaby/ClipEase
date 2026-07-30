import Foundation
import SwiftUI
import Testing
@testable import ClipEase

@Test func historyCardHighlightCacheReusesHitsAndInvalidatesExactKeyChanges() async throws {
    let cache = HistoryCardHighlightCache(maximumEntryCount: 16)
    let itemID = UUID()
    let text = Array(repeating: "Café performance cache", count: 2_048)
        .joined(separator: " ")
    let initialKey = HistoryCardHighlightCache.Key(
        itemID: itemID,
        query: "cafe",
        contentDigest: Data([0x01])
    )

    let first = try await cache.matchRanges(for: initialKey, text: text)
    let repeated = try await cache.matchRanges(for: initialKey, text: text)
    var metrics = await cache.metrics()

    #expect(first == repeated)
    #expect(first.count == 2_048)
    #expect(metrics.scanCount == 1)
    #expect(metrics.hitCount == 1)

    let changedQueryKey = HistoryCardHighlightCache.Key(
        itemID: itemID,
        query: "performance",
        contentDigest: Data([0x01])
    )
    _ = try await cache.matchRanges(for: changedQueryKey, text: text)

    let changedRevisionKey = HistoryCardHighlightCache.Key(
        itemID: itemID,
        query: "performance",
        contentDigest: Data([0x02])
    )
    _ = try await cache.matchRanges(for: changedRevisionKey, text: text + " revised")
    metrics = await cache.metrics()

    #expect(metrics.scanCount == 3)
    #expect(metrics.entryCount == 3)
}

@Test func historyCardHighlightCacheSerializesConcurrentMissesForTheSameItem() async {
    let cache = HistoryCardHighlightCache(
        maximumEntryCount: 16,
        maximumMatchCount: 4_096
    )
    let text = Array(repeating: "needle haystack", count: 4_096)
        .joined(separator: " ")
    let key = HistoryCardHighlightCache.Key(
        itemID: UUID(),
        query: "needle",
        contentDigest: Data([0x63])
    )

    let results = await withTaskGroup(
        of: [HistoryCardHighlightRange].self,
        returning: [[HistoryCardHighlightRange]].self
    ) { group in
        for _ in 0..<32 {
            group.addTask {
                (try? await cache.matchRanges(for: key, text: text)) ?? []
            }
        }

        var collected: [[HistoryCardHighlightRange]] = []
        for await result in group {
            collected.append(result)
        }
        return collected
    }
    let metrics = await cache.metrics()

    #expect(results.count == 32)
    #expect(results.allSatisfy { $0.count == 4_096 })
    #expect(metrics.scanCount == 1)
    #expect(metrics.hitCount == 31)
}

@Test func historyCardHighlightIdentityUsesExactDisplayedText() {
    let itemID = UUID()
    let first = HistoryPreviewItem(
        id: itemID,
        type: .text,
        kind: "文本",
        time: "现在",
        iconName: "text.alignleft",
        headerColor: .blue,
        preview: "Cafe",
        footer: ""
    )
    let edited = HistoryPreviewItem(
        id: itemID,
        type: .text,
        kind: "文本",
        time: "现在",
        iconName: "text.alignleft",
        headerColor: .blue,
        preview: "CAFÉ",
        footer: ""
    )

    #expect(first.searchFingerprint == edited.searchFingerprint)
    #expect(first.highlightContentDigest != edited.highlightContentDigest)
}

@Test func cancelledHighlightRequestDoesNotPopulateCache() async {
    let cache = HistoryCardHighlightCache(maximumEntryCount: 16)
    let key = HistoryCardHighlightCache.Key(
        itemID: UUID(),
        query: "needle",
        contentDigest: Data([0x01])
    )
    let task = Task {
        try await cache.matchRanges(
            for: key,
            text: Array(repeating: "needle", count: 100_000).joined(separator: " ")
        )
    }
    task.cancel()
    _ = try? await task.value

    let metrics = await cache.metrics()
    #expect(metrics.scanCount == 0)
    #expect(metrics.entryCount == 0)
}

@Test func highlightCacheBoundsMatchesAndTotalCost() async throws {
    let cache = HistoryCardHighlightCache(
        maximumEntryCount: 16,
        maximumTotalCostBytes: 4_096,
        maximumScannedCharacterCount: 2_048,
        maximumMatchCount: 32
    )
    let key = HistoryCardHighlightCache.Key(
        itemID: UUID(),
        query: "a",
        contentDigest: Data([0x01])
    )

    let ranges = try await cache.matchRanges(
        for: key,
        text: String(repeating: "a", count: 100_000)
    )
    let metrics = await cache.metrics()

    #expect(ranges.count == 32)
    #expect(metrics.totalCostBytes <= 4_096)
}
