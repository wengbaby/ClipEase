import Foundation
import Testing
@testable import ClipEase

@Test func duplicateResolverBuildsSourceAgnosticTextHash() {
    let first = ClipboardItem.text("same text", sourceApp: .clipease)
    let second = ClipboardItem.text("same text", sourceApp: SourceAppInfo(
        name: "Other",
        bundleID: "com.example.other",
        iconName: "app.fill",
        iconFileName: nil,
        headerColorHex: "#8E8E93"
    ))

    #expect(DuplicateResolver.contentKey(for: first) == "text:same text")
    #expect(DuplicateResolver.contentKey(for: second) == DuplicateResolver.contentKey(for: first))
}

@Test func duplicateResolverBuildsSourceAgnosticImageHashWithFallbackID() {
    let first = ClipboardItem.image(
        fileName: "image.png",
        width: 128,
        height: 128,
        hash: "image-hash",
        sourceApp: .clipease
    )
    let second = ClipboardItem.image(
        fileName: "image-copy.png",
        width: 128,
        height: 128,
        hash: "image-hash",
        sourceApp: SourceAppInfo(
            name: "Other",
            bundleID: "com.example.other",
            iconName: "app.fill",
            iconFileName: nil,
            headerColorHex: "#8E8E93"
        )
    )

    #expect(DuplicateResolver.contentKey(for: first) == "image:image-hash")
    #expect(DuplicateResolver.contentKey(for: second) == DuplicateResolver.contentKey(for: first))
}

@Test func duplicateResolverBuildsSourceAgnosticFileHashFromOrderedPaths() {
    let itemID = UUID()
    let first = ClipboardItem.file(
        references: [
            ClipboardFileReference(itemID: itemID, orderIndex: 2, path: "/tmp/b.txt"),
            ClipboardFileReference(itemID: itemID, orderIndex: 0, path: "/tmp/a.txt")
        ],
        sourceApp: .clipease
    )
    let second = ClipboardItem.file(
        references: [
            ClipboardFileReference(itemID: UUID(), orderIndex: 4, path: "/tmp/b.txt"),
            ClipboardFileReference(itemID: UUID(), orderIndex: 1, path: "/tmp/a.txt")
        ],
        sourceApp: SourceAppInfo(
            name: "Other",
            bundleID: "com.example.other",
            iconName: "app.fill",
            iconFileName: nil,
            headerColorHex: "#8E8E93"
        )
    )

    #expect(
        DuplicateResolver.contentKey(for: first)
        == "files:0:/tmp/b.txt\u{1F}1:/tmp/a.txt"
    )
    #expect(DuplicateResolver.contentKey(for: second) == DuplicateResolver.contentKey(for: first))
}

@Test func duplicateResolverMergesDuplicateItemsKeepingFirstOccurrence() {
    let cached = ClipboardItem.text("cached", sourceApp: .clipease)
    let persisted = ClipboardItem.text("persisted", sourceApp: .clipease)
    let duplicatedPersisted = ClipboardItem(
        id: cached.id,
        type: cached.type,
        text: "cached from persistence",
        url: cached.url,
        linkTitle: cached.linkTitle,
        linkSubtitle: cached.linkSubtitle,
        imageFileName: cached.imageFileName,
        imageWidth: cached.imageWidth,
        imageHeight: cached.imageHeight,
        imageHash: cached.imageHash,
        richTextFileName: cached.richTextFileName,
        fileReferences: cached.fileReferences,
        createdAt: cached.createdAt,
        sourceAppName: cached.sourceAppName,
        sourceBundleID: cached.sourceBundleID,
        iconName: cached.iconName,
        iconFileName: cached.iconFileName,
        headerColorHex: cached.headerColorHex,
        isPinned: cached.isPinned,
        pinnedAt: cached.pinnedAt,
        groupID: cached.groupID,
        groupedAt: cached.groupedAt
    )

    let result = DuplicateResolver.mergedDuplicateItems(
        cachedItems: [cached],
        persistedItems: [duplicatedPersisted, persisted]
    )

    #expect(result.map(\.id) == [cached.id, persisted.id])
    #expect(result.first?.text == "cached")
}

@Test func duplicateResolverFiltersImportedDuplicatesByIDAndContent() {
    let existing = ClipboardItem.text("same text", sourceApp: .clipease)
    let sameID = ClipboardItem(
        id: existing.id,
        type: .text,
        text: "different text",
        url: nil,
        linkTitle: nil,
        linkSubtitle: nil,
        imageFileName: nil,
        imageWidth: nil,
        imageHeight: nil,
        imageHash: nil,
        richTextFileName: nil,
        fileReferences: [],
        createdAt: Date(),
        sourceAppName: SourceAppInfo.clipease.name,
        sourceBundleID: SourceAppInfo.clipease.bundleID,
        iconName: SourceAppInfo.clipease.iconName,
        iconFileName: SourceAppInfo.clipease.iconFileName,
        headerColorHex: SourceAppInfo.clipease.headerColorHex,
        isPinned: false,
        pinnedAt: nil,
        groupID: nil,
        groupedAt: nil
    )
    let sameContent = ClipboardItem.text("same text", sourceApp: .clipease)
    let unique = ClipboardItem.text("unique text", sourceApp: .clipease)

    let result = DuplicateResolver.nonDuplicateItems(
        importedItems: [sameID, sameContent, unique],
        existingItems: [existing]
    )

    #expect(result.map(\.id) == [unique.id])
}
