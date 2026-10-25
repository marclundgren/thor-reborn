import SwiftUI
import ThorRebornCore

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var launchAtLogin: LaunchAtLoginService
    @EnvironmentObject private var accessibility: AccessibilityService
    @EnvironmentObject private var commands: AppCommands
    @EnvironmentObject private var updater: UpdaterService

    @State private var launchAtLoginError: String?

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at login", isOn: Binding(
                    get: { launchAtLogin.isEnabled },
                    set: { setLaunchAtLogin($0) }
                ))
                if launchAtLogin.requiresApproval {
                    HStack {
                        Text("Approve ThorReborn in Login Items to finish enabling this.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Open Login Items") { launchAtLogin.openLoginItemsSettings() }
                            .controlSize(.small)
                    }
                }
                Toggle("Enable shortcuts", isOn: $settings.enableShortcuts)
            }

            Section("Menu Bar") {
                Toggle("Show menu bar icon", isOn: $settings.showMenuBarIcon)
                Toggle(isOn: $settings.menuBarToggleHotkeyEnabled) {
                    Text("Show/hide the menu bar icon with \(ThorShortcut.menuBarToggle.displayString)")
                    Text("Relaunch ThorReborn to get back to it while the icon is hidden.")
                }
            }

            Section("Deactivate Key") {
                Toggle(isOn: $settings.enableDeactivateKey) {
                    Text("Double-press a modifier key to pause shortcuts")
                    Text("Lets the keystroke reach the frontmost app instead of ThorReborn.")
                }
                Picker("Modifier key", selection: $settings.deactivateModifier) {
                    ForEach(DeactivateModifier.allCases) { Text($0.title).tag($0) }
                }
                .disabled(!settings.enableDeactivateKey)
                LabeledContent {
                    Slider(value: $settings.reactivationDelay, in: AppSettings.delayRange, step: 0.1) {
                        EmptyView()
                    } minimumValueLabel: {
                        Text("0.1s")
                    } maximumValueLabel: {
                        Text("2s")
                    }
                } label: {
                    Text("Re-enable after")
                    Text(String(format: "%.1f seconds", settings.reactivationDelay))
                }
                .disabled(!settings.enableDeactivateKey)
            }

            Section("Permissions") {
                LabeledContent("Accessibility") {
                    if accessibility.isTrusted {
                        Label("Granted", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button("Open System Settings…") { accessibility.openSystemSettings() }
                    }
                }
            }

            Section("Updates") {
                Toggle("Automatically check for updates", isOn: Binding(
                    get: { updater.automaticallyChecksForUpdates },
                    set: { updater.automaticallyChecksForUpdates = $0 }
                ))
                LabeledContent(MenuBarService.formattedVersion) {
                    Button("Check Now") { updater.checkForUpdates() }
                        .disabled(!updater.canCheckForUpdates)
                }
            }

            Section {
                HStack {
                    Spacer()
                    Button("Quit ThorReborn") { commands.quit() }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            launchAtLogin.refresh()
            accessibility.refresh()
        }
        .alert(
            "Couldn't change Launch at Login",
            isPresented: Binding(get: { launchAtLoginError != nil }, set: { if !$0 { launchAtLoginError = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(launchAtLoginError ?? "")
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try launchAtLogin.setEnabled(enabled)
        } catch {
            launchAtLoginError = error.localizedDescription
        }
    }
}
