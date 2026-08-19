import SwiftUI
import AppKit

struct CardViewportFrameReader: View {
    let itemID: HistoryPreviewItem.ID

    var body: some View {
        GeometryReader { proxy in
            Color.clear
                .preference(
                    key: CardViewportFramePreferenceKey.self,
                    value: [itemID: proxy.frame(in: .named("historyWindow"))]
                )
        }
    }
}

struct CardViewportFramePreferenceKey: PreferenceKey {
    static let defaultValue: [HistoryPreviewItem.ID: CGRect] = [:]

    static func reduce(value: inout [HistoryPreviewItem.ID: CGRect], nextValue: () -> [HistoryPreviewItem.ID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
