import Foundation
import Testing
@testable import ClipEase

@Test @MainActor func ocrCoordinatorCancelsSelectedAndAllTasks() {
    let coordinator = HistoryOCRCoordinator(
        limiter: ClipboardOCRConcurrencyLimiter(idleLimit: 0, interactiveLimit: 0)
    )
    let first = ClipboardItem.image(
        fileName: "first.png",
        width: 1,
        height: 1,
        hash: "first",
        sourceApp: .clipease
    )
    let second = ClipboardItem.image(
        fileName: "second.png",
        width: 1,
        height: 1,
        hash: "second",
        sourceApp: .clipease
    )

    coordinator.enqueue(
        item: first,
        sourceURL: URL(fileURLWithPath: "/tmp/first.png"),
        setProcessing: { _ in },
        applyResult: { _, _, _ in }
    )
    coordinator.enqueue(
        item: second,
        sourceURL: URL(fileURLWithPath: "/tmp/second.png"),
        setProcessing: { _ in },
        applyResult: { _, _, _ in }
    )

    #expect(coordinator.hasInFlightTask(for: first.id))
    #expect(coordinator.hasInFlightTask(for: second.id))

    coordinator.cancelTasks(for: [first.id])

    #expect(!coordinator.hasInFlightTask(for: first.id))
    #expect(coordinator.hasInFlightTask(for: second.id))

    coordinator.cancelAllTasks()

    #expect(!coordinator.hasInFlightTask(for: second.id))
}

@Test @MainActor func ocrCoordinatorAppliesFailedResultWhenSourceURLIsMissing() async {
    let coordinator = HistoryOCRCoordinator()
    let item = ClipboardItem.image(
        fileName: "missing.png",
        width: 1,
        height: 1,
        hash: "missing",
        sourceApp: .clipease
    )
    var appliedStatus: ClipboardOCRStatus?
    var appliedResult: ClipboardOCRMatch?

    coordinator.enqueue(
        item: item,
        sourceURL: nil,
        setProcessing: { _ in },
        applyResult: { result, status, _ in
            appliedResult = result
            appliedStatus = status
        }
    )

    for _ in 0..<20 where appliedStatus == nil {
        try? await Task.sleep(nanoseconds: 1_000_000)
    }

    #expect(appliedStatus == .failed)
    #expect(appliedResult == ClipboardOCRMatch(text: "", emails: [], phoneNumbers: [], urls: [], textRegions: []))
    #expect(!coordinator.hasInFlightTask(for: item.id))
}
