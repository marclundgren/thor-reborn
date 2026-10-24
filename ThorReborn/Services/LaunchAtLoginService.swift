import Combine
import os
import ServiceManagement

/// Launch at login via `SMAppService.mainApp` (macOS 13+). No helper app or pod needed.
@MainActor
final class LaunchAtLoginService: ObservableObject {
    @Published private(set) var isEnabled = false
    /// The user must approve the login item in System Settings › General › Login Items.
    @Published private(set) var requiresApproval = false

    private let logger = Logger(subsystem: Log.subsystem, category: "launch-at-login")

    init() {
        refresh()
    }

    func refresh() {
        let status = SMAppService.mainApp.status
        isEnabled = status == .enabled
        requiresApproval = status == .requiresApproval
    }

    func setEnabled(_ enabled: Bool) throws {
        defer { refresh() }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            logger.info("Launch at login \(enabled ? "enabled" : "disabled", privacy: .public)")
        } catch {
            logger.error("Launch at login change failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
