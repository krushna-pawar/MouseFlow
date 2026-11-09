// App updates through Sparkle. Sparkle reads the update feed from `SUFeedURL` in Info.plist and installs
// only updates signed with the private key that matches `SUPublicEDKey`.

import AppKit
import Combine
import Sparkle

@MainActor
final class UpdateController: NSObject, ObservableObject, @preconcurrency SPUStandardUserDriverDelegate {
    static let shared = UpdateController()

    /// False while a check or an update is already in progress.
    @Published private(set) var canCheckForUpdates = false

    private var controller: SPUStandardUpdaterController!

    private override init() {
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: self)
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

    // MARK: - SPUStandardUserDriverDelegate

    var supportsGentleScheduledUpdateReminders: Bool { true }

    /// MouseFlow has no Dock icon, so a background update window would sit unnoticed behind other apps.
    /// Bring MouseFlow forward whenever Sparkle shows an update.
    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        NSApp.activate(ignoringOtherApps: true)
    }
}
