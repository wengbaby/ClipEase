import Foundation

@MainActor
final class HistoryWindowRenderState: ObservableObject {
    static let initialVisibleItemLimit = 14
    static let preheatItemLimit = 18

    @Published private(set) var visibleItemLimit: Int?

    func prepareForShow() {
        visibleItemLimit = Self.initialVisibleItemLimit
    }

    func revealAllItems() {
        visibleItemLimit = nil
    }
}
