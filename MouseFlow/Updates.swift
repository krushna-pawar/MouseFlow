// App updates through Sparkle. Sparkle reads the update feed from `SUFeedURL` in Info.plist and installs
// only updates signed with the private key that matches `SUPublicEDKey`.

import Combine
import Sparkle

@MainActor
final class UpdateController: ObservableObject {
    static let shared = UpdateController()

    /// False while a check or an update is already in progress.
    @Published private(set) var canCheckForUpdates = false

    private let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

    private init() {
        controller.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }

    /// Checks once a day in the background when on.
    var checksAutomatically: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set {
            objectWillChange.send()
            controller.updater.automaticallyChecksForUpdates = newValue
        }
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
