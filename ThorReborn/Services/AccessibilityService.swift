import AppKit
import ApplicationServices
import Combine

/// Tracks whether ThorReborn is trusted for Accessibility and notices when that changes
/// (including the permission being revoked while the app is running).
@MainActor
final class AccessibilityService: ObservableObject {
    @Published private(set) var isTrusted = AXIsProcessTrusted()

    private static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
    private var pollTask: Task<Void, Never>?

    /// TCC posts no notification for Accessibility changes, so poll cheaply.
    func startMonitoring(interval: Duration = .seconds(1.5)) {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                self?.refresh()
            }
        }
    }

    func refresh() {
        let trusted = AXIsProcessTrusted()
        if trusted != isTrusted {
            isTrusted = trusted
        }
    }

    /// Opens System Settings at Privacy & Security › Accessibility.
    ///
    /// Asking with the prompt option first registers this exact build in the list, so the
    /// user only has to switch it on (instead of adding it with +).
    func openSystemSettings() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        isTrusted = AXIsProcessTrustedWithOptions(options)
        NSWorkspace.shared.open(Self.settingsURL)
    }
}
