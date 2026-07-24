import AppKit
import SwiftUI

struct ShortcutDescriptor: Equatable {
    let keyEquivalent: String
    let modifierMask: NSEvent.ModifierFlags
    let displayText: String

    static let commandComma = ShortcutDescriptor(
        keyEquivalent: ",",
        modifierMask: [.command],
        displayText: "⌘,"
    )

    static func command(_ key: String) -> ShortcutDescriptor {
        ShortcutDescriptor(
            keyEquivalent: key,
            modifierMask: [.command],
            displayText: "⌘\(key.uppercased())"
        )
    }

    static func shiftCommand(_ key: String) -> ShortcutDescriptor {
        ShortcutDescriptor(
            keyEquivalent: key,
            modifierMask: [.shift, .command],
            displayText: "⇧⌘\(key.uppercased())"
        )
    }

    static let space = ShortcutDescriptor(
        keyEquivalent: " ",
        modifierMask: [],
        displayText: "Space"
    )

    static let `return` = ShortcutDescriptor(
        keyEquivalent: "\r",
        modifierMask: [],
        displayText: "⏎"
    )

    static let shiftReturn = ShortcutDescriptor(
        keyEquivalent: "\r",
        modifierMask: [.shift],
        displayText: "⇧⏎"
    )
}

enum HistoryCommand {
    case settings
    case edit
    case toggleRecording
    case preview
    case paste
    case pastePlainText
    case copy
    case copyPlainText
    case newText
    case help
    case quit
    case about

    var title: String {
        switch self {
        case .settings:
            L("设置")
        case .edit:
            L("编辑")
        case .toggleRecording:
            L("暂停 / 恢复记录")
        case .preview:
            L("预览")
        case .paste:
            L("粘贴")
        case .pastePlainText:
            L("粘贴为纯文本")
        case .copy:
            L("复制")
        case .copyPlainText:
            L("复制纯文本")
        case .newText:
            L("新建文本")
        case .help:
            L("帮助")
        case .quit:
            L("退出")
        case .about:
            L("关于轻贴")
        }
    }

    var shortcut: ShortcutDescriptor? {
        switch self {
        case .settings:
            .commandComma
        case .edit:
            .command("e")
        case .toggleRecording:
            .command("t")
        case .preview:
            .space
        case .paste:
            .return
        case .pastePlainText:
            .shiftReturn
        case .copy:
            .command("c")
        case .copyPlainText:
            .shiftCommand("c")
        case .newText, .help, .quit, .about:
            nil
        }
    }
}

extension View {
    @ViewBuilder
    func historyKeyboardShortcut(_ command: HistoryCommand) -> some View {
        if let shortcut = command.shortcut {
            self.keyboardShortcut(
                KeyEquivalent(Character(shortcut.keyEquivalent)),
                modifiers: EventModifiers(shortcut.modifierMask)
            )
        } else {
            self
        }
    }
}

private extension EventModifiers {
    init(_ modifierFlags: NSEvent.ModifierFlags) {
        self.init()
        if modifierFlags.contains(.command) {
            insert(.command)
        }
        if modifierFlags.contains(.shift) {
            insert(.shift)
        }
        if modifierFlags.contains(.option) {
            insert(.option)
        }
        if modifierFlags.contains(.control) {
            insert(.control)
        }
    }
}
