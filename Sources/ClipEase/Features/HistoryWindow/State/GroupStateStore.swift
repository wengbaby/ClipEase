import Foundation
import SwiftUI

@MainActor
final class GroupStateStore: ObservableObject {
    @Published var uiState = HistoryWindowGroupUIState()
}
