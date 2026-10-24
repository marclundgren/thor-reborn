import Carbon.HIToolbox
import Testing
@testable import ThorRebornCore

@Suite("Shortcut string format")
struct ThorShortcutTests {
    @Test("Serializes modifiers in the original Thor order")
    func serializeOrder() {
        let shortcut = ThorShortcut(keyCode: kVK_ANSI_G, modifiers: [.command, .shift])
        #expect(shortcut.stringValue == "shift+cmd+g")
        #expect(ThorShortcut.menuBarToggle.stringValue == "shift+ctrl+alt+cmd+t")
    }

    @Test("Parses modifiers in any order", arguments: ["cmd+shift+g", "shift+cmd+g", "SHIFT+CMD+G", "command+shift+g"])
    func parseAnyOrder(string: String) throws {
        let shortcut = try #require(ThorShortcut(string: string))
        #expect(shortcut.keyCode == kVK_ANSI_G)
        #expect(shortcut.modifiers == [.shift, .command])
    }

    @Test("Every key name round-trips with every modifier combination")
    func roundTripAllKeys() throws {
        let modifierCombos: [ThorShortcut.Modifiers] = (0..<16).map { ThorShortcut.Modifiers(rawValue: $0) }
        for keyCode in ThorShortcut.keyNames.keys {
            for modifiers in modifierCombos {
                let original = ThorShortcut(keyCode: keyCode, modifiers: modifiers)
                let parsed = try #require(ThorShortcut(string: original.stringValue), "\(original.stringValue)")
                #expect(parsed == original)
            }
        }
    }

    @Test("Original Thor strings parse", arguments: [
        ("shift+ctrl+alt+cmd+t", kVK_ANSI_T),
        ("alt+cmd+space", kVK_Space),
        ("ctrl+numpad_add", kVK_ANSI_KeypadPlus),
        ("cmd+\"", kVK_ANSI_Quote),
        ("cmd+'", kVK_ANSI_Quote),
        ("f5", kVK_F5),
        ("ctrl+=", kVK_ANSI_Equal)
    ])
    func parsesOriginalStrings(string: String, keyCode: Int) throws {
        #expect(try #require(ThorShortcut(string: string)).keyCode == keyCode)
    }

    @Test("Keys without a name use a keycode_N fallback that round-trips")
    func unnamedKeyFallback() throws {
        let shortcut = ThorShortcut(keyCode: kVK_F21Placeholder, modifiers: [.control])
        #expect(shortcut.stringValue == "ctrl+keycode_\(kVK_F21Placeholder)")
        #expect(ThorShortcut(string: shortcut.stringValue) == shortcut)
    }

    @Test("Invalid strings are rejected", arguments: [
        "", "cmd", "cmd+shift", "shift+ctrl+alt+cmd", // modifier-only
        "cmd+g+h", "cmd+cmd+g", "cmd++g", "+g", "g+", "hyper+g", "cmd+keycode_56", "cmd+keycode_999"
    ])
    func rejectsInvalid(string: String) {
        #expect(ThorShortcut(string: string) == nil)
    }
}

/// An otherwise unnamed key code (kVK_JIS_Yen) used to exercise the fallback path.
private let kVK_F21Placeholder = kVK_JIS_Yen
