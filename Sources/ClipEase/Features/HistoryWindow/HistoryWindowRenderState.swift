import Foundation

@MainActor
final class HistoryWindowRenderState: ObservableObject {
    static let preheatItemLimit = 18

    @Published private(set) var renderGeneration = UUID()

    func prepareForShow() {
        renderGeneration = UUID()
    }
}
