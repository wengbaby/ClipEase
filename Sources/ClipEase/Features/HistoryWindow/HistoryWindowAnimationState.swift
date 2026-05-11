import SwiftUI

@MainActor
final class HistoryWindowAnimationState: ObservableObject {
    @Published var contentOffset: CGFloat = 0
}
