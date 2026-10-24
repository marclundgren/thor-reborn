import SwiftUI

/// Explains why ThorReborn needs Accessibility access. Shown at launch while access is
/// missing, and again if access is revoked while the app is running.
struct OnboardingView: View {
    @EnvironmentObject private var accessibility: AccessibilityService
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: accessibility.isTrusted ? "checkmark.shield.fill" : "hand.raised.square.on.square.fill")
                .font(.system(size: 52))
                .foregroundStyle(accessibility.isTrusted ? .green : .accentColor)
                .contentTransition(.symbolEffect(.replace))

            Text(accessibility.isTrusted ? "You're All Set" : "Allow Accessibility Access")
                .font(.title2.bold())

            if accessibility.isTrusted {
                Text("ThorReborn can now respond to your global shortcuts and the deactivate key.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("ThorReborn listens for global keyboard shortcuts so it can launch, activate, or hide apps from anywhere. macOS requires Accessibility permission for apps that monitor the keyboard while other apps are in front.")
                    Text("1. Click **Open System Settings**.\n2. In Privacy & Security › Accessibility, turn on **ThorReborn** (click + to add it if it isn't listed).\n3. Come back here; this window updates automatically.")
                    Text("Already switched on? macOS ties the permission to the app's exact signature, so an updated or rebuilt copy isn't covered. Select ThorReborn, remove it with −, then turn on the new entry.")
                        .font(.callout)
                }
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            HStack {
                if accessibility.isTrusted {
                    Spacer()
                    Button("Done", action: onClose)
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Later", action: onClose)
                        .keyboardShortcut(.cancelAction)
                    Spacer()
                    Button("Open System Settings") { accessibility.openSystemSettings() }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(24)
        .frame(width: 460, height: 470)
        .animation(.default, value: accessibility.isTrusted)
    }
}
