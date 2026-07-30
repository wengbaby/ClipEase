import Foundation
import PDFKit
import Testing
@testable import ClipEase

@Test func ocrInputPolicyEnforcesImageBytePixelAndEdgeLimits() {
    #expect(ClipboardOCRInputPolicy.imageDecision(
        byteCount: 32 * 1_024 * 1_024,
        pixelWidth: 4_096,
        pixelHeight: 4_096
    ) == .accepted)
    #expect(ClipboardOCRInputPolicy.imageDecision(
        byteCount: 32 * 1_024 * 1_024 + 1,
        pixelWidth: 1,
        pixelHeight: 1
    ) == .skipped(.imageByteLimit))
    #expect(ClipboardOCRInputPolicy.imageDecision(
        byteCount: 1,
        pixelWidth: 8_001,
        pixelHeight: 4_000
    ) == .skipped(.imagePixelLimit))
    #expect(ClipboardOCRInputPolicy.downsampleMaxPixelEdge == 4_096)
}

@Test func ocrInputPolicyEnforcesPDFByteAndPageLimits() {
    #expect(ClipboardOCRInputPolicy.pdfDecision(
        byteCount: 50 * 1_024 * 1_024,
        pageCount: 25
    ) == .accepted)
    #expect(ClipboardOCRInputPolicy.pdfDecision(
        byteCount: 50 * 1_024 * 1_024 + 1,
        pageCount: 1
    ) == .skipped(.pdfByteLimit))
    #expect(ClipboardOCRInputPolicy.pdfDecision(
        byteCount: 1,
        pageCount: 26
    ) == .skipped(.pdfPageLimit))
}

@MainActor
@Test func pdfTwentyFivePageBoundaryIsAcceptedWithoutUnboundedOCR() throws {
    let data = try makePayloadTestPDF(pageCount: 25)
    let document = PDFDocument(data: data)

    #expect(document?.pageCount == 25)
    #expect(ClipboardOCRInputPolicy.pdfDecision(
        byteCount: data.count,
        pageCount: document?.pageCount ?? 0
    ) == .accepted)
    #expect(ClipboardOCRInputPolicy.maximumPDFPages == 25)
    #expect(ClipboardOCRInputPolicy.pageTimeoutNanoseconds == 2_000_000_000)
    #expect(ClipboardOCRInputPolicy.itemTimeoutNanoseconds == 10_000_000_000)
}

@Test func ocrLimiterUsesBoundedProductionDefaultsAndDefersWhenQueueIsFull() async {
    #expect(ClipboardOCRConcurrencyLimiter.defaultInteractiveLimit == 1)
    #expect(ClipboardOCRConcurrencyLimiter.defaultIdleLimit == 2)
    #expect(ClipboardOCRConcurrencyLimiter.defaultMaximumWaitingCount == 64)

    let limiter = ClipboardOCRConcurrencyLimiter(
        idleLimit: 0,
        interactiveLimit: 0,
        maximumWaitingCount: 0
    )
    #expect(await limiter.waitForTurn() == .deferred)
}

@MainActor
@Test func ocrCoordinatorPublishesTimeoutOutcomeAndFinishesTask() async {
    let item = ClipboardItem.image(
        fileName: "slow.png",
        width: 1,
        height: 1,
        hash: "slow",
        sourceApp: .clipease
    )
    let coordinator = HistoryOCRCoordinator(
        limiter: ClipboardOCRConcurrencyLimiter(idleLimit: 1, interactiveLimit: 1),
        imageRecognizer: { _ in
            try? await Task.sleep(nanoseconds: 100_000_000)
            return ClipboardOCRMatch(
                text: "late",
                emails: [],
                phoneNumbers: [],
                urls: [],
                textRegions: []
            )
        },
        itemTimeoutNanoseconds: 1_000_000
    )
    var outcome: ClipboardOCRExecutionOutcome?

    coordinator.enqueue(
        item: item,
        sourceURL: URL(fileURLWithPath: "/tmp/slow.png"),
        setProcessing: { _ in },
        applyResult: { _, _, _ in },
        applyOutcome: { value, _ in
            outcome = value
        }
    )

    for _ in 0..<100 where outcome == nil {
        try? await Task.sleep(nanoseconds: 1_000_000)
    }

    #expect(outcome == .failed(.timedOut))
    #expect(!coordinator.hasInFlightTask(for: item.id))
}

