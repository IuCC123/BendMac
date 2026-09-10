import AppKit
import Combine
import Sparkle

/// Sparkle owns downloading, signature verification, replacement, and relaunch.
@MainActor
final class UpdateController: NSObject, ObservableObject, SPUUpdaterDelegate, NSMenuItemValidation {
    @Published private(set) var availableVersion: String?
    @Published private(set) var canCheckForUpdates = false

    private var controller: SPUStandardUpdaterController?

    func start() {
        guard controller == nil else { return }
        let controller = SPUStandardUpdaterController(
            startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
        self.controller = controller
        controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .assign(to: &$canCheckForUpdates)
        controller.startUpdater()
        // Populate the sidebar without showing an update dialog on launch.
        controller.updater.checkForUpdateInformation()
    }

    @objc func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        canCheckForUpdates
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        availableVersion = item.displayVersionString
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        availableVersion = nil
    }
}
