import SwiftUI
import ThorRebornCore

/// Searchable list of installed apps. Double-click an app, or select several and click Add.
struct AddAppPickerView: View {
    @EnvironmentObject private var discovery: AppDiscoveryService
    @EnvironmentObject private var store: AppAssignmentStore
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var selection: Set<DiscoveredApp.ID> = []
    @FocusState private var searchFocused: Bool

    private var assignedPaths: Set<String> {
        Set(store.apps.map { $0.appBundleURL.standardizedFileURL.path })
    }

    private var filteredApps: [DiscoveredApp] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return discovery.apps }
        return discovery.apps.filter {
            $0.name.localizedCaseInsensitiveContains(query) || $0.url.lastPathComponent.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search apps", text: $searchText)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                if discovery.isSearching {
                    ProgressView().controlSize(.small)
                }
            }
            .padding(10)

            Divider()

            List(selection: $selection) {
                ForEach(filteredApps) { app in
                    let isAssigned = assignedPaths.contains(app.id)
                    HStack(spacing: 10) {
                        AppIconView(url: app.url, size: 28)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(app.name)
                            Text(app.url.deletingLastPathComponent().path)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                        if isAssigned {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.secondary)
                                .help("Already added")
                        }
                    }
                    .opacity(isAssigned ? 0.5 : 1)
                    .tag(app.id)
                    .selectionDisabled(isAssigned)
                }
            }
            .contextMenu(forSelectionType: DiscoveredApp.ID.self, menu: { _ in }) { ids in
                add(ids) // double-click / Return
            }
            .overlay {
                if filteredApps.isEmpty && !discovery.isSearching {
                    ContentUnavailableView.search(text: searchText)
                }
            }

            Divider()

            HStack {
                Text("\(filteredApps.count) apps")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(selection.count > 1 ? "Add \(selection.count) Apps" : "Add") { add(selection) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selection.isEmpty)
            }
            .padding(10)
        }
        .frame(width: 460, height: 520)
        .onAppear {
            searchFocused = true
            discovery.refresh()
        }
    }

    private func add(_ ids: Set<DiscoveredApp.ID>) {
        let assigned = assignedPaths
        let newApps = discovery.apps
            .filter { ids.contains($0.id) && !assigned.contains($0.id) }
            // Directory URL → "file:///Applications/Safari.app/" (trailing slash, like the original).
            .map { AssignedApp(appBundleURL: URL(filePath: $0.url.path, directoryHint: .isDirectory), appDisplayName: $0.name) }
        guard !newApps.isEmpty else { return }
        store.add(contentsOf: newApps)
        dismiss()
    }
}
