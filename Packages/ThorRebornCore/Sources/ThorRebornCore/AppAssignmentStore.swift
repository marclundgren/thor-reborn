import Combine
import Foundation
import os

/// Owns the list of assigned apps and persists it as JSON (`apps.json`).
///
/// Every mutation is saved immediately, like the original Thor's `AppsManager`.
@MainActor
public final class AppAssignmentStore: ObservableObject {
    @Published public private(set) var apps: [AssignedApp] = []

    public let fileURL: URL
    private let bundleExists: (URL) -> Bool
    private let logger = Logger(subsystem: "ThorRebornCore", category: "store")

    /// - Parameters:
    ///   - fileURL: Where `apps.json` lives.
    ///   - bundleExists: Used on load/import to drop apps that were deleted from disk.
    public init(
        fileURL: URL = AppAssignmentStore.defaultFileURL,
        bundleExists: @escaping (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
    ) {
        self.fileURL = fileURL
        self.bundleExists = bundleExists
    }

    /// `~/Library/Application Support/ThorReborn/apps.json`
    public nonisolated static var defaultFileURL: URL {
        URL.applicationSupportDirectory
            .appending(path: "ThorReborn", directoryHint: .isDirectory)
            .appending(path: "apps.json", directoryHint: .notDirectory)
    }

    // MARK: Loading and saving

    /// Loads `apps.json`. A missing file means "no apps yet" and is not an error.
    ///
    /// Entries that cannot be decoded, point at a bundle that no longer exists, or
    /// duplicate an earlier entry are dropped and logged; the cleaned list is saved back.
    public func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            apps = []
            return
        }
        do {
            let (loaded, droppedCount) = try decodeApps(from: Data(contentsOf: fileURL))
            apps = loaded
            if droppedCount > 0 {
                save()
            }
        } catch {
            logger.error("Could not read \(self.fileURL.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            apps = []
        }
    }

    @discardableResult
    public func save() -> Bool {
        do {
            try write(to: fileURL)
            return true
        } catch {
            logger.error("Could not save \(self.fileURL.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    // MARK: Export / import

    /// Writes the current assignments to `url` in the `apps.json` format.
    public func export(to url: URL) throws {
        try write(to: url)
    }

    /// Replaces all assignments with the ones in the file at `url` (same behavior as the original Thor).
    /// - Returns: The number of entries that were skipped (undecodable, missing bundle, or duplicate).
    @discardableResult
    public func importApps(from url: URL) throws -> Int {
        let (imported, droppedCount) = try decodeApps(from: Data(contentsOf: url))
        apps = imported
        save()
        return droppedCount
    }

    // MARK: Mutations

    /// Appends an app unless an app with the same bundle URL is already assigned.
    public func add(_ app: AssignedApp) {
        add(contentsOf: [app])
    }

    public func add(contentsOf newApps: [AssignedApp]) {
        var seen = Set(apps.map(\.id))
        let additions = newApps.filter { seen.insert($0.id).inserted }
        guard !additions.isEmpty else { return }
        apps.append(contentsOf: additions)
        save()
    }

    public func remove(atOffsets offsets: IndexSet) {
        guard !offsets.isEmpty else { return }
        apps = apps.enumerated().filter { !offsets.contains($0.offset) }.map(\.element)
        save()
    }

    public func remove(ids: Set<AssignedApp.ID>) {
        remove(atOffsets: IndexSet(apps.indices.filter { ids.contains(apps[$0].id) }))
    }

    public func removeAll() {
        apps = []
        save()
    }

    /// Same semantics as SwiftUI's `move(fromOffsets:toOffset:)`.
    public func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        let moving = source.map { apps[$0] }
        var remaining = apps.enumerated().filter { !source.contains($0.offset) }.map(\.element)
        let insertionIndex = destination - source.count(in: 0..<destination)
        remaining.insert(contentsOf: moving, at: max(0, min(insertionIndex, remaining.count)))
        guard remaining != apps else { return }
        apps = remaining
        save()
    }

    public func setShortcut(_ shortcut: ThorShortcut?, forAppID id: AssignedApp.ID) {
        guard let index = apps.firstIndex(where: { $0.id == id }), apps[index].shortcut != shortcut else { return }
        apps[index].shortcut = shortcut
        save()
    }

    /// The assigned app (other than `excludedID`) that already uses `shortcut`, if any.
    public func app(using shortcut: ThorShortcut, excluding excludedID: AssignedApp.ID? = nil) -> AssignedApp? {
        apps.first { $0.shortcut == shortcut && $0.id != excludedID }
    }

    // MARK: Private

    private func write(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(apps)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    private func decodeApps(from data: Data) throws -> (apps: [AssignedApp], droppedCount: Int) {
        let entries = try JSONDecoder().decode([LossyEntry].self, from: data)
        var result: [AssignedApp] = []
        var seen = Set<AssignedApp.ID>()
        var dropped = 0

        for entry in entries {
            switch entry.result {
            case .failure(let error):
                logger.warning("Dropping undecodable app entry: \(String(describing: error), privacy: .public)")
                dropped += 1
            case .success(let app) where !bundleExists(app.appBundleURL):
                logger.warning("Dropping \(app.appDisplayName, privacy: .public): bundle no longer exists at \(app.appBundleURL.path, privacy: .public)")
                dropped += 1
            case .success(let app) where !seen.insert(app.id).inserted:
                logger.warning("Dropping duplicate entry for \(app.appDisplayName, privacy: .public)")
                dropped += 1
            case .success(let app):
                result.append(app)
            }
        }
        return (result, dropped)
    }
}

/// Decodes one array element without failing the whole array.
private struct LossyEntry: Decodable {
    let result: Result<AssignedApp, any Error>

    init(from decoder: any Decoder) throws {
        do {
            result = .success(try AssignedApp(from: decoder))
        } catch {
            result = .failure(error)
        }
    }
}
