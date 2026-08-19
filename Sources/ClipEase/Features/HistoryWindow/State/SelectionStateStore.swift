import Foundation
import SwiftUI

@MainActor
final class SelectionStateStore: ObservableObject {
    @Published var cardInteraction = HistoryWindowCardInteractionState()
    @Published var focus = HistoryWindowFocusState()
}
