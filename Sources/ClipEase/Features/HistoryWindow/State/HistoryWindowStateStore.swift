import Foundation
import SwiftUI

@MainActor
final class HistoryWindowStateStore: ObservableObject {
    @Published var search = SearchStateStore()
    @Published var selection = SelectionStateStore()
    @Published var viewport = ViewportStateStore()
    @Published var preview = PreviewStateStore()
    @Published var groups = GroupStateStore()

    let searchCoordinator = HistorySearchCoordinator()
    let previewCoordinator = HistoryPreviewCoordinator()
    let viewportStore = HistoryViewportStore()
    let groupAppearanceCoordinator = GroupAppearanceCoordinator()
    let groupMouseMonitorRegistry = HistoryGroupMouseMonitorRegistry()
    let assetPreheater = PreviewAssetPreheater()
}
