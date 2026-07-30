import AppKit
import Foundation
import Testing
@testable import ClipEase

@Test func payloadStagerMapsDiskFullToExplicitFailure() async {
    let probe = PayloadStagingFileSystemProbe(
        writeError: NSError(
            domain: NSPOSIXErrorDomain,
            code: Int(POSIXErrorCode.ENOSPC.rawValue)
        )
    )
    let stager = ClipboardPayloadStager(
        directoryProvider: { URL(fileURLWithPath: "/test/payload-staging") },
        fileSystem: probe.fileSystem
    )

    do {
        _ = try await stager.stage(
            ClipboardPayloadStagingSource(
                data: Data([0x01]),
                contentKind: .image
            )
        )
        Issue.record("Disk-full staging must not return a staged payload")
    } catch let error as ClipboardPayloadStagingError {
        #expect(error == .diskFull)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }

    let diagnostics = stager.diagnostics
    #expect(diagnostics.residentTaskCount == 0)
    #expect(diagnostics.retainedByteCount == 0)
    #expect(probe.writeCount == 1)
}

@Test func payloadStagerFindsDiskFullInsideFoundationUnderlyingError() {
    let wrapped = NSError(
        domain: NSCocoaErrorDomain,
        code: NSFileWriteUnknownError,
        userInfo: [
            NSUnderlyingErrorKey: NSError(
                domain: NSPOSIXErrorDomain,
                code: Int(POSIXErrorCode.ENOSPC.rawValue)
            )
        ]
    )

    #expect(ClipboardPayloadStager.stagingError(for: wrapped) == .diskFull)
}

@Test func payloadStagerMapsAtomicWriteFailureAndNeverReturnsSuccess() async {
    let probe = PayloadStagingFileSystemProbe(
        writeError: NSError(
            domain: NSCocoaErrorDomain,
            code: NSFileWriteUnknownError
        )
    )
    let stager = ClipboardPayloadStager(
        directoryProvider: { URL(fileURLWithPath: "/test/payload-staging") },
        fileSystem: probe.fileSystem
    )

    do {
        _ = try await stager.stage(
            ClipboardPayloadStagingSource(
                data: Data([0x02]),
                contentKind: .richTextRTF
            )
        )
        Issue.record("A failed atomic write must not return a staged payload")
    } catch let error as ClipboardPayloadStagingError {
        #expect(error == .atomicWriteFailed)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }

    #expect(probe.writeCount == 1)
}

@Test func stagedOriginalPromotionMapsDiskFullAndRemainsCleanable() async throws {
    let probe = PayloadStagingFileSystemProbe(
        moveError: NSError(
            domain: NSPOSIXErrorDomain,
            code: Int(POSIXErrorCode.ENOSPC.rawValue)
        )
    )
    let stager = ClipboardPayloadStager(
        directoryProvider: { URL(fileURLWithPath: "/test/payload-staging") },
        fileSystem: probe.fileSystem
    )
    let staged = try await stager.stage(
        ClipboardPayloadStagingSource(
            data: Data([0x01]),
            contentKind: .image,
            preferredFileExtension: "png"
        )
    )

    #expect(throws: ClipboardPayloadStagingError.diskFull) {
        try staged.promote(to: URL(fileURLWithPath: "/test/images/original.png"))
    }
    staged.discard()
    #expect(probe.removeCount == 1)
}

@Test func stagedPayloadReadFailureIsExplicitAndDiscardIsIdempotent() throws {
    let probe = PayloadStagingFileSystemProbe(
        readError: NSError(
            domain: NSCocoaErrorDomain,
            code: NSFileReadUnknownError
        )
    )
    let payload = ClipboardStagedPayload(
        id: UUID(),
        fileURL: URL(fileURLWithPath: "/test/payload-staging/payload.rtf"),
        byteCount: 32,
        contentKind: .richTextRTF,
        fileSystem: probe.fileSystem
    )

    do {
        _ = try payload.readData()
        Issue.record("Unreadable staged data must not be treated as an empty payload")
    } catch let error as ClipboardPayloadStagingError {
        #expect(error == .stagedFileUnreadable)
    }

    payload.discard()
    payload.discard()
    #expect(probe.removeCount == 1)
}

@Test func failedDiscardIsRetriedAndStartupScavengerRemovesAbandonedPayloads() async throws {
    let staleURL = URL(
        fileURLWithPath: "/test/payload-staging/\(UUID().uuidString).pdf"
    )
    let probe = PayloadStagingFileSystemProbe(
        removeFailureCount: 4,
        directoryContents: [staleURL]
    )
    let stager = ClipboardPayloadStager(
        directoryProvider: { URL(fileURLWithPath: "/test/payload-staging") },
        fileSystem: probe.fileSystem
    )

    let staged = try await stager.stage(
        ClipboardPayloadStagingSource(
            data: Data([0x01]),
            contentKind: .image
        )
    )
    staged.discard()
    if await stager.pendingCleanupCount > 0 {
        await stager.drainCleanup(maximumAttempts: 3)
    }
    #expect(await stager.pendingCleanupCount == 0)
    #expect(probe.removedURLs.contains(staleURL))
    #expect(probe.removeCount >= 6)
}

@Test func startupScavengerRetriesAfterATransientDirectoryReadFailure() async throws {
    let abandonedURL = URL(
        fileURLWithPath: "/test/payload-staging/\(UUID().uuidString).pdf"
    )
    let probe = PayloadStagingFileSystemProbe(
        contentsFailureCount: 1,
        directoryContents: [abandonedURL]
    )
    let stager = ClipboardPayloadStager(
        directoryProvider: { URL(fileURLWithPath: "/test/payload-staging") },
        fileSystem: probe.fileSystem
    )
    let source = ClipboardPayloadStagingSource(
        data: Data([0x01]),
        contentKind: .image
    )

    await #expect(throws: ClipboardPayloadStagingError.atomicWriteFailed) {
        _ = try await stager.stage(source)
    }
    let staged = try await stager.stage(source)
    staged.discard()
    await stager.drainCleanup()

    #expect(probe.contentsCallCount == 2)
    #expect(probe.removedURLs.contains(abandonedURL))
}

