import Carbon.HIToolbox
import Foundation
import Testing
@testable import ThorRebornCore

@MainActor
@Suite("App assignment store")
final class AppAssignmentStoreTests {
    let directory: URL
    let fileURL: URL

    init() {
        directory = FileManager.default.temporaryDirectory.appending(path: "ThorRebornTests-\(UUID().uuidString)")
        fileURL = directory.appending(path: "nested/apps.json")
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeStore(existing: Set<String>? = nil) -> AppAssignmentStore {
        AppAssignmentStore(fileURL: fileURL) { url in existing.map { $0.contains(url.path) } ?? true }
    }

    private let safari = AssignedApp(
        appBundleURL: URL(filePath: "/Applications/Safari.app", directoryHint: .isDirectory),
        appDisplayName: "Safari",
        shortcut: ThorShortcut(keyCode: kVK_ANSI_S, modifiers: [.command, .shift])
    )
    private let notes = AssignedApp(
        appBundleURL: URL(filePath: "/System/Applications/Notes.app", directoryHint: .isDirectory),
        appDisplayName: "Notes",
        shortcut: nil
    )

    @Test("Save then load returns the same apps in the same order")
    func saveLoadRoundTrip() {
        let store = makeStore()
        store.add(contentsOf: [safari, notes])

        let reloaded = makeStore()
        reloaded.load()
        #expect(reloaded.apps == [safari, notes])
    }

    @Test("JSON matches the original Thor apps.json shape")
    func jsonShape() throws {
        let store = makeStore()
        store.add(contentsOf: [safari, notes])

        let json = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: fileURL)) as? [[String: String]])
        #expect(json == [
            ["appBundleURL": "file:///Applications/Safari.app/", "appDisplayName": "Safari", "shortcut": "shift+cmd+s"],
            ["appBundleURL": "file:///System/Applications/Notes.app/", "appDisplayName": "Notes", "shortcut": ""]
        ])
    }

    @Test("Loading drops missing bundles, bad entries and duplicates, then rewrites the file")
    func loadDropsInvalid() throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let json = """
        [
          {"appBundleURL": "file:///Applications/Safari.app/", "appDisplayName": "Safari", "shortcut": "cmd+shift+s"},
          {"appBundleURL": "file:///Applications/Gone.app/", "appDisplayName": "Gone", "shortcut": "cmd+g"},
          {"appDisplayName": "No URL", "shortcut": "cmd+u"},
          {"appBundleURL": "file:///Applications/Safari.app/", "appDisplayName": "Safari again", "shortcut": ""},
          {"appBundleURL": "file:///System/Applications/Notes.app/", "appDisplayName": "Notes", "shortcut": "not+a+shortcut"}
        ]
        """
        try Data(json.utf8).write(to: fileURL)

        let store = makeStore(existing: ["/Applications/Safari.app", "/System/Applications/Notes.app"])
        store.load()
        #expect(store.apps == [safari, notes]) // Notes keeps its row; the unparseable shortcut is cleared

        let reloaded = makeStore()
        reloaded.load()
        #expect(reloaded.apps == [safari, notes])
    }

    @Test("Export, delete all, import restores the assignments")
    func exportImportRoundTrip() throws {
        let store = makeStore()
        store.add(contentsOf: [safari, notes])
        let exportURL = directory.appending(path: "thor_shortcuts.json")

        try store.export(to: exportURL)
        store.removeAll()
        #expect(store.apps.isEmpty)

        let skipped = try store.importApps(from: exportURL)
        #expect(skipped == 0)
        #expect(store.apps == [safari, notes])

        let reloaded = makeStore()
        reloaded.load()
        #expect(reloaded.apps == [safari, notes])
    }

    @Test("Missing file loads as empty")
    func missingFile() {
        let store = makeStore()
        store.load()
        #expect(store.apps.isEmpty)
    }

    @Test("Move, set shortcut, remove and conflict lookup")
    func mutations() {
        let store = makeStore()
        store.add(contentsOf: [safari, notes, safari])
        #expect(store.apps.map(\.appDisplayName) == ["Safari", "Notes"])

        store.move(fromOffsets: [0], toOffset: 2)
        #expect(store.apps.map(\.appDisplayName) == ["Notes", "Safari"])

        let shortcut = ThorShortcut(keyCode: kVK_ANSI_N, modifiers: [.option, .command])
        store.setShortcut(shortcut, forAppID: notes.id)
        #expect(store.app(using: shortcut)?.id == notes.id)
        #expect(store.app(using: shortcut, excluding: notes.id) == nil)

        store.remove(ids: [notes.id])
        #expect(store.apps == [safari])
    }
}
