import Foundation
import AppKit
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

@Test func cardInteractionStateTreatsRepeatedValuesAsNoOps() {
    let id = UUID()
    var state = HistoryWindowCardInteractionState()

    let repeatedNilSelection = state.select(nil)
    let firstSelection = state.select(id)
    let repeatedSelection = state.select(id)
    #expect(!repeatedNilSelection)
    #expect(firstSelection)
    #expect(!repeatedSelection)

    let firstHover = state.setHover(id, isHovered: true)
    let repeatedHover = state.setHover(id, isHovered: true)
    let firstHoverClear = state.setHover(id, isHovered: false)
    let repeatedHoverClear = state.setHover(id, isHovered: false)
    #expect(firstHover)
    #expect(!repeatedHover)
    #expect(firstHoverClear)
    #expect(!repeatedHoverClear)

    let firstPress = state.setPress(id, isPressed: true)
    let repeatedPress = state.setPress(id, isPressed: true)
    let firstPressClear = state.setPress(id, isPressed: false)
    let repeatedPressClear = state.setPress(id, isPressed: false)
    #expect(firstPress)
    #expect(!repeatedPress)
    #expect(firstPressClear)
    #expect(!repeatedPressClear)
}

@Test @MainActor func cardDragSourceTracksHoverOnlyAtEnteredAndExitedBoundaries() throws {
    let view = FileCardDragSourceNSView(frame: NSRect(x: 0, y: 0, width: 250, height: 270))
    var hoverChanges: [Bool] = []
    var pressChanges: [Bool] = []
    view.onHoverChanged = { hoverChanges.append($0) }
    view.onPressChanged = { pressChanges.append($0) }

    view.updateTrackingAreas()
    let enteredEvent = try #require(cardEnterExitEvent(type: .mouseEntered))
    let mouseDownEvent = try #require(cardMouseEvent(type: .leftMouseDown))
    let exitedEvent = try #require(cardEnterExitEvent(type: .mouseExited))
    view.mouseEntered(with: enteredEvent)
    view.mouseDown(with: mouseDownEvent)
    view.mouseExited(with: exitedEvent)

    #expect(!view.trackingAreas.isEmpty)
    #expect(view.trackingAreas.allSatisfy { !$0.options.contains(.mouseMoved) })
    #expect(view.trackingAreas.contains { $0.options.contains(.mouseEnteredAndExited) })
    #expect(hoverChanges == [true, false])
    #expect(pressChanges == [true, false])
}

@Test @MainActor func cardMouseUpInsidePreservesHoverWithoutMouseMovedTracking() throws {
    let view = FileCardDragSourceNSView(frame: NSRect(x: 0, y: 0, width: 250, height: 270))
    var hoverChanges: [Bool] = []
    var pressChanges: [Bool] = []
    view.onHoverChanged = { hoverChanges.append($0) }
    view.onPressChanged = { pressChanges.append($0) }

    let enteredEvent = try #require(cardEnterExitEvent(type: .mouseEntered))
    let mouseDownEvent = try #require(cardMouseEvent(type: .leftMouseDown))
    let mouseUpEvent = try #require(cardMouseEvent(type: .leftMouseUp))
    view.mouseEntered(with: enteredEvent)
    view.mouseDown(with: mouseDownEvent)
    view.mouseUp(with: mouseUpEvent)

    #expect(hoverChanges == [true, true])
    #expect(pressChanges == [true, false])
}

@MainActor
private func cardEnterExitEvent(type: NSEvent.EventType) -> NSEvent? {
    NSEvent.enterExitEvent(
        with: type,
        location: .zero,
        modifierFlags: [],
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        eventNumber: 0,
        trackingNumber: 0,
        userData: nil
    )
}

@MainActor
private func cardMouseEvent(type: NSEvent.EventType) -> NSEvent? {
    NSEvent.mouseEvent(
        with: type,
        location: .zero,
        modifierFlags: [],
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        eventNumber: 0,
        clickCount: 1,
        pressure: 0
    )
}
