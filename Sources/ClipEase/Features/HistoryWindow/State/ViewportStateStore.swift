import Foundation
import SwiftUI

@MainActor
final class ViewportStateStore: ObservableObject {
    @Published var viewport = HistoryWindowViewportState()
}
