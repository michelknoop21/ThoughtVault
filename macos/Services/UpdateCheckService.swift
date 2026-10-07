import Foundation
import UserNotifications
#if os(macOS)
import Sparkle
#endif

@MainActor
@Observable
final class UpdateCheckService: NSObject {
    var availableVersion: String?
    var downloadURL: URL?
    var isUpdateAvailable: Bool { availableVersion != nil }
    var isDownloading = false
    var downloadProgress: Double = 0
    var errorMessage: String?
    @ObservationIgnored var installationStateChanged: (Bool) -> Void = { _ in }
    @ObservationIgnored var isBusy: () -> Bool = { true }
    @ObservationIgnored private var lastCheck: Date?
#if os(macOS)
    @ObservationIgnored private var controller: SPUStandardUpdaterController?

    private func prepareUpdater() throws {
        guard controller == nil else { return }
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
        self.controller = controller
        controller.updater.automaticallyChecksForUpdates = false
        controller.updater.automaticallyDownloadsUpdates = false
        try controller.updater.start()
    }
#endif

    func checkForUpdate() async {
#if os(macOS)
        guard lastCheck == nil || Date().timeIntervalSince(lastCheck!) >= 6 * 60 * 60 else { return }
        do {
            try prepareUpdater()
            guard controller?.updater.canCheckForUpdates == true else { return }
            lastCheck = Date()
            controller?.updater.checkForUpdateInformation()
        } catch { /* Offline checks and setup failures do not interrupt recording. */ }
#endif
    }

    func downloadAndOpen() async {
#if os(macOS)
        guard !isBusy() else {
            errorMessage = "Bijwerken kan zodra opnemen en verwerken klaar zijn."
            return
        }
        do {
            try prepareUpdater()
            errorMessage = nil
            controller?.checkForUpdates(nil)
        } catch { errorMessage = "Bijwerken mislukt: \(error.localizedDescription)" }
#endif
    }

    private func notify(version: String) async {
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: "notifiedUpdateVersion") != version else { return }
        let center = UNUserNotificationCenter.current()
        guard await center.notificationSettings().authorizationStatus == .authorized else { return }
        let content = UNMutableNotificationContent()
        content.title = "Update beschikbaar"
        content.body = "Versie \(version) van ThoughtVault is beschikbaar."
        do {
            try await center.add(UNNotificationRequest(identifier: "update-\(version)", content: content, trigger: nil))
            defaults.set(version, forKey: "notifiedUpdateVersion")
        } catch { /* The in-app banner remains available. */ }
    }
}

#if os(macOS)
extension UpdateCheckService: SPUUpdaterDelegate {
    func feedURLString(for updater: SPUUpdater) -> String? {
        let channel = Bundle.main.bundleIdentifier?.hasSuffix(".dev") == true ? "dev" : "stable"
        return "https://thoughtvault.yinga.ai/releases/macos/\(channel).xml"
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        availableVersion = item.displayVersionString
        downloadURL = item.fileURL
        Task { await notify(version: item.displayVersionString) }
    }

    func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem, untilInvokingBlock installHandler: @escaping () -> Void) -> Bool {
        guard isBusy() else { installationStateChanged(true); return false }
        errorMessage = "Update gedownload. Installatie wacht tot opnemen en verwerken klaar zijn."
        Task { @MainActor in
            while isBusy() { try? await Task.sleep(for: .seconds(1)) }
            installationStateChanged(true)
            installHandler()
        }
        return true
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        isDownloading = false
        installationStateChanged(false)
        if (error as NSError).code != SUError.noUpdateError.rawValue { errorMessage = "Bijwerken mislukt: \(error.localizedDescription)" }
    }
}
#endif
