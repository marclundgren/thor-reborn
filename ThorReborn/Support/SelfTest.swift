#if DEBUG
import AppKit
import Carbon.HIToolbox
import ThorRebornCore

/// End-to-end checks of the running app's real services, for machines where key presses
/// can't be synthesized (synthetic input needs Accessibility for the sender).
///
/// Run a Debug build with `--self-test <report-path>`. Hotkey registration is verified
/// against Carbon itself: registering an already-registered combination fails with
/// `eventHotKeyExistsErr`. The report is written to the path, then the app quits.
///
/// The test runs in a sandbox: a throwaway `apps.json` and a separate `UserDefaults`
/// suite, so the user's real assignments and settings are never read or modified.
/// (Launch at login is the exception: it is a system-wide toggle, so the test turns it
/// on and back off, and skips it if it was already on.)
@MainActor
struct SelfTest {
    struct Sandbox {
        let directory: URL
        let reportURL: URL
        let defaultsSuite: String

        var storeURL: URL { directory.appending(path: "apps.json") }
        var defaults: UserDefaults { UserDefaults(suiteName: defaultsSuite)! }

        static func fromLaunchArguments() -> Sandbox? {
            let arguments = ProcessInfo.processInfo.arguments
            guard let index = arguments.firstIndex(of: "--self-test"), arguments.indices.contains(index + 1) else {
                return nil
            }
            let directory = FileManager.default.temporaryDirectory
                .appending(path: "ThorRebornSelfTest-\(ProcessInfo.processInfo.processIdentifier)")
            return Sandbox(
                directory: directory,
                reportURL: URL(filePath: arguments[index + 1]),
                defaultsSuite: "dev.thorreborn.ThorReborn.selftest"
            )
        }

        func cleanUp() {
            try? FileManager.default.removeItem(at: directory)
            UserDefaults.standard.removePersistentDomain(forName: defaultsSuite)
        }
    }

    let services: AppServices
    let menuBar: MenuBarService
    let sandbox: Sandbox

    private static let calculator = URL(filePath: "/System/Applications/Calculator.app", directoryHint: .isDirectory)
    private static let textEdit = URL(filePath: "/System/Applications/TextEdit.app", directoryHint: .isDirectory)
    private static let cmdShiftG = ThorShortcut(keyCode: kVK_ANSI_G, modifiers: [.shift, .command])

    private final class Report {
        var lines: [String] = []
        var failures = 0
        func check(_ name: String, _ condition: Bool, _ detail: @autoclosure () -> String = "") {
            lines.append("\(condition ? "PASS" : "FAIL") \(name)\(condition ? "" : ": \(detail())")")
            if !condition { failures += 1 }
        }
    }

    func run() async {
        let report = Report()
        let store = services.store
        let settings = services.settings
        let hotkeys = services.hotkeys
        guard store.fileURL == sandbox.storeURL else {
            report.check("self-test runs against the sandbox store", false, store.fileURL.path)
            return finish(report)
        }
        settings.enableShortcuts = true
        settings.menuBarToggleHotkeyEnabled = true
        await settle()

        // Menu bar toggle hotkey (fixed ⇧⌃⌥⌘T)
        report.check("menu bar toggle hotkey registered", isCarbonRegistered(.menuBarToggle))
        let iconVisible = settings.showMenuBarIcon
        menuBar.toggleIconVisibility()
        report.check("toggle hides/shows menu bar icon", settings.showMenuBarIcon == !iconVisible)
        menuBar.toggleIconVisibility()
        settings.menuBarToggleHotkeyEnabled = false
        await settle()
        report.check("menu bar toggle hotkey unregistered when turned off", !isCarbonRegistered(.menuBarToggle))
        settings.menuBarToggleHotkeyEnabled = true
        await settle()

        // 3. Assign ⇧⌘G to Calculator; press launches/activates; press while frontmost hides.
        report.check("⇧⌘G free before assignment", !isCarbonRegistered(Self.cmdShiftG))
        let calculator = AssignedApp(appBundleURL: Self.calculator, appDisplayName: "Calculator")
        store.add(calculator)
        hotkeys.assign(Self.cmdShiftG, to: calculator.id)
        await settle()
        report.check("⇧⌘G registered after assignment", isCarbonRegistered(Self.cmdShiftG))
        report.check("stored as shift+cmd+g", store.apps.first?.shortcut?.stringValue == "shift+cmd+g")

        let calculatorID = "com.apple.calculator"
        let wasRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: calculatorID).isEmpty
        hotkeys.handlePress(of: Self.cmdShiftG)
        let launched = await waitUntil { NSWorkspace.shared.frontmostApplication?.bundleIdentifier == calculatorID }
        report.check("press launches/activates Calculator (frontmost)", launched,
                     "frontmost=\(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "nil")")

        hotkeys.handlePress(of: Self.cmdShiftG)
        let hidden = await waitUntil {
            NSRunningApplication.runningApplications(withBundleIdentifier: calculatorID).first?.isHidden == true
        }
        report.check("press while frontmost hides Calculator", hidden)

        hotkeys.handlePress(of: Self.cmdShiftG)
        let reactivated = await waitUntil { NSWorkspace.shared.frontmostApplication?.bundleIdentifier == calculatorID }
        report.check("press again re-activates hidden Calculator", reactivated)