@Test func explicitInitializationAndDrainCleanupRunBoundedScavenging() async throws {
    let directoryURL = URL(fileURLWithPath: "/test/payload-staging")
    let staleURLs = (0..<5).map { _ in
        directoryURL.appendingPathComponent("\(UUID().uuidString).pdf")
    }
    let initializationProbe = PayloadStagingFileSystemProbe(
        directoryContents: staleURLs
    )
    let initializationStager = ClipboardPayloadStager(
        maximumScavengedEntryCount: 2,
        directoryProvider: { directoryURL },
        fileSystem: initializationProbe.fileSystem
    )

    try await initializationStager.initializeAndScavenge()

    #expect(initializationProbe.contentsCallCount == 1)
    #expect(initializationProbe.removedURLs.count == 2)

    let drainProbe = PayloadStagingFileSystemProbe(
        directoryContents: [staleURLs[0]]
    )
    let drainStager = ClipboardPayloadStager(
        directoryProvider: { directoryURL },
        fileSystem: drainProbe.fileSystem
    )

    await drainStager.drainCleanup()

    #expect(drainProbe.contentsCallCount == 1)
    #expect(drainProbe.removedURLs == [staleURLs[0]])
}

@Test func liveStagingUsesControlledUUIDNamesAndPrivatePermissions() async throws {
    let fileManager = FileManager.default
    let rootURL = fileManager.temporaryDirectory.appendingPathComponent(
        "ClipEase-Staging-Permissions-\(UUID().uuidString)",
        isDirectory: true
    )
    defer { try? fileManager.removeItem(at: rootURL) }
    let stagingURL = rootURL.appendingPathComponent(
        "PayloadStaging",
        isDirectory: true
    )
    let stager = ClipboardPayloadStager(directoryProvider: { stagingURL })
    let bytes = Data([0x89, 0x50, 0x4E, 0x47])

    let staged = try await stager.stage(
        ClipboardPayloadStagingSource(
            data: bytes,
            contentKind: .image,
            preferredFileExtension: "../../executable"
        )
    )
    defer { staged.discard() }

    #expect(UUID(uuidString: staged.fileURL.deletingPathExtension().lastPathComponent) != nil)
    #expect(staged.fileURL.pathExtension == "image")
    #expect(try staged.readData() == bytes)
    let directoryAttributes = try fileManager.attributesOfItem(
        atPath: stagingURL.path
    )
    let fileAttributes = try fileManager.attributesOfItem(
        atPath: staged.fileURL.path
    )
    #expect((directoryAttributes[.posixPermissions] as? NSNumber)?.intValue == 0o700)
    #expect((fileAttributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
}

@Test func liveStagingRejectsSymlinkedParentWithoutTouchingTarget() async throws {
    let fileManager = FileManager.default
    let rootURL = fileManager.temporaryDirectory.appendingPathComponent(
        "ClipEase-Staging-Parent-Link-\(UUID().uuidString)",
        isDirectory: true
    )
    let outsideURL = fileManager.temporaryDirectory.appendingPathComponent(
        "ClipEase-Staging-Outside-\(UUID().uuidString)",
        isDirectory: true
    )
    defer {
        try? fileManager.removeItem(at: rootURL)
        try? fileManager.removeItem(at: outsideURL)
    }
    try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: outsideURL, withIntermediateDirectories: true)
    let markerURL = outsideURL.appendingPathComponent("marker.txt")
    try Data("untouched".utf8).write(to: markerURL)
    let linkedParentURL = rootURL.appendingPathComponent("linked-parent")
    try fileManager.createSymbolicLink(
        at: linkedParentURL,
        withDestinationURL: outsideURL
    )
    let stager = ClipboardPayloadStager(
        directoryProvider: {
            linkedParentURL.appendingPathComponent(
                "PayloadStaging",
                isDirectory: true
            )
        }
    )

    await #expect(throws: ClipboardPayloadStagingError.atomicWriteFailed) {
        try await stager.initializeAndScavenge()
    }

    #expect(try Data(contentsOf: markerURL) == Data("untouched".utf8))
    #expect(!fileManager.fileExists(
        atPath: outsideURL.appendingPathComponent("PayloadStaging").path
    ))
}

