import SwiftUI
import AppKit

struct GroupInlineTextField: NSViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    var placeholder: String
    var font: NSFont = .systemFont(ofSize: 13, weight: .regular)
    var textColor: NSColor = .labelColor
    var drawsBackground = true
    var isGroupRenameField = false
    var focusRequestID = 0
    var onEscape: () -> Void
    var onSubmit: (() -> Void)? = nil

    func makeNSView(context: Context) -> InlineNSTextField {
        let textField = InlineNSTextField()
        textField.delegate = context.coordinator
        textField.coordinator = context.coordinator
        textField.placeholderString = placeholder
        textField.font = font
        textField.textColor = textColor
        textField.isGroupRenameField = isGroupRenameField
        textField.isBordered = drawsBackground
        textField.isBezeled = drawsBackground
        textField.bezelStyle = .roundedBezel
        textField.drawsBackground = drawsBackground
        textField.focusRingType = drawsBackground ? .default : .none
        textField.cell?.sendsActionOnEndEditing = false
        return textField
    }

    func updateNSView(_ textField: InlineNSTextField, context: Context) {
        context.coordinator.parent = self
        textField.coordinator = context.coordinator
        if textField.stringValue != text {
            textField.stringValue = text
        }
        textField.placeholderString = placeholder
        textField.font = font
        textField.textColor = textColor
        textField.isGroupRenameField = isGroupRenameField
        textField.isBordered = drawsBackground
        textField.isBezeled = drawsBackground
        textField.drawsBackground = drawsBackground
        textField.focusRingType = drawsBackground ? .default : .none

        if isFocused {
            context.coordinator.focus(textField)
        } else if textField.window?.firstResponder === textField.currentEditor() {
            textField.window?.makeFirstResponder(nil)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    @MainActor
    final class InlineNSTextField: NSTextField {
        weak var coordinator: Coordinator?
        var isGroupRenameField = false

        override func mouseDown(with event: NSEvent) {
            coordinator?.focus(self)
            super.mouseDown(with: event)
            coordinator?.focus(self)
        }

        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            guard event.modifierFlags.contains(.command),
                  let characters = event.charactersIgnoringModifiers?.lowercased(),
                  characters.count == 1,
                  let editor = currentEditor() as? NSTextView else {
                return super.performKeyEquivalent(with: event)
            }

            switch characters {
            case "a":
                editor.selectAll(nil)
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
                return super.performKeyEquivalent(with: event)
            }
        }

        override func keyDown(with event: NSEvent) {
            switch HistoryGroupRenameKeyPolicy.action(for: event.keyCode) {
            case .submit:
                coordinator?.parent.onSubmit?()
                return
            case .cancel:
                coordinator?.parent.onEscape()
                return
            case nil:
                break
            }

            super.keyDown(with: event)
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: GroupInlineTextField
        private var handledFocusRequestID: Int?

        init(parent: GroupInlineTextField) {
            self.parent = parent
        }

        func focus(_ textField: NSTextField) {
            guard let window = textField.window else {
                requestFocusSoon(in: textField)
                return
            }

            if window.firstResponder !== textField.currentEditor() {
                window.makeFirstResponder(textField)
            }

            if handledFocusRequestID != parent.focusRequestID {
                handledFocusRequestID = parent.focusRequestID
                requestFocusSoon(in: textField)
            }
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            parent.isFocused = true
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else {
                return
            }

            parent.text = textField.stringValue
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            guard parent.isFocused else {
                return
            }

            parent.isFocused = false
            if let inputState = HistoryWindowInputState.currentForTextEditing {
                inputState.setTextInputFocused(false)
            }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.insertNewline(_:)):
                parent.onSubmit?()
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                parent.onEscape()
                return true
            default:
                return false
            }
        }

        private func requestFocusSoon(in textField: NSTextField) {
            DispatchQueue.main.async { [weak textField] in
                guard let textField,
                      let window = textField.window else {
                    return
                }

                if window.firstResponder !== textField.currentEditor() {
                    window.makeFirstResponder(textField)
                }

                guard let editor = textField.currentEditor() else {
                    return
                }

                let endLocation = (textField.stringValue as NSString).length
                editor.selectedRange = NSRange(location: endLocation, length: 0)
            }
        }
    }
}