        // Conflict detection
        let textEdit = AssignedApp(appBundleURL: Self.textEdit, appDisplayName: "TextEdit")
        store.add(textEdit)
        report.check("conflict with another row detected",
                     hotkeys.conflict(for: Self.cmdShiftG, assigningTo: textEdit.id) == .app(store.apps[0]))
        report.check("menu bar toggle hotkey is reserved",
                     hotkeys.conflict(for: .menuBarToggle, assigningTo: textEdit.id) == .menuBarToggle)
        hotkeys.assign(.menuBarToggle, to: textEdit.id)
        report.check("reserved hotkey can't be assigned", store.apps.last?.shortcut == nil)
        hotkeys.assign(Self.cmdShiftG, to: textEdit.id)
        report.check("confirmed overwrite moves the shortcut",
                     store.apps.last?.shortcut == Self.cmdShiftG && store.apps.first?.shortcut == nil)
        hotkeys.assign(Self.cmdShiftG, to: calculator.id)
        store.remove(ids: [textEdit.id])

        // 4. Disable / re-enable from the menu
        menuBarToggleShortcuts()
        await settle()
        report.check("disabling unregisters hotkeys", !settings.enableShortcuts && !isCarbonRegistered(Self.cmdShiftG))
        menuBarToggleShortcuts()
        await settle()
        report.check("re-enabling registers hotkeys", settings.enableShortcuts && isCarbonRegistered(Self.cmdShiftG))

        // 5. Deactivate key: double-press ⌘, shortcuts suspend, then resume after the delay.
        settings.enableDeactivateKey = true
        settings.deactivateModifier = .command
        settings.reactivationDelay = 0.5
        let monitor = services.deactivateKey
        monitor.handle([.command]); monitor.handle([])
        try? await Task.sleep(for: .seconds(0.4))
        monitor.handle([.command]); monitor.handle([])
        report.check("slow double-press (> 0.3s) does not suspend", !hotkeys.isSuspended)
        try? await Task.sleep(for: .seconds(0.4))
        monitor.handle([.command]); monitor.handle([])
        monitor.handle([.command]); monitor.handle([])
        await settle()
        report.check("double-press suspends and unregisters", hotkeys.isSuspended && !isCarbonRegistered(Self.cmdShiftG))
        try? await Task.sleep(for: .seconds(0.6))
        report.check("shortcuts resume after the delay", !hotkeys.isSuspended && isCarbonRegistered(Self.cmdShiftG))
        report.check("user's enable setting untouched by suspension", settings.enableShortcuts)

        // 6. Launch at login on and off (system-wide, so leave it alone if the user enabled it)
        let launchAtLogin = services.launchAtLogin
        if launchAtLogin.isEnabled {
            report.lines.append("SKIP launch at login (already enabled by the user)")
        } else { do {
            try launchAtLogin.setEnabled(true)
            report.check("launch at login enabled", launchAtLogin.isEnabled || launchAtLogin.requiresApproval,
                         "status=\(launchAtLogin.isEnabled)")
            try launchAtLogin.setEnabled(false)
            report.check("launch at login disabled", !launchAtLogin.isEnabled)
        } catch {
            report.check("launch at login toggles without errors", false, error.localizedDescription)
        } }

        // 7. Export, delete all, import
        let exportURL = sandbox.directory.appending(path: ImportExportService.defaultFileName)
        let before = store.apps
        do {
            try store.export(to: exportURL)
            store.removeAll()
            await settle()
            report.check("delete all unregisters", store.apps.isEmpty && !isCarbonRegistered(Self.cmdShiftG))
            try store.importApps(from: exportURL)
            await settle()
            report.check("import restores assignments", store.apps == before)
            report.check("imported hotkeys registered", isCarbonRegistered(Self.cmdShiftG))
        } catch {
            report.check("export/import", false, error.localizedDescription)
        }

        // 8. Persistence: a fresh store reading the same file sees the same assignments
        let reloaded = AppAssignmentStore(fileURL: store.fileURL)
        reloaded.load()
        report.check("assignments persist across store instances", reloaded.apps == store.apps && !reloaded.apps.isEmpty)

        // Fallback icon for a missing bundle
        let icon = AppIconProvider.shared.icon(for: URL(filePath: "/Applications/DoesNotExist.app"))
        report.check("missing bundle gets a fallback icon", icon.size.width > 0)

        if !wasRunning {
            NSRunningApplication.runningApplications(withBundleIdentifier: calculatorID).forEach { $0.terminate() }
        }
        finish(report)
    }

    private func finish(_ report: Report) {
        report.lines.append(report.failures == 0 ? "ALL PASSED" : "\(report.failures) FAILED")
        try? report.lines.joined(separator: "\n").appending("\n")
            .write(to: sandbox.reportURL, atomically: true, encoding: .utf8)
        sandbox.cleanUp()
        NSApp.terminate(nil)
    }

    /// Same action as the menu's Enable/Disable Shortcuts item.
    private func menuBarToggleShortcuts() {
        services.hotkeys.setShortcutsEnabled(!services.settings.enableShortcuts)
    }

    /// Lets Combine sinks and KeyboardShortcuts' async (un)registration run.
    private func settle() async {
        try? await Task.sleep(for: .milliseconds(150))
    }

    private func waitUntil(timeout: TimeInterval = 5, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return condition()
    }

    private func isCarbonRegistered(_ shortcut: ThorShortcut) -> Bool {
        var modifiers: UInt32 = 0
        if shortcut.modifiers.contains(.shift) { modifiers |= UInt32(shiftKey) }
        if shortcut.modifiers.contains(.control) { modifiers |= UInt32(controlKey) }
        if shortcut.modifiers.contains(.option) { modifiers |= UInt32(optionKey) }
        if shortcut.modifiers.contains(.command) { modifiers |= UInt32(cmdKey) }
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(shortcut.keyCode), modifiers, EventHotKeyID(signature: 0x5448_5254, id: 9_999),
            GetEventDispatcherTarget(), 0, &ref
        )
        if status == noErr, let ref {
            UnregisterEventHotKey(ref)
            return false
        }
        return status == eventHotKeyExistsErr
    }
}
#endif
