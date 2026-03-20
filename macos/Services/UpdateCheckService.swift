// UpdateCheckService.swift
// TranscriptStudio
// nl.prezent.TranscriptStudio
//
// Checks releases.json for available app updates, once per session.
// Displays a non-blocking banner on the home screen when a newer version exists.
// Posts a macOS system notification on startup when a newer version is found.

import Foundation
import UserNotifications
import OSLog

private let logger = Logger(subsystem: "nl.prezent.TranscriptStudio", category: "UpdateCheck")

@Observable
final class UpdateCheckService {

    var availableVersion: String?
    var downloadURL: URL?
    var isUpdateAvailable: Bool { availableVersion != nil }

    @ObservationIgnored private var hasFetched = false

    private static let releasesURL = URL(string: "https://n8n.prezent.nl/tstudio/download/releases.json")!
    private static let downloadBaseURL = "https://n8n.prezent.nl"

    @MainActor
    func checkForUpdate() async {
        guard !hasFetched else { return }
        hasFetched = true

        do {
            let (data, _) = try await URLSession.shared.data(from: Self.releasesURL)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

            let isDev = Bundle.main.bundleIdentifier?.contains(".dev") == true

            let versionKey = isDev ? "dev_latest_version" : "latest_version"
            let platformKey = isDev ? "dev_macos" : "macos"

            guard let latestVersion = json[versionKey] as? String else { return }
            let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"

            guard Self.isNewer(latestVersion, than: currentVersion) else { return }

            var resolvedURL: URL?
            if let platformInfo = json[platformKey] as? [String: Any],
               let urlPath = platformInfo["url"] as? String {
                resolvedURL = URL(string: Self.downloadBaseURL + urlPath)
            }

            availableVersion = latestVersion
            downloadURL = resolvedURL

            await Self.postSystemNotification(version: latestVersion)
        } catch {
            // Silently ignore — update check is best-effort
        }
    }

    private static func postSystemNotification(version: String) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        guard settings.authorizationStatus == .authorized else {
            logger.debug("Notification permission not granted, skipping update notification")
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Update beschikbaar"
        content.body = "Versie \(version) van TranscriptStudio is beschikbaar."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "update-available-\(version)",
            content: content,
            trigger: nil // deliver immediately
        )

        do {
            try await center.add(request)
            logger.info("Posted system notification for update \(version)")
        } catch {
            logger.warning("Failed to post update notification: \(error.localizedDescription)")
        }
    }

    private static func isNewer(_ remote: String, than local: String) -> Bool {
        let r = remote.split(separator: ".").compactMap { Int($0) }
        let l = local.split(separator: ".").compactMap { Int($0) }
        guard r.count >= 3, l.count >= 3 else { return false }
        if r[0] != l[0] { return r[0] > l[0] }
        if r[1] != l[1] { return r[1] > l[1] }
        return r[2] > l[2]
    }
}
