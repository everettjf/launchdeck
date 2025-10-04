import AppKit
import Carbon

struct KeyboardShortcutPreference: Codable, Equatable {
    var keyCode: UInt16
    var modifiers: NSEvent.ModifierFlags

    static let `default` = KeyboardShortcutPreference(keyCode: 49, // space bar
                                                      modifiers: [.command, .shift, .control])

    init(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        self.modifiers = modifiers.intersection(.deviceIndependentFlagsMask)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        keyCode = UInt16(try container.decode(UInt32.self, forKey: .keyCode))
        let rawModifiers = try container.decode(UInt.self, forKey: .modifiers)
        modifiers = NSEvent.ModifierFlags(rawValue: rawModifiers)
            .intersection(.deviceIndependentFlagsMask)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(UInt32(keyCode), forKey: .keyCode)
        try container.encode(modifiers.rawValue, forKey: .modifiers)
    }

    var displayString: String {
        let symbols = modifiers.displaySymbols
        let key = KeyCodeTransformer.displayName(for: keyCode)
        return symbols + key
    }

    fileprivate enum CodingKeys: String, CodingKey {
        case keyCode
        case modifiers
    }
}

private enum KeyCodeTransformer {
    static func displayName(for keyCode: UInt16) -> String {
        if let special = specialKeyNames[keyCode] {
            return special
        }
        if let characters = keyCodeToString(keyCode), !characters.isEmpty {
            return characters.uppercased()
        }
        return "Key \(keyCode)"
    }

    private static func keyCodeToString(_ keyCode: UInt16) -> String? {
        if let mapped = keyCodeMap[keyCode] {
            return mapped
        }
        return nil
    }

    private static let specialKeyNames: [UInt16: String] = [
        36: "⏎",
        48: "⇥",
        49: "Space",
        51: "⌫",
        53: "⎋",
        122: "F1",
        120: "F2",
        99: "F3",
        118: "F4",
        96: "F5",
        97: "F6",
        98: "F7",
        100: "F8",
        101: "F9",
        109: "F10",
        103: "F11",
        111: "F12"
    ]

    private static let keyCodeMap: [UInt16: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
        8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
        16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
        23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
        30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 37: "L",
        38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/",
        45: "N", 46: "M", 47: ".", 50: "`", 65: ".", 67: "*", 69: "+",
        71: "/", 75: "-", 76: "⏎", 78: "=", 81: "0", 82: "1", 83: "2",
        84: "3", 85: "4", 86: "5", 87: "6", 88: "7", 89: "8", 91: "="
    ]
}

extension NSEvent.ModifierFlags {
    var carbonFlags: UInt32 {
        var result: UInt32 = 0
        if contains(.command) { result |= UInt32(cmdKey) }
        if contains(.option) { result |= UInt32(optionKey) }
        if contains(.control) { result |= UInt32(controlKey) }
        if contains(.shift) { result |= UInt32(shiftKey) }
        return result
    }

    var displaySymbols: String {
        var symbols = ""
        if contains(.control) { symbols += "⌃" }
        if contains(.option) { symbols += "⌥" }
        if contains(.shift) { symbols += "⇧" }
        if contains(.command) { symbols += "⌘" }
        return symbols
    }
}

extension KeyboardShortcutPreference {
    func withUpdated(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> KeyboardShortcutPreference {
        KeyboardShortcutPreference(keyCode: keyCode, modifiers: modifiers)
    }
}
