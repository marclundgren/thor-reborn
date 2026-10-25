import Combine
import Sparkle

/// Sparkle 2. The feed is `docs/appcast.xml`, served by GitHub Pages; each update is
/// EdDSA-signed with the key in `SUPublicEDKey` (see README › Releasing an update).
@MainActor
final class UpdaterService: ObservableObject {
    @Published private(set) var canCheckForUpdates = false

    private let controller = SPUStandardUpdaterController(
        startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil
    )
    private var cancellables: Set<AnyCancellable> = []

    var updater: SPUUpdater { controller.updater }

    /// Bound to the Settings toggle. Until the user decides, Sparkle asks on the second
    /// launch whether to check automatically.
    var automaticallyChecksForUpdates: Bool {
        get { updater.automaticallyChecksForUpdates }
        set {
            objectWillChange.send()
            updater.automaticallyChecksForUpdates = newValue
        }
    }

    func start() {
        controller.startUpdater()
        updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.canCheckForUpdates = $0 }
            .store(in: &cancellables)
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
