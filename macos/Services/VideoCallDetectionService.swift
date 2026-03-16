// VideoCallDetectionService.swift
// TranscriptStudio
// nl.prezent.TranscriptStudio
//
// Detects active video calls by monitoring camera usage and known video app processes.
// Posts .videoCallDetected when a call is detected, reusing the existing CalendarEvent
// and MeetingNotificationService infrastructure.

#if os(macOS)
import Foundation
import AVFoundation
import AppKit
import OSLog

private let logger = Logger(subsystem: "nl.prezent.TranscriptStudio", category: "VideoCallDetection")

@Observable
final class VideoCallDetectionService: @unchecked Sendable {

    static let shared = VideoCallDetectionService()

    // MARK: - State

    enum DetectionState: Sendable {
        case idle
        case detected
        case cooldown
    }

    private(set) var state: DetectionState = .idle

    private var isEnabled: Bool {
        UserDefaults.standard.object(forKey: "videoCallDetectionEnabled") as? Bool ?? true
    }

    // MARK: - Known Video Apps

    static let knownVideoApps: [String: (name: String, platform: MeetingPlatform)] = [
        "com.microsoft.teams":       ("Microsoft Teams", .teams),
        "com.microsoft.teams2":      ("Microsoft Teams", .teams),
        "us.zoom.xos":               ("Zoom", .zoom),
        "com.apple.FaceTime":        ("FaceTime", .other),
        "com.tinyspeck.slackmacgap": ("Slack", .other),
        "com.webex.meetingmanager":  ("Webex", .other),
        "com.hhgilmore.Discord":     ("Discord", .other),
    ]

    static let browserBundleIds: Set<String> = [
        "com.apple.Safari",
        "com.google.Chrome",
        "com.microsoft.edgemac",
        "com.brave.Browser",
        "company.thebrowser.Browser",
        "org.mozilla.firefox",
    ]

    // MARK: - Private State

    private var dismissedSessionIds: Set<String> = []
    private var currentSessionId: String?
    private var cameraObservation: NSKeyValueObservation?
    private var cooldownTask: Task<Void, Never>?
    private var pollingTask: Task<Void, Never>?
    private var isMonitoring = false

    // MARK: - Init

    private init() {}

    // MARK: - Monitoring

    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true

