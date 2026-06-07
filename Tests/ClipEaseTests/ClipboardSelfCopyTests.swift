import AppKit
import Testing
@testable import ClipEase

@MainActor
@Test func skippedClipboardTextIsConsumedOnce() {
    let store = ClipboardHistoryStore(persistence: ClipboardHistoryPersistence(repository: EmptyClipboardHistoryRepository()))

    store.skipNextClipboardText("  self copy  ")

    #expect(store.consumeSkippedClipboardText("self copy"))
    #expect(!store.consumeSkippedClipboardText("self copy"))
}

@MainActor
@Test func skippedClipboardTextIsNotAddedToHistory() {
    let store = ClipboardHistoryStore(persistence: ClipboardHistoryPersistence(repository: EmptyClipboardHistoryRepository()))

    store.skipNextClipboardText("self copy")
    store.addText("self copy", sourceApp: .clipease)

    #expect(store.items.isEmpty)
}

@Test func pasteboardWriterKeepsRichTextAndPlainText() {
    let pasteboard = NSPasteboard(name: NSPasteboard.Name("ClipEaseTests-\(UUID().uuidString)"))
    let richTextData = Data("{\\rtf1 rich}".utf8)
    var skippedText: String?

    let didWrite = PasteboardWriter.writeText(
        "rich",
        to: pasteboard,
        richTextData: richTextData,
        skipRecording: { skippedText = $0 }
    )

    #expect(didWrite)
    #expect(skippedText == "rich")
    #expect(pasteboard.string(forType: .string) == "rich")
    #expect(pasteboard.data(forType: .rtf) == richTextData)
}

@Test func clipboardWriteCoordinatorWritesTextAndRegistersSkip() {
    let pasteboard = NSPasteboard(name: NSPasteboard.Name("ClipEaseTests-\(UUID().uuidString)"))
    var skippedText: String?
    let coordinator = ClipboardWriteCoordinator(
        pasteboard: pasteboard,
        skipText: { skippedText = $0 },
        skipImage: { _ in },
        skipFiles: { _ in }
    )

    let didWrite = coordinator.writeText("  self copy  ")

    #expect(didWrite)
    #expect(skippedText == "self copy")
    #expect(pasteboard.string(forType: .string) == "self copy")
}

@Test func clipboardWriteCoordinatorWritesFilesAndRegistersSkip() {
    let pasteboard = NSPasteboard(name: NSPasteboard.Name("ClipEaseTests-\(UUID().uuidString)"))
    let url = URL(fileURLWithPath: "/tmp/clipease-test-\(UUID().uuidString).txt")
    var skippedFiles: [URL] = []
    let coordinator = ClipboardWriteCoordinator(
        pasteboard: pasteboard,
        skipText: { _ in },
        skipImage: { _ in },
        skipFiles: { skippedFiles = $0 }
    )

    let didWrite = coordinator.writeFileURLs([url])

    #expect(didWrite)
    #expect(skippedFiles == [url])
}

@Test func clipboardWriteCoordinatorWritesImageAndRegistersSkip() {
    let pasteboard = NSPasteboard(name: NSPasteboard.Name("ClipEaseTests-\(UUID().uuidString)"))
    let item = ClipboardItem.image(
        fileName: "test.png",
        width: 2,
        height: 2,
        hash: "image-hash",
        sourceApp: .clipease
    )
    var skippedImageID: ClipboardItem.ID?
    let coordinator = ClipboardWriteCoordinator(
        pasteboard: pasteboard,
        skipText: { _ in },
        skipImage: { skippedImageID = $0.id },
        skipFiles: { _ in }
    )
    let image = NSImage(size: NSSize(width: 2, height: 2))

    let didWrite = coordinator.writeImage(image, item: item)

    #expect(didWrite)
    #expect(skippedImageID == item.id)
}

private struct EmptyClipboardHistoryRepository: ClipboardHistoryRepository {
    func loadSnapshot() throws -> ClipboardHistorySnapshot {
        ClipboardHistorySnapshot(items: [], groups: [])
    }

    func saveSnapshot(_ snapshot: ClipboardHistorySnapshot) throws {}
}