@Test func liveScavengerUnlinksSymlinkEntryWithoutTouchingTarget() async throws {
    let fileManager = FileManager.default
    let rootURL = fileManager.temporaryDirectory.appendingPathComponent(
        "ClipEase-Staging-Entry-Link-\(UUID().uuidString)",
        isDirectory: true
    )
    let outsideURL = fileManager.temporaryDirectory.appendingPathComponent(
        "ClipEase-Staging-Entry-Outside-\(UUID().uuidString)",
        isDirectory: true
    )
    defer {
        try? fileManager.removeItem(at: rootURL)
        try? fileManager.removeItem(at: outsideURL)
    }
    let stagingURL = rootURL.appendingPathComponent(
        "PayloadStaging",
        isDirectory: true
    )
    try ClipboardPayloadStagingFileSystem.live.createDirectory(stagingURL)
    try fileManager.createDirectory(at: outsideURL, withIntermediateDirectories: true)
    let markerURL = outsideURL.appendingPathComponent("marker.txt")
    try Data("untouched".utf8).write(to: markerURL)
    let symlinkURL = stagingURL.appendingPathComponent(
        "\(UUID().uuidString).pdf"
    )
    try fileManager.createSymbolicLink(
        at: symlinkURL,
        withDestinationURL: markerURL
    )
    let stager = ClipboardPayloadStager(directoryProvider: { stagingURL })

    try await stager.initializeAndScavenge()

    #expect(try Data(contentsOf: markerURL) == Data("untouched".utf8))
    #expect(!fileManager.fileExists(atPath: symlinkURL.path))
}

@Test func richTextStagingEnvelopeRoundTripsWithoutQueueingClipboardText() throws {
    let original = ClipboardRichTextPasteboardPayload.html(
        data: Data("<b>ClipEase</b>".utf8),
        fallbackPlainText: "ClipEase"
    )
    let source = ClipboardRichTextStagingEnvelope.encode(original)
    let decoded = try ClipboardRichTextStagingEnvelope.decode(
        source.data,
        contentKind: source.contentKind
    )

    guard case .html(let data, let fallbackPlainText) = decoded else {
        Issue.record("Expected an HTML staging envelope")
        return
    }
    #expect(data == Data("<b>ClipEase</b>".utf8))
    #expect(fallbackPlainText == "ClipEase")
}

@Test func richTextStagingEnvelopeRejectsMaliciousMaximumLengthWithoutTrapping() {
    var malicious = Data("CERT1".utf8)
    malicious.append(0)
    var maximumLength = UInt64.max.bigEndian
    withUnsafeBytes(of: &maximumLength) {
        malicious.append(contentsOf: $0)
    }

    #expect(throws: ClipboardPayloadStagingError.stagedFileUnreadable) {
        _ = try ClipboardRichTextStagingEnvelope.decode(
            malicious,
            contentKind: .richTextRTF
        )
    }
}

@MainActor
@Test func payloadProcessingFailuresHaveUserVisibleBoundedMessages() {
    #expect(
        ClipboardPayloadProcessingStatusPresenter.userVisibleMessage(
            for: .failed(.diskFull)
        ) == L("磁盘空间不足，剪贴板内容未保存")
    )
    #expect(
        ClipboardPayloadProcessingStatusPresenter.userVisibleMessage(
            for: .failed(.atomicWriteFailed)
        ) == L("剪贴板内容未能保存")
    )
    #expect(
        ClipboardPayloadProcessingStatusPresenter.userVisibleMessage(
            for: .completed
        ) == nil
    )
    #expect(
        ClipboardPayloadProcessingStatusPresenter.userVisibleMessage(
            for: .skipped(.selfWrite)
        ) == nil
    )
}

@Test func pdfPayloadUsesAppOwnedStagingReferenceAndDeterministicCleanup() async throws {
    let probe = PayloadStagingFileSystemProbe()
    let ownedDirectory = URL(fileURLWithPath: "/test/app-support/PayloadStaging")
    let stager = ClipboardPayloadStager(
        directoryProvider: { ownedDirectory },
        fileSystem: probe.fileSystem
    )

    let stagedPayload = try await stager.stage(
        ClipboardPayloadStagingSource(
            data: Data("%PDF-1.7".utf8),
            contentKind: .pdf
        )
    )

    #expect(stagedPayload.contentKind == .pdf)
    #expect(
        stagedPayload.fileURL.deletingLastPathComponent().standardizedFileURL.path
            == ownedDirectory.standardizedFileURL.path
    )
    #expect(stagedPayload.fileURL.pathExtension == "pdf")
    #expect(stager.diagnostics.residentTaskCount == 0)
    #expect(stager.diagnostics.retainedByteCount == 0)
    stagedPayload.discard()
    #expect(probe.removeCount == 1)
    #expect(stager.diagnostics.residentTaskCount == 0)
    #expect(stager.diagnostics.retainedByteCount == 0)
}

@Test func durableStagedFileReferenceImmediatelyReleasesRawMemoryLease() async throws {
    let probe = PayloadStagingFileSystemProbe()
    let stager = ClipboardPayloadStager(
        maximumResidentTasks: 4,
        maximumRetainedBytes: 128,
        directoryProvider: { URL(fileURLWithPath: "/test/payload-staging") },
        fileSystem: probe.fileSystem
    )
    let source = ClipboardPayloadStagingSource(
        data: Data(repeating: 0x5A, count: 32),
        contentKind: .image
    )

    var stagedPayloads: [ClipboardStagedPayload] = []
    for _ in 0..<30 {
        stagedPayloads.append(try await stager.stage(source))
    }
    #expect(stager.diagnostics.residentTaskCount == 0)
    #expect(stager.diagnostics.retainedByteCount == 0)
    #expect(stager.diagnostics.rejectedTaskCount == 0)
    stagedPayloads.forEach { $0.discard() }
}

