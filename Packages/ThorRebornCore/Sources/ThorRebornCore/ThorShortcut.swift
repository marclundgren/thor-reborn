import Carbon.HIToolbox

/// A global keyboard shortcut: one non-modifier key plus a set of modifiers.
///
/// Serializes to the same string format as the original Thor's `apps.json`:
/// modifiers joined with `+` in the fixed order `shift`, `ctrl`, `alt`, `cmd`,
/// followed by the key name — for example `"shift+cmd+g"`.
///
/// A shortcut always has exactly one non-modifier key; modifier-only shortcuts
/// cannot be constructed or parsed.
public struct ThorShortcut: Hashable, Sendable, CustomStringConvertible {
    public struct Modifiers: OptionSet, Hashable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        public static let shift = Modifiers(rawValue: 1 << 0)
        public static let control = Modifiers(rawValue: 1 << 1)
        public static let option = Modifiers(rawValue: 1 << 2)
        public static let command = Modifiers(rawValue: 1 << 3)

        public static let all: Modifiers = [.shift, .control, .option, .command]
    }

    /// Carbon virtual key code (`kVK_*`).
    public let keyCode: Int
    public let modifiers: Modifiers

    public init(keyCode: Int, modifiers: Modifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// The fixed menu-bar icon toggle hotkey: Shift+Control+Option+Command+T.
    public static let menuBarToggle = ThorShortcut(keyCode: kVK_ANSI_T, modifiers: .all)

    // MARK: String format

    /// Parses a shortcut string such as `"shift+cmd+g"`.
    ///
    /// Modifiers may appear in any order. Returns `nil` for empty strings, unknown
    /// tokens, repeated modifiers, more than one key, or modifier-only strings.
    public init?(string: String) {
        // No key name contains "+", so an empty token always means a malformed string.
        let tokens = string.lowercased().split(separator: "+", omittingEmptySubsequences: false).map(String.init)
        guard !tokens.contains(where: \.isEmpty) else { return nil }

        var modifiers: Modifiers = []
        var keyCode: Int?

        for token in tokens {
            if let modifier = Self.modifierAliases[token] {
                guard !modifiers.contains(modifier) else { return nil }
                modifiers.insert(modifier)
            } else if let code = Self.keyCode(forName: token) {
                guard keyCode == nil else { return nil } // only one key per shortcut
                keyCode = code
            } else {
                return nil
            }
        }

        guard let keyCode else { return nil }
        self.init(keyCode: keyCode, modifiers: modifiers)
    }

    /// The serialized form, e.g. `"shift+cmd+g"`.
    public var stringValue: String {
        var components: [String] = []
        if modifiers.contains(.shift) { components.append("shift") }
        if modifiers.contains(.control) { components.append("ctrl") }
        if modifiers.contains(.option) { components.append("alt") }
        if modifiers.contains(.command) { components.append("cmd") }
        components.append(keyName)
        return components.joined(separator: "+")
    }

    /// The name of the non-modifier key as used in the string format.
    public var keyName: String {
        Self.keyNames[keyCode] ?? "keycode_\(keyCode)"
    }

    public var description: String { stringValue }

    // MARK: Tables

    private static func keyCode(forName name: String) -> Int? {
        if let code = keyCodesByName[name] {
            return code
        }
        if name.hasPrefix("keycode_"), let code = Int(name.dropFirst("keycode_".count)), (0...0x7F).contains(code),
           !modifierKeyCodes.contains(code) {
            return code
        }
        return nil
    }

    /// Accepted modifier spellings. The canonical (serialized) names are `shift`, `ctrl`, `alt`, `cmd`.
    static let modifierAliases: [String: Modifiers] = [
        "shift": .shift,
        "ctrl": .control, "control": .control,
        "alt": .option, "opt": .option, "option": .option,
        "cmd": .command, "command": .command
    ]

    /// Key codes of the modifier keys themselves; these can never be "the key" of a shortcut.
    static let modifierKeyCodes: Set<Int> = [
        kVK_Shift, kVK_RightShift, kVK_Control, kVK_RightControl,
        kVK_Option, kVK_RightOption, kVK_Command, kVK_RightCommand, kVK_Function
    ]

    /// Key names, identical to the original Thor's `MASShortcut.keycodeMap`, plus a few
    /// keys the original could not serialize (`forwarddelete`, `help`, `section`).
    static let keyNames: [Int: String] = [
        kVK_ANSI_A: "a", kVK_ANSI_S: "s", kVK_ANSI_D: "d", kVK_ANSI_F: "f", kVK_ANSI_H: "h",
        kVK_ANSI_G: "g", kVK_ANSI_Z: "z", kVK_ANSI_X: "x", kVK_ANSI_C: "c", kVK_ANSI_V: "v",
        kVK_ANSI_B: "b", kVK_ANSI_Q: "q", kVK_ANSI_W: "w", kVK_ANSI_E: "e", kVK_ANSI_R: "r",
        kVK_ANSI_Y: "y", kVK_ANSI_T: "t", kVK_ANSI_O: "o", kVK_ANSI_U: "u", kVK_ANSI_I: "i",
        kVK_ANSI_P: "p", kVK_ANSI_L: "l", kVK_ANSI_J: "j", kVK_ANSI_K: "k", kVK_ANSI_N: "n",
        kVK_ANSI_M: "m",

        kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3", kVK_ANSI_4: "4", kVK_ANSI_5: "5",
        kVK_ANSI_6: "6", kVK_ANSI_7: "7", kVK_ANSI_8: "8", kVK_ANSI_9: "9", kVK_ANSI_0: "0",

        kVK_ANSI_Equal: "=", kVK_ANSI_Minus: "-", kVK_ANSI_RightBracket: "]",
        kVK_ANSI_LeftBracket: "[", kVK_ANSI_Quote: "\"", kVK_ANSI_Semicolon: ";",
        kVK_ANSI_Backslash: "\\", kVK_ANSI_Comma: ",", kVK_ANSI_Slash: "/",
        kVK_ANSI_Period: ".", kVK_ANSI_Grave: "`",

        kVK_ANSI_KeypadDecimal: "numpad_decimal", kVK_ANSI_KeypadMultiply: "numpad_multiply",
        kVK_ANSI_KeypadPlus: "numpad_add", kVK_ANSI_KeypadDivide: "numpad_divide",
        kVK_ANSI_KeypadMinus: "numpad_subtract", kVK_ANSI_KeypadClear: "numpad_clear",
        kVK_ANSI_KeypadEnter: "numpad_enter", kVK_ANSI_KeypadEquals: "numpad_equals",
        kVK_ANSI_Keypad0: "numpad0", kVK_ANSI_Keypad1: "numpad1", kVK_ANSI_Keypad2: "numpad2",
        kVK_ANSI_Keypad3: "numpad3", kVK_ANSI_Keypad4: "numpad4", kVK_ANSI_Keypad5: "numpad5",
        kVK_ANSI_Keypad6: "numpad6", kVK_ANSI_Keypad7: "numpad7", kVK_ANSI_Keypad8: "numpad8",
        kVK_ANSI_Keypad9: "numpad9",

        kVK_Return: "return", kVK_End: "end", kVK_Home: "home", kVK_Tab: "tab",
        kVK_Escape: "escape", kVK_Space: "space", kVK_Delete: "delete", kVK_CapsLock: "capslock",
        kVK_PageDown: "pagedown", kVK_PageUp: "pageup",

        kVK_LeftArrow: "left", kVK_RightArrow: "right", kVK_DownArrow: "down", kVK_UpArrow: "up",

        kVK_F1: "f1", kVK_F2: "f2", kVK_F3: "f3", kVK_F4: "f4", kVK_F5: "f5", kVK_F6: "f6",
        kVK_F7: "f7", kVK_F8: "f8", kVK_F9: "f9", kVK_F10: "f10", kVK_F11: "f11", kVK_F12: "f12",
        kVK_F13: "f13", kVK_F14: "f14", kVK_F15: "f15", kVK_F16: "f16", kVK_F17: "f17",
        kVK_F18: "f18", kVK_F19: "f19", kVK_F20: "f20",

        kVK_ForwardDelete: "forwarddelete", kVK_Help: "help", kVK_ISO_Section: "section"
    ]

    static let keyCodesByName: [String: Int] = {
        var map = Dictionary(uniqueKeysWithValues: keyNames.map { ($1, $0) })
        map["'"] = kVK_ANSI_Quote // lenient: the original wrote `"` for the quote key
        return map
    }()
}
