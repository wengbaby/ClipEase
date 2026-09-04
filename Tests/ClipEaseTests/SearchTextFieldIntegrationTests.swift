import AppKit
import Foundation
import SwiftUI
import Testing
@testable import ClipEase

@MainActor
@Test func searchTextFieldCoordinatorCommitsTextAndRoutesEditingCommands() async throws {
    let state = SearchTextFieldIntegrationState()
    let tokenKind = HistorySearchTokenKind.type(.text)
    let representable = state.representable(selectedTokenKind: tokenKind)
    let coordinator = representable.makeCoordinator()
    let field = SearchTextField.SearchNSTextField()
    field.cell = SearchTextFieldCell(textCell: "")
    field.delegate = coordinator
    field.coordinator = coordinator
    field.stringValue = "窗口"

    coordinator.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: field))
    try await Task.sleep(nanoseconds: SearchTextField.textCommitDelayNanoseconds + 20_000_000)
    #expect(state.text == "窗口")

    let editor = NSTextView()
    editor.string = ""
    editor.setSelectedRange(NSRange(location: 0, length: 0))
    #expect(coordinator.control(field, textView: editor, doCommandBy: #selector(NSResponder.moveLeft(_:))))
    #expect(state.previousTokenCount == 1)
    #expect(coordinator.control(field, textView: editor, doCommandBy: #selector(NSResponder.moveRight(_:))))
    #expect(state.nextTokenCount == 1)

    state.text = ""
    #expect(coordinator.control(field, textView: editor, doCommandBy: #selector(NSResponder.deleteBackward(_:))))
    #expect(state.deleteTokenCount == 1)
    #expect(coordinator.control(field, textView: editor, doCommandBy: #selector(NSResponder.insertNewline(_:))))
    #expect(state.enterCount == 1)
    #expect(coordinator.control(field, textView: editor, doCommandBy: #selector(NSResponder.cancelOperation(_:))))
    #expect(state.cancelCount == 1)

    coordinator.controlTextDidBeginEditing(Notification(name: NSControl.textDidBeginEditingNotification, object: field))
    coordinator.controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification, object: field))
    #expect(state.focusChanges == [true, false])
}

@MainActor
private final class SearchTextFieldIntegrationState {
    var text = ""
    var isFocused = true
    var isComposing = false
    var pendingEvent: HistoryKeyboardPendingTextInputEvent?
    var focusChanges: [Bool] = []
    var enterCount = 0
    var deleteTokenCount = 0
    var previousTokenCount = 0
    var nextTokenCount = 0
    var cancelCount = 0

    func representable(selectedTokenKind: HistorySearchTokenKind?) -> SearchTextField {
        SearchTextField(
            text: Binding(get: { self.text }, set: { self.text = $0 }),
            isFocused: Binding(get: { self.isFocused }, set: { self.isFocused = $0 }),
            isComposing: Binding(get: { self.isComposing }, set: { self.isComposing = $0 }),
            pendingComposedInputEvent: Binding(get: { self.pendingEvent }, set: { self.pendingEvent = $0 }),
            focusRequestID: 1,
            searchHasHandedOffFocusToCard: false,
            hasSearchResult: true,
            hasSearchTokens: true,
            selectedTokenKind: selectedTokenKind,
            textColor: .labelColor,
            font: .systemFont(ofSize: 13),
            onFocusChanged: { self.focusChanges.append($0) },
            onEnterFirstResult: { self.enterCount += 1 },
            onDeleteLastToken: { self.deleteTokenCount += 1 },
            onMoveToPreviousToken: { self.previousTokenCount += 1 },
            onMoveToNextToken: { self.nextTokenCount += 1 },
            onCancel: { self.cancelCount += 1 },
            onReachLeadingContent: {},
            onReachTrailingContent: {}
        )
    }
}
