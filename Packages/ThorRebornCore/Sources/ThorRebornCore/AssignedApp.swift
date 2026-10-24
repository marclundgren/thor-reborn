import Foundation

/// An application with an (optional) global shortcut.
///
/// Encodes to the original Thor's `apps.json` entry shape:
/// `{"appBundleURL": "file:///Applications/Safari.app/", "appDisplayName": "Safari", "shortcut": "shift+cmd+s"}`.
/// An app without a shortcut is written with `"shortcut": ""`, exactly like the original.
public struct AssignedApp: Codable, Identifiable, Hashable, Sendable {
    public var appBundleURL: URL
    public var appDisplayName: String
    public var shortcut: ThorShortcut?

    /// Apps are unique by bundle location (the original compared `appBundleURL.absoluteString`).
    public var id: String { appBundleURL.absoluteString }

    public init(appBundleURL: URL, appDisplayName: String, shortcut: ThorShortcut? = nil) {
        self.appBundleURL = appBundleURL
        self.appDisplayName = appDisplayName
        self.shortcut = shortcut
    }

    enum CodingKeys: String, CodingKey {
        case appBundleURL, appDisplayName, shortcut
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let urlString = try container.decode(String.self, forKey: .appBundleURL)
        guard let url = URL(string: urlString), url.isFileURL else {
            throw DecodingError.dataCorruptedError(
                forKey: .appBundleURL, in: container, debugDescription: "Not a file URL: \(urlString)"
            )
        }
        appBundleURL = url
        appDisplayName = try container.decode(String.self, forKey: .appDisplayName)
        let shortcutString = try container.decodeIfPresent(String.self, forKey: .shortcut) ?? ""
        shortcut = ThorShortcut(string: shortcutString)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(appBundleURL.absoluteString, forKey: .appBundleURL)
        try container.encode(appDisplayName, forKey: .appDisplayName)
        try container.encode(shortcut?.stringValue ?? "", forKey: .shortcut)
    }
}