@Test func thirtyIndependentEightMiBImagesApplyDeterministicMemoryBackpressure() async {
    let probe = BlockingPayloadStagingFileSystemProbe()
    let stager = ClipboardPayloadStager(
        maximumResidentTasks: 4,
        maximumRetainedBytes: 128 * 1_024 * 1_024,
        directoryProvider: { URL(fileURLWithPath: "/test/payload-staging") },
        fileSystem: probe.fileSystem
    )
    let payloadByteCount = 8 * 1_024 * 1_024
    var acceptedReservations: [(Int, ClipboardPayloadStagingReservation)] = []
    var reservationFailures: [ClipboardPayloadStagingError] = []
    for index in 0..<30 {
        do {
            acceptedReservations.append((
                index,
                try stager.reserveImmediately(byteCount: payloadByteCount)
            ))
        } catch let error as ClipboardPayloadStagingError {
            reservationFailures.append(error)
        } catch {
            reservationFailures.append(.atomicWriteFailed)
        }
    }

    #expect(acceptedReservations.count == 16)
    #expect(reservationFailures.count == 14)
    #expect(reservationFailures.allSatisfy { $0 == .retainedDataLimitExceeded })
    #expect(stager.diagnostics.residentTaskCount == 4)
    #expect(stager.diagnostics.waitingTaskCount == 12)
    #expect(stager.diagnostics.retainedByteCount == 128 * 1_024 * 1_024)
    #expect(stager.diagnostics.rejectedTaskCount == 14)

    let tasks = acceptedReservations.map { index, reservation in
        let source = ClipboardPayloadStagingSource(
            data: Data(
                repeating: UInt8(truncatingIfNeeded: index),
                count: payloadByteCount
            ),
            contentKind: .image
        )
        return Task {
            try await stager.stage(source, reservation: reservation)
        }
    }
    guard await probe.waitForStartedWriteCount(4) else {
        tasks.forEach { $0.cancel() }
        probe.releaseWrites(16)
        Issue.record("Timed out waiting for four bounded staging writes")
        for task in tasks {
            _ = try? await task.value
        }
        return
    }
    #expect(stager.diagnostics.residentTaskCount == 4)
    #expect(stager.diagnostics.retainedByteCount == 128 * 1_024 * 1_024)
    #expect(stager.diagnostics.waitingTaskCount == 12)
    #expect(probe.maximumConcurrentWriteCount == 4)

    probe.releaseWrites(16)
    var successfulPayloads: [ClipboardStagedPayload] = []
    for task in tasks {
        if let payload = try? await task.value {
            successfulPayloads.append(payload)
        }
    }

    #expect(successfulPayloads.count == 16)
    #expect(stager.diagnostics.residentTaskCount == 0)
    #expect(stager.diagnostics.retainedByteCount == 0)
    #expect(stager.diagnostics.waitingTaskCount == 0)
    #expect(probe.maximumConcurrentWriteCount <= 4)
    successfulPayloads.forEach { $0.discard() }
    #expect(stager.diagnostics.residentTaskCount == 0)
    #expect(stager.diagnostics.retainedByteCount == 0)
}

@Test func thirtySequentialEightMiBImagesAllReachDurableStaging() async throws {
    let probe = PayloadStagingFileSystemProbe()
    let stager = ClipboardPayloadStager(
        maximumResidentTasks: 4,
        maximumRetainedBytes: 128 * 1_024 * 1_024,
        directoryProvider: { URL(fileURLWithPath: "/test/payload-staging") },
        fileSystem: probe.fileSystem
    )
    let payloadByteCount = 8 * 1_024 * 1_024

    for index in 0..<30 {
        let reservation = try stager.reserveImmediately(
            byteCount: payloadByteCount
        )
        let staged = try await stager.stage(
            ClipboardPayloadStagingSource(
                data: Data(
                    repeating: UInt8(truncatingIfNeeded: index),
                    count: payloadByteCount
                ),
                contentKind: .image
            ),
            reservation: reservation
        )
        #expect(staged.byteCount == payloadByteCount)
        staged.discard()
    }

    #expect(stager.diagnostics.residentTaskCount == 0)
    #expect(stager.diagnostics.retainedByteCount == 0)
    #expect(stager.diagnostics.waitingTaskCount == 0)
    #expect(stager.diagnostics.rejectedTaskCount == 0)
}

@Test func cancelledCapacityWaiterCompletesWithoutLeakingItsReservation() async throws {
    let probe = BlockingPayloadStagingFileSystemProbe()
    let stager = ClipboardPayloadStager(
        maximumResidentTasks: 1,
        maximumRetainedBytes: 16,
        directoryProvider: { URL(fileURLWithPath: "/test/payload-staging") },
        fileSystem: probe.fileSystem
    )
    let source = ClipboardPayloadStagingSource(
        data: Data(repeating: 0x5A, count: 8),
        contentKind: .image
    )
    let activeReservation = try stager.reserveImmediately(byteCount: 8)
    let activeTask = Task {
        try await stager.stage(source, reservation: activeReservation)
    }
    guard await probe.waitForStartedWriteCount(1) else {
        activeTask.cancel()
        probe.releaseWrites(1)
        Issue.record("Timed out waiting for the active staging write")
        return
    }

    let waitingReservation = try stager.reserveImmediately(byteCount: 8)
    let waitingTask = Task { () -> Bool in
        do {
            _ = try await stager.stage(
                source,
                reservation: waitingReservation
            )
            return false
        } catch is CancellationError {
            return true
        } catch {
            return false
        }
    }
    let deadline = ContinuousClock().now.advanced(by: .seconds(2))
    while stager.diagnostics.waitingTaskCount < 1,
          ContinuousClock().now < deadline {
        await Task.yield()
    }
    #expect(stager.diagnostics.waitingTaskCount == 1)
    #expect(stager.diagnostics.retainedByteCount == 16)

    waitingTask.cancel()
    #expect(await waitingTask.value)
    #expect(stager.diagnostics.waitingTaskCount == 0)
    #expect(stager.diagnostics.retainedByteCount == 8)

    probe.releaseWrites(1)
    let staged = try await activeTask.value
    staged.discard()
    #expect(stager.diagnostics.residentTaskCount == 0)
    #expect(stager.diagnostics.retainedByteCount == 0)
}