        if let camera = AVCaptureDevice.default(for: .video) {
            // KVO on camera in-use state
            cameraObservation = camera.observe(\.isInUseByAnotherApplication, options: [.new]) { [weak self] _, change in
                let inUse = change.newValue ?? false
                DispatchQueue.main.async {
                    guard let self else { return }
                    if inUse {
                        self.handleCameraActive()
                    } else {
                        self.handleCameraInactive()
                    }
                }
            }
            // Check initial state
            if camera.isInUseByAnotherApplication {
                DispatchQueue.main.async { [weak self] in
                    self?.handleCameraActive()
                }
            }
            logger.info("VideoCallDetection: KVO monitoring started")
        } else {
            // Fallback: poll running apps when camera device is unavailable (sandbox)
            logger.info("VideoCallDetection: no camera device available, falling back to app polling")
            startAppPolling()
        }
    }

    func stopMonitoring() {
        isMonitoring = false
        cameraObservation?.invalidate()
        cameraObservation = nil
        pollingTask?.cancel()
        pollingTask = nil
        cooldownTask?.cancel()
        cooldownTask = nil
    }

    @MainActor
    func dismissSession(_ sessionId: String) {
        dismissedSessionIds.insert(sessionId)
        if currentSessionId == sessionId {
            enterCooldown()
        }
    }

    // MARK: - Camera Handlers

    @MainActor
    private func handleCameraActive() {
        guard isEnabled, state == .idle else { return }

        if let (appName, platform, sessionId) = detectRunningVideoApp() {
            guard !dismissedSessionIds.contains(sessionId) else { return }

            // Check if a calendar meeting already covers this time window
            if isCalendarMeetingActive() { return }

            currentSessionId = sessionId
            state = .detected

            let event = CalendarEvent(
                id: "videocall-\(sessionId)",
                title: "Videogesprek — \(appName)",
                date: Date(),
                endDate: Date().addingTimeInterval(3600),
                meetingURL: nil,
                platform: platform,
                calendarTitle: "Gedetecteerd"
            )

            // Post in-app notification
            NotificationCenter.default.post(
                name: .videoCallDetected,
                object: nil,
                userInfo: ["event": event]
            )

            // Schedule OS notification for background awareness
            Task {
                await MeetingNotificationService.shared.scheduleIfNeeded(for: event)
            }

            logger.info("VideoCallDetection: detected \(appName) call (session: \(sessionId))")
        }
    }

    @MainActor
    private func handleCameraInactive() {
        guard state == .detected else { return }
        enterCooldown()
    }

    // MARK: - App Detection

    @MainActor
    private func detectRunningVideoApp() -> (name: String, platform: MeetingPlatform, sessionId: String)? {
        let runningApps = NSWorkspace.shared.runningApplications

        // Check known video apps first
        for app in runningApps {
            guard let bundleId = app.bundleIdentifier else { continue }
            if let match = Self.knownVideoApps[bundleId] {
                let sessionId = "\(bundleId)-\(app.processIdentifier)"
                return (match.name, match.platform, sessionId)
            }
        }

        // Check browsers (camera + browser = likely web-based video call)
        for app in runningApps {
            guard let bundleId = app.bundleIdentifier else { continue }
            if Self.browserBundleIds.contains(bundleId) {
                let sessionId = "browser-\(bundleId)-\(app.processIdentifier)"
                return ("Videogesprek (browser)", .meet, sessionId)
            }
        }

        return nil
    }

    // MARK: - Calendar Dedup

    private func isCalendarMeetingActive() -> Bool {
        let now = Date()
        return CalendarService.shared.upcomingMeetings.contains { event in
            // Calendar meeting starting within 5 minutes or already started
            let startsNearby = abs(event.date.timeIntervalSince(now)) < 5 * 60
            let isOngoing = event.date <= now && event.endDate > now
            return startsNearby || isOngoing
        }
    }

    // MARK: - Cooldown

    @MainActor
    private func enterCooldown() {
        state = .cooldown
        currentSessionId = nil
        cooldownTask?.cancel()
        cooldownTask = Task {
            try? await Task.sleep(for: .seconds(60))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self.state = .idle
            }
            logger.info("VideoCallDetection: cooldown ended, returning to idle")
        }
    }

    // MARK: - Fallback Polling

    private func startAppPolling() {
        pollingTask = Task { @MainActor in
            var appDurations: [String: Date] = [:]

            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                guard !Task.isCancelled, isEnabled, state == .idle else {
                    appDurations.removeAll()
                    continue
                }

                let runningApps = NSWorkspace.shared.runningApplications
                var currentApps: Set<String> = []

                for app in runningApps {
                    guard let bundleId = app.bundleIdentifier else { continue }
                    let isVideoApp = Self.knownVideoApps[bundleId] != nil
                    guard isVideoApp else { continue }

                    currentApps.insert(bundleId)
                    if appDurations[bundleId] == nil {
                        appDurations[bundleId] = Date()
                    }

                    // Alert if video app has been running for > 30 seconds
                    if let startTime = appDurations[bundleId],
                       Date().timeIntervalSince(startTime) > 30 {
                        let match = Self.knownVideoApps[bundleId]!
                        let sessionId = "\(bundleId)-\(app.processIdentifier)"
                        guard !dismissedSessionIds.contains(sessionId) else { continue }
                        guard !isCalendarMeetingActive() else { continue }

                        currentSessionId = sessionId
                        state = .detected

                        let event = CalendarEvent(
                            id: "videocall-\(sessionId)",
                            title: "Videogesprek — \(match.name)",
                            date: Date(),
                            endDate: Date().addingTimeInterval(3600),
                            meetingURL: nil,
                            platform: match.platform,
                            calendarTitle: "Gedetecteerd"
                        )

                        NotificationCenter.default.post(
                            name: .videoCallDetected,
                            object: nil,
                            userInfo: ["event": event]
                        )

                        Task {
                            await MeetingNotificationService.shared.scheduleIfNeeded(for: event)
                        }

                        logger.info("VideoCallDetection (polling): detected \(match.name)")
                        break
                    }
                }

                // Clean up apps that are no longer running
                for bundleId in appDurations.keys where !currentApps.contains(bundleId) {
                    appDurations.removeValue(forKey: bundleId)
                }
            }
        }
    }
}
#endif
