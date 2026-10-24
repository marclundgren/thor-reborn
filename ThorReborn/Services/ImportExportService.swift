import AppKit
import os
import ThorRebornCore
import UniformTypeIdentifiers

/// Export/import of assignments as JSON through the standard file panels.
@MainActor
final class ImportExportService {
    static let defaultFileName = "thor_shortcuts.json"

    private let store: AppAssignmentStore
    private let logger = Logger(subsystem: Log.subsystem, category: "import-export")

    init(store: AppAssignmentStore) {
        self.store = store
    }

    func exportAssignments() {
        NSApp.activate()
        let panel = NSSavePanel()
        panel.title = "Export Shortcuts"
        panel.nameFieldStringValue = Self.defaultFileName
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.export(to: url)
        } catch {
            showError("Couldn't export shortcuts", error)
        }
    }

    func importAssignments() {
        NSApp.activate()
        let panel = NSOpenPanel()
        panel.title = "Import Shortcuts"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else { return }

        if !store.apps.isEmpty {
            let confirm = NSAlert()
            confirm.messageText = "Replace your current shortcuts?"
            confirm.informativeText = "Importing replaces all \(store.apps.count) current assignments with the ones in “\(url.lastPathComponent)”."
            confirm.addButton(withTitle: "Replace")
            confirm.addButton(withTitle: "Cancel")
            guard confirm.runModal() == .alertFirstButtonReturn else { return }
        }

        do {
            let skipped = try store.importApps(from: url)
            if skipped > 0 {
                let alert = NSAlert()
                alert.messageText = "Imported \(store.apps.count) apps"
                alert.informativeText = "\(skipped) entries were skipped because the app is no longer installed or the entry was invalid."
                alert.runModal()
            }
        } catch {
            showError("Couldn't import shortcuts", error)
        }
    }

    private func showError(_ message: String, _ error: any Error) {
        logger.error("\(message, privacy: .public): \(error.localizedDescription, privacy: .public)")
        let alert = NSAlert(error: error)
        alert.messageText = message
        alert.runModal()
    }
}
