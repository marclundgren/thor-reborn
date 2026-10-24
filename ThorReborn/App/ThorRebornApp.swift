import SwiftUI

@main
struct ThorRebornApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // All windows are owned by WindowCoordinator (opened from the menu bar), and
        // Settings is a tab in the main window like in the original Thor. SwiftUI still
        // needs one scene, so declare an empty Settings scene and remove its menu command.
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .appSettings) {}
        }
    }
}
