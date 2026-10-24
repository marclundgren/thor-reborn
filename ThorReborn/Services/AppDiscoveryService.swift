import AppKit
import Combine
import os

struct DiscoveredApp: Identifiable, Hashable, Sendable {
    let url: URL
    let name: String
    var id: String { url.path }
}

/// Finds installed applications: a scan of the standard Applications folders merged
/// with a Spotlight query for every application bundle on the Mac.
@MainActor
final class AppDiscoveryService: ObservableObject {
    @Published private(set) var apps: [DiscoveredApp] = []
    @Published private(set) var isSearching = false

    private var query: NSMetadataQuery?
    private var observer: NSObjectProtocol?
    private let logger = Logger(subsystem: Log.subsystem, category: "discovery")

    nonisolated static var searchDirectories: [URL] {
        [
            URL(filePath: "/Applications", directoryHint: .isDirectory),
            URL(filePath: "/System/Applications", directoryHint: .isDirectory),
            FileManager.default.homeDirectoryForCurrentUser.appending(path: "Applications", directoryHint: .isDirectory)
        ]
    }

    func refresh() {
        guard !isSearching else { return }
        isSearching = true

        Task {
            let scanned = await Task.detached(priority: .userInitiated) { Self.scanDirectories() }.value
            merge(scanned)
            startSpotlightQuery()
        }
    }

    // MARK: Spotlight

    private func startSpotlightQuery() {
        let query = NSMetadataQuery()
        query.predicate = NSPredicate(format: "kMDItemContentType == 'com.apple.application-bundle'")
        query.searchScopes = [NSMetadataQueryLocalComputerScope]
        self.query = query

        observer = NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidFinishGathering, object: query, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.finishSpotlightQuery() }
        }

        if !query.start() {
            logger.warning("Spotlight query failed to start; using folder scan only")
            finishSpotlightQuery()
        }
    }

    private func finishSpotlightQuery() {
        guard let query else { return }
        query.disableUpdates()
        query.stop()

        let urls = (0..<query.resultCount).compactMap { index -> URL? in
            guard let item = query.result(at: index) as? NSMetadataItem,
                  let path = item.value(forAttribute: NSMetadataItemPathKey) as? String else { return nil }
            return URL(filePath: path, directoryHint: .isDirectory)
        }
        merge(urls)

        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        self.query = nil
        isSearching = false
        logger.info("Discovered \(self.apps.count) apps")
    }

    // MARK: Merging

    private func merge(_ urls: [URL]) {
        var byPath = Dictionary(apps.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for url in urls {
            let resolved = url.resolvingSymlinksInPath().standardizedFileURL
            guard byPath[resolved.path] == nil else { continue }
            byPath[resolved.path] = DiscoveredApp(url: resolved, name: Self.displayName(for: resolved))
        }
        apps = byPath.values.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    nonisolated static func displayName(for url: URL) -> String {
        let name = FileManager.default.displayName(atPath: url.path)
        return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }

    /// Finds `.app` bundles up to two folders deep (e.g. /Applications/Utilities).
    nonisolated private static func scanDirectories() -> [URL] {
        var results: [URL] = []
        for directory in searchDirectories {
            guard let enumerator = FileManager.default.enumerator(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }

            for case let url as URL in enumerator {
                if url.pathExtension == "app" {
                    results.append(url)
                    enumerator.skipDescendants()
                } else if enumerator.level >= 2 {
                    enumerator.skipDescendants()
                }
            }
        }
        return results
    }
}
