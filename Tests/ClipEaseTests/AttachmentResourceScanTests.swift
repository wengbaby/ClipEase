import Foundation
import Testing
@testable import ClipEase

@Test func orphanedAttachmentCleanerSkipsReferencedFilesBeforeReadingMetadata() throws {
    let context = try AttachmentResourceScanTestContext()
    defer { context.remove() }
    try context.populate()

    let counter = AttachmentResourceScanCounter()
    let provider: AttachmentResourceValuesProvider = { url, keys in
        counter.increment()
        return try url.resourceValues(forKeys: keys)
    }

    let result = OrphanedAttachmentCleaner.clean(
        items: context.referencedItems,
        fileManager: context.fileManager,
        resourceValuesProvider: provider
    )

    #expect(result.removedFiles == 3)
    #expect(result.removedBytes == 3 * 17)
    #expect(counter.value == 3)
    #expect(context.fileExists(in: "Images", named: "referenced.png"))
    #expect(context.fileExists(in: "Thumbnails", named: "referenced.png"))
    #expect(context.fileExists(in: "RichTexts", named: "referenced.rtf"))
    #expect(!context.fileExists(in: "Images", named: "orphan-image.png"))
    #expect(!context.fileExists(in: "Thumbnails", named: "orphan-thumbnail.png"))
    #expect(!context.fileExists(in: "RichTexts", named: "orphan-rich-text.rtf"))
}

@Test func orphanedAttachmentCandidatesSkipsReferencedFilesBeforeReadingMetadata() throws {
    let context = try AttachmentResourceScanTestContext()
    defer { context.remove() }
    try context.populate()

    let counter = AttachmentResourceScanCounter()
    let provider: AttachmentResourceValuesProvider = { url, keys in
        counter.increment()
        return try url.resourceValues(forKeys: keys)
    }

    let result = OrphanedAttachmentCleaner.candidates(
        items: context.referencedItems,
        fileManager: context.fileManager,
        resourceValuesProvider: provider
    )

    #expect(result.imageFileNames == Set(["orphan-image.png", "orphan-thumbnail.png"]))
    #expect(result.richTextFileNames == Set(["orphan-rich-text.rtf"]))
    #expect(counter.value == 3)
}

@Test func historyDataHealthCheckerSkipsReferencedFilesBeforeReadingMetadata() throws {
    let context = try AttachmentResourceScanTestContext()
    defer { context.remove() }
    try context.populate()

    let counter = AttachmentResourceScanCounter()
    let provider: AttachmentResourceValuesProvider = { url, keys in
        counter.increment()
        return try url.resourceValues(forKeys: keys)
    }

    let report = HistoryDataHealthChecker.check(
        items: context.referencedItems,
        fileManager: context.fileManager,
        resourceValuesProvider: provider
    )

    #expect(report.missingImageFiles == 0)
    #expect(report.missingRichTextFiles == 0)
    #expect(report.orphanedAttachmentFiles == 3)
    #expect(report.orphanedAttachmentBytes == 3 * 17)
    #expect(counter.value == 3)
}

private final class AttachmentResourceScanTestContext {
    let rootURL: URL
    let fileManager: AttachmentResourceScanFileManager
    let referencedItems: [ClipboardItem]

    init() throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("clipease-attachment-scan-\(UUID().uuidString)", isDirectory: true)
        fileManager = AttachmentResourceScanFileManager(rootURL: rootURL)
        referencedItems = [
            .image(
                fileName: "referenced.png",
                width: 1,
                height: 1,
                hash: "fixture",
                sourceApp: .clipease
            ),
            .richText(
                plainText: "referenced",
                fileName: "referenced.rtf",
                sourceApp: .clipease
            ),
        ]
    }

    func populate() throws {
        let directories = try [
            ClipEaseStoragePaths.imagesDirectory(fileManager: fileManager),
            ClipEaseStoragePaths.thumbnailsDirectory(fileManager: fileManager),
            ClipEaseStoragePaths.richTextsDirectory(fileManager: fileManager),
        ]
        for directory in directories {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let fileNames = [
            (directories[0], ["referenced.png", "orphan-image.png"]),
            (directories[1], ["referenced.png", "orphan-thumbnail.png"]),
            (directories[2], ["referenced.rtf", "orphan-rich-text.rtf"]),
        ]
        for (directory, names) in fileNames {
            for name in names {
                let byteCount = name.hasPrefix("referenced") ? 5 : 17
                try Data(repeating: 0xAB, count: byteCount).write(
                    to: directory.appendingPathComponent(name),
                    options: .atomic
                )
            }
        }
    }

    func fileExists(in directoryName: String, named fileName: String) -> Bool {
        fileManager.fileExists(
            atPath: rootURL
                .appendingPathComponent("ClipEase", isDirectory: true)
                .appendingPathComponent(directoryName, isDirectory: true)
                .appendingPathComponent(fileName)
                .path
        )
    }

    func remove() {
        try? fileManager.removeItem(at: rootURL)
    }
}

private final class AttachmentResourceScanCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue = 0

    var value: Int {
        lock.withLock { storedValue }
    }

    func increment() {
        lock.withLock {
            storedValue += 1
        }
    }
}

private final class AttachmentResourceScanFileManager: FileManager, @unchecked Sendable {
    private let rootURL: URL

    init(rootURL: URL) {
        self.rootURL = rootURL
        super.init()
    }

    override func url(
        for directory: FileManager.SearchPathDirectory,
        in domain: FileManager.SearchPathDomainMask,
        appropriateFor url: URL?,
        create shouldCreate: Bool
    ) throws -> URL {
        if shouldCreate {
            try createDirectory(at: rootURL, withIntermediateDirectories: true)
        }
        return rootURL
    }
}