@Test func immediateReservationCapsWaiterCountAndConservesBytes() throws {
    let fileSystemProbe = PayloadStagingFileSystemProbe()
    let stager = ClipboardPayloadStager(
        maximumResidentTasks: 1,
        maximumRetainedBytes: 64,
        maximumWaitingCount: 2,
        directoryProvider: { URL(fileURLWithPath: "/test/payload-staging") },
        fileSystem: fileSystemProbe.fileSystem
    )
    let active = try stager.reserveImmediately(byteCount: 8)
    let firstWaiter = try stager.reserveImmediately(byteCount: 16)
    let secondWaiter = try stager.reserveImmediately(byteCount: 24)

    #expect(stager.diagnostics.residentTaskCount == 1)
    #expect(stager.diagnostics.waitingTaskCount == 2)
    #expect(stager.diagnostics.retainedByteCount == 48)
    #expect(throws: ClipboardPayloadStagingError.retainedDataLimitExceeded) {
        _ = try stager.reserveImmediately(byteCount: 1)
    }
    #expect(stager.diagnostics.rejectedTaskCount == 1)
    #expect(stager.diagnostics.retainedByteCount == 48)

    firstWaiter.release()
    #expect(stager.diagnostics.waitingTaskCount == 1)
    #expect(stager.diagnostics.retainedByteCount == 32)
    secondWaiter.release()
    active.release()
    #expect(stager.diagnostics.residentTaskCount == 0)
    #expect(stager.diagnostics.waitingTaskCount == 0)
    #expect(stager.diagnostics.retainedByteCount == 0)
}

@MainActor
@Test func clipboardMonitorReportsDiskFullWithoutCallingImporter() async {
    let payload = ClipboardPayloadStagingPasteboardProbe(
        changeCount: 1,
        imageData: Data([0x01, 0x02])
    )
    let fileSystemProbe = PayloadStagingFileSystemProbe(
        writeError: NSError(
            domain: NSPOSIXErrorDomain,
            code: Int(POSIXErrorCode.ENOSPC.rawValue)
        )
    )
    let importerProbe = ClipboardPayloadImporterCallProbe()
    var statusUpdates: [ClipboardPayloadProcessingUpdate] = []
    var diagnosticEvents: [ClipboardMonitorImportDiagnosticEvent] = []
    let monitor = makePayloadStagingMonitor(
        payload: payload,
        stager: ClipboardPayloadStager(
            directoryProvider: { URL(fileURLWithPath: "/test/payload-staging") },
            fileSystem: fileSystemProbe.fileSystem
        ),
        payloadImporter: { request in
            await importerProbe.record(request)
            throw ClipboardPayloadStagingError.atomicWriteFailed
        },
        statusRecorder: { statusUpdates.append($0) },
        diagnosticRecorder: { diagnosticEvents.append($0) }
    )

    payload.changeCount = 2
    monitor.start()
    #expect(await monitor.waitForPayloadImportsForTesting())

    #expect(await importerProbe.callCount == 0)
    #expect(statusUpdates.contains { $0.status == .failed(.diskFull) })
    #expect(!statusUpdates.contains { $0.status == .completed })
    #expect(diagnosticEvents == [.failure(capturedType: "image")])
    let writeCountAfterFailure = fileSystemProbe.writeCount
    _ = monitor.pollNow()
    await Task.yield()
    #expect(fileSystemProbe.writeCount == writeCountAfterFailure)
    monitor.stop()
}

@MainActor
@Test func monitorQueuesOnlyStagedReferenceAndCleansItAfterImporterFailure() async {
    let payload = ClipboardPayloadStagingPasteboardProbe(
        changeCount: 1,
        imageData: Data([0x05, 0x06])
    )
    let fileSystemProbe = PayloadStagingFileSystemProbe()
    let importerProbe = ClipboardPayloadImporterCallProbe()
    let ownedDirectory = URL(fileURLWithPath: "/test/app-support/PayloadStaging")
    var statusUpdates: [ClipboardPayloadProcessingUpdate] = []
    let monitor = makePayloadStagingMonitor(
        payload: payload,
        stager: ClipboardPayloadStager(
            directoryProvider: { ownedDirectory },
            fileSystem: fileSystemProbe.fileSystem
        ),
        payloadImporter: { request in
            await importerProbe.record(request)
            throw ClipboardPayloadStagingError.stagedFileUnreadable
        },
        statusRecorder: { statusUpdates.append($0) }
    )

    payload.changeCount = 2
    monitor.start()
    #expect(await monitor.waitForPayloadImportsForTesting())

    let request = await importerProbe.lastRequest
    guard let request,
          case .image(let stagedPayload, _) = request else {
        Issue.record("Expected a staged image reference")
        monitor.stop()
        return
    }
    #expect(
        stagedPayload.fileURL.deletingLastPathComponent().standardizedFileURL.path
            == ownedDirectory.standardizedFileURL.path
    )
    #expect(await importerProbe.callCount == 1)
    #expect(fileSystemProbe.removeCount == 1)
    #expect(statusUpdates.contains { $0.status == .failed(.stagedFileUnreadable) })
    #expect(!statusUpdates.contains { $0.status == .completed })
    monitor.stop()
}

