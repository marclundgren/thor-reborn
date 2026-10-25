import AppKit
import SwiftUI

/// Hosts the SwiftUI windows. A menu-bar (accessory) app can't rely on SwiftUI scenes
/// being openable from AppKit, so the windows are owned here.
@MainActor
final class WindowCoordinator {
    private let services: AppServices
    private var mainWindow: NSWindow?
    private var onboardingWindow: NSWindow?

    init(services: AppServices) {
        self.services = services
    }

    func showMainWindow() {
        let window = mainWindow ?? makeMainWindow(autosaveName: "MainWindow")
        mainWindow = window
        present(window)
    }

    func makeMainWindow(initialTab: MainWindowView.Tab = .apps, autosaveName: String?) -> NSWindow {
        makeWindow(
            title: "ThorReborn",
            autosaveName: autosaveName,
            size: NSSize(width: 520, height: 560),
            style: [.titled, .closable, .miniaturizable, .resizable],
            content: MainWindowView(initialTab: initialTab)
        )
    }

    func showOnboarding() {
        let window = onboardingWindow ?? makeWindow(
            title: "Accessibility Access",
            autosaveName: nil,
            size: NSSize(width: 460, height: 470),
            style: [.titled, .closable],
            content: OnboardingView(onClose: { [weak self] in self?.onboardingWindow?.close() })
        )
        onboardingWindow = window
        window.level = .floating
        present(window)
    }

    private func present(_ window: NSWindow) {
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        // Activation is cooperative on macOS 14+; make sure the window isn't left behind
        // the active app when ThorReborn was launched in the background.
        window.orderFrontRegardless()
    }

    private func makeWindow<Content: View>(
        title: String,
        autosaveName: String?,
        size: NSSize,
        style: NSWindow.StyleMask,
        content: Content
    ) -> NSWindow {
        let root = content
            .environmentObject(services.store)
            .environmentObject(services.settings)
            .environmentObject(services.hotkeys)
            .environmentObject(services.discovery)
            .environmentObject(services.accessibility)
            .environmentObject(services.launchAtLogin)
            .environmentObject(services.updater)
            .environmentObject(services.commands)

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: style,
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.isReleasedWhenClosed = false
        let hosting = NSHostingController(rootView: root)
        hosting.sizingOptions = [.minSize] // keep the window user-resizable
        window.contentViewController = hosting
        window.setContentSize(size)
        window.center()
        if let autosaveName {
            window.setFrameAutosaveName(autosaveName)
        }
        return window
    }
}
