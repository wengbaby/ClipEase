import Foundation
import Testing
@testable import ClipEase

@Test func hiddenInsertOpensDirectlyAtTheNewItemWithoutHorizontalAnimation() {
    let latestID = UUID()
    let firstID = UUID()

    let plan = HistoryPresentationPlanner.show(
        latestItemID: latestID,
        rememberedItemID: nil,
        firstItemID: firstID,
        hasUserNavigation: false
    )

    #expect(plan.selectedID == latestID)
    #expect(plan.viewport == .item(latestID, animated: false))
    #expect(plan.resetsScope)
    #expect(plan.consumesLatestFocus)
    #expect(!plan.playsEntranceAnimation)
}

@Test func visibleInsertProducesOneAnimatedViewportIntent() {
    let latestID = UUID()

    let plan = HistoryPresentationPlanner.inserted(
        itemID: latestID,
        windowPresented: true
    )

    #expect(plan.selectedID == latestID)
    #expect(plan.viewport == .item(latestID, animated: true))
    #expect(plan.resetsScope)
    #expect(plan.consumesLatestFocus)
    #expect(plan.playsEntranceAnimation)
}

@Test func repeatedOpenDoesNotReplayAConsumedLatestItemJump() {
    let rememberedID = UUID()
    let firstID = UUID()

    let plan = HistoryPresentationPlanner.show(
        latestItemID: nil,
        rememberedItemID: rememberedID,
        firstItemID: firstID,
        hasUserNavigation: true
    )

    #expect(plan.selectedID == rememberedID)
    #expect(plan.viewport == .restore)
    #expect(!plan.resetsScope)
    #expect(!plan.consumesLatestFocus)
    #expect(!plan.playsEntranceAnimation)
}

@Test func defaultOpenUsesTheFirstItemAndZeroOffset() {
    let firstID = UUID()

    let plan = HistoryPresentationPlanner.show(
        latestItemID: nil,
        rememberedItemID: nil,
        firstItemID: firstID,
        hasUserNavigation: false
    )

    #expect(plan.selectedID == firstID)
    #expect(plan.viewport == .first)
    #expect(!plan.resetsScope)
}

@Test func presentationPlannerComputesTheFinalLeadingOffsetBeforeOrdering() {
    let pinnedIDs = (0..<4).map { _ in UUID() }
    let latestID = UUID()

    #expect(HistoryPresentationPlanner.leadingOffset(
        for: latestID,
        orderedIDs: pinnedIDs + [latestID]
    ) == 1_080)
}
