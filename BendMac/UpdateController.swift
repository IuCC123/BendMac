import AppKit
import Combine
import Sparkle

/// Sparkle owns downloading, signature verification, replacement, and relaunch.
@MainActor
final class UpdateController: NSObject, ObservableObject, SPUUpdaterDelegate, SPUStandardUserDriverDelegate,
    NSMenuItemValidation
{
    @Published private(set) var availableVersion: String?
    @Published private(set) var canCheckForUpdates = false

    private var controller: SPUStandardUpdaterController?

    func start() {
        guard controller == nil else { return }
        let controller = SPUStandardUpdaterController(
            startingUpdater: false, updaterDelegate: self, userDriverDelegate: self)
        self.controller = controller
        controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .assign(to: &$canCheckForUpdates)
        controller.startUpdater()
        if controller.updater.automaticallyChecksForUpdates {
            controller.updater.checkForUpdatesInBackground()
        }
    }

    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        // Scheduled checks use the sidebar; manual checks still open Sparkle.
        false
    }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState
    ) {
        availableVersion = update.displayVersionString
    }

    func standardUserDriverWillFinishUpdateSession() {
        availableVersion = nil
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
