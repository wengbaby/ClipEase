import Foundation
import Testing
@testable import ClipEase

@MainActor
@Test func monitorCapsOwnershipAtSixtyEightAndRetriesTheNextPasteboardChange() async {
    let payload = ClipboardPayloadStagingPasteboardProbe(
        changeCount: 1,
        imageData: Data([0x01])
    )
    let gate = PayloadImportBlockingGate()
    let fileSystemProbe = PayloadStagingFileSystemProbe()
    var updates: [ClipboardPayloadProcessingUpdate] = []
    let monitor = makePayloadStagingMonitor(
        payload: payload,
        stager: ClipboardPayloadStager(
            directoryProvider: { URL(fileURLWithPath: "/test/payload-staging") },
            fileSystem: fileSystemProbe.fileSystem
        ),
        payloadImporter: { request in
            try await gate.importPayload(request)
        },
        statusRecorder: { updates.append($0) }
    )
    monitor.start()
    for changeCount in 2...69 {
        payload.changeCount = changeCount
        _ = monitor.pollNow()
        await Task.yield()
    }

    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: .seconds(5))
    while monitor.payloadImportPumpDiagnosticsForTesting.ownedRequestCount < 68,
          clock.now < deadline {
        await Task.yield()
    }
    #expect(monitor.payloadImportPumpDiagnosticsForTesting.ownedRequestCount == 68)
    payload.changeCount = 70
    #expect(monitor.pollNow() == nil)
    #expect(monitor.payloadImportPumpDiagnosticsForTesting.ownedRequestCount == 68)
    #expect(!updates.contains {
        $0.status == .failed(.residentTaskLimitExceeded)
            || $0.status == .deferred(.residentTaskLimitExceeded)
    })

    for index in 0..<68 {
        #expect(await gate.waitForCallCount(index + 1))
        await gate.resumeCall(at: index)
    }
    #expect(await monitor.waitForPayloadImportsForTesting())
    #expect(await gate.callCount == 68)

    _ = monitor.pollNow()
    #expect(await gate.waitForCallCount(69))
    await gate.resumeCall(at: 68)
    #expect(await monitor.waitForPayloadImportsForTesting())
    #expect(await gate.callCount == 69)
    await monitor.stopAndDrainPayloads()
}

@MainActor
@Test func reverseStagingCompletionStillImportsInPasteboardCaptureOrder() async {
    let payload = ClipboardPayloadStagingPasteboardProbe(
        changeCount: 1,
        imageData: Data([0x01])
    )
    let fileSystemProbe = ReverseCompletionPayloadStagingFileSystemProbe()
    let importOrder = PayloadImportOrderProbe()
    let monitor = makePayloadStagingMonitor(
        payload: payload,
        stager: ClipboardPayloadStager(
            directoryProvider: { URL(fileURLWithPath: "/test/payload-staging") },
            fileSystem: fileSystemProbe.fileSystem
        ),
        payloadImporter: { request in
            try await importOrder.importPayload(request)
        }
    )

    payload.changeCount = 2
    monitor.start()
    payload.imageData = Data([0x02])
    payload.changeCount = 3
    _ = monitor.pollNow()
    #expect(await fileSystemProbe.waitForSecondWrite())
    await Task.yield()
    #expect(await importOrder.importedValues.isEmpty)

    fileSystemProbe.releaseFirstWrite()
    #expect(await monitor.waitForPayloadImportsForTesting())
    #expect(await importOrder.importedValues == [0x01, 0x02])
    await monitor.stopAndDrainPayloads()
}

@MainActor
@Test func terminationDrainFinishesEveryAcceptedPayloadInsteadOfClearingTheQueue() async {
    let payload = ClipboardPayloadStagingPasteboardProbe(
        changeCount: 1,
        imageData: Data([0x01])
    )
    let gate = PayloadImportBlockingGate()
    let fileSystemProbe = PayloadStagingFileSystemProbe()
    var updates: [ClipboardPayloadProcessingUpdate] = []
    let monitor = makePayloadStagingMonitor(
        payload: payload,
        stager: ClipboardPayloadStager(
            directoryProvider: { URL(fileURLWithPath: "/test/payload-staging") },
            fileSystem: fileSystemProbe.fileSystem
        ),
        payloadImporter: { request in
            try await gate.importPayload(request)
        },
        statusRecorder: { updates.append($0) }
    )
    monitor.start()
    for changeCount in 2...4 {
        payload.changeCount = changeCount
        _ = monitor.pollNow()
        await Task.yield()
    }
    #expect(await gate.waitForCallCount(1))

    let drainTask = Task { @MainActor in
        await monitor.stopAndDrainPayloads()
    }
    for index in 0..<3 {
        #expect(await gate.waitForCallCount(index + 1))
        await gate.resumeCall(at: index)
    }
    await drainTask.value

    #expect(await gate.callCount == 3)
    #expect(!updates.contains { $0.status == .deferred(.staleGeneration) })
}
