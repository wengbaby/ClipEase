import Foundation

enum HistoryViewportIntent: Equatable {
    case first
    case restore
    case item(ClipboardItem.ID, animated: Bool)
}

struct HistoryPresentationPlan: Equatable {
    let selectedID: ClipboardItem.ID?
    let viewport: HistoryViewportIntent
    let resetsScope: Bool
    let consumesLatestFocus: Bool
    let playsEntranceAnimation: Bool
}

enum HistoryPresentationPlanner {
    static func show(
        latestItemID: ClipboardItem.ID?,
        rememberedItemID: ClipboardItem.ID?,
        firstItemID: ClipboardItem.ID?,
        hasUserNavigation: Bool
    ) -> HistoryPresentationPlan {
        if let latestItemID {
            return HistoryPresentationPlan(
                selectedID: latestItemID,
                viewport: .item(latestItemID, animated: false),
                resetsScope: true,
                consumesLatestFocus: true,
                playsEntranceAnimation: false
            )
        }

        if hasUserNavigation,
           let rememberedItemID {
            return HistoryPresentationPlan(
                selectedID: rememberedItemID,
                viewport: .restore,
                resetsScope: false,
                consumesLatestFocus: false,
                playsEntranceAnimation: false
            )
        }

        return HistoryPresentationPlan(
            selectedID: firstItemID,
            viewport: .first,
            resetsScope: false,
            consumesLatestFocus: false,
            playsEntranceAnimation: false
        )
    }

    static func inserted(
        itemID: ClipboardItem.ID,
        windowPresented: Bool
    ) -> HistoryPresentationPlan {
        HistoryPresentationPlan(
            selectedID: itemID,
            viewport: .item(itemID, animated: windowPresented),
            resetsScope: true,
            consumesLatestFocus: true,
            playsEntranceAnimation: true
        )
    }

    static func leadingOffset(
        for itemID: ClipboardItem.ID,
        orderedIDs: [ClipboardItem.ID],
        itemStride: CGFloat = 270
    ) -> CGFloat? {
        guard let index = orderedIDs.firstIndex(of: itemID) else {
            return nil
        }
        return CGFloat(index) * itemStride
    }
}
