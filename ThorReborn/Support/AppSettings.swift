import AppKit
import Combine

/// The modifier that can be double-pressed to temporarily suspend all shortcuts.
/// Raw values match the original Thor's `DeactivateKey` popup index.
enum DeactivateModifier: Int, CaseIterable, Identifiable, Sendable {
    case shift, control, option, command

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .shift: "⇧ Shift"
        case .control: "⌃ Control"
        case .option: "⌥ Option"
        case .command: "⌘ Command"
        }
    }

    var flag: NSEvent.ModifierFlags {
        switch self {
        case .shift: .shift
        case .control: .control
        case .option: .option
        case .command: .command
        }
    }
}

/// User preferences, persisted in `UserDefaults` with the same keys and defaults as the original Thor.
@MainActor
final class AppSettings: ObservableObject {
    static let delayRange: ClosedRange<Double> = 0.1...2.0

    private enum Key {
        static let enableShortcuts = "EnableShortcut"
        static let showMenuBarIcon = "enableMenuBarIcon"
        static let menuBarToggleHotkey = "enableMenuBarIconShowHideKey"
        static let enableDeactivateKey = "EnableDeactivateKey"
        static let deactivateKey = "DeactivateKey"
        static let delayInterval = "DelayInterval"
    }

    private let defaults: UserDefaults

    @Published var enableShortcuts: Bool {
        didSet { defaults.set(enableShortcuts, forKey: Key.enableShortcuts) }
    }

    @Published var showMenuBarIcon: Bool {
        didSet { defaults.set(showMenuBarIcon, forKey: Key.showMenuBarIcon) }
    }

    /// Whether Shift+Control+Option+Command+T shows/hides the menu bar icon.
    @Published var menuBarToggleHotkeyEnabled: Bool {
        didSet { defaults.set(menuBarToggleHotkeyEnabled, forKey: Key.menuBarToggleHotkey) }
    }

    @Published var enableDeactivateKey: Bool {
        didSet { defaults.set(enableDeactivateKey, forKey: Key.enableDeactivateKey) }
    }

    @Published var deactivateModifier: DeactivateModifier {
        didSet { defaults.set(deactivateModifier.rawValue, forKey: Key.deactivateKey) }
    }

    /// Seconds before shortcuts re-enable after a deactivate-key double press.
    @Published var reactivationDelay: Double {
        didSet { defaults.set(reactivationDelay, forKey: Key.delayInterval) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.enableShortcuts: true,
            Key.showMenuBarIcon: true,
            Key.menuBarToggleHotkey: true,
            Key.enableDeactivateKey: false,
            Key.deactivateKey: DeactivateModifier.shift.rawValue,
            Key.delayInterval: 0.3
        ])
        enableShortcuts = defaults.bool(forKey: Key.enableShortcuts)
        showMenuBarIcon = defaults.bool(forKey: Key.showMenuBarIcon)
        menuBarToggleHotkeyEnabled = defaults.bool(forKey: Key.menuBarToggleHotkey)
        enableDeactivateKey = defaults.bool(forKey: Key.enableDeactivateKey)
        deactivateModifier = DeactivateModifier(rawValue: defaults.integer(forKey: Key.deactivateKey)) ?? .shift
        reactivationDelay = min(max(defaults.double(forKey: Key.delayInterval), Self.delayRange.lowerBound), Self.delayRange.upperBound)
    }
}
