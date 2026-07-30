import AppKit
import Foundation
import Testing
@testable import ClipEase

@Test func payloadImportQueueHandlesEmptyAndBulkRemovalBoundaries() {
    var emptyQueue = ClipboardPayloadImportQueue<Int>(
        maximumResidentTasks: -1,
        maximumRetainedBytes: -1
    )
    #expect(emptyQueue.maximumResidentTasks == 0)
    #expect(emptyQueue.maximumRetainedBytes == 0)
    #expect(emptyQueue.dequeue() == nil)
    #expect(emptyQueue.removeAll().isEmpty)

    var queue = ClipboardPayloadImportQueue<Int>(
        maximumResidentTasks: 3,
        maximumRetainedBytes: 2
    )
    #expect(queue.enqueue(1, retaining: -10) == nil)
    #expect(queue.enqueue(2, retaining: 2) == nil)
    #expect(queue.values == [1, 2])
    #expect(queue.removeAll() == [1, 2])
    #expect(queue.residentTaskCount == 0)
    #expect(queue.retainedByteCount == 0)
}

@MainActor
@Test func installedWorkspaceLifecycleObserversSuspendAndResumePolling() async {
    let lifecycleState = ClipboardMonitorLifecycleState()
    let timerProbe = EnterpriseMonitorTimerProbe()
    let store = ClipboardHistoryStore(
        persistence: ClipboardHistoryPersistence(
            repository: ClipboardPayloadStagingEmptyRepository()
        )
    )
    let monitor = ClipboardMonitor(
        store: store,
        pasteboard: NSPasteboard(
            name: NSPasteboard.Name("ClipEaseTests-\(UUID().uuidString)")
        ),
        sourceAppProvider: { .clipease },
        isPaused: { false },
        isIgnored: { _ in false },
        timerScheduler: timerProbe.scheduler,
        pasteboardChangeCountProvider: { 0 },
        pasteboardSnapshotProvider: {
            ClipboardMonitorPasteboardReadSnapshot(
                changeCount: 0,
                types: [],
                strings: [:],
                data: [:],
                fileURLs: []
            )
        },
        lifecycleState: lifecycleState,
        observesSystemLifecycle: true
    )
    monitor.start()

    NSWorkspace.shared.notificationCenter.post(
        name: NSWorkspace.willSleepNotification,
        object: nil
    )
    #expect(await enterpriseEventually { lifecycleState.isSleeping })
    #expect(timerProbe.current?.isInvalidated == true)

    NSWorkspace.shared.notificationCenter.post(
        name: NSWorkspace.didWakeNotification,
        object: nil
    )
    #expect(await enterpriseEventually { !lifecycleState.isSleeping })
    #expect(timerProbe.current?.isInvalidated == false)

    NSWorkspace.shared.notificationCenter.post(
        name: NSWorkspace.sessionDidResignActiveNotification,
        object: nil
    )
    #expect(await enterpriseEventually { lifecycleState.isSessionLocked })

    NSWorkspace.shared.notificationCenter.post(
        name: NSWorkspace.sessionDidBecomeActiveNotification,
        object: nil
    )
    #expect(await enterpriseEventually { !lifecycleState.isSessionLocked })
    monitor.stop()
}

@MainActor
@Test(arguments: EnterpriseMonitorInjectedFailure.allCases)
func payloadImportErrorsMapToExplicitProcessingReasons(
    failure: EnterpriseMonitorInjectedFailure
) async {
    let payload = ClipboardPayloadStagingPasteboardProbe(
        changeCount: 1,
        imageData: Data([0x01, 0x02])
    )
    let fileSystemProbe = PayloadStagingFileSystemProbe()
    var updates: [ClipboardPayloadProcessingUpdate] = []
    let monitor = makePayloadStagingMonitor(
        payload: payload,
        stager: ClipboardPayloadStager(
            directoryProvider: {
                URL(
                    fileURLWithPath: "/test/enterprise-monitor-\(failure.rawValue)",
                    isDirectory: true
                )
            },
            fileSystem: fileSystemProbe.fileSystem
        ),
        payloadImporter: { _ in
            try failure.throwError()
        },
        statusRecorder: { updates.append($0) }
    )

    payload.changeCount = 2
    monitor.start()
    #expect(await monitor.waitForPayloadImportsForTesting())
    #expect(updates.contains { $0.status == .failed(failure.expectedReason) })
    #expect(!updates.contains { $0.status == .completed })
    await monitor.stopAndDrainPayloads()
}

@MainActor
@Test func rawPayloadAdmissionFailureIsExplicitAndStartsNoDetachedWrite() async {
    let payload = ClipboardPayloadStagingPasteboardProbe(
        changeCount: 1,
        imageData: Data([0x01, 0x02])
    )
    let fileSystemProbe = PayloadStagingFileSystemProbe()
    var updates: [ClipboardPayloadProcessingUpdate] = []
    let monitor = makePayloadStagingMonitor(
        payload: payload,
        stager: ClipboardPayloadStager(
            maximumResidentTasks: 1,
            maximumRetainedBytes: 1,
            directoryProvider: {
                URL(fileURLWithPath: "/test/enterprise-capacity", isDirectory: true)
            },
            fileSystem: fileSystemProbe.fileSystem
        ),
        payloadImporter: { _ in
            throw EnterpriseMonitorFixtureError.unexpectedPayload
        },
        statusRecorder: { updates.append($0) }
    )

    payload.changeCount = 2
    monitor.start()
    #expect(await monitor.waitForPayloadImportsForTesting())
    #expect(
        updates.contains {
            $0.status == .deferred(.retainedDataLimitExceeded)
        }
    )
    #expect(
        !updates.contains {
            $0.status == .failed(.retainedDataLimitExceeded)
        }
    )
    #expect(fileSystemProbe.writeCount == 0)
    await monitor.stopAndDrainPayloads()
}

