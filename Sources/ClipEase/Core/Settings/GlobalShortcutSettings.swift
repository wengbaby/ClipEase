import AppKit
import Carbon

struct GlobalShortcut: Equatable {
    let keyCode: UInt16
    let modifiers: UInt32

    var displayText: String {
        let modifierText = [
            (modifiers & UInt32(cmdKey)) != 0 ? "Command" : nil,
            (modifiers & UInt32(shiftKey)) != 0 ? "Shift" : nil,
            (modifiers & UInt32(optionKey)) != 0 ? "Option" : nil,
            (modifiers & UInt32(controlKey)) != 0 ? "Control" : nil
        ]
        .compactMap { $0 }
        .joined(separator: " + ")

        guard !modifierText.isEmpty else {
            return keyName
        }

        return "\(modifierText) + \(keyName)"
    }

    private var keyName: String {
        switch keyCode {
        case KeyCode.a: "A"
        case KeyCode.b: "B"
        case KeyCode.c: "C"
        case KeyCode.d: "D"
        case KeyCode.e: "E"
        case KeyCode.f: "F"
        case KeyCode.g: "G"
        case KeyCode.h: "H"
        case KeyCode.i: "I"
        case KeyCode.j: "J"
        case KeyCode.k: "K"
        case KeyCode.l: "L"
        case KeyCode.m: "M"
        case KeyCode.n: "N"
        case KeyCode.o: "O"
        case KeyCode.p: "P"
        case KeyCode.q: "Q"
        case KeyCode.r: "R"
        case KeyCode.s: "S"
        case KeyCode.t: "T"
        case KeyCode.u: "U"
        case KeyCode.v: "V"
        case KeyCode.w: "W"
        case KeyCode.x: "X"
        case KeyCode.y: "Y"
        case KeyCode.z: "Z"
        case KeyCode.space: "Space"
        default: "按键 \(keyCode)"
        }
    }
}

@MainActor
final class GlobalShortcutSettings: ObservableObject {
    @Published private(set) var shortcut: GlobalShortcut

    static let defaultShortcut = GlobalShortcut(
        keyCode: KeyCode.v,
        modifiers: UInt32(cmdKey | shiftKey)
    )

    private static let keyCodeKey = "globalShortcut.keyCode"
    private static let modifiersKey = "globalShortcut.modifiers"
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        let savedKeyCode = userDefaults.object(forKey: Self.keyCodeKey) as? Int
        let savedModifiers = userDefaults.object(forKey: Self.modifiersKey) as? Int
        self.shortcut = GlobalShortcut(
            keyCode: UInt16(savedKeyCode ?? Int(Self.defaultShortcut.keyCode)),
            modifiers: UInt32(savedModifiers ?? Int(Self.defaultShortcut.modifiers))
        )
    }

    @discardableResult
    func update(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags) -> Bool {
        guard keyCode != KeyCode.escape else {
            return false
        }

        let modifiers = Self.carbonModifiers(from: modifierFlags)
        let requiredModifiers = UInt32(cmdKey | controlKey | optionKey)
        guard (modifiers & requiredModifiers) != 0 else {
            return false
        }

        shortcut = GlobalShortcut(keyCode: keyCode, modifiers: modifiers)
        save()
        return true
    }

    func resetToDefault() {
        shortcut = Self.defaultShortcut
        save()
    }

    private func save() {
        userDefaults.set(Int(shortcut.keyCode), forKey: Self.keyCodeKey)
        userDefaults.set(Int(shortcut.modifiers), forKey: Self.modifiersKey)
    }

    private static func carbonModifiers(from modifierFlags: NSEvent.ModifierFlags) -> UInt32 {
        var modifiers: UInt32 = 0
        if modifierFlags.contains(.command) {
            modifiers |= UInt32(cmdKey)
        }
        if modifierFlags.contains(.shift) {
            modifiers |= UInt32(shiftKey)
        }
        if modifierFlags.contains(.option) {
            modifiers |= UInt32(optionKey)
        }
        if modifierFlags.contains(.control) {
            modifiers |= UInt32(controlKey)
        }
        return modifiers
    }
}
