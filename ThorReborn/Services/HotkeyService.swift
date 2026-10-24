import Combine
import Foundation
import KeyboardShortcuts
import os
import ThorRebornCore

/// Registers one global hotkey per assigned app and keeps the registrations in sync with
/// the store, the "Enable shortcuts" setting, and temporary suspension (deactivate key).
@MainActor
final class HotkeyService: ObservableObject {
    enum Conflict: Equatable {
        /// The fixed Shift+Control+Option+Command+T menu bar toggle. Can never be reassigned.
        case menuBarToggle
        /// Already assigned to another app.
        case app(AssignedApp)
    }

    /// `true` while a deactivate-key double press has shortcuts paused.
    @Published private(set) var isSuspended = false

    private let store: AppAssignmentStore
    private let settings: AppSettings
    private let activation: ActivationService
    private let logger = Logger(subsystem: Log.subsystem, category: "hotkeys")

    private var registrations: [ThorShortcut: Task<Void, Never>] = [:]
    private var resumeTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []

    init(store: AppAssignmentStore, settings: AppSettings, activation: ActivationService) {
        self.store = store
        self.settings = settings
        self.activation = activation
    }

    var isActive: Bool { settings.enableShortcuts && !isSuspended }

    func start() {
        // @Published emits in willSet, so read the incoming values from the publishers.
        Publishers.CombineLatest3(store.$apps, settings.$enableShortcuts, $isSuspended)
            .sink { [weak self] apps, enabled, suspended in
                self?.sync(apps: apps, active: enabled && !suspended)
            }
            .store(in: &cancellables)
    }

    func setShortcutsEnabled(_ enabled: Bool) {
        settings.enableShortcuts = enabled
    }

    /// Unregisters every app hotkey for `duration` seconds, then re-registers them.
    func suspend(for duration: TimeInterval) {
        resumeTask?.cancel()
        isSuspended = true
        logger.info("Shortcuts suspended for \(duration, format: .fixed(precision: 2))s")
        resumeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            self?.isSuspended = false
            self?.logger.info("Shortcuts resumed")
        }
    }

    // MARK: Conflicts

    static func isReserved(_ shortcut: ThorShortcut) -> Bool {
        shortcut == .menuBarToggle
    }

    func conflict(for shortcut: ThorShortcut, assigningTo appID: AssignedApp.ID) -> Conflict? {
        if Self.isReserved(shortcut) {
            return .menuBarToggle
        }
        if let other = store.app(using: shortcut, excluding: appID) {
            return .app(other)
        }
        return nil
    }

    /// Assigns `shortcut` to the app, clearing it from any other app that had it.
    func assign(_ shortcut: ThorShortcut?, to appID: AssignedApp.ID) {
        if let shortcut {
            guard !Self.isReserved(shortcut) else { return }
            if let other = store.app(using: shortcut, excluding: appID) {
                store.setShortcut(nil, forAppID: other.id)
            }
        }
        store.setShortcut(shortcut, forAppID: appID)
    }

    // MARK: Registration

    private func sync(apps: [AssignedApp], active: Bool) {
        let wanted: Set<ThorShortcut> = active
            ? Set(apps.compactMap(\.shortcut).filter { !Self.isReserved($0) })
            : []

        for (shortcut, task) in registrations where !wanted.contains(shortcut) {
            task.cancel() // ending the stream unregisters the Carbon hotkey
            registrations[shortcut] = nil
        }
        for shortcut in wanted where registrations[shortcut] == nil {
            registrations[shortcut] = register(shortcut)
        }
    }

    private func register(_ shortcut: ThorShortcut) -> Task<Void, Never> {
        let events = KeyboardShortcuts.events(.keyDown, for: shortcut.keyboardShortcut)
        return Task { [weak self] in
            for await _ in events {
                self?.handlePress(of: shortcut)
            }
        }
    }

    /// Runs when a registered hotkey is pressed (also driven directly by the DEBUG self-test).
    func handlePress(of shortcut: ThorShortcut) {
        // Resolve at fire time so reassigning a shortcut doesn't need a re-registration.
        guard isActive, let app = store.apps.first(where: { $0.shortcut == shortcut }) else { return }
        logger.debug("\(shortcut.stringValue, privacy: .public) → \(app.appDisplayName, privacy: .public)")
        activation.toggle(app)
    }
}