@MainActor
@Test func stagedRichTextURLAndColorKeepTheirSemanticClipboardTypes() async {
    for (plainText, expectedType) in [
        ("https://example.com/enterprise", ClipboardItemType.link),
        ("#AABBCC", ClipboardItemType.color),
    ] {
        let payload = ClipboardPayloadStagingPasteboardProbe(
            changeCount: 1,
            imageData: Data("{\\rtf1 test}".utf8),
            pasteboardType: .rtf
        )
        let fileSystemProbe = PayloadStagingFileSystemProbe()
        let store = ClipboardHistoryStore(
            persistence: ClipboardHistoryPersistence(
                repository: ClipboardPayloadStagingEmptyRepository()
            ),
            externalCopyFeedback: { _ in }
        )
        let monitor = makePayloadStagingMonitor(
            payload: payload,
            stager: ClipboardPayloadStager(
                directoryProvider: {
                    URL(
                        fileURLWithPath: "/test/enterprise-rich-text-\(UUID().uuidString)",
                        isDirectory: true
                    )
                },
                fileSystem: fileSystemProbe.fileSystem
            ),
            payloadImporter: { request in
                guard case .richText(let stagedPayload, _) = request else {
                    throw EnterpriseMonitorFixtureError.unexpectedPayload
                }
                return .richText(
                    ClipboardRichTextImportResult(
                        data: Data(),
                        plainText: plainText,
                        rawAsset: ClipboardRichTextRawAsset(
                            stagedPayload: stagedPayload,
                            storage: .primaryRTF
                        )
                    )
                )
            },
            store: store
        )

        payload.changeCount = 2
        monitor.start()
        #expect(await monitor.waitForPayloadImportsForTesting())
        #expect(store.items.first?.type == expectedType)
        #expect(store.items.first?.text == plainText)
        await monitor.stopAndDrainPayloads()
    }
}

enum EnterpriseMonitorInjectedFailure: String, CaseIterable, Sendable {
    case imageDiskFull
    case imageWriteFailed
    case imageThumbnailFailed
    case imageEncodingFailed
    case imageOutputTooLarge
    case fileSystemDiskFull
    case generic

    var expectedReason: ClipboardPayloadProcessingReason {
        switch self {
        case .imageDiskFull, .fileSystemDiskFull:
            .diskFull
        case .imageWriteFailed, .imageThumbnailFailed:
            .atomicWriteFailed
        case .imageEncodingFailed, .imageOutputTooLarge, .generic:
            .importFailed
        }
    }

    func throwError() throws -> Never {
        switch self {
        case .imageDiskFull:
            throw ClipboardImageStagingError.diskFull
        case .imageWriteFailed:
            throw ClipboardImageStagingError.writeFailed
        case .imageThumbnailFailed:
            throw ClipboardImageStagingError.thumbnailFailed
        case .imageEncodingFailed:
            throw ClipboardImageStagingError.encodingFailed
        case .imageOutputTooLarge:
            throw ClipboardImageStagingError.outputTooLarge
        case .fileSystemDiskFull:
            throw NSError(
                domain: NSPOSIXErrorDomain,
                code: Int(POSIXErrorCode.ENOSPC.rawValue)
            )
        case .generic:
            throw NSError(
                domain: NSCocoaErrorDomain,
                code: NSFileReadUnknownError
            )
        }
    }
}

private enum EnterpriseMonitorFixtureError: Error {
    case unexpectedPayload
}

@MainActor
private func enterpriseEventually(
    _ condition: @MainActor () -> Bool
) async -> Bool {
    for _ in 0..<1_000 {
        if condition() {
            return true
        }
        await Task.yield()
    }
    return condition()
}

@MainActor
private final class EnterpriseMonitorTimerToken: ClipboardMonitorTimerToken {
    let timeInterval: TimeInterval
    var tolerance: TimeInterval = 0
    private(set) var isInvalidated = false

    init(timeInterval: TimeInterval) {
        self.timeInterval = timeInterval
    }

    func invalidate() {
        isInvalidated = true
    }
}

@MainActor
private final class EnterpriseMonitorTimerProbe {
    private(set) var tokens: [EnterpriseMonitorTimerToken] = []

    var current: EnterpriseMonitorTimerToken? {
        tokens.last
    }

    lazy var scheduler = ClipboardMonitorTimerScheduler { [weak self] interval, _ in
        let token = EnterpriseMonitorTimerToken(timeInterval: interval)
        self?.tokens.append(token)
        return token
    }
}
