import Foundation
import Testing
@testable import ClipEase

@Test func linkMetadataServiceAdvancesAndFinishesCurrentGenerationOnly() {
    var service = LinkMetadataService()
    let id = UUID()

    let first = service.nextGeneration(for: id)
    let second = service.nextGeneration(for: id)

    #expect(first == 1)
    #expect(second == 2)
    let didFinishStaleGeneration = service.finishTask(for: id, generation: first)
    #expect(!didFinishStaleGeneration)
    #expect(service.hasInFlightTask(for: id))
    let didFinishCurrentGeneration = service.finishTask(for: id, generation: second)
    #expect(didFinishCurrentGeneration)
    #expect(!service.hasInFlightTask(for: id))
}

@Test func linkMetadataServiceCancelsSelectedAndAllTasks() {
    var service = LinkMetadataService()
    let first = UUID()
    let second = UUID()
    _ = service.nextGeneration(for: first)
    _ = service.nextGeneration(for: second)

    service.cancelTasks(for: [first])

    #expect(!service.hasInFlightTask(for: first))
    #expect(service.hasInFlightTask(for: second))

    service.cancelAllTasks()

    #expect(!service.hasInFlightTask(for: second))
}

@Test func linkMetadataServiceAllowsOnlyMatchingLinkItemForMetadataUpdate() {
    let url = URL(string: "https://example.com")!
    let link = ClipboardItem.link(url, originalText: url.absoluteString, sourceApp: .clipease)
    let text = ClipboardItem.text(url.absoluteString, sourceApp: .clipease)

    #expect(LinkMetadataService.canApplyMetadata(to: link, expectedURL: url))
    #expect(!LinkMetadataService.canApplyMetadata(to: text, expectedURL: url))
    #expect(!LinkMetadataService.canApplyMetadata(
        to: link,
        expectedURL: URL(string: "https://example.org")!
    ))
}

@Test func linkMetadataServiceSkipsUnchangedTitleWithoutImage() {
    var link = ClipboardItem.link(
        URL(string: "https://example.com")!,
        originalText: "https://example.com",
        sourceApp: .clipease
    )
    link.linkTitle = "Example"

    #expect(!LinkMetadataService.shouldApplyMetadata(title: "Example", storedImage: nil, to: link))
    #expect(LinkMetadataService.shouldApplyMetadata(title: "New title", storedImage: nil, to: link))
    #expect(LinkMetadataService.shouldApplyMetadata(
        title: "Example",
        storedImage: StoredClipboardImage(fileName: "image.png", width: 10, height: 10, hash: "hash"),
        to: link
    ))
}