@MainActor
@Test func imageSelfWriteIsSilentlySkippedWithoutFailureToastOrHistoryCommit() async {
    let payload = ClipboardPayloadStagingPasteboardProbe(
        changeCount: 1,
        imageData: Data([0x89, 0x50, 0x4E, 0x47])
    )
    let persistence = ClipboardHistoryPersistence(
        repository: ClipboardPayloadStagingEmptyRepository()
    )
    let store = ClipboardHistoryStore(
        persistence: persistence,
        imageSelfWriteConsumer: { _, _ in true },
        externalCopyFeedback: { _ in }
    )
    var updates: [ClipboardPayloadProcessingUpdate] = []
    var diagnostics: [ClipboardMonitorImportDiagnosticEvent] = []
    let fileSystemProbe = PayloadStagingFileSystemProbe()
    let monitor = makePayloadStagingMonitor(
        payload: payload,
        stager: ClipboardPayloadStager(
            directoryProvider: { URL(fileURLWithPath: "/test/payload-staging") },
            fileSystem: fileSystemProbe.fileSystem
        ),
        payloadImporter: { _ in
            .image(
                ClipboardImportedImage(
                    storedImage: StoredClipboardImage(
                        fileName: "self-write.png",
                        width: 1,
                        height: 1,
                        hash: "hash"
                    ),
                    fingerprint: String(repeating: "a", count: 64)
                )
            )
        },
        statusRecorder: { updates.append($0) },
        diagnosticRecorder: { diagnostics.append($0) },
        store: store
    )

    payload.changeCount = 2
    monitor.start()
    #expect(await monitor.waitForPayloadImportsForTesting())

    #expect(updates.contains { $0.status == .skipped(.selfWrite) })
    #expect(!updates.contains {
        ClipboardPayloadProcessingStatusPresenter.userVisibleMessage(for: $0.status) != nil
    })
    #expect(diagnostics.isEmpty)
    #expect(store.items.isEmpty)
    await monitor.stopAndDrainPayloads()
}

@MainActor
@Test func overLimitImageSelfWriteUsesChangeCountFallbackWhenFingerprintIsNil() async {
    let payload = ClipboardPayloadStagingPasteboardProbe(
        changeCount: 1,
        imageData: Data([0x89, 0x50, 0x4E, 0x47])
    )
    final class ConsumerProbe: @unchecked Sendable {
        let lock = NSLock()
        var values: [(Int, String?)] = []
    }
    let consumerProbe = ConsumerProbe()
    let persistence = ClipboardHistoryPersistence(
        repository: ClipboardPayloadStagingEmptyRepository()
    )
    let store = ClipboardHistoryStore(
        persistence: persistence,
        imageSelfWriteConsumer: { changeCount, fingerprint in
            consumerProbe.lock.withLock {
                consumerProbe.values.append((changeCount, fingerprint))
            }
            return true
        },
        externalCopyFeedback: { _ in }
    )
    var updates: [ClipboardPayloadProcessingUpdate] = []
    let fileSystemProbe = PayloadStagingFileSystemProbe()
    let monitor = makePayloadStagingMonitor(
        payload: payload,
        stager: ClipboardPayloadStager(
            directoryProvider: { URL(fileURLWithPath: "/test/payload-staging") },
            fileSystem: fileSystemProbe.fileSystem
        ),
        payloadImporter: { _ in
            .image(
                ClipboardImportedImage(
                    storedImage: StoredClipboardImage(
                        fileName: "over-limit-self-write.png",
                        width: 0,
                        height: 0,
                        hash: "hash"
                    ),
                    fingerprint: nil,
                    previewSkipReason: .previewLimitExceeded
                )
            )
        },
        statusRecorder: { updates.append($0) },
        store: store
    )

    payload.changeCount = 2
    monitor.start()
    #expect(await monitor.waitForPayloadImportsForTesting())

    let consumedValues = consumerProbe.lock.withLock { consumerProbe.values }
    #expect(consumedValues.count == 1)
    #expect(consumedValues.first?.0 == 2)
    #expect(consumedValues.first?.1 == nil)
    #expect(updates.contains { $0.status == .skipped(.selfWrite) })
    #expect(store.items.isEmpty)
    await monitor.stopAndDrainPayloads()
}

