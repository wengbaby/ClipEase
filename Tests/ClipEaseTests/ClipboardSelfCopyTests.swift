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

private struct EmptyClipboardHistoryRepository: ClipboardHistoryRepository {
    func loadSnapshot() throws -> ClipboardHistorySnapshot {
        ClipboardHistorySnapshot(items: [], groups: [])
    }

    func saveSnapshot(_ snapshot: ClipboardHistorySnapshot) throws {}
}
