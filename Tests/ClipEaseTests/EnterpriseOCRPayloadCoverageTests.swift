import AppKit
import Foundation
import Testing
@testable import ClipEase

@Suite(.serialized)
@MainActor
struct EnterpriseOCRPayloadCoverageTests {
    @Test func ocrServiceRejectsUnavailableOversizedAndUnrecognizableImages() async throws {
        let context = try PayloadImporterTestContext()
        defer { context.cleanup() }
        let service = ClipboardOCRService()
        let missingURL = context.rootURL.appendingPathComponent("missing.png")

        #expect(
            await service.recognizeImageResult(at: missingURL)
                == .failed(.sourceUnavailable)
        )
        #expect(await service.recognizeImage(at: missingURL) == nil)

        let pngData = try makePayloadTestPNG()
        let oversizedURL = try writeSparseFile(
            pngData,
            named: "oversized.png",
            byteCount: ClipboardOCRInputPolicy.maximumImageBytes + 1,
            in: context.rootURL
        )
        #expect(
            await service.recognizeImageResult(at: oversizedURL)
                == .skipped(.imageByteLimit)
        )

        let blankURL = try writeFile(
            pngData,
            named: "blank.png",
            in: context.rootURL
        )
        #expect(
            await service.recognizeImageResult(at: blankURL)
                == .failed(.recognitionFailed)
        )
    }

    @Test func ocrServiceRejectsUnavailableOversizedAndCancelledPDFs() async throws {
        let context = try PayloadImporterTestContext()
        defer { context.cleanup() }
        let service = ClipboardOCRService()
        let missingURL = context.rootURL.appendingPathComponent("missing.pdf")

        #expect(
            await service.recognizePDFResult(at: missingURL)
                == .failed(.sourceUnavailable)
        )
        #expect(await service.recognizePDF(at: missingURL) == nil)

        let tooManyPagesURL = try writeFile(
            makePayloadTestPDF(pageCount: ClipboardOCRInputPolicy.maximumPDFPages + 1),
            named: "too-many-pages.pdf",
            in: context.rootURL
        )
        #expect(
            await service.recognizePDFResult(at: tooManyPagesURL)
                == .skipped(.pdfPageLimit)
        )

        let oversizedURL = try writeSparsePDF(
            makePayloadTestPDF(),
            named: "oversized.pdf",
            byteCount: ClipboardOCRInputPolicy.maximumPDFBytes + 1,
            in: context.rootURL
        )
        #expect(
            await service.recognizePDFResult(at: oversizedURL)
                == .skipped(.pdfByteLimit)
        )

        let cancelledURL = try writeFile(
            makePayloadTestPDF(),
            named: "cancelled.pdf",
            in: context.rootURL
        )
        let cancelledTask = Task {
            await Task.yield()
            return await service.recognizePDFResult(at: cancelledURL)
        }
        cancelledTask.cancel()
        #expect(await cancelledTask.value == .failed(.recognitionFailed))
    }

    @Test func ocrTimeoutReturnsValueTimeoutAndPreinstalledCancellation() async {
        let valueTask = Task<Int, Never> { 17 }
        switch await ClipboardOCRTimeout.wait(
            for: valueTask,
            nanoseconds: 1_000_000_000
        ) {
        case .value(let value):
            #expect(value == 17)
        case .timedOut, .cancelled:
            Issue.record("Expected the completed task value")
        }

        let slowTask = Task<Int, Never> {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            return 23
        }
        switch await ClipboardOCRTimeout.wait(
            for: slowTask,
            nanoseconds: 1_000_000
        ) {
        case .timedOut:
            slowTask.cancel()
        case .value, .cancelled:
            Issue.record("Expected the timeout result")
        }

        let cancelledWaiter = Task { () -> ClipboardOCRTimeoutResult<Int> in
            withUnsafeCurrentTask { task in
                task?.cancel()
            }
            let childTask = Task<Int, Never> { 31 }
            return await ClipboardOCRTimeout.wait(
                for: childTask,
                nanoseconds: 1_000_000_000
            )
        }
        switch await cancelledWaiter.value {
        case .cancelled:
            break
        case .value, .timedOut:
            Issue.record("Expected cancellation to win before continuation installation")
        }
    }

    @Test func ocrOneShotContinuationRejectsSequentialAndConcurrentDuplicates() async {
        let sequentialValue: Int = await withCheckedContinuation {
            (continuation: CheckedContinuation<Int, Never>) in
            let resolution = ClipboardOCROneShotContinuation(continuation)
            #expect(resolution.resolve(17))
            #expect(!resolution.resolve(23))
        }
        #expect(sequentialValue == 17)

        let winnerProbe = EnterpriseOCRResolutionWinnerProbe()
        let concurrentValue: Int = await withCheckedContinuation {
            (continuation: CheckedContinuation<Int, Never>) in
            let resolution = ClipboardOCROneShotContinuation(continuation)
            DispatchQueue.concurrentPerform(iterations: 256) { value in
                if resolution.resolve(value) {
                    winnerProbe.record(value)
                }
            }
        }
        let winners = winnerProbe.values
        #expect(winners.count == 1)
        #expect(concurrentValue == winners.first)
    }

    @Test func ocrCoordinatorMapsCustomRecognizerSuccessAndFailure() async {
        let successImage = ClipboardItem.image(
            fileName: "success.png",
            width: 1,
            height: 1,
            hash: "success",
            sourceApp: .clipease
        )
        let successPDF = makePendingPDFItem(name: "success.pdf")
        let successCoordinator = HistoryOCRCoordinator(
            limiter: ClipboardOCRConcurrencyLimiter(
                idleLimit: 2,
                interactiveLimit: 2
            ),
            imageRecognizer: { url in
                Self.makeOCRMatch(text: "image:\(url.lastPathComponent)")
            },
            pdfRecognizer: { url in
                Self.makeOCRMatch(text: "pdf:\(url.lastPathComponent)")
            }
        )
        var successOutcomes: [ClipboardItem.ID: ClipboardOCRExecutionOutcome] = [:]
        var successTexts: [ClipboardItem.ID: String] = [:]

        for item in [successImage, successPDF] {
            successCoordinator.enqueue(
                item: item,
                sourceURL: URL(fileURLWithPath: "/tmp/\(item.linkTitle ?? item.text)"),
                setProcessing: { _ in },
                applyResult: { result, _, id in
                    successTexts[id] = result.text
                },
                applyOutcome: { outcome, id in
                    successOutcomes[id] = outcome
                }
            )
        }
        await waitUntil { successOutcomes.count == 2 }

        #expect(successOutcomes[successImage.id] == .completed)
        #expect(successOutcomes[successPDF.id] == .completed)
        #expect(successTexts[successImage.id]?.hasPrefix("image:") == true)
        #expect(successTexts[successPDF.id]?.hasPrefix("pdf:") == true)

        let failedImage = ClipboardItem.image(
            fileName: "failed.png",
            width: 1,
            height: 1,
            hash: "failed",
            sourceApp: .clipease
        )
        let failedPDF = makePendingPDFItem(name: "failed.pdf")
        let failureCoordinator = HistoryOCRCoordinator(
            limiter: ClipboardOCRConcurrencyLimiter(
                idleLimit: 2,
                interactiveLimit: 2
            ),
            imageRecognizer: { _ in nil },
            pdfRecognizer: { _ in nil }
        )
        var failedOutcomes: [ClipboardItem.ID: ClipboardOCRExecutionOutcome] = [:]
        for item in [failedImage, failedPDF] {
            failureCoordinator.enqueue(
                item: item,
                sourceURL: URL(fileURLWithPath: "/tmp/\(item.id.uuidString)"),
                setProcessing: { _ in },
                applyResult: { _, _, _ in },
                applyOutcome: { outcome, id in
                    failedOutcomes[id] = outcome
                }
            )
        }
        await waitUntil { failedOutcomes.count == 2 }

        #expect(failedOutcomes[failedImage.id] == .failed(.recognitionFailed))
        #expect(failedOutcomes[failedPDF.id] == .failed(.recognitionFailed))
    }

    @Test func ocrCoordinatorUsesDefaultServicesForBothSupportedKinds() async {
        let image = ClipboardItem.image(
            fileName: "missing-default.png",
            width: 1,
            height: 1,
            hash: "missing-default",
            sourceApp: .clipease
        )
        let pdf = makePendingPDFItem(name: "missing-default.pdf")
        let coordinator = HistoryOCRCoordinator(
            limiter: ClipboardOCRConcurrencyLimiter(
                idleLimit: 2,
                interactiveLimit: 2
            )
        )
        var outcomes: [ClipboardItem.ID: ClipboardOCRExecutionOutcome] = [:]

        coordinator.enqueue(
            item: image,
            sourceURL: URL(fileURLWithPath: "/tmp/does-not-exist-\(UUID()).png"),
            setProcessing: { _ in },
            applyResult: { _, _, _ in },
            applyOutcome: { outcome, id in outcomes[id] = outcome }
        )
        coordinator.enqueue(
            item: pdf,
            sourceURL: URL(fileURLWithPath: "/tmp/does-not-exist-\(UUID()).pdf"),
            setProcessing: { _ in },
            applyResult: { _, _, _ in },
            applyOutcome: { outcome, id in outcomes[id] = outcome }
        )
        await waitUntil { outcomes.count == 2 }

        #expect(outcomes[image.id] == .failed(.sourceUnavailable))
        #expect(outcomes[pdf.id] == .failed(.sourceUnavailable))
    }

    @Test func ocrCoordinatorReportsDeferredUnsupportedAndCancelledWork() async {
        let deferredItem = ClipboardItem.image(
            fileName: "deferred.png",
            width: 1,
            height: 1,
            hash: "deferred",
            sourceApp: .clipease
        )
        let deferredCoordinator = HistoryOCRCoordinator(
            limiter: ClipboardOCRConcurrencyLimiter(
                idleLimit: 0,
                interactiveLimit: 0,
                maximumWaitingCount: 0
            ),
            imageRecognizer: { _ in Self.makeOCRMatch(text: "unexpected") }
        )
        var deferredOutcome: ClipboardOCRExecutionOutcome?
        deferredCoordinator.enqueue(
            item: deferredItem,
            sourceURL: URL(fileURLWithPath: "/tmp/deferred.png"),
            setProcessing: { _ in },
            applyResult: { _, _, _ in },
            applyOutcome: { outcome, _ in deferredOutcome = outcome }
        )
        await waitUntil { deferredOutcome != nil }
        #expect(deferredOutcome == .deferred)

        var unsupportedItem = ClipboardItem.text(
            "unsupported",
            sourceApp: .clipease
        )
        unsupportedItem.ocrStatus = .pending
        let unsupportedCoordinator = HistoryOCRCoordinator(
            limiter: ClipboardOCRConcurrencyLimiter(
                idleLimit: 1,
                interactiveLimit: 1
            )
        )
        var unsupportedOutcome: ClipboardOCRExecutionOutcome?
        var unsupportedStatus: ClipboardOCRStatus?
        unsupportedCoordinator.enqueue(
            item: unsupportedItem,
            sourceURL: URL(fileURLWithPath: "/tmp/unsupported.txt"),
            setProcessing: { _ in },
            applyResult: { _, status, _ in unsupportedStatus = status },
            applyOutcome: { outcome, _ in unsupportedOutcome = outcome }
        )
        await waitUntil { unsupportedOutcome != nil }
        #expect(unsupportedOutcome == .skipped(.unsupportedItem))
        #expect(unsupportedStatus == .failed)

        let cancelledItem = ClipboardItem.image(
            fileName: "cancelled.png",
            width: 1,
            height: 1,
            hash: "cancelled",
            sourceApp: .clipease
        )
        let cancelledCoordinator = HistoryOCRCoordinator(
            limiter: ClipboardOCRConcurrencyLimiter(
                idleLimit: 1,
                interactiveLimit: 1
            ),
            imageRecognizer: { _ in
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                return Self.makeOCRMatch(text: "late")
            }
        )
        var didStart = false
        var cancelledOutcome: ClipboardOCRExecutionOutcome?
        cancelledCoordinator.enqueue(
            item: cancelledItem,
            sourceURL: URL(fileURLWithPath: "/tmp/cancelled.png"),
            setProcessing: { _ in didStart = true },
            applyResult: { _, _, _ in },
            applyOutcome: { outcome, _ in cancelledOutcome = outcome }
        )
        await waitUntil { didStart }
        cancelledCoordinator.cancelTasks(for: [cancelledItem])
        try? await Task.sleep(nanoseconds: 10_000_000)

        #expect(cancelledOutcome == nil)
        #expect(!cancelledCoordinator.hasInFlightTask(for: cancelledItem.id))
    }

    @Test func ocrLimiterResumesAndCancelsQueuedWaiters() async {
        let resumeLimiter = ClipboardOCRConcurrencyLimiter(
            idleLimit: 1,
            interactiveLimit: 1,
            maximumWaitingCount: 1
        )
        #expect(await resumeLimiter.waitForTurn() == .acquired)
        let resumedWaiter = Task {
            await resumeLimiter.waitForTurn()
        }
        try? await Task.sleep(nanoseconds: 5_000_000)
        await resumeLimiter.finishTurn()
        #expect(await resumedWaiter.value == .acquired)
        await resumeLimiter.finishTurn()

        let cancellationLimiter = ClipboardOCRConcurrencyLimiter(
            idleLimit: 0,
            interactiveLimit: 0,
            maximumWaitingCount: 1
        )
        let queuedWaiter = Task {
            await cancellationLimiter.waitForTurn()
        }
        try? await Task.sleep(nanoseconds: 5_000_000)
        queuedWaiter.cancel()
        #expect(await queuedWaiter.value == .cancelled)

        let preCancelledWaiter = Task {
            withUnsafeCurrentTask { task in
                task?.cancel()
            }
            return await cancellationLimiter.waitForTurn()
        }
        #expect(await preCancelledWaiter.value == .cancelled)
    }

    @Test func stagedImagesWithoutWorkingSetPreserveRawAssetsAndFallbackPreviews() async throws {
        let context = try PayloadImporterTestContext()
        defer { context.cleanup() }
        let pngData = try makePayloadTestPNG()

        let invalidTypePayload = try await context.stager.stage(
            ClipboardPayloadStagingSource(
                data: pngData,
                contentKind: .image,
                preferredFileExtension: "png"
            )
        )
        let invalidTypeResult = try await ClipboardPayloadImporter(
            persistence: context.persistence
        ).importImageForMonitor(
            invalidTypePayload,
            declaredTypeIdentifier: "public.data"
        )
        #expect(invalidTypeResult.previewSkipReason == .previewLimitExceeded)
        #expect(invalidTypeResult.fingerprint == nil)
        #expect(invalidTypeResult.storedImage.width == 0)
        #expect(
            try storedImageData(
                invalidTypeResult.storedImage,
                fileManager: context.fileManager
            ) == pngData
        )

        let outputLimitedPayload = try await context.stager.stage(
            ClipboardPayloadStagingSource(
                data: pngData,
                contentKind: .image,
                preferredFileExtension: "png"
            )
        )
        let outputLimitedResult = try await ClipboardPayloadImporter(
            persistence: context.persistence,
            limits: ClipboardPayloadImportLimits(maximumPNGOutputBytes: 0)
        ).importImageForMonitor(
            outputLimitedPayload,
            declaredTypeIdentifier: "public.png"
        )
        #expect(outputLimitedResult.previewSkipReason == .previewLimitExceeded)
        #expect(outputLimitedResult.fingerprint == nil)
        #expect(
            try storedImageData(
                outputLimitedResult.storedImage,
                fileManager: context.fileManager
            ) == pngData
        )

        let transparentData = try makeTransparentPNG()
        let transparentPayload = try await context.stager.stage(
            ClipboardPayloadStagingSource(
                data: transparentData,
                contentKind: .image,
                preferredFileExtension: "png"
            )
        )
        let transparentResult = try await ClipboardPayloadImporter(
            persistence: context.persistence
        ).importImageForMonitor(
            transparentPayload,
            declaredTypeIdentifier: "public.png"
        )
        #expect(transparentResult.previewSkipReason == nil)
        #expect(transparentResult.fingerprint?.count == 64)
    }

    @Test func directImageImporterMapsEveryBoundaryFailure() async throws {
        let context = try PayloadImporterTestContext()
        defer { context.cleanup() }
        let pngData = try makePayloadTestPNG()

        await #expect(throws: ClipboardPayloadImportError.imageInputTooLarge) {
            _ = try await ClipboardPayloadImporter(
                persistence: context.persistence,
                limits: ClipboardPayloadImportLimits(
                    maximumImageInputBytes: max(0, pngData.count - 1)
                )
            ).importImage(pngData, declaredTypeIdentifier: "public.png")
        }
        await #expect(throws: ClipboardPayloadImportError.unsupportedImageType) {
            _ = try await ClipboardPayloadImporter(
                persistence: context.persistence
            ).importImage(pngData, declaredTypeIdentifier: "public.data")
        }
        await #expect(throws: ClipboardPayloadImportError.invalidImage) {
            _ = try await ClipboardPayloadImporter(
                persistence: context.persistence
            ).importImage(Data("not-an-image".utf8), declaredTypeIdentifier: "public.png")
        }
        await #expect(throws: ClipboardPayloadImportError.imageDimensionsTooLarge) {
            _ = try await ClipboardPayloadImporter(
                persistence: context.persistence,
                limits: ClipboardPayloadImportLimits(maximumImageSourceEdge: 1)
            ).importImage(pngData, declaredTypeIdentifier: "public.png")
        }
        await #expect(throws: ClipboardPayloadImportError.pngOutputTooLarge) {
            _ = try await ClipboardPayloadImporter(
                persistence: context.persistence,
                limits: ClipboardPayloadImportLimits(maximumPNGOutputBytes: 0)
            ).importImage(pngData, declaredTypeIdentifier: "public.png")
        }
    }

    @Test func stagedRTFUsesPlaceholderFallbackAndPreservesRawAsset() async throws {
        let context = try PayloadImporterTestContext()
        defer { context.cleanup() }
        let rtfData = try makeRTF("preserved RTF")
        let staged = try await context.stager.stage(
            ClipboardPayloadStagingSource(
                data: rtfData,
                contentKind: .richTextRTF,
                preferredFileExtension: "rtf"
            )
        )
        guard let result = try await ClipboardPayloadImporter(
            persistence: context.persistence,
            limits: ClipboardPayloadImportLimits(
                maximumRTFInputBytes: max(0, rtfData.count - 1)
            )
        ).importRichText(staged) else {
            Issue.record("Expected an over-limit RTF placeholder")
            return
        }

        #expect(result.data.isEmpty)
        #expect(result.plainText == "Rich text payload (\(rtfData.count) bytes)")
        #expect(result.previewSkipReason == .previewLimitExceeded)
        #expect(try result.rawAsset?.stagedPayload.readData() == rtfData)
        result.rawAsset?.stagedPayload.discard()

        let invalidData = Data()
        let invalidStaged = try await context.stager.stage(
            ClipboardPayloadStagingSource(
                data: invalidData,
                contentKind: .richTextRTF,
                preferredFileExtension: "rtf"
            )
        )
        guard let fallbackResult = try await ClipboardPayloadImporter(
            persistence: context.persistence
        ).importRichText(
            invalidStaged,
            fallbackPlainText: "  fallback RTF  "
        ) else {
            Issue.record("Expected the plain-text RTF fallback")
            return
        }
        #expect(fallbackResult.plainText == "fallback RTF")
        #expect(fallbackResult.previewSkipReason == .previewLimitExceeded)
        fallbackResult.rawAsset?.stagedPayload.discard()
    }

    @Test func stagedHTMLBuildsRTFAndFallsBackForInvalidContent() async throws {
        let context = try PayloadImporterTestContext()
        defer { context.cleanup() }
        let htmlData = Data("<html><body><b>HTML body</b></body></html>".utf8)
        let validStaged = try await context.stager.stage(
            ClipboardPayloadStagingSource(
                data: htmlData,
                contentKind: .richTextHTML,
                preferredFileExtension: "html"
            )
        )
        guard let validResult = try await ClipboardPayloadImporter(
            persistence: context.persistence
        ).importRichText(validStaged) else {
            Issue.record("Expected parsed HTML rich text")
            return
        }
        #expect(validResult.plainText.contains("HTML body"))
        #expect(!validResult.data.isEmpty)
        #expect(validResult.previewSkipReason == nil)
        #expect(try validResult.rawAsset?.stagedPayload.readData() == htmlData)
        validResult.rawAsset?.stagedPayload.discard()

        let invalidStaged = try await context.stager.stage(
            ClipboardPayloadStagingSource(
                data: Data(),
                contentKind: .richTextHTML,
                preferredFileExtension: "html"
            )
        )
        guard let fallbackResult = try await ClipboardPayloadImporter(
            persistence: context.persistence
        ).importRichText(invalidStaged) else {
            Issue.record("Expected invalid HTML to produce a durable placeholder")
            return
        }
        #expect(fallbackResult.plainText == "Rich text payload (0 bytes)")
        #expect(fallbackResult.previewSkipReason == .previewLimitExceeded)
        #expect(!fallbackResult.data.isEmpty)
        fallbackResult.rawAsset?.stagedPayload.discard()
    }

    @Test func stagedRichTextRejectsWrongKindAndSaturatesWorkingSet() async throws {
        let context = try PayloadImporterTestContext()
        defer { context.cleanup() }
        let imagePayload = try await context.stager.stage(
            ClipboardPayloadStagingSource(
                data: try makePayloadTestPNG(),
                contentKind: .image,
                preferredFileExtension: "png"
            )
        )
        await #expect(throws: ClipboardPayloadStagingError.stagedFileUnreadable) {
            _ = try await ClipboardPayloadImporter(
                persistence: context.persistence,
                payloadStager: context.stager
            ).importRichText(imagePayload)
        }
        imagePayload.discard()

        let fakeURL = try writeFile(
            makeRTF("overflow"),
            named: "\(UUID().uuidString).rtf",
            in: context.rootURL
        )
        let enormousPayload = ClipboardStagedPayload(
            id: UUID(),
            fileURL: fakeURL,
            byteCount: Int.max,
            contentKind: .richTextRTF,
            fileSystem: .live,
            preferredFileExtension: "rtf"
        )
        defer { enormousPayload.discard() }
        await #expect(throws: ClipboardPayloadStagingError.retainedDataLimitExceeded) {
            _ = try await ClipboardPayloadImporter(
                persistence: context.persistence,
                limits: ClipboardPayloadImportLimits(
                    maximumRTFInputBytes: Int.max,
                    maximumRichTextOutputBytes: Int.max
                ),
                payloadStager: context.stager
            ).importRichText(enormousPayload)
        }
    }

    @Test func directRichTextImporterMapsLimitsAndFallbacks() async throws {
        let context = try PayloadImporterTestContext()
        defer { context.cleanup() }
        let rtfData = try makeRTF("direct RTF")
        let htmlData = Data("<p>direct HTML</p>".utf8)

        await #expect(throws: ClipboardPayloadImportError.rtfInputTooLarge) {
            _ = try await ClipboardPayloadImporter(
                persistence: context.persistence,
                limits: ClipboardPayloadImportLimits(maximumRTFInputBytes: 0)
            ).importRichText(.rtf(data: rtfData, fallbackPlainText: nil))
        }
        await #expect(throws: ClipboardPayloadImportError.richTextOutputTooLarge) {
            _ = try await ClipboardPayloadImporter(
                persistence: context.persistence,
                limits: ClipboardPayloadImportLimits(
                    maximumRTFInputBytes: rtfData.count,
                    maximumRichTextOutputBytes: 0
                )
            ).importRichText(.rtf(data: rtfData, fallbackPlainText: nil))
        }
        await #expect(throws: ClipboardPayloadImportError.htmlInputTooLarge) {
            _ = try await ClipboardPayloadImporter(
                persistence: context.persistence,
                limits: ClipboardPayloadImportLimits(maximumHTMLInputBytes: 0)
            ).importRichText(.html(data: htmlData, fallbackPlainText: nil))
        }
        await #expect(throws: ClipboardPayloadImportError.richTextOutputTooLarge) {
            _ = try await ClipboardPayloadImporter(
                persistence: context.persistence,
                limits: ClipboardPayloadImportLimits(
                    maximumHTMLInputBytes: htmlData.count,
                    maximumRichTextOutputBytes: 0
                )
            ).importRichText(.html(data: htmlData, fallbackPlainText: nil))
        }

        let emptyRTF = try await ClipboardPayloadImporter(
            persistence: context.persistence
        ).importRichText(.rtf(data: Data(), fallbackPlainText: "   "))
        #expect(emptyRTF == nil)

        let plainHTML = try await ClipboardPayloadImporter(
            persistence: context.persistence
        ).importRichText(
            .html(data: Data("invalid".utf8), fallbackPlainText: "HTML fallback")
        )
        #expect(plainHTML?.plainText == "invalid")
    }

    @Test func pdfImporterPreservesValidInvalidPageLimitedAndByteLimitedOriginals() async throws {
        let context = try PayloadImporterTestContext()
        defer { context.cleanup() }
        let importer = ClipboardPayloadImporter(persistence: context.persistence)

        let validData = try makePayloadTestPDF()
        let validPayload = try await context.stager.stage(
            ClipboardPayloadStagingSource(
                data: validData,
                contentKind: .pdf,
                preferredFileExtension: "pdf"
            )
        )
        let validResult = try await importer.importPDF(validPayload)
        #expect(validResult.previewSkipReason == nil)
        #expect(try Data(contentsOf: validResult.storedFile.fileURL) == validData)

        let invalidData = Data("not-a-pdf".utf8)
        let invalidPayload = try await context.stager.stage(
            ClipboardPayloadStagingSource(
                data: invalidData,
                contentKind: .pdf,
                preferredFileExtension: "pdf"
            )
        )
        let invalidResult = try await importer.importPDF(invalidPayload)
        #expect(invalidResult.previewSkipReason == .ocrLimitExceeded)
        #expect(try Data(contentsOf: invalidResult.storedFile.fileURL) == invalidData)

        let pageLimitedData = try makePayloadTestPDF(pageCount: 26)
        let pageLimitedPayload = try await context.stager.stage(
            ClipboardPayloadStagingSource(
                data: pageLimitedData,
                contentKind: .pdf,
                preferredFileExtension: "pdf"
            )
        )
        let pageLimitedResult = try await importer.importPDF(pageLimitedPayload)
        #expect(pageLimitedResult.previewSkipReason == .ocrLimitExceeded)

        let spoofedData = try makePayloadTestPDF()
        let spoofedURL = try writeFile(
            spoofedData,
            named: "\(UUID().uuidString).pdf",
            in: context.rootURL
        )
        let byteLimitedPayload = ClipboardStagedPayload(
            id: UUID(),
            fileURL: spoofedURL,
            byteCount: 50 * 1_024 * 1_024 + 1,
            contentKind: .pdf,
            fileSystem: .live,
            preferredFileExtension: "pdf"
        )
        let byteLimitedResult = try await importer.importPDF(byteLimitedPayload)
        #expect(byteLimitedResult.previewSkipReason == .ocrLimitExceeded)
        #expect(try Data(contentsOf: byteLimitedResult.storedFile.fileURL) == spoofedData)
    }

    @Test func previewSignatureUpdateCoversFullPrefixAndMismatchBranches() {
        let existing = makePreviewItem(id: UUID(), text: "existing", createdAt: 1)
        let inserted = makePreviewItem(id: UUID(), text: "inserted", createdAt: 2)
        let changedExisting = makePreviewItem(
            id: existing.id,
            text: "changed",
            createdAt: 1
        )

        let initial = HistoryPreviewBuildCoordinator.previewSignatureUpdate(
            sourceItems: [existing],
            currentSourceSignature: []
        )
        #expect(initial.hasChanges)
        #expect(initial.sourceSignature.map(\.text) == ["existing"])

        let unchanged = HistoryPreviewBuildCoordinator.previewSignatureUpdate(
            sourceItems: [existing],
            currentSourceSignature: initial.sourceSignature
        )
        #expect(!unchanged.hasChanges)

        let prefixed = HistoryPreviewBuildCoordinator.previewSignatureUpdate(
            sourceItems: [inserted, existing],
            currentSourceSignature: initial.sourceSignature
        )
        #expect(prefixed.hasChanges)
        #expect(prefixed.sourceSignature.map(\.text) == ["inserted", "existing"])

        let mismatched = HistoryPreviewBuildCoordinator.previewSignatureUpdate(
            sourceItems: [inserted, changedExisting],
            currentSourceSignature: initial.sourceSignature
        )
        #expect(mismatched.hasChanges)
        #expect(mismatched.sourceSignature.map(\.text) == ["inserted", "changed"])
    }

    @Test func previewIncrementalInsertionRejectsLargeAndMismatchedChanges() throws {
        let existing = makePreviewItem(id: UUID(), text: "existing", createdAt: 1)
        let currentPreview = [HistoryPreviewItem(item: existing)]
        let currentSignature = [HistoryPreviewSourceSignature(item: existing)]
        let tooManyInserted = (0..<9).map { index in
            makePreviewItem(
                id: UUID(),
                text: "inserted-\(index)",
                createdAt: TimeInterval(index + 2)
            )
        }
        let tooManySourceItems = tooManyInserted + [existing]

        #expect(try HistoryPreviewBuildCoordinator.incrementalPreviewInsertion(
            sourceItems: tooManySourceItems,
            sourceSignature: tooManySourceItems.map(HistoryPreviewSourceSignature.init),
            currentPreviewItems: currentPreview,
            currentSourceSignature: currentSignature
        ) == nil)

        let changedExisting = makePreviewItem(
            id: existing.id,
            text: "changed",
            createdAt: 1
        )
        #expect(try HistoryPreviewBuildCoordinator.incrementalPreviewInsertion(
            sourceItems: [changedExisting],
            sourceSignature: [HistoryPreviewSourceSignature(item: changedExisting)],
            currentPreviewItems: currentPreview,
            currentSourceSignature: currentSignature
        ) == nil)

        let zeroInsertion = try HistoryPreviewBuildCoordinator.incrementalPreviewInsertion(
            sourceItems: [existing],
            sourceSignature: currentSignature,
            currentPreviewItems: currentPreview,
            currentSourceSignature: currentSignature
        )
        #expect(zeroInsertion?.insertedItems.isEmpty == true)
        #expect(zeroInsertion?.cacheHitCount == 1)
    }

    @Test func previewSignatureCheckingCancellationStopsImmediately() async {
        let items = (0..<512).map { index in
            makePreviewItem(
                id: UUID(),
                text: "item-\(index)",
                createdAt: TimeInterval(index)
            )
        }
        let task = Task {
            withUnsafeCurrentTask { currentTask in
                currentTask?.cancel()
            }
            return try HistoryPreviewBuildCoordinator
                .previewSignatureUpdateCheckingCancellation(
                    sourceItems: items,
                    currentSourceSignature: []
                )
        }

        await #expect(throws: CancellationError.self) {
            _ = try await task.value
        }
    }

    nonisolated private static func makeOCRMatch(text: String) -> ClipboardOCRMatch {
        ClipboardOCRMatch(
            text: text,
            emails: [],
            phoneNumbers: [],
            urls: [],
            textRegions: []
        )
    }

    private func makePendingPDFItem(name: String) -> ClipboardItem {
        let itemID = UUID()
        return ClipboardItem.file(
            references: [
                ClipboardFileReference(
                    itemID: itemID,
                    orderIndex: 0,
                    path: "/tmp/\(name)",
                    displayName: name,
                    fileExtension: "pdf",
                    contentType: "com.adobe.pdf"
                )
            ],
            sourceApp: .clipease
        )
    }

    private func makePreviewItem(
        id: UUID,
        text: String,
        createdAt: TimeInterval
    ) -> ClipboardItem {
        ClipboardItem(
            id: id,
            type: .text,
            text: text,
            url: nil,
            linkTitle: nil,
            linkSubtitle: nil,
            imageFileName: nil,
            imageWidth: nil,
            imageHeight: nil,
            imageHash: nil,
            richTextFileName: nil,
            fileReferences: [],
            createdAt: Date(timeIntervalSince1970: createdAt),
            sourceAppName: "ClipEase",
            sourceBundleID: "com.clipease.coverage",
            iconName: "app.fill",
            iconFileName: nil,
            headerColorHex: "#2E8CFF",
            isPinned: false,
            pinnedAt: nil,
            groupID: nil,
            groupedAt: nil
        )
    }

    private func makeRTF(_ text: String) throws -> Data {
        let attributedString = NSAttributedString(string: text)
        return try attributedString.data(
            from: NSRange(location: 0, length: attributedString.length),
            documentAttributes: [
                .documentType: NSAttributedString.DocumentType.rtf
            ]
        )
    }

    private func makeTransparentPNG() throws -> Data {
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 2,
            pixelsHigh: 2,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            throw EnterpriseCoverageFixtureError.imageEncodingFailed
        }
        for x in 0..<2 {
            for y in 0..<2 {
                bitmap.setColor(.clear, atX: x, y: y)
            }
        }
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw EnterpriseCoverageFixtureError.imageEncodingFailed
        }
        return data
    }

    private func storedImageData(
        _ storedImage: StoredClipboardImage,
        fileManager: FileManager
    ) throws -> Data {
        let url = try ClipEaseStoragePaths.imageFileURL(
            fileName: storedImage.fileName,
            fileManager: fileManager
        )
        return try Data(contentsOf: url)
    }

    @discardableResult
    private func writeFile(
        _ data: Data,
        named name: String,
        in directory: URL
    ) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try data.write(to: url, options: .atomic)
        return url
    }

    private func writeSparseFile(
        _ prefix: Data,
        named name: String,
        byteCount: Int,
        in directory: URL
    ) throws -> URL {
        let url = try writeFile(prefix, named: name, in: directory)
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(byteCount))
        try handle.close()
        return url
    }

    private func writeSparsePDF(
        _ data: Data,
        named name: String,
        byteCount: Int,
        in directory: URL
    ) throws -> URL {
        let marker = Data("startxref".utf8)
        guard let tailRange = data.range(
            of: marker,
            options: .backwards
        ) else {
            throw EnterpriseCoverageFixtureError.pdfEncodingFailed
        }
        let prefix = Data(data[..<tailRange.lowerBound])
        let tail = Data(data[tailRange.lowerBound...])
        let tailOffset = max(prefix.count, byteCount - tail.count)
        let url = try writeFile(prefix, named: name, in: directory)
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(tailOffset))
        try handle.seek(toOffset: UInt64(tailOffset))
        try handle.write(contentsOf: tail)
        try handle.close()
        return url
    }

    private func waitUntil(
        _ condition: @escaping @MainActor () -> Bool
    ) async {
        for _ in 0..<500 {
            if condition() {
                return
            }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
    }
}

private enum EnterpriseCoverageFixtureError: Error {
    case imageEncodingFailed
    case pdfEncodingFailed
}

private final class EnterpriseOCRResolutionWinnerProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValues: [Int] = []

    var values: [Int] {
        lock.withLock { storedValues }
    }

    func record(_ value: Int) {
        lock.withLock {
            storedValues.append(value)
        }
    }
}
