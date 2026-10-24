import AppKit
import os

/// Watches modifier-key presses. Double-pressing the configured modifier (alone) within
/// `doublePressWindow` suspends all app shortcuts for the configured delay.
///
/// Global key monitoring requires Accessibility permission, so the global monitor is
/// reinstalled whenever that permission is granted.
@MainActor
final class DeactivateKeyMonitor {
    /// Same fixed window as the original Thor.
    static let doublePressWindow: TimeInterval = 0.3

    private let settings: AppSettings
    private let hotkeys: HotkeyService
    private let logger = Logger(subsystem: Log.subsystem, category: "deactivate-key")

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var previousFlags: NSEvent.ModifierFlags = []
    private var lastPress: Date?

    init(settings: AppSettings, hotkeys: HotkeyService) {
        self.settings = settings
        self.hotkeys = hotkeys
    }

    func start() {
        installMonitors()
    }

    /// Global monitors installed before Accessibility was granted never receive events.
    func reinstallMonitors() {
        installMonitors()
    }

    private func installMonitors() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            let flags = event.modifierFlags
            MainActor.assumeIsolated { self?.handle(flags) }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            let flags = event.modifierFlags
            MainActor.assumeIsolated { self?.handle(flags) }
            return event
        }
    }

    /// Processes one flagsChanged event (also driven directly by the DEBUG self-test).
    func handle(_ rawFlags: NSEvent.ModifierFlags) {
        let flags = rawFlags.intersection([.shift, .control, .option, .command])
        defer { previousFlags = flags }

        guard settings.enableDeactivateKey else {
            lastPress = nil
            return
        }

        // A "press" is the deactivate modifier going down on its own (no other modifiers held).
        let key = settings.deactivateModifier.flag
        guard flags == key, !previousFlags.contains(key) else {
            if !flags.isEmpty, flags != key { lastPress = nil } // chorded with something else
            return
        }

        let now = Date()
        if let lastPress, now.timeIntervalSince(lastPress) <= Self.doublePressWindow {
            self.lastPress = nil
            logger.info("Deactivate key double-pressed")
            hotkeys.suspend(for: settings.reactivationDelay)
        } else {
            lastPress = now
        }
    }
}
