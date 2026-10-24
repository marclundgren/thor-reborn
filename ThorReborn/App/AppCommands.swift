import AppKit
import Combine

/// Actions the SwiftUI views can trigger without touching AppKit themselves.
@MainActor
final class AppCommands: ObservableObject {
    private let importExport: ImportExportService

    init(importExport: ImportExportService) {
        self.importExport = importExport
    }

    func exportShortcuts() { importExport.exportAssignments() }
    func importShortcuts() { importExport.importAssignments() }
    func quit() { NSApp.terminate(nil) }
}
