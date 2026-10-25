import KeyboardShortcuts
import SwiftUI
import ThorRebornCore

/// The main window: the assignment list plus a Settings tab (mirrors the original
/// Thor's "Apps" / "Settings" toolbar tabs).
struct MainWindowView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case apps = "Apps"
        case settings = "Settings"
        var id: String { rawValue }
    }

    @State private var tab: Tab

    init(initialTab: Tab = .apps) {
        _tab = State(initialValue: initialTab)
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("View", selection: $tab) {
                ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .padding(.vertical, 10)

            Divider()

            switch tab {
            case .apps: AssignmentListView()
            case .settings: SettingsView()
            }
        }
        .frame(minWidth: 460, minHeight: 420)
    }
}

/// One row per assigned app: icon, name, and a shortcut recorder.
struct AssignmentListView: View {
    @EnvironmentObject private var store: AppAssignmentStore
    @EnvironmentObject private var hotkeys: HotkeyService
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var commands: AppCommands

    @State private var selection: Set<AssignedApp.ID> = []
    @State private var isPickerPresented = false
    @State private var pendingConflict: PendingConflict?
    @State private var pendingDeletion: Set<AssignedApp.ID> = []
    /// Bumped to make recorders re-read the store after a rejected change.
    @State private var recorderRevision = 0

    struct PendingConflict: Identifiable {
        let id = UUID()
        let shortcut: ThorShortcut
        let target: AssignedApp
        let current: AssignedApp
    }

    var body: some View {
        VStack(spacing: 0) {
            statusBanner
            if store.apps.isEmpty {
                ContentUnavailableView {
                    Label("No Apps Yet", systemImage: "hammer")
                } description: {
                    Text("Add an app, then click its shortcut field and press a key combination.")
                } actions: {
                    Button("Add App…") { isPickerPresented = true }
                }
                .frame(maxHeight: .infinity)
            } else {
                list
            }
            Divider()
            bottomBar
        }
        .sheet(isPresented: $isPickerPresented) {
            AddAppPickerView()
        }
        .alert(
            "Shortcut Already in Use",
            isPresented: Binding(get: { pendingConflict != nil }, set: { if !$0 { pendingConflict = nil } }),
            presenting: pendingConflict
        ) { conflict in
            Button("Use for \(conflict.target.appDisplayName)", role: .destructive) {
                hotkeys.assign(conflict.shortcut, to: conflict.target.id)
            }
            Button("Cancel", role: .cancel) {}
        } message: { conflict in
            Text("\(conflict.shortcut.displayString) is assigned to \(conflict.current.appDisplayName). Assigning it to \(conflict.target.appDisplayName) removes it from \(conflict.current.appDisplayName).")
        }
        .confirmationDialog(
            pendingDeletion.count == 1 ? "Delete this shortcut?" : "Delete \(pendingDeletion.count) shortcuts?",
            isPresented: Binding(get: { !pendingDeletion.isEmpty }, set: { if !$0 { pendingDeletion = [] } })
        ) {
            Button("Delete", role: .destructive) {
                store.remove(ids: pendingDeletion)
                selection.subtract(pendingDeletion)
                pendingDeletion = []
            }
        }
    }

    @ViewBuilder
    private var statusBanner: some View {
        if !settings.enableShortcuts {
            banner("Shortcuts are disabled.", systemImage: "pause.circle.fill", action: (title: "Enable", run: {
                hotkeys.setShortcutsEnabled(true)
            }))
        } else if hotkeys.isSuspended {
            banner("Shortcuts are paused by the deactivate key.", systemImage: "pause.circle", action: nil)
        }
    }

    private func banner(_ text: String, systemImage: String, action: (title: String, run: () -> Void)?) -> some View {
        HStack {
            Label(text, systemImage: systemImage)
            Spacer()
            if let action {
                Button(action.title, action: action.run).controlSize(.small)
            }
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.yellow.opacity(0.18))
    }

    private var list: some View {
        List(selection: $selection) {
            ForEach(store.apps) { app in
                AssignmentRow(
                    app: app,
                    revision: recorderRevision,
                    shortcut: Binding(
                        get: { app.shortcut },
                        set: { requestShortcut($0, for: app) }
                    )
                )
                .tag(app.id)
                .swipeActions(edge: .trailing) {
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        store.remove(ids: [app.id])
                    }
                }
                .contextMenu {
                    Button("Clear Shortcut") { hotkeys.assign(nil, to: app.id) }
                        .disabled(app.shortcut == nil)
                    Button("Delete", role: .destructive) { pendingDeletion = [app.id] }
                }
            }
            .onMove { store.move(fromOffsets: $0, toOffset: $1) }
            .onDelete { store.remove(atOffsets: $0) }
        }
        .listStyle(.inset)
        .alternatingRowBackgrounds()
        .onDeleteCommand {
            if !selection.isEmpty { pendingDeletion = selection }
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 8) {
            Button { isPickerPresented = true } label: {
                Image(systemName: "plus").frame(width: 16, height: 16)
            }
            .help("Add apps")

            Button { pendingDeletion = selection } label: {
                Image(systemName: "minus").frame(width: 16, height: 16)
            }
            .help("Delete the selected apps")
            .disabled(selection.isEmpty)

            Spacer()

            Button("Export…") { commands.exportShortcuts() }
                .disabled(store.apps.isEmpty)
            Button("Import…") { commands.importShortcuts() }
        }
        .buttonStyle(.bordered)
        .padding(10)
    }

    /// Validates a newly recorded shortcut. Reserved shortcuts are already blocked by the
    /// recorder's validation; conflicts with other rows ask for confirmation first.
    private func requestShortcut(_ shortcut: ThorShortcut?, for app: AssignedApp) {
        guard let shortcut else {
            hotkeys.assign(nil, to: app.id)
            return
        }
        switch hotkeys.conflict(for: shortcut, assigningTo: app.id) {
        case nil:
            hotkeys.assign(shortcut, to: app.id)
        case .app(let other):
            recorderRevision += 1 // show the old value until the user confirms
            pendingConflict = PendingConflict(shortcut: shortcut, target: app, current: other)
        case .menuBarToggle:
            recorderRevision += 1
        }
    }
}

struct AssignmentRow: View {
    let app: AssignedApp
    /// Not displayed; a changed value forces the recorder to resync with `shortcut`.
    let revision: Int
    @Binding var shortcut: ThorShortcut?

    var body: some View {
        HStack(spacing: 10) {
            AppIconView(url: app.appBundleURL, size: 36)
            Text(app.appDisplayName)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 12)
            KeyboardShortcuts.Recorder(
                shortcut: Binding(
                    get: { shortcut?.keyboardShortcut },
                    set: { shortcut = $0.map(ThorShortcut.init) }
                )
            )
            .shortcutValidation { recorded in
                HotkeyService.isReserved(ThorShortcut(recorded))
                    ? .disallow(reason: "⇧⌃⌥⌘T is reserved for showing and hiding the ThorReborn menu bar icon.")
                    : .allow
            }
            .frame(width: 150)
            .id(revision)
        }
        .padding(.vertical, 4)
    }
}

struct AppIconView: View {
    let url: URL
    let size: CGFloat

    var body: some View {
        Image(nsImage: AppIconProvider.shared.icon(for: url))
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
    }
}
