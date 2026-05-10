import Foundation

@MainActor
final class HistoryPreviewState: ObservableObject {
    @Published var itemID: ClipboardItem.ID?

    var isVisible: Bool {
        itemID != nil
    }

    func open(_ id: ClipboardItem.ID) {
        itemID = id
    }

    func close() {
        itemID = nil
    }
}
