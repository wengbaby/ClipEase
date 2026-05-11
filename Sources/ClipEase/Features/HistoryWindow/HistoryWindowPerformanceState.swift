import SwiftUI

@MainActor
final class HistoryWindowPerformanceState: ObservableObject {
    @Published var useLightweightBackground = false
}
