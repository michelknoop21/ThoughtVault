import Foundation
import UserNotifications
#if os(macOS)
import AppKit
#endif
// APP_STORE builds (TestFlight/App Store) ship without Sparkle and update through the store,
// so every update entry point below compiles to a no-op there.
#if os(macOS) && !APP_STORE
import Sparkle
#endif

@MainActor
@Observable
final class UpdateCheckService: NSObject {
    struct Installer: Decodable {
        let version: String
        let filename: String

        static let baseURL = URL(string: "https://thoughtvault.yinga.ai/d-05921304471ce66e62d0a2b7f324c2354dfb1d895d23a895bba7f86110e2472e/")!

        var url: URL? {
            guard filename.range(of: #"^[A-Za-z0-9._-]+\.dmg$"#, options: .regularExpression) != nil else { return nil }
            return Self.baseURL.appendingPathComponent(filename)
        }

        static func isNewer(_ remote: String, than local: String) -> Bool {
            func parts(_ value: String) -> [Int]? {
                let components = value.split(separator: ".", omittingEmptySubsequences: false)
                guard components.count == 3, components.allSatisfy({ !$0.isEmpty && $0.allSatisfy({ $0.isASCII && $0.isNumber }) }) else { return nil }
                let numbers = components.compactMap { Int($0) }
                return numbers.count == 3 ? numbers : nil
            }
            guard let remote = parts(remote), let local = parts(local) else { return false }
            return local.lexicographicallyPrecedes(remote)
        }
    }

    var usesInstallerDownload = false
    var isChecking = false
    var availableVersion: String?
    var downloadURL: URL?
    var isUpdateAvailable: Bool { availableVersion != nil }
    var isDownloading = false
    var downloadProgress: Double = 0
    var errorMessage: String?
    @ObservationIgnored var installationStateChanged: (Bool) -> Void = { _ in }
    @ObservationIgnored var isBusy: () -> Bool = { true }
    @ObservationIgnored private var lastCheck: Date?
    @ObservationIgnored private let session: URLSession
    @ObservationIgnored var openInstaller: (URL) -> Bool = { url in
        #if os(macOS)
        NSWorkspace.shared.open(url)
        #else
        false
        #endif
    }

    init(session: URLSession = .shared) {
        self.session = session
        super.init()
    }
#if os(macOS) && !APP_STORE
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

    func checkForUpdate(force: Bool = false) async {
#if os(macOS) && !APP_STORE
        guard !isChecking else { return }
        guard force || lastCheck == nil || Date().timeIntervalSince(lastCheck!) >= 6 * 60 * 60 else { return }
        isChecking = true
        errorMessage = nil
        defer { isChecking = false }
        do {
            let request = URLRequest(url: Installer.baseURL.appendingPathComponent("releases.json"), cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let key = Bundle.main.bundleIdentifier?.hasSuffix(".dev") == true ? "dev_macos" : "macos"
            let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
            if let raw = object?[key], let encoded = try? JSONSerialization.data(withJSONObject: raw), let entry = try? JSONDecoder().decode(Installer.self, from: encoded), Installer.isNewer(entry.version, than: current), let url = entry.url {
                if availableVersion == nil || Installer.isNewer(entry.version, than: availableVersion!) {
                    availableVersion = entry.version
                    downloadURL = url
                    usesInstallerDownload = true
                    await notify(version: entry.version)
                }
            }
            lastCheck = Date()
        } catch {
            if force { errorMessage = "Controleren mislukt. Controleer je internetverbinding en probeer opnieuw." }
        }
        do {
            try prepareUpdater()
            if controller?.updater.canCheckForUpdates == true { controller?.updater.checkForUpdateInformation() }
        } catch {
            if force && availableVersion == nil { errorMessage = "Controleren mislukt. Probeer opnieuw." }
        }
#endif
    }

    func downloadAndOpen() async {
#if os(macOS) && !APP_STORE
        guard !isDownloading else { return }
        guard !isBusy() else {
            errorMessage = "Bijwerken kan zodra opnemen en verwerken klaar zijn."
            return
        }
        if usesInstallerDownload {
            guard let url = downloadURL else { return }
            isDownloading = true
            defer { isDownloading = false }
            do {
                var request = URLRequest(url: url, timeoutInterval: 20)
                request.httpMethod = "HEAD"
                let (_, response) = try await session.data(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 200, response.url == url else { throw URLError(.badServerResponse) }
                guard !isBusy() else { errorMessage = "Bijwerken kan zodra opnemen en verwerken klaar zijn."; return }
                guard openInstaller(url) else { throw URLError(.cannotOpenFile) }
                errorMessage = nil
            } catch { errorMessage = "Download openen mislukt. Controleer je verbinding en probeer opnieuw." }
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

#if os(macOS) && !APP_STORE
extension UpdateCheckService: SPUUpdaterDelegate {
    func feedURLString(for updater: SPUUpdater) -> String? {
        let channel = Bundle.main.bundleIdentifier?.hasSuffix(".dev") == true ? "dev" : "stable"
        return "https://thoughtvault.yinga.ai/releases/macos/\(channel).xml"
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        if let availableVersion, Installer.isNewer(availableVersion, than: item.displayVersionString) { return }
        usesInstallerDownload = false
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
        if !usesInstallerDownload && (error as NSError).code != SUError.noUpdateError.rawValue { errorMessage = "Bijwerken mislukt: \(error.localizedDescription)" }
    }
}
#endif
