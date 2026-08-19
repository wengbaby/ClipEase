import Foundation
import SwiftUI

@MainActor
final class SearchStateStore: ObservableObject {
    @Published var uiState = HistoryWindowSearchUIState()
}