@MainActor
@Test func rawPDFPasteboardFlowsThroughMonitorImporterStoreAndKeepsOwnedOriginal() async throws {
    let rootURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("ClipEase-PDF-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(
        at: rootURL,
        withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(at: rootURL) }

    let testFileManager = PayloadTestFileManager(rootURL: rootURL)
    let persistence = ClipboardHistoryPersistence(
        fileManager: testFileManager,
        repository: ClipboardPayloadStagingEmptyRepository()
    )
    let store = ClipboardHistoryStore(
        persistence: persistence,
        externalCopyFeedback: { _ in }
    )
    let rawPDF = try makePayloadTestPDF()
    let payload = ClipboardPayloadStagingPasteboardProbe(
        changeCount: 1,
        imageData: rawPDF,
        pasteboardType: .pdf
    )
    var updates: [ClipboardPayloadProcessingUpdate] = []
    let monitor = ClipboardMonitor(
        store: store,
        pasteboard: NSPasteboard(
            name: NSPasteboard.Name("ClipEaseTests-\(UUID().uuidString)")
        ),
        sourceAppProvider: {
            SourceAppInfo(
                name: "Source",
                bundleID: "com.example.source",
                iconName: "app.fill",
                iconFileName: nil,
                headerColorHex: "#2E8CFF"
            )
        },
        isPaused: { false },
        isIgnored: { _ in false },
        pasteboardChangeCountProvider: { payload.changeCount },
        pasteboardSnapshotProvider: { payload.snapshot() },
        payloadStager: ClipboardPayloadStager(
            directoryProvider: {
                rootURL.appendingPathComponent("PayloadStaging", isDirectory: true)
            }
        ),
        payloadProcessingRecorder: { updates.append($0) },
        observesSystemLifecycle: false
    )

    payload.changeCount = 2
    monitor.start()
    #expect(await monitor.waitForPayloadImportsForTesting())

    guard let item = store.items.first,
          let reference = item.fileReferences.first else {
        let statusText = updates
            .map { String(describing: $0.status) }
            .joined(separator: ",")
        Issue.record(
            "Expected an owned PDF history item; statuses=\(statusText)"
        )
        await monitor.stopAndDrainPayloads()
        return
    }
    let ownedURL = URL(fileURLWithPath: reference.path)
    #expect(item.type == .file)
    #expect(item.richTextFileName != nil)
    #expect(try Data(contentsOf: ownedURL) == rawPDF)
    #expect(updates.contains {
        $0.status == .completed || $0.status == .skipped(.ocrLimitExceeded)
    })
    await monitor.stopAndDrainPayloads()
}

@MainActor
@Test func importedOwnedPDFCanCommitThroughTheStoreReceiptBarrier() async throws {
    let context = try PayloadImporterTestContext()
    defer { context.cleanup() }
    let rawPDF = try makePayloadTestPDF()
    let staged = try await context.stager.stage(
        ClipboardPayloadStagingSource(
            data: rawPDF,
            contentKind: .pdf,
            preferredFileExtension: "pdf"
        )
    )
    let importer = context.store.makeClipboardPayloadImporter(
        payloadStager: context.stager
    )
    let imported = try await importer.importPDF(staged)
    let item = try await context.store.addOwnedFile(
        imported.storedFile,
        sourceApp: .clipease,
        automaticOCRAllowed: true
    )

    #expect(item != nil)
    #expect(item?.fileReferences.count == 1)
}

@MainActor
@Test func overLimitImageCommitsRawPlaceholderWithoutFullDecode() async throws {
    let context = try PayloadImporterTestContext()
    defer { context.cleanup() }
    let encodedPNG = try makePayloadTestPNG()
    let staged = try await context.stager.stage(
        ClipboardPayloadStagingSource(
            data: encodedPNG,
            contentKind: .image,
            preferredFileExtension: "png"
        )
    )
    let decodeProbe = PayloadDecodeProbe()
    let importer = ClipboardPayloadImporter(
        persistence: context.persistence,
        limits: ClipboardPayloadImportLimits(
            maximumImageInputBytes: max(0, encodedPNG.count - 1)
        ),
        onImageDecode: { decodeProbe.recordDecode() },
        payloadStager: context.stager
    )

    let imported = try await importer.importImageForMonitor(
        staged,
        declaredTypeIdentifier: "public.png"
    )
    #expect(imported.previewSkipReason == .previewLimitExceeded)
    let item = try await context.store.addImage(
        imported.storedImage,
        sourceApp: .clipease,
        automaticOCRAllowed: imported.previewSkipReason != .previewLimitExceeded
    )
    #expect(item != nil)
    #expect(item?.ocrStatus == ClipboardOCRStatus.none)
    let ownedURL = try ClipEaseStoragePaths.imageFileURL(
        fileName: imported.storedImage.fileName,
        fileManager: context.fileManager
    )
    let thumbnailURL = try ClipEaseStoragePaths.thumbnailFileURL(
        fileName: imported.storedImage.fileName,
        fileManager: context.fileManager
    )
    #expect(try Data(contentsOf: ownedURL) == encodedPNG)
    let thumbnailData = try Data(contentsOf: thumbnailURL)
    #expect(thumbnailData != encodedPNG)
    #expect(NSBitmapImageRep(data: thumbnailData) != nil)
    #expect(context.stager.diagnostics.residentTaskCount == 0)
    #expect(context.stager.diagnostics.retainedByteCount == 0)
    #expect(decodeProbe.decodeCount == 0)
}

