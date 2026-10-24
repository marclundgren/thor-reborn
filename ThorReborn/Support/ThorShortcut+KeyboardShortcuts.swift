import AppKit
import KeyboardShortcuts
import ThorRebornCore

/// Bridges the persisted shortcut model and the KeyboardShortcuts package.
extension ThorShortcut {
    init(_ shortcut: KeyboardShortcuts.Shortcut) {
        var modifiers: Modifiers = []
        if shortcut.modifiers.contains(.shift) { modifiers.insert(.shift) }
        if shortcut.modifiers.contains(.control) { modifiers.insert(.control) }
        if shortcut.modifiers.contains(.option) { modifiers.insert(.option) }
        if shortcut.modifiers.contains(.command) { modifiers.insert(.command) }
        self.init(keyCode: shortcut.carbonKeyCode, modifiers: modifiers)
    }

    var keyboardShortcut: KeyboardShortcuts.Shortcut {
        var flags: NSEvent.ModifierFlags = []
        if modifiers.contains(.shift) { flags.insert(.shift) }
        if modifiers.contains(.control) { flags.insert(.control) }
        if modifiers.contains(.option) { flags.insert(.option) }
        if modifiers.contains(.command) { flags.insert(.command) }
        return KeyboardShortcuts.Shortcut(KeyboardShortcuts.Key(rawValue: keyCode), modifiers: flags)
    }

    /// Human-readable symbols, e.g. "⇧⌘G".
    @MainActor var displayString: String { keyboardShortcut.description }
}
