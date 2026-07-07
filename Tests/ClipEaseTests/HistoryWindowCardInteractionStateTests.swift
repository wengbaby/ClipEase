import Foundation
import Testing
@testable import ClipEase

@Test func cardInteractionStateTracksSelectionHoverAndPress() {
    let first = UUID()
    let second = UUID()
    var state = HistoryWindowCardInteractionState()

    state.select(first)
    state.setHover(first, isHovered: true)
    state.setPress(first, isPressed: true)

    #expect(state.selectedItemID == first)
    #expect(state.hoveredCardID == first)
    #expect(state.pressedCardID == first)

    state.setHover(second, isHovered: false)
    state.setPress(second, isPressed: false)

    #expect(state.hoveredCardID == first)
    #expect(state.pressedCardID == first)

    state.setHover(first, isHovered: false)
    state.setPress(first, isPressed: false)

    #expect(state.hoveredCardID == nil)
    #expect(state.pressedCardID == nil)
}

@Test func cardInteractionStateStartsAndFinishesEntranceAnimation() {
    let id = UUID()
    var state = HistoryWindowCardInteractionState()

    state.startEntranceAnimation(for: id, startTime: 12)

    #expect(state.enteringItemIDs == [id])
    #expect(state.entranceSheenItemIDs == [id])
    #expect(state.entranceSheenStartTime == 12)

    state.finishEntranceSheen(for: id)
    #expect(state.entranceSheenItemIDs.isEmpty)
    #expect(state.entranceSheenStartTime == nil)

    state.finishEntering(for: id)
    #expect(state.enteringItemIDs.isEmpty)
}

@Test func cardInteractionStateClearsTransientCardState() {
    let id = UUID()
    var state = HistoryWindowCardInteractionState()
    state.select(id)
    state.setHover(id, isHovered: true)
    state.setPress(id, isPressed: true)
    state.startEntranceAnimation(for: id, startTime: 12)

    state.clearTransientState()

    #expect(state.selectedItemID == id)
    #expect(state.hoveredCardID == nil)
    #expect(state.pressedCardID == nil)
    #expect(state.enteringItemIDs.isEmpty)
    #expect(state.entranceSheenItemIDs.isEmpty)
    #expect(state.entranceSheenStartTime == nil)
}
