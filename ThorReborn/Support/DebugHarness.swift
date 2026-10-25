#if DEBUG
import AppKit
import Carbon.HIToolbox
import Sparkle
import ThorRebornCore

/// `--screenshots <dir>`: renders the real main window (both tabs, light and dark) with a
/// sample list of apps into PNGs for the website, then quits. Rendering the window's own
/// views needs no Screen Recording permission.
@MainActor
struct Screenshots {
    let services: AppServices
    let windows: WindowCoordinator
    let sandbox: SelfTest.Sandbox

    private static let samples: [(path: String, key: Int, modifiers: ThorShortcut.Modifiers)] = [
        ("/Applications/Safari.app", kVK_ANSI_S, [.shift, .command]),
        ("/System/Applications/Mail.app", kVK_ANSI_M, [.shift, .command]),
        ("/System/Applications/Messages.app", kVK_ANSI_M, [.option, .command]),
        ("/System/Applications/Notes.app", kVK_ANSI_N, [.shift, .command]),
        ("/System/Applications/Calendar.app", kVK_ANSI_C, [.control, .option]),
        ("/System/Applications/Music.app", kVK_ANSI_P, [.control, .option]),
        ("/System/Applications/Utilities/Terminal.app", kVK_ANSI_T, [.control, .option]),
    ]

    func run() {
        services.store.add(contentsOf: Self.samples.compactMap { sample in
            let url = URL(filePath: sample.path, directoryHint: .isDirectory)
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            return AssignedApp(
                appBundleURL: url,
                appDisplayName: FileManager.default.displayName(atPath: url.path).replacing(".app", with: ""),
                shortcut: ThorShortcut(keyCode: sample.key, modifiers: sample.modifiers)
            )
        })

        Task {
            let directory = sandbox.reportURL
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                for tab in MainWindowView.Tab.allCases {
                    let window = windows.makeMainWindow(initialTab: tab, autosaveName: nil)
                    window.appearance = NSAppearance(named: appearance)
                    window.setContentSize(NSSize(width: 520, height: tab == .apps ? 456 : 640))
                    NSApp.activate()
                    window.makeKeyAndOrderFront(nil)
                    window.orderFrontRegardless()
                    try? await Task.sleep(for: .seconds(1.5)) // layout, icons, recorders
                    let file = directory.appending(path: "\(tab.rawValue.lowercased())-\(name).png")
                    if let png = Self.png(of: window) {
                        try? png.write(to: file)
                    }
                    window.close()
                }
            }
            sandbox.cleanUp()
            NSApp.terminate(nil)
        }
    }

    /// The window as the window server composites it, shadow included. Capturing your own
    /// windows needs no Screen Recording permission. `CGWindowListCreateImage` is
    /// unavailable to Swift in the macOS 15+ SDK but still exported, so look it up.
    private static func png(of window: NSWindow) -> Data? {
        typealias CreateImage = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
        if let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage") {
            let createImage = unsafeBitCast(symbol, to: CreateImage.self)
            let includingWindow: UInt32 = 1 << 3 // kCGWindowListOptionIncludingWindow
            if let image = createImage(.null, includingWindow, UInt32(window.windowNumber), 0)?.takeRetainedValue() {
                return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
            }
        }
        // Fallback: draw the view hierarchy (the frame view is the content view's superview).
        guard let frameView = window.contentView?.superview,
              let rep = frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds) else { return nil }
        frameView.cacheDisplay(in: frameView.bounds, to: rep)
        return rep.representation(using: .png, properties: [:])
    }
}

/// `--update-test <report>`: checks the real feed with a headless Sparkle user driver that
/// accepts everything, so an update can be verified end to end without clicking. Sparkle
/// quits the app to install; relaunching is suppressed. Progress is appended to the report.
@MainActor
final class UpdateTest: NSObject, SPUUserDriver, SPUUpdaterDelegate {
    private static var current: UpdateTest?

    private let sandbox: SelfTest.Sandbox
    private var updater: SPUUpdater?
    private var installing = false

    init(sandbox: SelfTest.Sandbox) {
        self.sandbox = sandbox
    }

    func run() {
        Self.current = self
        try? Data().write(to: sandbox.reportURL)
        let info = Bundle.main.infoDictionary ?? [:]
        log("running \(info["CFBundleShortVersionString"] ?? "?") (\(info["CFBundleVersion"] ?? "?")) at \(Bundle.main.bundlePath)")
        let updater = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: self, delegate: self)
        self.updater = updater
        do {
            try updater.start()
        } catch {
            return finish("FAIL could not start updater: \(error)")
        }
        updater.checkForUpdates()
    }

    private func log(_ line: String) {
        guard let handle = try? FileHandle(forWritingTo: sandbox.reportURL) else { return }
        handle.seekToEndOfFile()
        handle.write(Data((line + "\n").utf8))
        try? handle.close()
    }

    private func finish(_ line: String) {
        log(line)
        sandbox.cleanUp()
        NSApp.terminate(nil)
    }

    // MARK: SPUUpdaterDelegate

    func updaterShouldRelaunchApplication(_ updater: SPUUpdater) -> Bool { false }

    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        log("installing \(item.displayVersionString) (\(item.versionString))")
    }

    // MARK: SPUUserDriver

    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: false, sendSystemProfile: false))
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        log("checking \(updater?.feedURL?.absoluteString ?? "?")")
    }

    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        log("found \(appcastItem.displayVersionString) (\(appcastItem.versionString)) at \(appcastItem.fileURL?.absoluteString ?? "?")")
        reply(.install)
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}
    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: any Error) {}

    func showUpdateNotFoundWithError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        acknowledgement()
        finish("NO UPDATE \(error.localizedDescription)")
    }

    func showUpdaterError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        acknowledgement()
        finish("FAIL \(error.localizedDescription) \((error as NSError).userInfo)")
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) { log("downloading") }
    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {}
    func showDownloadDidReceiveData(ofLength length: UInt64) {}
    func showDownloadDidStartExtractingUpdate() { log("extracting (EdDSA signature verified)") }
    func showExtractionReceivedProgress(_ progress: Double) {}

    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        log("ready to install")
        installing = true
        reply(.install)
    }

    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) {
        log("installer running (app terminated: \(applicationTerminated))")
    }

    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        acknowledgement()
        log("installed (relaunched: \(relaunched))")
    }

    func dismissUpdateInstallation() {
        if !installing { finish("dismissed") }
    }
}
#endif
