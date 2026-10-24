import AppKit
import os
import ThorRebornCore

/// What a per-app hotkey does: hide the app if it's frontmost, otherwise launch or activate it.
@MainActor
final class ActivationService {
    private let logger = Logger(subsystem: Log.subsystem, category: "activation")

    func toggle(_ app: AssignedApp) {
        if let frontmost = NSWorkspace.shared.frontmostApplication, Self.isSameApp(frontmost, as: app.appBundleURL) {
            frontmost.hide()
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        let name = app.appDisplayName
        NSWorkspace.shared.openApplication(at: app.appBundleURL, configuration: configuration) { [logger] _, error in
            if let error {
                logger.error("Could not open \(name, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Matches by bundle identifier like the original Thor, falling back to the bundle location.
    private static func isSameApp(_ running: NSRunningApplication, as bundleURL: URL) -> Bool {
        if let runningID = running.bundleIdentifier, let targetID = Bundle(url: bundleURL)?.bundleIdentifier {
            return runningID == targetID
        }
        return running.bundleURL?.standardizedFileURL == bundleURL.standardizedFileURL
    }
}