@MainActor
@Test func ocrTimeoutReleasesLimiterSlotWhileUncooperativeRecognizerDrainsCleanly() async {
    let stalledRecognizer = ControlledUncooperativeOCRRecognizer()
    let stalledItem = ClipboardItem.image(
        fileName: "never.png",
        width: 1,
        height: 1,
        hash: "never",
        sourceApp: .clipease
    )
    let followingItem = ClipboardItem.image(
        fileName: "following.png",
        width: 1,
        height: 1,
        hash: "following",
        sourceApp: .clipease
    )
    let limiter = ClipboardOCRConcurrencyLimiter(
        idleLimit: 1,
        interactiveLimit: 1
    )
    let coordinator = HistoryOCRCoordinator(
        limiter: limiter,
        imageRecognizer: { url in
            if url.lastPathComponent == "never.png" {
                await stalledRecognizer.waitUntilReleased()
            }
            let result = ClipboardOCRMatch(
                text: url.lastPathComponent,
                emails: [],
                phoneNumbers: [],
                urls: [],
                textRegions: []
            )
            if url.lastPathComponent == "never.png" {
                stalledRecognizer.markFinished()
            }
            return result
        },
        itemTimeoutNanoseconds: 1_000_000
    )
    let followingCoordinator = HistoryOCRCoordinator(
        limiter: limiter,
        imageRecognizer: { url in
            ClipboardOCRMatch(
                text: url.lastPathComponent,
                emails: [],
                phoneNumbers: [],
                urls: [],
                textRegions: []
            )
        },
        itemTimeoutNanoseconds: 1_000_000_000
    )
    var stalledOutcome: ClipboardOCRExecutionOutcome?
    var followingStatus: ClipboardOCRStatus?

    coordinator.enqueue(
        item: stalledItem,
        sourceURL: URL(fileURLWithPath: "/tmp/never.png"),
        setProcessing: { _ in },
        applyResult: { _, _, _ in },
        applyOutcome: { value, _ in
            stalledOutcome = value
        }
    )

    for _ in 0..<100 where stalledOutcome == nil {
        try? await Task.sleep(nanoseconds: 1_000_000)
    }
    #expect(stalledOutcome == .failed(.timedOut))

    followingCoordinator.enqueue(
        item: followingItem,
        sourceURL: URL(fileURLWithPath: "/tmp/following.png"),
        setProcessing: { _ in },
        applyResult: { _, status, _ in
            followingStatus = status
        }
    )

    for _ in 0..<100 where followingStatus == nil {
        try? await Task.sleep(nanoseconds: 1_000_000)
    }

    #expect(followingStatus == .completed)
    #expect(!followingCoordinator.hasInFlightTask(for: followingItem.id))

    stalledRecognizer.release()
    for _ in 0..<100 where !stalledRecognizer.didFinish {
        try? await Task.sleep(nanoseconds: 1_000_000)
    }
    #expect(stalledRecognizer.didFinish)
}

private final class ControlledUncooperativeOCRRecognizer: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Never>?
    private var wasReleased = false
    private var storedDidFinish = false

    var didFinish: Bool {
        lock.withLock { storedDidFinish }
    }

    func waitUntilReleased() async {
        await withCheckedContinuation { continuation in
            let shouldResume = lock.withLock {
                if wasReleased {
                    return true
                }
                self.continuation = continuation
                return false
            }
            if shouldResume {
                continuation.resume()
            }
        }
    }

    func markFinished() {
        lock.withLock {
            storedDidFinish = true
        }
    }

    func release() {
        let continuation = lock.withLock {
            wasReleased = true
            let continuation = self.continuation
            self.continuation = nil
            return continuation
        }
        continuation?.resume()
    }
}
