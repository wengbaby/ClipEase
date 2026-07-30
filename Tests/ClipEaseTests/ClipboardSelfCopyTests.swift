import AppKit
import Testing
@testable import ClipEase

@MainActor
@Test func storeConsumesRegisteredClipboardTextOnce() {
    let store = ClipboardHistoryStore(
        persistence: ClipboardHistoryPersistence(repository: EmptyClipboardHistoryRepository())
    )

    store.registerSelfWrite(changeCount: 101, payload: .text("self copy"))

    #expect(store.consumeSelfWrite(changeCount: 101, payload: .text("self copy")))
    #expect(!store.consumeSelfWrite(changeCount: 101, payload: .text("self copy")))
}

@Test func clipboardSelfWriteGuardConsumesMatchingValuesOnce() {
    let guardStore = ClipboardSelfWriteGuard()
    let fileURL = URL(fileURLWithPath: "/tmp/clipease-guard.txt")

    guardStore.register(changeCount: 1, payload: .text("text"))
    guardStore.register(changeCount: 2, payload: .imageHash("image-hash"))
    guardStore.register(changeCount: 3, payload: .files([fileURL]))

    #expect(guardStore.consume(changeCount: 1, payload: .text("text")))
    #expect(!guardStore.consume(changeCount: 1, payload: .text("text")))
    #expect(guardStore.consume(changeCount: 2, payload: .imageHash("image-hash")))
    #expect(!guardStore.consume(changeCount: 2, payload: .imageHash("image-hash")))
    #expect(guardStore.consume(changeCount: 3, payload: .files([fileURL])))
    #expect(!guardStore.consume(changeCount: 3, payload: .files([fileURL])))
}

@Test func clipboardSelfWriteGuardConsumesPendingImageByExactChangeCountWhenPreviewIsSkipped() async {
    let release = DispatchSemaphore(value: 0)
    let guardStore = ClipboardSelfWriteGuard(imageFingerprint: { _ in
        release.wait()
        return nil
    })
    guardStore.registerPendingImage(
        changeCount: 42,
        payload: ClipboardEncodedImagePayload(
            data: Data([0x01]),
            declaredTypeIdentifier: "public.png"
        )
    )

    let matched = await guardStore.consumeImage(
        changeCount: 42,
        fingerprint: nil
    )
    release.signal()
    let duplicate = await guardStore.consumeImage(
        changeCount: 42,
        fingerprint: nil
    )

    #expect(matched)
    #expect(!duplicate)
}

@MainActor
@Test func pasteboardWriterKeepsRichTextPlainTextAndRegistersSelfWrite() {
    let pasteboard = NSPasteboard(name: NSPasteboard.Name("ClipEaseTests-\(UUID().uuidString)"))
    let richTextData = Data("{\\rtf1 rich}".utf8)
    var registeredPayload: ClipboardSelfWritePayload?

    let didWrite = PasteboardWriter.writeText(
        "rich",
        to: pasteboard,
        richTextData: richTextData,
        registerSelfWrite: { _, payload in registeredPayload = payload }
    )

    #expect(didWrite)
    #expect(registeredPayload == .richText("rich"))
    #expect(pasteboard.string(forType: .string) == "rich")
    #expect(pasteboard.data(forType: .rtf) == richTextData)
}

@MainActor
@Test func clipboardWriteCoordinatorWritesTextAndRegistersSelfWrite() {
    let pasteboard = NSPasteboard(name: NSPasteboard.Name("ClipEaseTests-\(UUID().uuidString)"))
    var registeredPayload: ClipboardSelfWritePayload?
    let coordinator = ClipboardWriteCoordinator(
        pasteboard: pasteboard,
        registerSelfWrite: { _, payload in registeredPayload = payload }
    )

    let didWrite = coordinator.writeText("  self copy  ")

    #expect(didWrite)
    #expect(registeredPayload == .text("self copy"))
    #expect(pasteboard.string(forType: .string) == "self copy")
}

@MainActor
@Test func clipboardWriteCoordinatorWritesFilesAndRegistersSelfWrite() {
    let pasteboard = NSPasteboard(name: NSPasteboard.Name("ClipEaseTests-\(UUID().uuidString)"))
    let url = URL(fileURLWithPath: "/tmp/clipease-test-\(UUID().uuidString).txt")
    var registeredPayload: ClipboardSelfWritePayload?
    let coordinator = ClipboardWriteCoordinator(
        pasteboard: pasteboard,
        registerSelfWrite: { _, payload in registeredPayload = payload }
    )

    let didWrite = coordinator.writeFileURLs([url])

    #expect(didWrite)
    #expect(registeredPayload == .files([url]))
}

private struct EmptyClipboardHistoryRepository: ClipboardHistoryRepository {
    func loadSnapshot() throws -> ClipboardHistorySnapshot {
        ClipboardHistorySnapshot(items: [], groups: [])
    }

    func saveSnapshot(_ snapshot: ClipboardHistorySnapshot) throws {}
}
