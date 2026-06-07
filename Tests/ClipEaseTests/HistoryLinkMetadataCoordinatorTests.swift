import Foundation
import Testing
@testable import ClipEase

@Test @MainActor func linkMetadataCoordinatorCancelsSelectedAndAllTasks() {
    let coordinator = HistoryLinkMetadataCoordinator()
    let first = UUID()
    let second = UUID()

    coordinator.fetch(
        id: first,
        url: URL(string: "https://example.com/first")!,
        persistence: ClipboardHistoryPersistence()
    ) { _, _, _, _ in }
    coordinator.fetch(
        id: second,
        url: URL(string: "https://example.com/second")!,
        persistence: ClipboardHistoryPersistence()
    ) { _, _, _, _ in }

    #expect(coordinator.hasInFlightTask(for: first))
    #expect(coordinator.hasInFlightTask(for: second))

    coordinator.cancelTasks(for: [first])

    #expect(!coordinator.hasInFlightTask(for: first))
    #expect(coordinator.hasInFlightTask(for: second))

    coordinator.cancelAllTasks()

    #expect(!coordinator.hasInFlightTask(for: second))
}
