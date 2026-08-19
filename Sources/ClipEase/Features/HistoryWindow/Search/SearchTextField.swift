import SwiftUI
import AppKit

struct SearchTextField: NSViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    @Binding var isComposing: Bool
    @Binding var pendingComposedInputEvent: HistoryKeyboardPendingTextInputEvent?
    let focusRequestID: Int
    let searchHasHandedOffFocusToCard: Bool
    let hasSearchResult: Bool
    let hasSearchTokens: Bool
    let textColor: NSColor
    let font: NSFont
    let onFocusChanged: (Bool) -> Void
    let onEnterFirstResult: () -> Void
    let onDeleteLastToken: () -> Void
    let onCancel: () -> Void
    let onReachLeadingContent: () -> Void
    let onReachTrailingContent: () -> Void

    func makeNSView(context: Context) -> SearchNSTextField {
        let textField = SearchNSTextField()
        textField.delegate = context.coordinator
        textField.coordinator = context.coordinator
        textField.isBordered = false
        textField.isBezeled = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.font = font
        textField.textColor = textColor
        textField.placeholderString = L("搜索")
        textField.lineBreakMode = .byTruncatingTail
        textField.cell?.sendsActionOnEndEditing = false
        return textField
    }

    func updateNSView(_ nsView: SearchNSTextField, context: Context) {
        context.coordinator.parent = self
        nsView.coordinator = context.coordinator
        let editor = nsView.currentEditor() as? NSTextView
        let hasMarkedText = editor?.hasMarkedText() ?? false

        if !hasMarkedText, nsView.stringValue != text {
            nsView.stringValue = text
        }
        nsView.placeholderString = hasSearchTokens ? nil : L("搜索")

        if nsView.font != font {
            nsView.font = font
        }
        nsView.textColor = textColor

        if searchHasHandedOffFocusToCard {
            if nsView.window?.firstResponder === nsView.currentEditor() {
                nsView.window?.makeFirstResponder(nil)
            }
        } else if isFocused {
            if nsView.window?.firstResponder !== nsView.currentEditor() {
                nsView.window?.makeFirstResponder(nsView)
            }
            context.coordinator.configureEditor(in: nsView)
            if !hasMarkedText, context.coordinator.handledFocusRequestID != focusRequestID {
                context.coordinator.handledFocusRequestID = focusRequestID
                context.coordinator.moveInsertionPointToEndSoon(in: nsView)
            }
            context.coordinator.consumePendingComposedInputEventSoon(in: nsView)
        } else if nsView.window?.firstResponder === nsView.currentEditor() {
            nsView.window?.makeFirstResponder(nil)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    @MainActor
    final class SearchNSTextField: NSTextField {
        weak var coordinator: Coordinator?

        override func keyDown(with event: NSEvent) {
            guard HistoryInputFocusCoordinator().shouldRestoreSearchTextFieldFocus(
                searchHasHandedOffFocusToCard: coordinator?.parent.searchHasHandedOffFocusToCard ?? false
            ) else {
                if event.keyCode == KeyCode.space {
                    HistoryWindowInputState.currentForTextEditing?.dispatch(.togglePreview)
                    return
                }
                super.keyDown(with: event)
                return
            }

            coordinator?.parent.onFocusChanged(true)
            super.keyDown(with: event)
        }

        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            guard HistoryInputFocusCoordinator().shouldRestoreSearchTextFieldFocus(
                searchHasHandedOffFocusToCard: coordinator?.parent.searchHasHandedOffFocusToCard ?? false
            ) else {
                return super.performKeyEquivalent(with: event)
            }

            coordinator?.parent.onFocusChanged(true)

            guard event.modifierFlags.contains(.command),
                  let characters = event.charactersIgnoringModifiers?.lowercased(),
                  characters.count == 1,
                  let editor = currentEditor() as? NSTextView else {
                return super.performKeyEquivalent(with: event)
            }

            switch characters {
            case "a":
                editor.selectAll(nil)
                editor.setNeedsDisplay(editor.visibleRect)
                return true
            case "c":
                editor.copy(nil)
                return true
            case "x":
                editor.cut(nil)
                return true
            case "v":
                editor.paste(nil)
                return true
            case "z":
                if event.modifierFlags.contains(.shift) {
                    editor.undoManager?.redo()
                } else {
                    editor.undoManager?.undo()
                }
                return true
            default:
                return true
            }
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: SearchTextField
        var handledFocusRequestID = 0

        init(parent: SearchTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else {
                return
            }

            parent.isComposing = (textField.currentEditor() as? NSTextView)?.hasMarkedText() ?? false
            parent.text = textField.stringValue
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            parent.onFocusChanged(true)
            if let textField = notification.object as? NSTextField {
                configureEditor(in: textField)
            }
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            parent.isComposing = false
            parent.onFocusChanged(false)
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.insertNewline(_:)):
                if parent.hasSearchResult {
                    parent.onEnterFirstResult()
                }
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                parent.onCancel()
                return true
            case #selector(NSResponder.insertTab(_:)):
                if parent.hasSearchResult {
                    parent.onEnterFirstResult()
                }
                return true
            case #selector(NSResponder.moveDown(_:)):
                if parent.hasSearchResult {
                    parent.onEnterFirstResult()
                }
                return true
            case #selector(NSResponder.moveLeft(_:)):
                if textView.selectedRange().location == 0 {
                    DispatchQueue.main.async { [parent] in
                        parent.onReachLeadingContent()
                    }
                }
                return false
            case #selector(NSResponder.moveRight(_:)):
                let selection = textView.selectedRange()
                if selection.location + selection.length == (textView.string as NSString).length {
                    DispatchQueue.main.async { [parent] in
                        parent.onReachTrailingContent()
                    }
                }
                return false
            case #selector(NSResponder.deleteBackward(_:)):
                guard parent.text.isEmpty, parent.hasSearchTokens else {
                    return false
                }

                parent.onDeleteLastToken()
                return true
            case #selector(NSResponder.selectAll(_:)):
                textView.selectAll(nil)
                return true
            default:
                return false
            }
        }

        func moveInsertionPointToEnd(in textField: NSTextField) {
            guard let editor = textField.currentEditor() else {
                return
            }

            let endLocation = (textField.stringValue as NSString).length
            if editor.selectedRange.location != endLocation || editor.selectedRange.length != 0 {
                editor.selectedRange = NSRange(location: endLocation, length: 0)
            }
        }

        func configureEditor(in textField: NSTextField) {
            guard let editor = textField.currentEditor() as? NSTextView else {
                return
            }

            editor.insertionPointColor = .labelColor
            editor.selectedTextAttributes = [
                .backgroundColor: NSColor.selectedTextBackgroundColor,
                .foregroundColor: NSColor.selectedTextColor
            ]
        }

        func moveInsertionPointToEndSoon(in textField: NSTextField) {
            DispatchQueue.main.async { [weak textField] in
                guard let textField else {
                    return
                }

                if textField.window?.firstResponder !== textField.currentEditor() {
                    textField.window?.makeFirstResponder(textField)
                }
                self.moveInsertionPointToEnd(in: textField)
            }
        }

        func consumePendingComposedInputEventSoon(in textField: SearchNSTextField) {
            guard parent.pendingComposedInputEvent != nil else {
                return
            }

            DispatchQueue.main.async { [weak self, weak textField] in
                guard let self,
                      let textField,
                      let event = self.parent.pendingComposedInputEvent else {
                    return
                }

                if textField.window?.firstResponder !== textField.currentEditor() {
                    textField.window?.makeFirstResponder(textField)
                }

                guard let editor = textField.currentEditor() as? NSTextView,
                      let nsEvent = NSEvent.keyEvent(
                        with: .keyDown,
                        location: .zero,
                        modifierFlags: NSEvent.ModifierFlags(rawValue: event.modifierFlags),
                        timestamp: ProcessInfo.processInfo.systemUptime,
                        windowNumber: textField.window?.windowNumber ?? 0,
                        context: nil,
                        characters: event.characters,
                        charactersIgnoringModifiers: event.characters,
                        isARepeat: false,
                        keyCode: event.keyCode
                      ) else {
                    return
                }

                self.parent.pendingComposedInputEvent = nil
                editor.keyDown(with: nsEvent)
            }
        }

    }
}