@MainActor
@Test func thumbnailDiskFullIsReportedButRawImageStillCommits() async throws {
    let rootURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("ClipEase-Image-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: rootURL) }
    let fileManager = PayloadTestFileManager(rootURL: rootURL)
    let persistence = ClipboardHistoryPersistence(
        fileManager: fileManager,
        repository: ClipboardPayloadStagingEmptyRepository(),
        encodedImageThumbnailWriter: { _, _ in
            throw NSError(
                domain: NSPOSIXErrorDomain,
                code: Int(POSIXErrorCode.ENOSPC.rawValue)
            )
        }
    )
    let stager = ClipboardPayloadStager(
        directoryProvider: {
            rootURL.appendingPathComponent("PayloadStaging", isDirectory: true)
        }
    )
    let encodedPNG = try makePayloadTestPNG()
    let staged = try await stager.stage(
        ClipboardPayloadStagingSource(
            data: encodedPNG,
            contentKind: .image,
            preferredFileExtension: "png"
        )
    )
    let imported = try await ClipboardPayloadImporter(
        persistence: persistence,
        payloadStager: stager
    ).importImageForMonitor(
        staged,
        declaredTypeIdentifier: "public.png"
    )
    let expectedFingerprint = try ClipboardImageFingerprint.encoded(
        ClipboardEncodedImagePayload(
            data: encodedPNG,
            declaredTypeIdentifier: "public.png"
        )
    )

    #expect(imported.previewSkipReason == .diskFull)
    #expect(imported.fingerprint == expectedFingerprint)
    let ownedURL = try ClipEaseStoragePaths.imageFileURL(
        fileName: imported.storedImage.fileName,
        fileManager: fileManager
    )
    #expect(try Data(contentsOf: ownedURL) == encodedPNG)
}

@MainActor
@Test func overLimitHTMLCommitsValidRTFPlaceholderAndIndependentOwnedRawSidecar() async throws {
    let context = try PayloadImporterTestContext()
    defer { context.cleanup() }
    let rawHTML = Data("<html><body><b>preserve me</b></body></html>".utf8)
    let staged = try await context.stager.stage(
        ClipboardPayloadStagingSource(
            data: rawHTML,
            contentKind: .richTextHTML,
            preferredFileExtension: "html"
        )
    )
    let importer = ClipboardPayloadImporter(
        persistence: context.persistence,
        limits: ClipboardPayloadImportLimits(maximumHTMLInputBytes: 1),
        payloadStager: context.stager
    )
    guard let imported = try await importer.importRichText(
        staged,
        fallbackPlainText: "preserved rich text"
    ) else {
        Issue.record("Expected a rich-text placeholder")
        return
    }
    let item = try await context.store.addRichText(
        imported.data,
        plainText: imported.plainText,
        sourceApp: .clipease,
        rawAsset: imported.rawAsset
    )

    guard let fileName = item?.richTextFileName else {
        Issue.record("Expected a committed rich-text asset")
        return
    }
    let rtfURL = try ClipEaseStoragePaths.richTextFileURL(
        fileName: fileName,
        fileManager: context.fileManager
    )
    let rawURL = rtfURL.deletingLastPathComponent()
        .appendingPathComponent(".\(fileName).raw.html")
    #expect(try Data(contentsOf: rawURL) == rawHTML)
    #expect(String(data: try Data(contentsOf: rtfURL), encoding: .ascii)?.contains("\\rtf") == true)
    #expect(imported.previewSkipReason == .previewLimitExceeded)
}

@MainActor
@Test func stoppedMonitorDiscardsLateStagingCompletionWithoutImporterWriteback() async {
    let payload = ClipboardPayloadStagingPasteboardProbe(
        changeCount: 1,
        imageData: Data([0x03, 0x04])
    )
    let fileSystemProbe = BlockingPayloadStagingFileSystemProbe()
    let importerProbe = ClipboardPayloadImporterCallProbe()
    var statusUpdates: [ClipboardPayloadProcessingUpdate] = []
    let monitor = makePayloadStagingMonitor(
        payload: payload,
        stager: ClipboardPayloadStager(
            directoryProvider: { URL(fileURLWithPath: "/test/payload-staging") },
            fileSystem: fileSystemProbe.fileSystem
        ),
        payloadImporter: { request in
            await importerProbe.record(request)
            throw CancellationError()
        },
        statusRecorder: { statusUpdates.append($0) }
    )

    payload.changeCount = 2
    monitor.start()
    guard await fileSystemProbe.waitForStartedWriteCount(1) else {
        Issue.record("Timed out waiting for the staging write")
        monitor.stop()
        return
    }
    monitor.stop()
    fileSystemProbe.releaseWrites(1)
    #expect(await fileSystemProbe.waitForRemoveCount(1))
    await Task.yield()

    #expect(await importerProbe.callCount == 0)
    #expect(statusUpdates.contains { $0.status == .deferred(.staleGeneration) })
    #expect(!statusUpdates.contains { $0.status == .completed })
    #expect(fileSystemProbe.removeCount == 1)
}

@MainActor
@Test func monitorDrainRetriesFailedPayloadRemovalBeforeTerminationReturns() async {
    let payload = ClipboardPayloadStagingPasteboardProbe(
        changeCount: 1,
        imageData: Data([0x05])
    )
    let fileSystemProbe = PayloadStagingFileSystemProbe(removeFailureCount: 1)
    let stager = ClipboardPayloadStager(
        directoryProvider: { URL(fileURLWithPath: "/test/payload-staging") },
        fileSystem: fileSystemProbe.fileSystem
    )
    let monitor = makePayloadStagingMonitor(
        payload: payload,
        stager: stager,
        payloadImporter: { _ in
            throw ClipboardPayloadStagingError.stagedFileUnreadable
        }
    )

    payload.changeCount = 2
    monitor.start()
    #expect(await monitor.waitForPayloadImportsForTesting())
    await monitor.stopAndDrainPayloads()

    #expect(await stager.pendingCleanupCount == 0)
    #expect(fileSystemProbe.removeCount >= 2)
}
