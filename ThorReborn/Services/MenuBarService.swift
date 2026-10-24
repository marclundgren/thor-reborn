import AppKit
import Combine
import KeyboardShortcuts
import Sparkle
import ThorRebornCore

/// The status item, its menu, and the fixed Shift+Control+Option+Command+T hotkey that
/// shows/hides the status item.
@MainActor
final class MenuBarService: NSObject, NSMenuDelegate {
    struct Actions {
        var showApps: () -> Void
        var exportShortcuts: () -> Void
        var importShortcuts: () -> Void
    }

    static let privacyPolicyURL = URL(string: "https://github.com/gbammc/Thor/blob/master/privacy.md")!

    private let settings: AppSettings
    private let hotkeys: HotkeyService
    private let actions: Actions
    private let updaterController: SPUStandardUpdaterController

    private var statusItem: NSStatusItem?
    private let toggleShortcutsItem = NSMenuItem()
    private let versionItem = NSMenuItem()
    private var toggleHotkeyTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []

    init(settings: AppSettings, hotkeys: HotkeyService, actions: Actions) {
        self.settings = settings
        self.hotkeys = hotkeys
        self.actions = actions
        // Placeholder feed (see Info.plist / README). Automatic checks are off by default.
        self.updaterController = SPUStandardUpdaterController(
            startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil
        )
        super.init()
    }

    func start() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = Self.statusImage
        item.menu = makeMenu()
        statusItem = item

        settings.$showMenuBarIcon
            .sink { [weak self] visible in self?.statusItem?.isVisible = visible }
            .store(in: &cancellables)

        settings.$menuBarToggleHotkeyEnabled
            .sink { [weak self] enabled in self?.setToggleHotkeyRegistered(enabled) }
            .store(in: &cancellables)
    }

    func toggleIconVisibility() {
        settings.showMenuBarIcon.toggle()
    }

    // MARK: Toggle hotkey

    private func setToggleHotkeyRegistered(_ registered: Bool) {
        toggleHotkeyTask?.cancel()
        toggleHotkeyTask = nil
        guard registered else { return }

        let events = KeyboardShortcuts.events(.keyDown, for: ThorShortcut.menuBarToggle.keyboardShortcut)
        toggleHotkeyTask = Task { [weak self] in
            for await _ in events {
                self?.toggleIconVisibility()
            }
        }
    }

    // MARK: Menu

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false

        menu.addItem(item("Show Apps", #selector(showApps), key: ""))
        menu.addItem(.separator())

        toggleShortcutsItem.target = self
        toggleShortcutsItem.action = #selector(toggleShortcuts)
        menu.addItem(toggleShortcutsItem)
        menu.addItem(.separator())

        menu.addItem(item("Export Shortcuts…", #selector(exportShortcuts)))
        menu.addItem(item("Import Shortcuts…", #selector(importShortcuts)))
        menu.addItem(.separator())

        let updateItem = NSMenuItem(
            title: "Check for Updates…",
            action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)),
            keyEquivalent: ""
        )
        updateItem.target = updaterController
        menu.addItem(updateItem)

        versionItem.isEnabled = false
        menu.addItem(versionItem)
        menu.addItem(item("Privacy Policy", #selector(openPrivacyPolicy)))
        menu.addItem(.separator())

        menu.addItem(item("Quit ThorReborn", #selector(quit), key: "q"))
        updateDynamicTitles()
        return menu
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    nonisolated func menuWillOpen(_ menu: NSMenu) {
        MainActor.assumeIsolated { updateDynamicTitles() }
    }

    private func updateDynamicTitles() {
        toggleShortcutsItem.title = settings.enableShortcuts ? "Disable Shortcuts" : "Enable Shortcuts"
        versionItem.title = Self.formattedVersion
    }

    static var formattedVersion: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        return "Version \(version) (\(build))"
    }

    private static var statusImage: NSImage? {
        let image = NSImage(systemSymbolName: "hammer.fill", accessibilityDescription: "ThorReborn")
        image?.isTemplate = true
        return image
    }

    // MARK: Actions

    @objc private func showApps() { actions.showApps() }
    @objc private func toggleShortcuts() { hotkeys.setShortcutsEnabled(!settings.enableShortcuts) }
    @objc private func exportShortcuts() { actions.exportShortcuts() }
    @objc private func importShortcuts() { actions.importShortcuts() }
    @objc private func openPrivacyPolicy() { NSWorkspace.shared.open(Self.privacyPolicyURL) }
    @objc private func quit() { NSApp.terminate(nil) }
}
