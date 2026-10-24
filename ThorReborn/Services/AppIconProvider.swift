import AppKit
import UniformTypeIdentifiers

/// Cached application icons. Always returns an image: bundles without an icon (or that
/// have disappeared) get the system's generic application icon.
@MainActor
final class AppIconProvider {
    static let shared = AppIconProvider()

    private let cache = NSCache<NSString, NSImage>()

    func icon(for bundleURL: URL) -> NSImage {
        let key = bundleURL.path as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }
        let icon: NSImage
        if FileManager.default.fileExists(atPath: bundleURL.path) {
            icon = NSWorkspace.shared.icon(forFile: bundleURL.path)
        } else {
            icon = Self.fallbackIcon
        }
        cache.setObject(icon, forKey: key)
        return icon
    }

    static var fallbackIcon: NSImage {
        NSWorkspace.shared.icon(for: .applicationBundle)
    }
}
