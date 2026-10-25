import AppKit
import Combine
import os

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let services = AppDelegate.makeServices()
    private lazy var windows = WindowCoordinator(services: services)
    private var menuBar: MenuBarService?
    private var cancellables: Set<AnyCancellable> = []
    private var finishedLaunchingAt: Date?
    private let logger = Logger(subsystem: Log.subsystem, category: "app")

    private static func makeServices() -> AppServices {
        #if DEBUG
        if let sandbox = SelfTest.Sandbox.fromLaunchArguments() {
            return AppServices(storeURL: sandbox.storeURL, defaults: sandbox.defaults)
        }
        #endif
        return AppServices()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if handOffToRunningInstance() { return }
        NSApp.setActivationPolicy(.accessory) // menu bar only, no Dock icon

        services.store.load()
        services.hotkeys.start()
        services.deactivateKey.start()

        #if DEBUG
        let sandbox = SelfTest.Sandbox.fromLaunchArguments()
        switch sandbox?.mode {
        case .screenshots?:
            return Screenshots(services: services, windows: windows, sandbox: sandbox!).run()
        case .updateTest?:
            return UpdateTest(sandbox: sandbox!).run()
        default:
            break
        }
        #endif

        services.updater.start()
        let menuBar = MenuBarService(
            settings: services.settings,
            hotkeys: services.hotkeys,
            updater: services.updater,
            actions: .init(
                showApps: { [weak self] in self?.windows.showMainWindow() },
                exportShortcuts: { [weak self] in self?.services.importExport.exportAssignments() },
                importShortcuts: { [weak self] in self?.services.importExport.importAssignments() }
            )
        )
        menuBar.start()
        self.menuBar = menuBar

        observeAccessibility()

        if services.store.apps.isEmpty {
            windows.showMainWindow()
        }
        if !services.accessibility.isTrusted {
            windows.showOnboarding()
        }
        finishedLaunchingAt = Date()
        logger.info("Launched with \(self.services.store.apps.count) assigned apps")

        #if DEBUG
        if let sandbox, sandbox.mode == .selfTest {
            let selfTest = SelfTest(services: services, menuBar: menuBar, sandbox: sandbox)
            Task { await selfTest.run() }
        }
        #endif
    }

    /// Like the original Thor: re-activating the running app (e.g. opening it again from
    /// Finder or Spotlight) shows the main window. Activations during launch are ignored.
    func applicationWillBecomeActive(_ notification: Notification) {
        guard let finishedLaunchingAt, Date().timeIntervalSince(finishedLaunchingAt) > 1 else { return }
        windows.showMainWindow()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        windows.showMainWindow()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Two copies would register the same hotkeys and toggle each app twice. If another
    /// copy is already running, activate it (which makes it show its main window) and quit.
    private func handOffToRunningInstance() -> Bool {
        #if DEBUG
        if SelfTest.Sandbox.fromLaunchArguments() != nil { return false }
        #endif
        guard let bundleID = Bundle.main.bundleIdentifier,
              let other = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
                .first(where: { $0 != .current }) else { return false }

        logger.info("Another instance is running (pid \(other.processIdentifier)); handing off")
        NSApp.yieldActivation(to: other)
        other.activate()
        NSApp.terminate(nil)
        return true
    }

    private func observeAccessibility() {
        services.accessibility.startMonitoring()
        services.accessibility.$isTrusted
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] trusted in
                guard let self else { return }
                if trusted {
                    logger.info("Accessibility permission granted")
                    services.deactivateKey.reinstallMonitors()
                } else {
                    logger.warning("Accessibility permission revoked; showing onboarding")
                    windows.showOnboarding()
                }
            }
            .store(in: &cancellables)
    }
}
