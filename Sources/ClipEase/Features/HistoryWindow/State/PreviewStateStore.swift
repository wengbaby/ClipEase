import Foundation
import SwiftUI

@MainActor
final class PreviewStateStore: ObservableObject {
    @Published var items = HistoryWindowPreviewItemsState()
}
