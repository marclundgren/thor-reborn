import Foundation
import ThorRebornCore

/// The app's object graph, created once at launch.
@MainActor
final class AppServices {
    let settings: AppSettings
    let store: AppAssignmentStore
    let activation = ActivationService()
    let discovery = AppDiscoveryService()
    let accessibility = AccessibilityService()
    let launchAtLogin = LaunchAtLoginService()
    let hotkeys: HotkeyService
    let deactivateKey: DeactivateKeyMonitor
    let importExport: ImportExportService
    let commands: AppCommands

    /// - Parameters:
    ///   - storeURL: Location of `apps.json` (the real one unless isolated for the self-test).
    ///   - defaults: Where settings are persisted.
    init(storeURL: URL = AppAssignmentStore.defaultFileURL, defaults: UserDefaults = .standard) {
        settings = AppSettings(defaults: defaults)
        store = AppAssignmentStore(fileURL: storeURL)
        hotkeys = HotkeyService(store: store, settings: settings, activation: activation)
        deactivateKey = DeactivateKeyMonitor(settings: settings, hotkeys: hotkeys)
        importExport = ImportExportService(store: store)
        commands = AppCommands(importExport: importExport)
    }
}
